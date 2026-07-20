//
//  SharedImportInbox.swift
//  Menej
//
//  Counterpart to MenejShareExtension/SharedImportInbox.swift (duplicated
//  rather than shared across targets — see that file for why). The
//  extension drops shared PDFs into the App Group container; this side
//  drains them into ImportViewModel's normal pipeline next time
//  ImportFlowView appears.
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

    static func pendingFiles() -> [URL] {
        guard let directory else { return [] }
        return (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
    }

    /// Moves a pending file out of the App Group container into the app's
    /// own Documents directory. This has to be a move, not a copy-then-read:
    /// `ImportViewModel` reads the URL twice on two different occasions —
    /// once to parse (immediately) and again to hash it when the user taps
    /// Confirm (arbitrarily later) — so the file needs to stay valid for the
    /// rest of the review flow, not just for the initial parse.
    static func moveIntoAppStorage(_ url: URL) -> URL? {
        guard let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return nil
        }
        let importsDirectory = documentsDirectory.appendingPathComponent("SharedImports", isDirectory: true)
        try? FileManager.default.createDirectory(at: importsDirectory, withIntermediateDirectories: true)
        let destination = importsDirectory.appendingPathComponent(url.lastPathComponent)
        do {
            try FileManager.default.moveItem(at: url, to: destination)
            return destination
        } catch {
            return nil
        }
    }
}
