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
