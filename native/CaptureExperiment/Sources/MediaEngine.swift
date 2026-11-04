import AVFoundation
import UIKit
import CoreText

struct RenderPlan {
    let composition: AVMutableComposition
    let video: AVMutableVideoComposition
    let audio: AVMutableAudioMix
    let duration: CMTime
}

/// AVFoundation owns all frames, clocks, compositing and encoding.
/// A fresh immutable plan is built for each preview/export revision.
enum MediaEngine {
    static func time(_ ticks: Int64) -> CMTime {
        CMTime(value: ticks, timescale: EditProject.timescale)
    }

    static func inspectVideo(_ url: URL) async throws -> Int64 {
        let asset = AVURLAsset(url: url)
        guard try await asset.load(.isReadable),
              let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw ExperimentError.invalid("Unreadable video or no video track.")
        }
        guard !(try await track.load(.mediaCharacteristics)).contains(.containsHDRVideo) else {
            throw ExperimentError.invalid("HDR is outside this SDR experiment. Use an SDR source; no silent tone mapping.")
        }
        let duration = try await asset.load(.duration)
        guard duration.isNumeric, duration.seconds > 0, duration.seconds <= 600 else {
            throw ExperimentError.invalid("Source must have a finite duration of at most 10 minutes.")
        }
        return Int64((duration.seconds * 30).rounded(.down)) * 20
    }

    static func build(_ project: EditProject, media: URL, exporting: Bool) async throws -> RenderPlan {
        try project.validate(forRender: true)
        let composition = AVMutableComposition()
        guard let videoTrack = composition.addMutableTrack(withMediaType: .video,
                                                           preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw ExperimentError.invalid("Cannot allocate video track.")
        }
        var instructions: [AVMutableVideoCompositionInstruction] = []
        var mix: [AVMutableAudioMixInputParameters] = []
        var cursor = CMTime.zero
        let canvas = CGSize(width: 1080, height: 1920)

        for clip in project.clips {
            let url = media.appendingPathComponent(clip.file)
            let sourceTicks = try await inspectVideo(url)
            guard clip.startTicks + clip.durationTicks <= sourceTicks else {
                throw ExperimentError.invalid("Trim exceeds the current media duration.")
            }
            let asset = AVURLAsset(url: url)
            guard let source = try await asset.loadTracks(withMediaType: .video).first else {
                throw ExperimentError.invalid("Missing video track.")
            }
            let range = CMTimeRange(start: time(clip.startTicks), duration: time(clip.durationTicks))
            try videoTrack.insertTimeRange(range, of: source, at: cursor)
            let size = try await source.load(.naturalSize)
            let preferred = try await source.load(.preferredTransform)
            let oriented = CGRect(origin: .zero, size: size).applying(preferred)
            guard oriented.width > 0, oriented.height > 0 else {
                throw ExperimentError.invalid("Invalid video dimensions.")
            }
            // Normalize rotated source bounds, aspect-fill, then center-crop.
            let scale = max(canvas.width / oriented.width, canvas.height / oriented.height)
            let transform = preferred
                .concatenating(CGAffineTransform(translationX: -oriented.minX, y: -oriented.minY))
                .concatenating(CGAffineTransform(scaleX: scale, y: scale))
                .concatenating(CGAffineTransform(
                    translationX: (canvas.width - oriented.width * scale) / 2,
                    y: (canvas.height - oriented.height * scale) / 2))
            let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: videoTrack)
            layer.setTransform(transform, at: cursor)
            let instruction = AVMutableVideoCompositionInstruction()
            instruction.timeRange = CMTimeRange(start: cursor, duration: range.duration)
            instruction.layerInstructions = [layer]
            instructions.append(instruction)

            if let audio = try await asset.loadTracks(withMediaType: .audio).first {
                let available = try await audio.load(.timeRange)
                let overlap = range.intersection(available)
                if overlap.isValid && overlap.duration > .zero {
                    guard let destination = composition.addMutableTrack(
                        withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
                        throw ExperimentError.invalid("Cannot allocate source audio track.")
                    }
                    let offset = CMTimeSubtract(overlap.start, range.start)
                    try destination.insertTimeRange(overlap, of: audio, at: CMTimeAdd(cursor, offset))
                    let parameters = AVMutableAudioMixInputParameters(track: destination)
                    parameters.setVolume(project.sourceGain, at: .zero)
                    mix.append(parameters)
                }
            }
            cursor = CMTimeAdd(cursor, range.duration)
        }

        if let music = project.music {
            let asset = AVURLAsset(url: media.appendingPathComponent(music))
            guard let source = try await asset.loadTracks(withMediaType: .audio).first,
                  let destination = composition.addMutableTrack(
                    withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
                throw ExperimentError.invalid("Music is missing or contains no audio.")
            }
            let available = try await source.load(.timeRange)
            guard available.duration >= cursor else {
                throw ExperimentError.invalid("Music must cover the whole project; this harness does not loop or pad it.")
            }
            try destination.insertTimeRange(CMTimeRange(start: available.start, duration: cursor),
                                            of: source, at: .zero)
            let parameters = AVMutableAudioMixInputParameters(track: destination)
            parameters.setVolume(project.musicGain, at: .zero)
            mix.append(parameters)
        }

        let video = AVMutableVideoComposition()
        video.renderSize = canvas
        video.frameDuration = CMTime(value: 1, timescale: 30)
        video.instructions = instructions
        video.colorPrimaries = AVVideoColorPrimaries_ITU_R_709_2
        video.colorTransferFunction = AVVideoTransferFunction_ITU_R_709_2
        video.colorYCbCrMatrix = AVVideoYCbCrMatrix_ITU_R_709_2
        if exporting && !project.title.isEmpty {
            let parent = CALayer()
            parent.frame = CGRect(origin: .zero, size: canvas)
            let picture = CALayer()
            picture.frame = parent.bounds
            parent.addSublayer(picture)
            parent.addSublayer(TitleLayer.make(project.title))
            video.animationTool = AVVideoCompositionCoreAnimationTool(
                postProcessingAsVideoLayer: picture, in: parent)
        }
        let audio = AVMutableAudioMix()
        audio.inputParameters = mix
        return RenderPlan(composition: composition, video: video, audio: audio, duration: cursor)
    }

    static func verifyExport(_ url: URL, expected: CMTime) async throws {
        let asset = AVURLAsset(url: url)
        guard try await asset.load(.isReadable),
              let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw ExperimentError.invalid("Export has no readable video.")
        }
        let size = try await track.load(.naturalSize)
        let duration = try await asset.load(.duration)
        guard size == CGSize(width: 1080, height: 1920),
              abs(duration.seconds - expected.seconds) <= 1.0 / 30.0 + 0.001 else {
            throw ExperimentError.invalid("Export duration or dimensions failed verification.")
        }
        // Metadata checks only. Full decode/A-V offset are independent Mac checks.
    }
}

enum TitleLayer {
    static func make(_ title: String) -> CATextLayer {
        let layer = CATextLayer()
        layer.string = title
        layer.font = CTFontCreateWithName("Helvetica-Bold" as CFString, 48, nil)
        layer.fontSize = 48
        layer.foregroundColor = UIColor.white.cgColor
        layer.backgroundColor = UIColor.black.withAlphaComponent(0.65).cgColor
        layer.alignmentMode = .center
        layer.isWrapped = true
        layer.contentsScale = 1
        // Centered in both coordinate conventions (Core Animation export vs UIKit).
        layer.frame = CGRect(x: 60, y: 860, width: 960, height: 200)
        return layer
    }
}