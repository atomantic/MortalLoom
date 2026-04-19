import Foundation
import os
#if os(iOS)
import UIKit
#else
import AppKit
#endif

private let logger = Logger(subsystem: "net.shadowpuppet.MeatSpaceTracker", category: "iCloud")

/// Watches for iCloud file changes and reloads DataStore when the remote file updates.
@MainActor @Observable
final class ICloudMonitor {
    static let shared = ICloudMonitor()

    private var query: NSMetadataQuery?
    private var debounceTask: Task<Void, Never>?
    private var lastWriteDate = Date.distantPast

    private let debounceInterval: TimeInterval = 2.0
    private let writeSuppressionWindow: TimeInterval = 5.0

    private(set) var isSyncing = false
    private(set) var isICloud = false

    private init() {}

    func start() {
        guard query == nil else { return }

        isICloud = FileManager.default.url(forUbiquityContainerIdentifier: CloudConfig.containerID) != nil

        let q = NSMetadataQuery()
        q.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope]
        q.predicate = NSPredicate(format: "%K == %@", NSMetadataItemFSNameKey, "MortalLoom.json")

        NotificationCenter.default.addObserver(
            self, selector: #selector(queryDidFinishGathering),
            name: .NSMetadataQueryDidFinishGathering, object: q
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(queryDidUpdate),
            name: .NSMetadataQueryDidUpdate, object: q
        )
        // Proactive sync when app returns to foreground — covers the case where
        // NSMetadataQuery notifications were missed while the app was sleeping.
        #if os(iOS)
        NotificationCenter.default.addObserver(
            self, selector: #selector(appDidEnterForeground),
            name: UIApplication.willEnterForegroundNotification, object: nil
        )
        #else
        NotificationCenter.default.addObserver(
            self, selector: #selector(appDidEnterForeground),
            name: NSApplication.willBecomeActiveNotification, object: nil
        )
        #endif

        q.start()
        query = q
        logger.info("☁️ iCloud monitor started, isICloud=\(self.isICloud, privacy: .public)")
    }

    func stop() {
        query?.stop()
        query = nil
        debounceTask?.cancel()
        NotificationCenter.default.removeObserver(self)
    }

    /// Manual sync — force reload from iCloud.
    func syncNow() async {
        logger.info("☁️ manual sync triggered")
        isSyncing = true
        await applyReloadIfNeeded()
        isSyncing = false
    }

    /// Call after local writes to suppress reload from our own iCloud changes.
    func markLocalWrite() {
        lastWriteDate = Date()
    }

    @objc private func queryDidFinishGathering(_ notification: Notification) {
        query?.enableUpdates()
        logger.info("☁️ initial iCloud gather complete")
        // Trigger an initial reload in case the cloud file is newer than local.
        // This covers the case where the app was reinstalled or updated and the
        // iCloud file has data that wasn't available when DataStore.load() ran.
        Task { @MainActor in
            await applyReloadIfNeeded()
        }
    }

    @objc private func queryDidUpdate(_ notification: Notification) {
        logger.info("☁️ iCloud file changed, scheduling reload")
        scheduleReload()
    }

    @objc private func appDidEnterForeground(_ notification: Notification) {
        logger.info("☁️ app foregrounded — scheduling proactive iCloud sync")
        scheduleReload()
    }

    private func scheduleReload() {
        debounceTask?.cancel()
        debounceTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(debounceInterval))
            guard !Task.isCancelled else { return }

            let sinceLastWrite = Date().timeIntervalSince(lastWriteDate)
            guard sinceLastWrite > writeSuppressionWindow else {
                logger.debug("☁️ skipping reload, local write was \(sinceLastWrite, format: .fixed(precision: 1))s ago")
                return
            }

            isSyncing = true
            await applyReloadIfNeeded()
            isSyncing = false
        }
    }

    private func applyReloadIfNeeded() async {
        let didChange = await DataStore.shared.reloadIfNeeded()
        if didChange {
            NotificationCenter.default.post(name: .dataDidSync, object: nil)
            NotificationCenter.default.post(name: .profileDidChange, object: nil)
            logger.info("☁️ sync: data updated from iCloud")
        }
    }
}
