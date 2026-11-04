import AVFoundation
import SwiftUI

@MainActor
final class ExperimentModel: ObservableObject {
    static let root = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Experiment", isDirectory: true)
    let store = ProjectStore(root: ExperimentModel.root)
    let probe = Probe(root: ExperimentModel.root)
    let camera = Camera()
    let player = AVPlayer()
    @Published var project = EditProject() {
        didSet {
            if oldValue != project {
                player.pause()
                previewRevision = nil
            }
        }
    }
    @Published var message = "Opening project…"
    @Published var busy = false
    @Published var exporting = false
    @Published var exportProgress: Float = 0
    @Published var exportURL: URL?
    @Published var previewRevision: Int?
    @Published var seekSeconds = 0.0
    @Published var recovered = false
    @Published var recoveryWarning: String?
    private var exportSession: AVAssetExportSession?
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    private var exportTimer: Timer?
    private var seeking = false
    private var cancelled = false
    private var lastSaved = EditProject()
    private var observations: [NSObjectProtocol] = []

    var duration: Double { Double(project.durationTicks) / 600 }
    var dirty: Bool { project != lastSaved }
    var canRender: Bool {
        recovered && !busy && !exporting && !camera.recording && !camera.starting &&
            ProcessInfo.processInfo.thermalState.rawValue < ProcessInfo.ThermalState.serious.rawValue
    }
    var media: URL { Self.root.appendingPathComponent("Media") }
    var exportMarker: URL { Self.root.appendingPathComponent("export-job.json") }

    init() {
        camera.onEvent = { [weak self] event, fields in
            Task { @MainActor in self?.probe.record(event, fields) }
        }
        camera.discover()
        for name in [AVCaptureSession.wasInterruptedNotification,
                     AVCaptureSession.interruptionEndedNotification,
                     AVCaptureSession.runtimeErrorNotification,
                     AVAudioSession.interruptionNotification,
                     AVAudioSession.routeChangeNotification,
                     ProcessInfo.thermalStateDidChangeNotification,
                     UIApplication.didReceiveMemoryWarningNotification] {
            observations.append(NotificationCenter.default.addObserver(
                forName: name, object: nil, queue: .main) { [weak self] notification in
                    Task { @MainActor in
                        self?.probe.record("notification", [
                            "name": notification.name.rawValue,
                            "details": String(describing: notification.userInfo ?? [:])
                        ])
                        if name == AVCaptureSession.wasInterruptedNotification ||
                            name == AVCaptureSession.runtimeErrorNotification {
                            self?.camera.stopRecording()
                            if let camera = self?.camera { Task { await camera.stop() } }
                            self?.camera.ready = false
                            self?.camera.message = "Camera interrupted. Stop recording if needed, then restart camera."
                        }
                        if name == ProcessInfo.thermalStateDidChangeNotification,
                           ProcessInfo.processInfo.thermalState.rawValue >= ProcessInfo.ThermalState.serious.rawValue {
                            self?.player.pause()
                            self?.camera.stopRecording()
                            if let camera = self?.camera { Task { await camera.stop() } }
                            if self?.exporting == true {
                                self?.cancelExport(reason: "Serious or critical thermal state")
                            }
                            self?.message = "Thermal limit reached. Playback/capture stopped and any export cancelled. Let the device cool before retrying."
                        }
                    }
                })
        }
    }

    func open() async {
        guard !recovered else { return }
        do {
            let result = try await store.recover()
            project = result.project
            lastSaved = result.project
            recoveryWarning = result.warning
            recovered = true
            message = "Recovered revision \(project.revision)."
            probe.record("recovered", ["revision": project.revision, "warning": result.warning ?? ""])
            if FileManager.default.fileExists(atPath: exportMarker.path) {
                let data = try Data(contentsOf: exportMarker)
                let marker = try JSONDecoder().decode(ExportMarker.self, from: data)
                if marker.state == "running" {
                    message += " Previous export was interrupted; it is not a successful output. Retry export."
                    try writeMarker(.init(state: "interrupted", revision: marker.revision,
                                          output: nil, detail: "App relaunched before job completion"))
                    probe.record("exportInterrupted", ["revision": marker.revision])
                } else if marker.state == "completed", let file = marker.output {
                    try EditProject.validateFilename(file)
                    let url = Self.root.appendingPathComponent("Exports/\(file)")
                    if FileManager.default.fileExists(atPath: url.path) { exportURL = url }
                }
            }
        } catch { message = error.localizedDescription; probe.record("openFailure", ["error": message]) }
    }

