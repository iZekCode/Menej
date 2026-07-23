//
//  StatementFilesView.swift
//  Menej
//
//  The PDFs the app is holding on to. Every import copies its file into
//  Documents so the URL outlives the security-scoped access that produced it
//  (see ImportFlowView.copyIntoAppStorage) — but nothing ever cleaned them up,
//  so they accumulated with no way to see or remove them.
//
//  Deleting one does not touch the ledger. The transactions are already
//  imported; the file is only kept so a statement can be re-parsed later.
//

import SwiftUI
import SwiftData

struct StatementFilesView: View {
    @Query private var statements: [Statement]

    @State private var files: [StoredStatementFile] = []
    @State private var isLoading = true

    private let store = StatementFileStore()

    var body: some View {
        List {
            if isLoading {
                HStack(spacing: AppSpacing.grid) {
                    ProgressView()
                    Text("Reading files…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else if files.isEmpty {
                EmptyStateView(
                    systemImage: "doc",
                    title: "No stored files",
                    message: "Statement PDFs you import are kept here so they can be re-parsed later."
                )
            } else {
                Section {
                    ForEach(files) { file in
                        FileRow(file: file, statement: statement(for: file))
                    }
                    .onDelete(perform: delete)
                } header: {
                    Text("\(files.count) files · \(totalSize)")
                } footer: {
                    Text("Deleting a file leaves your imported transactions untouched. It only means that statement can't be re-imported without adding the PDF again.")
                }
            }
        }
        .navigationTitle("Stored Files")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: isLoading) {
            guard isLoading else { return }
            await load()
        }
    }

    private var totalSize: String {
        ByteCountFormatter.string(fromByteCount: store.totalByteSize(of: files), countStyle: .file)
    }

    /// Matched on content hash — `Statement.fileHash` is the SHA256 of the
    /// same bytes, so it's the join without needing a stored path.
    private func statement(for file: StoredStatementFile) -> Statement? {
        statements.first { $0.fileHash == file.hash }
    }

    /// Hashing every stored PDF is milliseconds at this scale but it's still
    /// file I/O, so it's kept off the first frame.
    private func load() async {
        let store = store
        let loaded = await Task.detached { store.storedFiles() }.value
        files = loaded
        isLoading = false
    }

    private func delete(at offsets: IndexSet) {
        let doomed = offsets.map { files[$0] }
        for file in doomed {
            store.delete(file)
        }
        files.remove(atOffsets: offsets)
    }
}

private struct FileRow: View {
    let file: StoredStatementFile
    /// The import this file produced, when it's still in the ledger.
    let statement: Statement?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(file.name)
                .lineLimit(1)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private var subtitle: String {
        guard let statement else {
            // A file with no matching statement was never confirmed, or its
            // statement was deleted. Worth saying — it's the clearest
            // candidate for deletion.
            return "\(file.formattedSize) · not imported"
        }
        return "\(file.formattedSize) · \(statement.issuer.displayName) \(statement.periodEnd.formatted(.dateTime.month(.abbreviated).year()))"
    }
}

#Preview {
    NavigationStack {
        StatementFilesView()
    }
    .modelContainer(for: PersistenceService.modelTypes, inMemory: true)
}
