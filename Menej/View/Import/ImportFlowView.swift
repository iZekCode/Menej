//
//  ImportFlowView.swift
//  Menej
//
//  In-app import: document picker, multi-file support — see PRD §6 F2.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct ImportFlowView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppState.self) private var appState
    @Query(sort: \Statement.periodEnd, order: .reverse) private var statements: [Statement]
    @Query private var transactions: [Transaction]
    @State private var viewModel = ImportViewModel()
    @State private var isPickerPresented = false
    /// Stored PDFs keyed by content hash, so a past import can find its file
    /// and offer re-import. Loaded once per appearance — hashing every stored
    /// file is cheap but not free, and it can't change while this screen is up
    /// except through this screen.
    @State private var filesByHash: [String: StoredStatementFile] = [:]
    @State private var statementPendingDeletion: Statement?

    var body: some View {
        NavigationStack {
            List {
                if viewModel.files.isEmpty && statements.isEmpty {
                    EmptyStateView(
                        systemImage: "square.and.arrow.down",
                        title: "Import a statement",
                        message: "Add a PDF from myBCA, GoPay, or Grab. You can also share a file directly from Mail or Files."
                    )
                } else {
                    ForEach(groups) { group in
                        Section {
                            ForEach(group.files) { file in
                                row(for: file)
                                    .swipeActions(edge: .trailing) {
                                        Button("Remove", systemImage: "trash", role: .destructive) {
                                            viewModel.remove(file)
                                        }
                                    }
                            }
                        } header: {
                            Text(group.title)
                        }
                    }
                    importedSection
                }
            }
            .listSectionSpacing(AppSpacing.margin)
            .navigationTitle("Import")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Add Files", systemImage: "plus") {
                        isPickerPresented = true
                    }
                }
            }
            .fileImporter(isPresented: $isPickerPresented, allowedContentTypes: [.pdf], allowsMultipleSelection: true) { result in
                if case .success(let urls) = result {
                    viewModel.importFiles(copyIntoAppStorage(urls))
                }
            }
            .confirmationDialog(
                "Delete this statement?",
                isPresented: Binding(
                    get: { statementPendingDeletion != nil },
                    set: { if !$0 { statementPendingDeletion = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    if let statement = statementPendingDeletion { delete(statement) }
                    statementPendingDeletion = nil
                }
                Button("Cancel", role: .cancel) { statementPendingDeletion = nil }
            } message: {
                // Snapshots are frozen once written (SnapshotService), so a
                // deletion can't walk history back. Saying so beats letting
                // the user discover a net-worth chart that disagrees.
                Text("Its transactions are removed from your ledger. Net worth history for past months keeps the figures it already recorded.")
            }
            .onAppear {
                importPendingSharedFiles()
                reloadStoredFiles()
            }
        }
    }

    // MARK: - Imported history

    /// Past imports, read back from the `Statement` records. Without this the
    /// screen only ever showed the current session's queue, so relaunching
    /// looked like the imports had been lost.
    @ViewBuilder
    private var importedSection: some View {
        if !statements.isEmpty {
            Section {
                ForEach(statements) { statement in
                    NavigationLink {
                        StatementDetailView(statement: statement)
                    } label: {
                        ImportedStatementRow(
                            statement: statement,
                            transactionCount: transactionCount(for: statement),
                            hasStoredFile: filesByHash[statement.fileHash] != nil
                        )
                    }
                    .swipeActions(edge: .trailing) {
                        Button("Delete", systemImage: "trash", role: .destructive) {
                            statementPendingDeletion = statement
                        }
                        if let file = filesByHash[statement.fileHash] {
                            Button("Re-import", systemImage: "arrow.clockwise") {
                                reimport(statement, from: file)
                            }
                            .tint(AppColor.accent)
                        }
                    }
                }
            } header: {
                Text("Imported")
            } footer: {
                Text("Swipe a statement to re-import or delete it.")
            }
        }
    }

    private func transactionCount(for statement: Statement) -> Int {
        transactions.count { $0.sourceStatementId == statement.id }
    }

    private func reloadStoredFiles() {
        let files = StatementFileStore().storedFiles()
        filesByHash = Dictionary(files.map { ($0.hash, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// Re-runs a stored PDF through the parser. `confirmImport` already
    /// replaces a statement with a matching `fileHash` and carries the user's
    /// corrections onto the re-parsed rows, so this is the after-a-parser-fix
    /// path, not a duplicate import.
    private func reimport(_ statement: Statement, from file: StoredStatementFile) {
        viewModel.importFiles([file.url])
        guard let queued = viewModel.files.first(where: { $0.url == file.url }),
              let parsed = queued.parsed else { return }
        try? viewModel.confirmImport(url: file.url, statement: parsed, modelContext: modelContext)
    }

    private func delete(_ statement: Statement) {
        let statementId = statement.id
        for transaction in transactions where transaction.sourceStatementId == statementId {
            modelContext.delete(transaction)
        }
        modelContext.delete(statement)
        try? modelContext.save()
    }

    /// Only a file still awaiting review pushes anywhere — an imported or
    /// failed row has nothing to confirm.
    @ViewBuilder
    private func row(for file: ImportFile) -> some View {
        if case .needsReview = file.status, let statement = file.parsed {
            NavigationLink {
                ReviewStatementView(statement: statement) {
                    try? viewModel.confirmImport(url: file.url, statement: statement, modelContext: modelContext)
                    // Pushes the import nudge on to the next month. Without
                    // this it keeps pointing at the month just imported, and
                    // would eventually fire asking for it again — nothing runs
                    // in the background to notice otherwise.
                    Task {
                        await ReminderScheduler.sync(
                            modelContext: modelContext,
                            isEnabled: appState.areRemindersEnabled
                        )
                    }
                }
            } label: {
                ImportRow(file: file)
            }
        } else {
            ImportRow(file: file)
        }
    }

    /// One section per statement month, newest first. Anything without a
    /// month — a file that failed to parse, or one that parsed to zero
    /// transactions — is collected at the top, where it's actionable rather
    /// than buried under months of successful imports.
    private var groups: [ImportGroup] {
        let calendar = Calendar.current
        var byMonth: [Date: [ImportFile]] = [:]
        var needsAttention: [ImportFile] = []

        for file in viewModel.files {
            guard let periodEnd = file.periodEnd,
                  let month = calendar.dateInterval(of: .month, for: periodEnd)?.start else {
                needsAttention.append(file)
                continue
            }
            byMonth[month, default: []].append(file)
        }

        var result = byMonth.keys.sorted(by: >).map { month in
            ImportGroup(
                id: "\(month.timeIntervalSince1970)",
                title: month.formatted(.dateTime.month(.wide).year()),
                // Within a month, by issuer name — a stable order, unlike the
                // dictionary this list used to iterate.
                files: byMonth[month, default: []].sorted { $0.displayName < $1.displayName }
            )
        }
        if !needsAttention.isEmpty {
            result.insert(ImportGroup(id: "needsAttention", title: "Needs Attention", files: needsAttention), at: 0)
        }
        return result
    }

    /// Picks up PDFs the share extension dropped in the App Group container
    /// (MenejShareExtension/ShareViewController.swift) — the extension's own
    /// process can't reach ImportViewModel directly, so this is the handoff
    /// point. Files are moved into the app's own storage before parsing (see
    /// SharedImportInbox.moveIntoAppStorage) so the URL stays valid through
    /// the whole review flow, not just the initial parse.
    private func importPendingSharedFiles() {
        let moved = SharedImportInbox.pendingFiles().compactMap(SharedImportInbox.moveIntoAppStorage)
        guard !moved.isEmpty else { return }
        viewModel.importFiles(moved)
    }

    /// `.fileImporter` hands back security-scoped URLs (Files app, iCloud
    /// Drive, etc.) that are only guaranteed readable inside this callback.
    /// `ImportViewModel` reads the file twice — once to parse immediately,
    /// again to hash it whenever the user taps Confirm, arbitrarily later —
    /// so the second read needs a URL that doesn't depend on that scope
    /// still being open. Copying (not moving, unlike the shared-import
    /// case) into the app's own Documents directory sidesteps that: the
    /// original file, wherever the user picked it from, is left untouched.
    private func copyIntoAppStorage(_ urls: [URL]) -> [URL] {
        guard let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return []
        }
        let importsDirectory = documentsDirectory.appendingPathComponent("PickedImports", isDirectory: true)

        return urls.compactMap { url in
            let didStartAccessing = url.startAccessingSecurityScopedResource()
            defer { if didStartAccessing { url.stopAccessingSecurityScopedResource() } }

            // Each file gets its own subdirectory (rather than a UUID-prefixed
            // filename) so ImportRow can keep showing the real filename.
            let destination = importsDirectory
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
                .appendingPathComponent(url.lastPathComponent)
            do {
                try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                try FileManager.default.copyItem(at: url, to: destination)
                return destination
            } catch {
                return nil
            }
        }
    }
}

private struct ImportGroup: Identifiable {
    let id: String
    let title: String
    let files: [ImportFile]
}

/// One past import, from its persisted `Statement` record.
private struct ImportedStatementRow: View {
    let statement: Statement
    let transactionCount: Int
    /// False when the source PDF is no longer on disk — the row still shows,
    /// it just can't be re-imported.
    let hasStoredFile: Bool

    var body: some View {
        HStack(spacing: AppSpacing.grid) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(statement.issuer.displayName) — \(statement.periodEnd.formatted(.dateTime.month(.wide).year()))")
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if !hasStoredFile {
                // The PDF is gone, so re-import isn't offered on this row.
                // Marked rather than left as a mystery when swiping.
                Image(systemName: "doc.badge.ellipsis")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
                    .accessibilityLabel("Original file no longer stored")
            }
        }
    }

    private var subtitle: String {
        let count = transactionCount == 1 ? "1 transaction" : "\(transactionCount) transactions"
        let imported = statement.parsedAt.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted))
        return "\(count) · imported \(imported)"
    }
}

