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
                if viewModel.fileStatuses.isEmpty {
                    EmptyStateView(
                        systemImage: "square.and.arrow.down",
                        title: "Import a statement",
                        message: "Add a PDF from myBCA, GoPay, or Grab. You can also share a file directly from Mail or Files."
                    )
                } else {
                    ForEach(Array(viewModel.fileStatuses.keys), id: \.self) { url in
                        if case .needsReview(let statement) = viewModel.fileStatuses[url] {
                            NavigationLink {
                                ReviewStatementView(statement: statement) {
                                    try? viewModel.confirmImport(url: url, statement: statement, modelContext: modelContext)
                                }
                            } label: {
                                ImportRow(url: url, status: viewModel.fileStatuses[url])
                            }
                        } else {
                            ImportRow(url: url, status: viewModel.fileStatuses[url])
                        }
                    }
                }
            }
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

private struct ImportRow: View {
    let url: URL
    let status: ImportFileStatus?

    var body: some View {
        HStack {
            Text(url.lastPathComponent)
            Spacer()
            statusView
        }
    }

    @ViewBuilder
    private var statusView: some View {
        switch status {
        case .pending, .none:
            Image(systemName: "clock")
        case .parsing:
            ProgressView()
        case .needsReview:
            Label("Review", systemImage: "exclamationmark.circle")
                .foregroundStyle(AppColor.accent)
        case .failed:
            Label("Failed", systemImage: "xmark.circle")
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
