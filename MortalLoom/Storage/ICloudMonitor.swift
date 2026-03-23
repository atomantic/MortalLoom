import Foundation

/// Watches for iCloud file changes and reloads DataStore when the remote file updates.
@MainActor
final class ICloudMonitor {
    static let shared = ICloudMonitor()

    private var query: NSMetadataQuery?

    func start() {
        guard query == nil else { return }

        let q = NSMetadataQuery()
        q.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope]
        q.predicate = NSPredicate(format: "%K == %@", NSMetadataItemFSNameKey, "MortalLoom.json")

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(queryDidUpdate),
            name: .NSMetadataQueryDidUpdate,
            object: q
        )

        q.start()
        query = q
    }

    func stop() {
        query?.stop()
        query = nil
    }

    @objc private func queryDidUpdate() {
        Task {
            let didChange = await DataStore.shared.reloadIfNeeded()
            if didChange {
                NotificationCenter.default.post(name: .dataDidSync, object: nil)
                NotificationCenter.default.post(name: .profileDidChange, object: nil)
            }
        }
    }
}
