//
//  AutoBackupService.swift
//  Menej
//
//  Writes a backup to a folder the user nominated, at most once a day.
//
//  DELIBERATELY NOT "DAILY". The app has no background execution — no
//  BGTaskScheduler, no background modes — so nothing can run while the app is
//  closed. This fires on launch and only if a day has passed, which means: if
//  the user doesn't open the app, no backup is written. `BGProcessingTask`
//  wouldn't honestly fix that either (iOS runs those opportunistically with no
//  timing guarantee), so the UI says "when you open Menej" rather than
//  promising a schedule the app can't keep.
//
//  The destination is a folder the user picks once, held as a security-scoped
//  bookmark. That choice matters:
//
//  - Writing inside the app's own container would look like a backup and not
//    be one. Deleting the app deletes it, and the SwiftData store already sits
//    there and already rides along in the user's iCloud device backup — it
//    would protect against nothing new.
//  - A user-nominated folder survives app deletion, needs no iCloud
//    entitlement, and keeps the app's privacy promise intact: the app isn't
//    transmitting anything, the user chose where their own data goes.
//

import Foundation
import SwiftData

@MainActor
struct AutoBackupService {
    /// A day between runs. Checked against wall-clock time rather than a
    /// calendar day so a launch at 23:55 followed by one at 00:05 doesn't
    /// count as two days.
    static let minimumInterval: TimeInterval = 24 * 60 * 60

    /// How many dated files to keep. Enough history to recover from a mistake
    /// noticed a few days late, bounded so the folder can't grow forever —
    /// each file carries inventory photos as base64.
    static let keepCount = 7

    private let backupService: BackupServiceProtocol

    init(backupService: BackupServiceProtocol? = nil) {
        self.backupService = backupService ?? BackupService()
    }

    // MARK: - Destination

    private enum Keys {
        static let bookmark = "autoBackupBookmark"
        static let lastRun = "autoBackupLastRunAt"
        static let destinationName = "autoBackupDestinationName"
    }

    /// Auto-backup is on exactly when a destination is set. No separate
    /// toggle: a switch that can be on with nowhere to write is a state that
    /// only ever confuses.
    static var isEnabled: Bool { UserDefaults.standard.data(forKey: Keys.bookmark) != nil }

    static var destinationName: String? {
        UserDefaults.standard.string(forKey: Keys.destinationName)
    }

    static var lastRunAt: Date? {
        UserDefaults.standard.object(forKey: Keys.lastRun) as? Date
    }

    /// Stores a bookmark to the picked folder so access survives relaunch.
    /// The caller must still be inside the `.fileImporter` callback's
    /// security scope when this runs.
    static func setDestination(_ url: URL) throws {
        let didStartAccessing = url.startAccessingSecurityScopedResource()
        defer { if didStartAccessing { url.stopAccessingSecurityScopedResource() } }

        let bookmark = try url.bookmarkData()
        UserDefaults.standard.set(bookmark, forKey: Keys.bookmark)
        UserDefaults.standard.set(url.lastPathComponent, forKey: Keys.destinationName)
        // Clear the clock so the first backup happens on the next launch
        // rather than up to a day later.
        UserDefaults.standard.removeObject(forKey: Keys.lastRun)
    }

    static func clearDestination() {
        UserDefaults.standard.removeObject(forKey: Keys.bookmark)
        UserDefaults.standard.removeObject(forKey: Keys.destinationName)
        UserDefaults.standard.removeObject(forKey: Keys.lastRun)
    }

    /// Resolves the stored bookmark, refreshing it if the folder moved.
    /// Returns nil when the folder is gone — a destination the user deleted
    /// or revoked shouldn't silently resurrect.
    private static func resolveDestination() -> URL? {
        guard let bookmark = UserDefaults.standard.data(forKey: Keys.bookmark) else { return nil }
        var isStale = false
        guard let url = try? URL(resolvingBookmarkData: bookmark, bookmarkDataIsStale: &isStale) else {
            return nil
        }
        if isStale, let refreshed = try? url.bookmarkData() {
            UserDefaults.standard.set(refreshed, forKey: Keys.bookmark)
        }
        return url
    }

    // MARK: - Running

    enum RunOutcome {
        case notConfigured
        case notDue
        case written(URL)
        case failed(String)
    }

    /// Exports and writes if a destination is set and a day has passed.
    ///
    /// The export itself has to happen on the main actor (it reads the
    /// ModelContext) and serializes inventory photos, so it's kept behind the
    /// interval check rather than run on every launch. The file write and the
    /// pruning are pushed off the main actor.
    @discardableResult
    func runIfDue(modelContext: ModelContext, now: Date = .now) async -> RunOutcome {
        guard Self.isEnabled else { return .notConfigured }
        if let lastRun = Self.lastRunAt, now.timeIntervalSince(lastRun) < Self.minimumInterval {
            return .notDue
        }
        guard let directory = Self.resolveDestination() else {
            return .failed("The backup folder is no longer available.")
        }

        let data: Data
        do {
            data = try backupService.export(modelContext: modelContext)
        } catch {
            return .failed("Couldn't build the backup: \(error.localizedDescription)")
        }

        let destination = directory.appendingPathComponent(BackupService.suggestedFilename(date: now))
        let keepCount = Self.keepCount

        let result = await Task.detached(priority: .background) { () -> Result<URL, Error> in
            let didStartAccessing = directory.startAccessingSecurityScopedResource()
            defer { if didStartAccessing { directory.stopAccessingSecurityScopedResource() } }
            do {
                try data.write(to: destination, options: .atomic)
                Self.prune(in: directory, keeping: keepCount)
                return .success(destination)
            } catch {
                return .failure(error)
            }
        }.value

        switch result {
        case .success(let url):
            UserDefaults.standard.set(now, forKey: Keys.lastRun)
            return .written(url)
        case .failure(let error):
            // The clock is deliberately not advanced, so a failure retries on
            // the next launch instead of waiting out a day.
            return .failed(error.localizedDescription)
        }
    }

    /// Keeps the newest `keeping` dated backups and deletes the rest. Names
    /// are `Menej-Backup-yyyy-MM-dd.json`, so lexical order is date order.
    /// Only files matching that shape are touched — the folder is the user's
    /// and may hold anything else.
    nonisolated private static func prune(in directory: URL, keeping: Int) {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return }

        let backups = contents
            .filter { $0.lastPathComponent.hasPrefix("Menej-Backup-") && $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }

        for url in backups.dropFirst(keeping) {
            try? FileManager.default.removeItem(at: url)
        }
    }
}
