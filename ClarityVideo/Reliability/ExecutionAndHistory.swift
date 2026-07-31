import Foundation
import UIKit

@MainActor
final class BackgroundExecutionManager {
    private var identifier: UIBackgroundTaskIdentifier = .invalid

    func begin(expiration: @escaping @MainActor () -> Void) {
        end()
        UIApplication.shared.isIdleTimerDisabled = true
        identifier = UIApplication.shared.beginBackgroundTask(withName: "Finish Clarity checkpoint") { [weak self] in
            Task { @MainActor in
                expiration()
                self?.end()
            }
        }
    }

    func end() {
        UIApplication.shared.isIdleTimerDisabled = false
        guard identifier != .invalid else { return }
        UIApplication.shared.endBackgroundTask(identifier)
        identifier = .invalid
    }
}

enum JobHistoryStore {
    private static var url: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("export-history.json")
    }

    static func load() -> [ProcessingJob] {
        guard let data = try? Data(contentsOf: url),
              let jobs = try? JSONDecoder().decode([ProcessingJob].self, from: data) else { return [] }
        return jobs.filter { job in
            guard job.status == .completed, let outputURL = job.outputURL else { return job.status != .completed }
            return FileManager.default.fileExists(atPath: outputURL.path)
        }
    }

    static func save(_ jobs: [ProcessingJob]) {
        guard let data = try? JSONEncoder().encode(Array(jobs.prefix(50))) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }
}

enum ProcessingCache {
    static var rootURL: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ProcessingJobs", isDirectory: true)
    }

    static func jobFolder(_ id: UUID) throws -> URL {
        let url = rootURL.appendingPathComponent(id.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func clear() throws {
        if FileManager.default.fileExists(atPath: rootURL.path) {
            try FileManager.default.removeItem(at: rootURL)
        }
    }

    static func cleanupExpired(olderThan age: TimeInterval = 7 * 24 * 60 * 60) {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }
        let cutoff = Date().addingTimeInterval(-age)
        for url in urls {
            let modified = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
            if let modified, modified < cutoff { try? FileManager.default.removeItem(at: url) }
        }
    }
}

struct CapabilitySnapshot: Codable, Sendable {
    var generatedAt: Date
    var osVersion: String
    var capabilities: DeviceEnhancementCapabilities
    var lastSuccessfulSelfTest: Date?
}

enum CapabilitySnapshotStore {
    private static var url: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("capability-snapshot.json")
    }

    static func loadForCurrentOS() -> CapabilitySnapshot? {
        guard let data = try? Data(contentsOf: url),
              let snapshot = try? JSONDecoder().decode(CapabilitySnapshot.self, from: data),
              snapshot.osVersion == ProcessInfo.processInfo.operatingSystemVersionString else { return nil }
        return snapshot
    }

    static func save(capabilities: DeviceEnhancementCapabilities, lastSuccessfulSelfTest: Date?) {
        let snapshot = CapabilitySnapshot(
            generatedAt: Date(),
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            capabilities: capabilities,
            lastSuccessfulSelfTest: lastSuccessfulSelfTest
        )
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }
}
