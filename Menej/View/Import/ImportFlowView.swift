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
                    viewModel.importFiles(urls)
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
