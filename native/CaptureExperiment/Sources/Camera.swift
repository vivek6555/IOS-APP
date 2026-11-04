import AVFoundation
import SwiftUI

final class Camera: NSObject, ObservableObject, AVCaptureFileOutputRecordingDelegate {
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "studio.capture.session", qos: .userInitiated)
    private let output = AVCaptureMovieFileOutput()
    private var device: AVCaptureDevice?
    private var configured = false
    private var completion: ((Result<URL, Error>) -> Void)?
    var onEvent: ((String, [String: Any]) -> Void)?
    @Published var ready = false
    @Published var starting = false
    @Published var recording = false
    @Published var message = "Camera has not started."
    @Published var canFocus = false
    @Published var canExpose = false
    @Published var isoBounds: ClosedRange<Float> = 25...100
    @Published var shutterBounds: ClosedRange<Double> = 0.001...0.03
    @Published var lenses: [AVCaptureDevice] = []
    @Published var selectedLens = ""

    func discover() {
        lenses = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .builtInUltraWideCamera, .builtInTelephotoCamera],
            mediaType: .video, position: .back).devices
        if selectedLens.isEmpty { selectedLens = lenses.first?.uniqueID ?? "" }
    }

    func start() {
        guard !starting else { return }
        guard ProcessInfo.processInfo.thermalState.rawValue < ProcessInfo.ThermalState.serious.rawValue else {
            message = "Camera blocked by serious/critical thermal state. Let the phone cool."
            return
        }
        starting = true
        let id = selectedLens
        Task {
            let video = await AVCaptureDevice.requestAccess(for: .video)
            let audio = await AVCaptureDevice.requestAccess(for: .audio)
            guard video && audio else {
                await MainActor.run {
                    self.starting = false
                    self.message = "Camera and microphone permissions are required. Enable them in Settings."
                }
                return
            }
            queue.async {
                do {
                    try self.configure(id: id)
                    self.session.startRunning()
                    DispatchQueue.main.async {
                        self.starting = false
                        self.ready = true
                        self.message = "1080p30 SDR camera ready."
                    }
                } catch {
                    DispatchQueue.main.async {
                        self.starting = false
                        self.ready = false
                        self.message = error.localizedDescription
                    }
                }
            }
        }
    }

    private func configure(id: String) throws {
        if configured { return }
        guard let camera = AVCaptureDevice(uniqueID: id),
              let microphone = AVCaptureDevice.default(for: .audio) else {
            throw ExperimentError.invalid("Selected camera or microphone unavailable.")
        }
        // Deliberately restrict capture to a discovered SDR 1080p30 format.
        guard let format = camera.formats.first(where: {
            let dimensions = CMVideoFormatDescriptionGetDimensions($0.formatDescription)
            let subtype = CMFormatDescriptionGetMediaSubType($0.formatDescription)
            return dimensions.width == 1920 && dimensions.height == 1080 &&
                subtype == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange &&
                $0.videoSupportedFrameRateRanges.contains { $0.minFrameRate <= 30 && $0.maxFrameRate >= 30 }
        }) else {
            throw ExperimentError.invalid("This lens exposes no supported 8-bit 1080p30 format.")
        }
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .inputPriority
        for input in session.inputs { session.removeInput(input) }
        let cameraInput = try AVCaptureDeviceInput(device: camera)
        let audioInput = try AVCaptureDeviceInput(device: microphone)
        guard session.canAddInput(cameraInput), session.canAddInput(audioInput) else {
            throw ExperimentError.invalid("Cannot attach capture inputs.")
        }
        session.addInput(cameraInput)
        session.addInput(audioInput)
        if !session.outputs.contains(output) {
            guard session.canAddOutput(output) else {
                throw ExperimentError.invalid("Movie output unavailable.")
            }
            session.addOutput(output)
        }
        try camera.lockForConfiguration()
        camera.activeFormat = format
        camera.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 30)
        camera.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: 30)
        camera.automaticallyAdjustsVideoHDREnabled = false
        camera.isVideoHDREnabled = false
        camera.unlockForConfiguration()
        if let connection = output.connection(with: .video) {
            if connection.isVideoRotationAngleSupported(90) { connection.videoRotationAngle = 90 }
            if connection.isVideoStabilizationSupported { connection.preferredVideoStabilizationMode = .off }
            if output.availableVideoCodecTypes.contains(.h264) {
                output.setOutputSettings([AVVideoCodecKey: AVVideoCodecType.h264], for: connection)
            } else { throw ExperimentError.invalid("H.264 capture is unavailable.") }
        }
        output.maxRecordedDuration = CMTime(seconds: 30, preferredTimescale: 600)
        output.minFreeDiskSpaceLimit = 256 * 1024 * 1024
        device = camera
        configured = true
        onEvent?("captureConfigured", [
            "lensID": camera.uniqueID,
            "lensName": camera.localizedName,
            "width": 1920, "height": 1080,
            "frameDurationSeconds": camera.activeVideoMinFrameDuration.seconds,
            "hdrEnabled": camera.isVideoHDREnabled,
            "manualFocusSupported": camera.isLockingFocusWithCustomLensPositionSupported,
            "manualExposureSupported": camera.isExposureModeSupported(.custom),
            "minISO": format.minISO, "maxISO": format.maxISO,
            "minExposureSeconds": format.minExposureDuration.seconds,
            "maxExposureSeconds": min(format.maxExposureDuration.seconds, 1.0 / 30)
        ])
        DispatchQueue.main.async {
            self.canFocus = camera.isLockingFocusWithCustomLensPositionSupported
            self.canExpose = camera.isExposureModeSupported(.custom)
            self.isoBounds = format.minISO...format.maxISO
            self.shutterBounds = max(format.minExposureDuration.seconds, 0.00001)...min(format.maxExposureDuration.seconds, 1.0 / 30)
            self.message = "Applied \(camera.localizedName): 1920×1080, 30 fps, H.264 SDR."
        }
    }

    func apply(focus: Float, iso: Float, shutter: Double) {
        queue.async {
            guard let device = self.device else { return }
            do {
                try device.lockForConfiguration()
                defer { device.unlockForConfiguration() }
                if device.isLockingFocusWithCustomLensPositionSupported {
                    device.setFocusModeLocked(lensPosition: max(0, min(1, focus))) { _ in
                        self.onEvent?("focusApplied", ["lensPosition": device.lensPosition])
                    }
                }
                if device.isExposureModeSupported(.custom) {
                    let format = device.activeFormat
                    let boundedISO = max(format.minISO, min(format.maxISO, iso))
                    let boundedShutter = max(format.minExposureDuration.seconds,
                                             min(format.maxExposureDuration.seconds, min(shutter, 1.0 / 30)))
                    device.setExposureModeCustom(
                        duration: CMTime(seconds: boundedShutter, preferredTimescale: 1_000_000),
                        iso: boundedISO) { _ in
                            self.onEvent?("exposureApplied", [
                                "iso": device.iso,
                                "shutterSeconds": device.exposureDuration.seconds,
                                "lensPosition": device.lensPosition
                            ])
                            DispatchQueue.main.async {
                                self.message = "Applied ISO \(device.iso), shutter \(device.exposureDuration.seconds)s, focus \(device.lensPosition)."
                            }
                        }
                }
            } catch { DispatchQueue.main.async { self.message = error.localizedDescription } }
        }
    }

    func record(to url: URL, completion: @escaping (Result<URL, Error>) -> Void) {
        queue.async {
            guard self.session.isRunning, !self.output.isRecording else {
                DispatchQueue.main.async { completion(.failure(ExperimentError.invalid("Camera is not ready."))) }
                return
            }
            self.completion = completion
            self.output.startRecording(to: url, recordingDelegate: self)
        }
    }

    func stopRecording() { queue.async { if self.output.isRecording { self.output.stopRecording() } } }

    func stop() async {
        await withCheckedContinuation { continuation in
            queue.async {
                if self.output.isRecording { self.output.stopRecording() }
                self.session.stopRunning()
                self.configured = false
                DispatchQueue.main.async { self.ready = false }
                continuation.resume()
            }
        }
    }

    func fileOutput(_ output: AVCaptureFileOutput, didStartRecordingTo fileURL: URL,
                    from connections: [AVCaptureConnection]) {
        DispatchQueue.main.async { self.recording = true; self.message = "Recording (30-second maximum)." }
    }

    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo url: URL,
                    from connections: [AVCaptureConnection], error: Error?) {
        queue.async {
            let callback = self.completion
            self.completion = nil
            let nsError = error as NSError?
            let succeeded = nsError == nil ||
                (nsError?.userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool == true)
            DispatchQueue.main.async {
                self.recording = false
                self.message = succeeded ? "Capture finished; validating media." : (error?.localizedDescription ?? "Capture failed.")
                callback?(succeeded ? .success(url) : .failure(error ?? ExperimentError.invalid("Capture failed.")))
            }
        }
    }
}

struct CameraSurface: UIViewRepresentable {
    let camera: Camera
    final class Surface: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    }
    func makeUIView(context: Context) -> Surface {
        let view = Surface()
        let layer = view.layer as! AVCaptureVideoPreviewLayer
        layer.session = camera.session
        layer.videoGravity = .resizeAspectFill
        return view
    }
    func updateUIView(_ view: Surface, context: Context) {
        let layer = view.layer as! AVCaptureVideoPreviewLayer
        if let connection = layer.connection, connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90
        }
    }
}