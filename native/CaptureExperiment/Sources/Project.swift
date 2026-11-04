import Foundation
import CryptoKit

enum ExperimentError: LocalizedError {
    case invalid(String)
    var errorDescription: String? {
        switch self { case .invalid(let message): return message }
    }
}

struct Clip: Codable, Identifiable, Equatable {
    var id = UUID()
    var file: String
    var sourceTicks: Int64
    var startTicks: Int64 = 0
    var durationTicks: Int64
}

struct EditProject: Codable, Equatable {
    var schema = 1
    var revision = 0
    var clips: [Clip] = []
    var title = "Native capture experiment"
    var music: String?
    var sourceGain: Float = 0.5
    var musicGain: Float = 0.25

    static let timescale: Int32 = 600
    var durationTicks: Int64 { clips.reduce(0) { $0 + $1.durationTicks } }

    func validate(forRender: Bool = false) throws {
        guard schema == 1, revision >= 0, clips.count <= 2,
              title.count <= 80, sourceGain.isFinite, musicGain.isFinite,
              (0...0.5).contains(sourceGain), (0...0.5).contains(musicGain) else {
            throw ExperimentError.invalid("Invalid project schema, title, tracks or audio gain.")
        }
        if forRender && clips.count != 2 {
            throw ExperimentError.invalid("Import exactly two clips before preview/export.")
        }
        for clip in clips {
            try Self.validateFilename(clip.file)
            guard clip.sourceTicks > 0, clip.sourceTicks <= 600 * 600,
                  clip.startTicks >= 0, clip.durationTicks >= 20,
                  clip.startTicks <= clip.sourceTicks - clip.durationTicks,
                  clip.startTicks % 20 == 0, clip.durationTicks % 20 == 0 else {
                throw ExperimentError.invalid("Trim must fit inside the source on a 30 fps boundary.")
            }
        }
        guard durationTicks <= 60 * 600 else {
            throw ExperimentError.invalid("This experiment is limited to 60 seconds.")
        }
        if let music { try Self.validateFilename(music) }
    }

    static func validateFilename(_ file: String) throws {
        guard !file.isEmpty, file == URL(fileURLWithPath: file).lastPathComponent,
              !file.contains(".."), !file.contains("/") else {
            throw ExperimentError.invalid("Invalid managed media path.")
        }
    }
}

struct Snapshot: Codable {
    let payload: Data
    let sha256: String
}

struct Recovery {
    let project: EditProject
    let warning: String?
}

/// Immutable, checksummed full-revision journal. Nothing acknowledged as saved
/// depends on the UI's in-memory draft. Originals and older revisions are retained.
actor ProjectStore {
    let root: URL
    private let fm = FileManager.default

    init(root: URL) { self.root = root }

    func prepare() throws {
        for folder in ["Media", "Revisions", "Exports", "Logs"] {
            try fm.createDirectory(at: root.appendingPathComponent(folder),
                                   withIntermediateDirectories: true)
        }
    }

    private func revisionFiles() throws -> [URL] {
        try fm.contentsOfDirectory(at: root.appendingPathComponent("Revisions"),
                                   includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    func recover() throws -> Recovery {
        try prepare()
        let files = try revisionFiles()
        var rejected: [String] = []
        for url in files {
            do {
                let envelope = try JSONDecoder().decode(Snapshot.self, from: Data(contentsOf: url))
                guard Self.hash(envelope.payload) == envelope.sha256 else {
                    throw ExperimentError.invalid("Checksum mismatch")
                }
                let project = try JSONDecoder().decode(EditProject.self, from: envelope.payload)
                try project.validate()
                var warning = rejected.isEmpty ? nil :
                    "RECOVERY FAILURE: newer revisions are unreadable: \(rejected.joined(separator: ", ")). Recovered revision \(project.revision); do not count this as a passing recovery."
                let missing = (project.clips.map(\.file) + [project.music].compactMap { $0 })
                    .filter { !fm.fileExists(atPath: root.appendingPathComponent("Media/\($0)").path) }
                if !missing.isEmpty {
                    warning = (warning.map { $0 + "\n" } ?? "") +
                        "Missing media: \(missing.joined(separator: ", ")). Export is blocked; restore originals."
                }
                return Recovery(project: project, warning: warning)
            } catch {
                rejected.append(url.lastPathComponent)
            }
        }
        guard files.isEmpty else {
            throw ExperimentError.invalid("No readable revision. Preserve the app container for diagnosis; nothing was reset.")
        }
        return Recovery(project: EditProject(), warning: nil)
    }

    func save(_ draft: EditProject) throws -> EditProject {
        try prepare()
        var project = draft
        let maxRevision = try revisionFiles().compactMap {
            Int($0.deletingPathExtension().lastPathComponent)
        }.max() ?? 0
        project.revision = maxRevision + 1
        try project.validate()
        let payload = try JSONEncoder().encode(project)
        let envelope = Snapshot(payload: payload, sha256: Self.hash(payload))
        let data = try JSONEncoder().encode(envelope)
        let name = String(format: "%010d.json", project.revision)
        let url = root.appendingPathComponent("Revisions/\(name)")
        try data.write(to: url, options: .atomic)
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.synchronize()
        guard try Data(contentsOf: url) == data else {
            throw ExperimentError.invalid("Save verification failed. Edit was not acknowledged.")
        }
        return project
    }

    func importFile(_ source: URL) throws -> String {
        try prepare()
        let access = source.startAccessingSecurityScopedResource()
        defer { if access { source.stopAccessingSecurityScopedResource() } }
        let size = try source.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        try requireSpace(bytes: Int64(size) + 256 * 1024 * 1024)
        let ext = source.pathExtension.lowercased()
        guard ["mov", "mp4", "m4v", "m4a", "mp3", "wav", "aif", "aiff", "aac"].contains(ext) else {
            throw ExperimentError.invalid("Use MOV/MP4 video or M4A/MP3/WAV/AIFF/AAC audio.")
        }
        let name = UUID().uuidString + "." + ext
        let destination = root.appendingPathComponent("Media/\(name)")
        let temporary = root.appendingPathComponent("Media/\(UUID().uuidString).importing")
        do {
            try fm.copyItem(at: source, to: temporary)
            let handle = try FileHandle(forWritingTo: temporary)
            defer { try? handle.close() }
            try handle.synchronize()
            try fm.moveItem(at: temporary, to: destination)
        } catch {
            try? fm.removeItem(at: temporary)
            throw error
        }
        return name
    }

    func requireSpace(bytes: Int64) throws {
        let values = try root.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        guard let available = values.volumeAvailableCapacityForImportantUsage,
              available >= bytes else {
            throw ExperimentError.invalid("Insufficient disk space (or capacity unavailable). Free space and retry.")
        }
    }

    static func hash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
