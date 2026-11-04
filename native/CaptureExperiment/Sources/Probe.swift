import Foundation
import UIKit
import Darwin
import os

@MainActor
final class Probe: ObservableObject {
    @Published var latest = ""
    let url: URL
    private let logger = Logger(subsystem: "studio.capture.experiment", category: "measurements")
    private var timer: Timer?
    private var handle: FileHandle?
    private var peakBytes: UInt64 = 0
    private let start = ProcessInfo.processInfo.systemUptime

    init(root: URL) {
        url = root.appendingPathComponent("Logs/\(UUID().uuidString).jsonl")
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            guard FileManager.default.createFile(atPath: url.path, contents: nil) else {
                throw ExperimentError.invalid("Could not create measurement log.")
            }
            handle = try FileHandle(forWritingTo: url)
        } catch { latest = "Log failure: \(error.localizedDescription)" }
        UIDevice.current.isBatteryMonitoringEnabled = true
        record("session", [
            "os": ProcessInfo.processInfo.operatingSystemVersionString,
            "hardware": Self.hardware(),
            "appVersion": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "",
            "build": Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "",
            "note": "1 Hz physical footprint samples are not Instruments peak allocation measurements."
        ])
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.sample() }
        }
    }

    func record(_ event: String, _ fields: [String: Any] = [:]) {
        var row = fields
        row["event"] = event
        row["utc"] = ISO8601DateFormatter().string(from: Date())
        row["elapsedSeconds"] = ProcessInfo.processInfo.systemUptime - start
        do {
            var data = try JSONSerialization.data(withJSONObject: row, options: [.sortedKeys])
            data.append(0x0A)
            guard let handle else { throw ExperimentError.invalid("Log unavailable") }
            try handle.write(contentsOf: data)
            try handle.synchronize()
            logger.info("\(event, privacy: .public)")
        } catch {
            latest = "Measurement log failed: \(error.localizedDescription)"
        }
    }

    func sample() {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        var fields: [String: Any] = [
            "thermalState": ProcessInfo.processInfo.thermalState.rawValue,
            "batteryLevel": UIDevice.current.batteryLevel,
            "batteryState": UIDevice.current.batteryState.rawValue,
            "appState": UIApplication.shared.applicationState.rawValue
        ]
        if result == KERN_SUCCESS {
            peakBytes = max(peakBytes, info.phys_footprint)
            fields["physicalFootprintBytes"] = info.phys_footprint
            fields["sampledPeakBytes"] = peakBytes
        } else { fields["memorySamplingError"] = result }
        record("resourceSample", fields)
    }

    func flush() { try? handle?.synchronize() }

    private static func hardware() -> String {
        var system = utsname()
        uname(&system)
        let capacity = MemoryLayout.size(ofValue: system.machine)
        return withUnsafePointer(to: &system.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: capacity) {
                String(cString: $0)
            }
        }
    }
}
