//
//  StatementFileStore.swift
//  Menej
//
//  The PDFs the app keeps for itself. Two directories, both inside Documents:
//
//  - `PickedImports/<uuid>/<name>.pdf` — copies of files picked through
//    `.fileImporter`. Copies, not moves: the user's original stays wherever
//    they keep it (see ImportFlowView.copyIntoAppStorage).
//  - `SharedImports/<name>.pdf` — files the share extension dropped in the App
//    Group, moved here so the URL survives the whole review flow. These are
//    the app's only copy.
//
//  Both exist because ImportViewModel reads a file twice on two different
//  occasions — once to parse, again to hash on Confirm — so the URL has to
//  outlive the security-scoped access that produced it.
//
//  This type also owns the SHA256 hashing. That's deliberate and load-bearing:
//  `Statement.fileHash` is the same hash, so it is what links a stored PDF back
//  to the statement it produced, and what makes a re-import replace rather than
//  duplicate. One implementation, or that link silently breaks.
//

import Foundation
import CryptoKit

struct StoredStatementFile: Identifiable {
    let url: URL
    let name: String
    let byteSize: Int64
    /// SHA256 of the contents — matches `Statement.fileHash`.
    let hash: String

    var id: URL { url }

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: byteSize, countStyle: .file)
    }
}

enum StatementFileStoreError: Error {
    case unreadableFile
}

struct StatementFileStore {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    // MARK: - Locations

    private var documentsDirectory: URL? {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
    }

    /// The two roots, in the order they're listed to the user.
    var directories: [URL] {
        guard let documentsDirectory else { return [] }
        return [
            documentsDirectory.appendingPathComponent("PickedImports", isDirectory: true),
            documentsDirectory.appendingPathComponent("SharedImports", isDirectory: true),
        ]
    }

    /// True for anything inside the app's own storage. The rename and delete
    /// paths check this so nothing outside the container is ever touched.
    func isManaged(_ url: URL) -> Bool {
        guard let documentsDirectory else { return false }
        return url.path.hasPrefix(documentsDirectory.path)
    }

    // MARK: - Listing

    /// Every stored PDF, newest first, each hashed. Hashing is the expensive
    /// part — SHA256 over a few hundred KB apiece — so callers should hold the
    /// result rather than recomputing per redraw.
    func storedFiles() -> [StoredStatementFile] {
        var files: [StoredStatementFile] = []
        for directory in directories {
            guard let enumerator = fileManager.enumerator(
                at: directory,
                includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            for case let url as URL in enumerator {
                guard url.pathExtension.lowercased() == "pdf" else { continue }
                guard let hash = try? Self.hash(of: url) else { continue }
                let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                files.append(StoredStatementFile(
                    url: url,
                    name: url.lastPathComponent,
                    byteSize: Int64(size),
                    hash: hash
                ))
            }
        }
        return files.sorted { $0.name > $1.name }
    }

    func totalByteSize(of files: [StoredStatementFile]) -> Int64 {
        files.reduce(0) { $0 + $1.byteSize }
    }

    // MARK: - Mutation

    /// Removes the app's copy. Never touches the ledger: the transactions are
    /// already imported and the file is only needed to *re*-import.
    ///
    /// For a picked file this also removes its containing UUID directory,
    /// which would otherwise be left behind empty.
    func delete(_ file: StoredStatementFile) {
        guard isManaged(file.url) else { return }
        try? fileManager.removeItem(at: file.url)

        let parent = file.url.deletingLastPathComponent()
        guard parent.lastPathComponent != "SharedImports",
              let remaining = try? fileManager.contentsOfDirectory(atPath: parent.path),
              remaining.isEmpty else { return }
        try? fileManager.removeItem(at: parent)
    }

    // MARK: - Hashing

    /// The one SHA256 implementation. `ImportViewModel` hashes on Confirm to
    /// populate `Statement.fileHash`; this same function is what later matches
    /// a stored file back to that statement.
    static func hash(of url: URL) throws -> String {
        guard let data = try? Data(contentsOf: url) else {
            throw StatementFileStoreError.unreadableFile
        }
        return SHA256.hash(data: data).compactMap { String(format: "%02x", $0) }.joined()
    }
}
