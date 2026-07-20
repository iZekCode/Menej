//
//  SharedImportInbox.swift
//  MenejShareExtension
//
//  The App Group container is the only channel between this extension's
//  process and the main app — see PersistenceService.swift for why the
//  SwiftData store itself isn't shared: the extension never touches it, it
//  just drops PDFs here for the main app's normal ImportViewModel pipeline
//  to pick up. Requires the "App Groups" capability (group.Filbert.Menej) on
//  both this target and the main app target.
//

import Foundation

enum SharedImportInbox {
    static let appGroupIdentifier = "group.Filbert.Menej"

    static var directory: URL? {
        guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) else {
            return nil
        }
        let directory = container.appendingPathComponent("PendingImports", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