    func importMedia(_ source: URL, music: Bool) async {
        guard canRender else { return }
        busy = true
        defer { busy = false }
        do {
            await camera.stop()
            player.pause()
            let name = try await store.importFile(source)
            var next = project
            if music {
                let asset = AVURLAsset(url: media.appendingPathComponent(name))
                guard !(try await asset.loadTracks(withMediaType: .audio)).isEmpty else {
                    throw ExperimentError.invalid("Selected music file has no audio.")
                }
                next.music = name
            } else {
                guard next.clips.count < 2 else {
                    throw ExperimentError.invalid("Two clips already loaded. Remove one before importing.")
                }
                let ticks = try await MediaEngine.inspectVideo(media.appendingPathComponent(name))
                let available = 60 * 600 - next.durationTicks
                guard available >= 20 else { throw ExperimentError.invalid("Trim the first clip to leave room for the second.") }
                next.clips.append(Clip(file: name, sourceTicks: ticks,
                                       durationTicks: min(ticks, min(30 * 600, available))))
            }
            try await commit(next)
            probe.record("imported", ["file": name, "kind": music ? "music" : "video"])
        } catch { fail(error) }
    }

    func commit(_ next: EditProject) async throws {
        let saved = try await store.save(next)
        project = saved
        lastSaved = saved
        message = "Saved revision \(saved.revision)."
        probe.record("saved", ["revision": saved.revision])
    }

    func save() async {
        guard canRender else { return }
        busy = true
        defer { busy = false }
        do { try await commit(project) } catch { fail(error) }
    }

    func preparePreview() async {
        guard canRender else { return }
        busy = true
        defer { busy = false }
        do {
            await camera.stop()
            try project.validate(forRender: true)
            try await commit(project)
            let plan = try await MediaEngine.build(project, media: media, exporting: false)
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
            try AVAudioSession.sharedInstance().setActive(true)
            let item = AVPlayerItem(asset: plan.composition)
            item.videoComposition = plan.video
            item.audioMix = plan.audio
            player.replaceCurrentItem(with: item)
            previewRevision = project.revision
            seekSeconds = 0
            message = "Preview revision \(project.revision): \(duration)s, 1080×1920 SDR."
            probe.record("previewPrepared", ["revision": project.revision, "durationSeconds": duration])
        } catch { fail(error) }
    }

    func playPause() {
        guard previewRevision == project.revision else { return }
        if player.rate != 0 {
            player.pause()
            probe.record("playbackPause", ["positionSeconds": player.currentTime().seconds])
        } else {
            if player.currentTime().seconds >= duration - 1.0 / 30 { player.seek(to: .zero) }
            player.play()
            probe.record("playbackStart", ["revision": project.revision])
        }
    }

    func seek(to seconds: Double) async {
        guard previewRevision == project.revision, !seeking else { return }
        seeking = true
        defer { seeking = false }
        player.pause()
        let start = ProcessInfo.processInfo.systemUptime
        let target = CMTime(seconds: max(0, min(duration - 1.0 / 30, seconds)), preferredTimescale: 600)
        let completed = await player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
        let elapsed = (ProcessInfo.processInfo.systemUptime - start) * 1000
        probe.record("seekCompletion", [
            "targetSeconds": target.seconds, "latencyMilliseconds": elapsed, "completed": completed,
            "metric": "AVPlayer seek completion, NOT seek-to-displayed-frame latency"
        ])
    }

