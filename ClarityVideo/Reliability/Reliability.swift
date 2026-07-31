import Foundation
import UIKit

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
    func remove(_ id: UUID) throws {
        try? FileManager.default.removeItem(at: folder.appendingPathComponent(id.uuidString + ".json"))
    }
}