/// The transactions one statement produced. Reuses `TransactionRow`, the same
/// row the Ledger and Insights use, so a transaction looks identical wherever
/// it's read from.
private struct StatementDetailView: View {
    let statement: Statement

    @Query private var transactions: [Transaction]
    @Query private var accounts: [Account]

    private var statementTransactions: [Transaction] {
        transactions
            .filter { $0.sourceStatementId == statement.id }
            .sorted { $0.date > $1.date }
    }

    private var issuerByAccount: [UUID: Issuer] {
        Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0.issuer) })
    }

    var body: some View {
        List {
            Section {
                LabeledContent("Period", value: periodText)
                LabeledContent("Imported", value: statement.parsedAt.formatted(date: .abbreviated, time: .shortened))
                LabeledContent("Confidence", value: "\((statement.confidence * 100).formatted(.number.precision(.fractionLength(0))))%")
                if statement.unaccountedAmount != 0 {
                    // PRD §6 F1 — the reconciliation gap is always shown, never
                    // hidden.
                    LabeledContent("Unaccounted") {
                        AmountText(amount: statement.unaccountedAmount)
                    }
                }
            }
            Section("Transactions") {
                ForEach(statementTransactions) { transaction in
                    TransactionRow(transaction: transaction, issuer: issuerByAccount[transaction.accountId])
                }
            }
        }
        .navigationTitle(statement.issuer.displayName)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var periodText: String {
        let style = Date.FormatStyle(date: .abbreviated, time: .omitted)
        return "\(statement.periodStart.formatted(style)) – \(statement.periodEnd.formatted(style))"
    }
}

