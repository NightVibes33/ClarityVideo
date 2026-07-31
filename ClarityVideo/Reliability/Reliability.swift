import Foundation
import UIKit
import Darwin
enum ProcessMemory {
    static func peakResidentBytes() -> UInt64? {
        var usage = rusage()
        guard getrusage(RUSAGE_SELF, &usage) == 0 else { return nil }
        return UInt64(max(0, usage.ru_maxrss))
    }
}


@MainActor
final class ThermalMonitor {
    private(set) var transitions: [String] = []
    var current: ProcessInfo.ThermalState { ProcessInfo.processInfo.thermalState }
    var mustPause: Bool { current == .critical }
    func record() { transitions.append(String(describing: current)) }
}

actor CheckpointStore {
    private let folder: URL
    init() {
        folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Checkpoints", isDirectory: true)
    }
    func save(_ checkpoint: ProcessingCheckpoint) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(checkpoint)
        try data.write(to: folder.appendingPathComponent(checkpoint.jobID.uuidString + ".json"), options: .atomic)
    }
    func load(_ id: UUID) throws -> ProcessingCheckpoint? {
        let url = folder.appendingPathComponent(id.uuidString + ".json")
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try JSONDecoder().decode(ProcessingCheckpoint.self, from: Data(contentsOf: url))
    }
    func loadCompatible(sourceFingerprint: String, configuration: ExportConfiguration, segmentCount: Int) throws -> ProcessingCheckpoint? {
        guard FileManager.default.fileExists(atPath: folder.path) else { return nil }
        let urls = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
        for url in urls {
            guard let checkpoint = try? JSONDecoder().decode(ProcessingCheckpoint.self, from: Data(contentsOf: url)) else { continue }
            if checkpoint.isCompatible(sourceFingerprint: sourceFingerprint, configuration: configuration, segmentCount: segmentCount) {
                return checkpoint
            }
        }
        return nil
    }

    func remove(_ id: UUID) throws {
        try? FileManager.default.removeItem(at: folder.appendingPathComponent(id.uuidString + ".json"))
    }
}