    func runSeeks() async {
        guard previewRevision == project.revision, !busy else { return }
        busy = true
        defer { busy = false }
        for index in 0..<100 {
            // Repeatable sequence, alternating large and small jumps.
            let fraction = Double((index * 37) % 100) / 100
            await seek(to: fraction * max(0, duration - 1.0 / 30))
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        message = "Logged 100 seek completions. Display latency still needs Instruments."
    }

    func capture() {
        guard canRender, camera.ready, project.clips.count < 2 else { return }
        busy = true
        player.pause()
        previewRevision = nil
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).mov")
        probe.record("captureRequested", ["lensID": camera.selectedLens])
        camera.record(to: url) { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                self.busy = false
                switch result {
                case .success(let url):
                    self.probe.record("captureFinished")
                    await self.importMedia(url, music: false)
                    try? FileManager.default.removeItem(at: url)
                case .failure(let error): self.fail(error)
                }
            }
        }
    }

    func export() async {
        guard canRender else { return }
        busy = true
        exporting = true
        cancelled = false
        exportURL = nil
        exportProgress = 0
        let name = UUID().uuidString
        let partial = Self.root.appendingPathComponent("Exports/\(name).partial.mp4")
        let final = Self.root.appendingPathComponent("Exports/\(name).mp4")
        var revision = project.revision
        let started = ProcessInfo.processInfo.systemUptime
        defer {
            exportTimer?.invalidate()
            exportTimer = nil
            exportSession = nil
            busy = false
            exporting = false
            if backgroundTask != .invalid {
                UIApplication.shared.endBackgroundTask(backgroundTask)
                backgroundTask = .invalid
            }
        }
        do {
            await camera.stop()
            player.pause()
            try project.validate(forRender: true)
            try await store.requireSpace(bytes: 1024 * 1024 * 1024)
            try await commit(project)
            revision = project.revision
            try writeMarker(.init(state: "running", revision: revision, output: nil, detail: ""))
            backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Bounded export") { [weak self] in
                Task { @MainActor in
                    self?.probe.record("backgroundTimeExpired")
                    self?.cancelExport(reason: "Finite background execution expired")
                }
            }
            let plan = try await MediaEngine.build(project, media: media, exporting: true)
            guard !cancelled else { throw CancellationError() }
            guard let session = AVAssetExportSession(asset: plan.composition,
                                                      presetName: AVAssetExportPresetHighestQuality) else {
                throw ExperimentError.invalid("No compatible export session.")
            }
            guard session.supportedFileTypes.contains(.mp4) else {
                throw ExperimentError.invalid("MP4 export unsupported for this composition.")
            }
            session.outputURL = partial
            session.outputFileType = .mp4
            session.videoComposition = plan.video
            session.audioMix = plan.audio
            session.timeRange = CMTimeRange(start: .zero, duration: plan.duration)
            session.shouldOptimizeForNetworkUse = false
            exportSession = session
            exportTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.exportProgress = session.progress }
            }
            probe.record("exportStart", ["revision": revision, "durationSeconds": plan.duration.seconds])
            await withCheckedContinuation { continuation in
                session.exportAsynchronously { continuation.resume() }
            }
            guard session.status == .completed && !cancelled else {
                throw session.error ?? ExperimentError.invalid("Export cancelled or failed; no successful output published.")
            }
            try await MediaEngine.verifyExport(partial, expected: plan.duration)
            guard !cancelled else { throw CancellationError() }
            try FileManager.default.moveItem(at: partial, to: final)
            try writeMarker(.init(state: "completed", revision: revision,
                                  output: final.lastPathComponent, detail: "Metadata checked; full decode pending"))
            exportURL = final
            exportProgress = 1
            message = "Export revision \(revision) finished. Dimensions/duration checked; independent decode and A/V checks still required."
            probe.record("exportCompleted", [
                "revision": revision, "wallSeconds": ProcessInfo.processInfo.systemUptime - started,
                "output": final.lastPathComponent, "verification": "metadata only"
            ])
        } catch {
            try? FileManager.default.removeItem(at: partial)
            let state = cancelled ? "cancelled" : "failed"
            do {
                try writeMarker(.init(state: state, revision: revision, output: nil,
                                      detail: error.localizedDescription))
            } catch { probe.record("exportMarkerFailure", ["error": error.localizedDescription]) }
            fail(error)
            probe.record("exportEnded", ["state": state, "wallSeconds": ProcessInfo.processInfo.systemUptime - started])
        }
    }

    func cancelExport(reason: String = "User cancellation") {
        cancelled = true
        exportSession?.cancelExport()
        probe.record("exportCancelRequested", ["reason": reason])
    }

    func sceneChanged(_ phase: ScenePhase) {
        probe.record("scenePhase", ["phase": String(describing: phase)])
        if phase != .active {
            player.pause()
            if camera.recording { camera.stopRecording() }
            probe.flush()
        }
    }

    private func fail(_ error: Error) {
        message = error.localizedDescription
        probe.record("error", ["message": message])
    }

    private func writeMarker(_ value: ExportMarker) throws {
        try JSONEncoder().encode(value).write(to: exportMarker, options: .atomic)
    }
}

private struct ExportMarker: Codable {
    let state: String
    let revision: Int
    let output: String?
    let detail: String
}