private struct ImportRow: View {
    let file: ImportFile

    var body: some View {
        HStack(spacing: AppSpacing.grid) {
            VStack(alignment: .leading, spacing: 2) {
                Text(file.displayName)
                    .lineLimit(1)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            statusView
        }
    }

    /// Once a file is renamed, its title says the issuer and month, so the
    /// subtitle carries what the title no longer can: how much is in it, and
    /// — for a file that never parsed — the name it actually arrived with.
    private var subtitle: String? {
        if case .failed = file.status {
            return "Couldn't read this file"
        }
        guard let parsed = file.parsed else { return nil }
        let count = parsed.transactions.count
        return count == 1 ? "1 transaction" : "\(count) transactions"
    }

    @ViewBuilder
    private var statusView: some View {
        switch file.status {
        case .pending:
            Image(systemName: "clock")
                .foregroundStyle(.secondary)
        case .parsing:
            ProgressView()
        case .needsReview:
            Label("Review", systemImage: "exclamationmark.circle")
                .font(.subheadline)
                .foregroundStyle(AppColor.accent)
        case .failed:
            Label("Failed", systemImage: "xmark.circle")
                .font(.subheadline)
                .foregroundStyle(AppColor.loss)
        case .imported:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(AppColor.gain)
        }
    }
}

#Preview {
    ImportFlowView()
        .modelContainer(for: PersistenceService.modelTypes, inMemory: true)
}
