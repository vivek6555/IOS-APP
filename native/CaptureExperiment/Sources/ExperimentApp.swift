import SwiftUI
import AVFoundation
import UniformTypeIdentifiers

@main
struct ExperimentApp: App {
    @StateObject private var model = ExperimentModel()
    @Environment(\.scenePhase) private var scenePhase
    var body: some Scene {
        WindowGroup {
            ExperimentView(model: model)
                .task { await model.open() }
                .onChange(of: scenePhase) { _, phase in model.sceneChanged(phase) }
        }
    }
}

struct ExperimentView: View {
    @ObservedObject var model: ExperimentModel
    @State private var importing = false
    @State private var importingMusic = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Experiment status — not a production app") {
                    Text(model.message).textSelection(.enabled)
                    if let warning = model.recoveryWarning {
                        Text(warning).foregroundStyle(.red).textSelection(.enabled)
                    }
                    Text("Revision \(model.project.revision) · \(model.dirty ? "Unsaved edits" : "Saved state")")
                    Text("Two clips · max 60s · portrait 1080p30 SDR")
                    Text("This is a source harness, not evidence of device performance.")
                        .font(.caption)
                }
                Section("1. Capture a clip") {
                    CameraControls(model: model, camera: model.camera)
                }
                Section("2. Import and edit") {
                    Button("Import video from Files") {
                        importingMusic = false
                        importing = true
                    }.disabled(!model.canRender || model.project.clips.count == 2)
                    ForEach(Array(model.project.clips.enumerated()), id: \.element.id) { index, clip in
                        VStack(alignment: .leading) {
                            Text("Clip \(index + 1) · \(clip.file.prefix(8))")
                            Text("Source: \(Double(clip.sourceTicks) / 600, specifier: "%.2f")s")
                                .font(.caption)
                            HStack {
                                Text("Start frame")
                                TextField("Start frame", value: frameBinding(index, start: true), format: .number)
                                    .keyboardType(.numbersAndPunctuation)
                            }
                            HStack {
                                Text("Length in frames")
                                TextField("Length", value: frameBinding(index, start: false), format: .number)
                                    .keyboardType(.numbersAndPunctuation)
                            }
                            Button("Remove clip \(index + 1)", role: .destructive) {
                                model.project.clips.remove(at: index)
                            }
                        }
                    }
                    Button("Swap clip order") { model.project.clips.swapAt(0, 1) }
                        .disabled(model.project.clips.count != 2)
                    Text("Trim uses 30 fps frames: 900 frames = 30 seconds. Draft edits require Save.")
                        .font(.caption)
                    TextField("Title (80 characters maximum)", text: $model.project.title)
                    Button(model.project.music == nil ? "Import music from Files" : "Replace music") {
                        importingMusic = true
                        importing = true
                    }
                    if model.project.music != nil {
                        Button("Remove music", role: .destructive) { model.project.music = nil }
                    }
                    Text("Source gain \(model.project.sourceGain, specifier: "%.2f")")
                    Slider(value: $model.project.sourceGain, in: 0...0.5)
                    Text("Music gain \(model.project.musicGain, specifier: "%.2f")")
                    Slider(value: $model.project.musicGain, in: 0...0.5)
                    Text("Music must cover the whole timeline. Originals are retained when removed.")
                        .font(.caption)
                    Button("Save edits") { Task { await model.save() } }
                }.disabled(!model.canRender)
                Section("3. Preview and seek") {
                    Button("Save + prepare native preview") { Task { await model.preparePreview() } }
                        .disabled(!model.canRender)
                    if model.previewRevision == model.project.revision {
                        PlayerSurface(player: model.player, title: model.project.title)
                            .aspectRatio(9.0 / 16, contentMode: .fit)
                            .frame(maxHeight: 350)
                        Button("Play / pause") { model.playPause() }.disabled(model.busy)
                        Slider(value: $model.seekSeconds, in: 0...max(model.duration, 0.01)) { editing in
                            if !editing { Task { await model.seek(to: model.seekSeconds) } }
                        }.disabled(model.busy)
                        Button("Run 100 seek-completion probes") { Task { await model.runSeeks() } }
                            .disabled(model.busy)
                        Text("Seek completion is not displayed-frame latency. Use Instruments for playback and display measurements.")
                            .font(.caption)
                    }
                }
                Section("4. Export and collect evidence") {
                    Button("Save + export 1080×1920 MP4") { Task { await model.export() } }
                        .disabled(!model.canRender)
                    if model.exporting {
                        ProgressView(value: model.exportProgress)
                        Button("Cancel export", role: .destructive) { model.cancelExport() }
                    }
                    if let url = model.exportURL {
                        ShareLink("Share last completed export", item: url)
                    }
                    ShareLink("Share current measurement log", item: model.probe.url)
                    ProbeStatus(probe: model.probe)
                    Text("Background export uses finite execution time only. Expiration cancels; it is not resumable or guaranteed to finish.")
                        .font(.caption)
                    Text("Retrieve the full Experiment folder through Finder file sharing or Xcode’s app container download.")
                        .font(.caption)
                }
            }
            .navigationTitle("Capture experiment")
            .fileImporter(isPresented: $importing,
                          allowedContentTypes: importingMusic ? [.audio] : [.movie]) { result in
                switch result {
                case .success(let url):
                    Task { await model.importMedia(url, music: importingMusic) }
                case .failure(let error):
                    model.message = error.localizedDescription
                }
            }
        }
    }

    private func frameBinding(_ index: Int, start: Bool) -> Binding<Int64> {
        Binding {
            guard model.project.clips.indices.contains(index) else { return 0 }
            let clip = model.project.clips[index]
            return (start ? clip.startTicks : clip.durationTicks) / 20
        } set: { value in
            guard model.project.clips.indices.contains(index),
                  (-18_000...18_000).contains(value) else { return }
            if start { model.project.clips[index].startTicks = value * 20 }
            else { model.project.clips[index].durationTicks = value * 20 }
        }
    }
}

