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
    @State private var viewModel = ImportViewModel()
    @State private var isPickerPresented = false

    var body: some View {
        NavigationStack {
            List {
                if viewModel.files.isEmpty {
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
            .onAppear(perform: importPendingSharedFiles)
        }
    }

    /// Only a file still awaiting review pushes anywhere — an imported or
    /// failed row has nothing to confirm.
    @ViewBuilder
    private func row(for file: ImportFile) -> some View {
        if case .needsReview = file.status, let statement = file.parsed {
            NavigationLink {
                ReviewStatementView(statement: statement) {
                    try? viewModel.confirmImport(url: file.url, statement: statement, modelContext: modelContext)
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