private struct ProbeStatus: View {
    @ObservedObject var probe: Probe
    var body: some View {
        if !probe.latest.isEmpty { Text(probe.latest).foregroundStyle(.red) }
    }
}

private struct CameraControls: View {
    @ObservedObject var model: ExperimentModel
    @ObservedObject var camera: Camera
    @State private var focus: Float = 0.5
    @State private var iso: Float = 100
    @State private var shutter = 1.0 / 60
    var body: some View {
        Text(camera.message)
        Picker("Lens", selection: $camera.selectedLens) {
            ForEach(camera.lenses, id: \.uniqueID) { lens in
                Text(lens.localizedName).tag(lens.uniqueID)
            }
        }.disabled(camera.ready || camera.recording || camera.starting || model.busy || model.exporting)
        if camera.ready {
            CameraSurface(camera: camera).frame(height: 220).clipped()
            if camera.canFocus {
                Text("Manual focus")
                Slider(value: $focus, in: 0...1)
            }
            if camera.canExpose {
                Text("ISO \(iso, specifier: "%.0f")")
                Slider(value: $iso, in: camera.isoBounds)
                Text("Shutter \(shutter, specifier: "%.5f") seconds")
                Slider(value: $shutter, in: camera.shutterBounds)
            }
            Button("Apply supported manual controls") {
                camera.apply(focus: focus, iso: iso, shutter: shutter)
                model.probe.record("manualControlRequest", [
                    "focus": focus, "iso": iso, "shutterSeconds": shutter,
                    "focusSupported": camera.canFocus, "exposureSupported": camera.canExpose
                ])
            }.disabled(model.exporting)
            if camera.recording {
                Button("Stop recording") { camera.stopRecording() }
            } else {
                Button("Record up to 30 seconds") { model.capture() }
                    .disabled(model.busy || model.exporting || model.project.clips.count >= 2)
                Button("Stop camera / change lens") { Task { await camera.stop() } }
                    .disabled(model.busy || model.exporting)
            }
        } else {
            Button("Start camera") {
                model.player.pause()
                model.previewRevision = nil
                camera.start()
            }.disabled(model.busy || model.exporting || camera.starting || !model.recovered)
        }
    }
}

struct PlayerSurface: UIViewRepresentable {
    let player: AVPlayer
    let title: String
    final class Surface: UIView {
        let picture = AVPlayerLayer()
        let titleCanvas = CALayer()
        override init(frame: CGRect) {
            super.init(frame: frame)
            layer.addSublayer(picture)
            layer.addSublayer(titleCanvas)
            backgroundColor = .black
            picture.videoGravity = .resizeAspect
            titleCanvas.anchorPoint = .zero
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
        override func layoutSubviews() {
            super.layoutSubviews()
            picture.frame = bounds
            let scale = min(bounds.width / 1080, bounds.height / 1920)
            titleCanvas.bounds = CGRect(x: 0, y: 0, width: 1080, height: 1920)
            titleCanvas.position = CGPoint(x: (bounds.width - 1080 * scale) / 2,
                                           y: (bounds.height - 1920 * scale) / 2)
            titleCanvas.setAffineTransform(CGAffineTransform(scaleX: scale, y: scale))
        }
    }
    func makeUIView(context: Context) -> Surface { Surface() }
    func updateUIView(_ view: Surface, context: Context) {
        view.picture.player = player
        view.titleCanvas.sublayers?.forEach { $0.removeFromSuperlayer() }
        if !title.isEmpty { view.titleCanvas.addSublayer(TitleLayer.make(title)) }
    }
}
