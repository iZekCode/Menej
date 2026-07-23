//
//  SettingsView.swift
//  Menej
//
//  Inset-grouped settings — see PRD §7 Layout & motion.
//
//  Two conventions this screen follows, both of which the earlier version
//  broke in places: explanatory prose belongs in a Section `footer:`, never as
//  a Text row (a row draws as a content card, which reads as content rather
//  than as a note), and every control row leads with an SF Symbol. Read-only
//  value rows are the exception — they carry no icon, so the left edge doesn't
//  compete with the value column on the right.
//

import SwiftUI
import SwiftData
import UIKit
import UniformTypeIdentifiers

/// Wraps already-encoded backup JSON for `.fileExporter`. The encoding happens
/// in `BackupService`; this only hands the bytes to the system save sheet.
struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    let data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext

    // Counting via @Query loads the rows to count them, which is wasteful in
    // principle. It's deliberate at this scale — 15 statements and low
    // thousands of transactions — because it stays reactive and matches how
    // every other view in the app reads the store. Revisit with
    // `fetchCount` if the ledger ever grows an order of magnitude.
    @Query private var statements: [Statement]
    @Query private var transactions: [Transaction]
    @Query private var accounts: [Account]

    @State private var backupDocument: BackupDocument?
    @State private var isBackupPresented = false
    @State private var isRestorePresented = false
    @State private var restorePending: Data?
    @State private var backupMessage: String?
    @State private var isFolderPickerPresented = false
    /// Mirrored into view state so turning automatic backup on or off
    /// redraws — the underlying value lives in UserDefaults, which SwiftUI
    /// doesn't observe.
    @State private var autoBackupDestination = AutoBackupService.destinationName

    private let backupService = BackupService()

    var body: some View {
        NavigationStack {
            List {
                privacySection
                notificationsSection
                dataSection
                backupSection
                aboutSection
            }
            .navigationTitle("Settings")
            // Switching off has to cancel now, not at next launch — otherwise
            // a user who just turned reminders off still gets one tomorrow.
            // Switching on reschedules from current data.
            .onChange(of: appState.areRemindersEnabled) { _, isEnabled in
                Task { await ReminderScheduler.sync(modelContext: modelContext, isEnabled: isEnabled) }
            }
            .fileExporter(
                isPresented: $isBackupPresented,
                document: backupDocument,
                contentType: .json,
                defaultFilename: BackupService.suggestedFilename()
            ) { result in
                if case .failure(let error) = result {
                    backupMessage = error.localizedDescription
                }
            }
            .fileImporter(isPresented: $isRestorePresented, allowedContentTypes: [.json]) { result in
                guard case .success(let url) = result else { return }
                loadRestoreFile(at: url)
            }
            .fileImporter(isPresented: $isFolderPickerPresented, allowedContentTypes: [.folder]) { result in
                guard case .success(let url) = result else { return }
                do {
                    try AutoBackupService.setDestination(url)
                    autoBackupDestination = AutoBackupService.destinationName
                } catch {
                    backupMessage = "Couldn't use that folder: \(error.localizedDescription)"
                }
            }
            // Replace-all is destructive and irreversible, so it never happens
            // straight off a file pick.
            .confirmationDialog(
                "Replace everything?",
                isPresented: Binding(
                    get: { restorePending != nil },
                    set: { if !$0 { restorePending = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Replace", role: .destructive) { performRestore() }
                Button("Cancel", role: .cancel) { restorePending = nil }
            } message: {
                Text("Everything currently in Menej is deleted and replaced with the contents of this file. This can't be undone.")
            }
            .alert("Backup", isPresented: Binding(
                get: { backupMessage != nil },
                set: { if !$0 { backupMessage = nil } }
            )) {
                Button("OK") { backupMessage = nil }
            } message: {
                Text(backupMessage ?? "")
            }
        }
    }

    private func startBackup() {
        do {
            backupDocument = BackupDocument(data: try backupService.export(modelContext: modelContext))
            isBackupPresented = true
        } catch {
            backupMessage = "Couldn't build the backup: \(error.localizedDescription)"
        }
    }

    /// The picked file is security-scoped and only readable inside this
    /// callback, so it's read into memory now and restored after confirmation.
    private func loadRestoreFile(at url: URL) {
        let didStartAccessing = url.startAccessingSecurityScopedResource()
        defer { if didStartAccessing { url.stopAccessingSecurityScopedResource() } }

        guard let data = try? Data(contentsOf: url) else {
            backupMessage = "Couldn't read that file."
            return
        }
        restorePending = data
    }

    private func performRestore() {
        guard let data = restorePending else { return }
        restorePending = nil
        do {
            let restored = try backupService.restore(from: data, modelContext: modelContext)
            backupMessage = "Restored \(restored.itemCount.formatted()) items."
        } catch {
            backupMessage = error.localizedDescription
        }
    }

    // MARK: - Privacy & Security

    private var privacySection: some View {
        @Bindable var appState = appState
        return Section {
            Toggle(isOn: $appState.isFaceIDEnabled) {
                Label("Require Face ID", systemImage: "faceid")
            }
            // "Hide amounts in widget" used to sit here. There is no widget
            // yet — Widget/ has no extension target, so nothing ever reads
            // `isWidgetPrivacyModeEnabled` — and a switch that changes nothing
            // is worse than an absent one. Restore this row alongside the
            // widget itself (PRD §6 F9).
        } header: {
            Text("Privacy & Security")
        } footer: {
            Text("Your financial data never leaves this device. Only parser rule updates, asset prices, and FX rates are fetched over the network — none of them carry your data.")
        }
    }

    // MARK: - Notifications

    private var notificationsSection: some View {
        @Bindable var appState = appState
        return Section {
            Toggle(isOn: $appState.areRemindersEnabled) {
                Label("Reminders", systemImage: "bell")
            }
            // Reminders are provisional, so iOS Settings is where a user goes
            // to promote them to a banner or confirm they're allowed at all.
            if let url = URL(string: UIApplication.openSettingsURLString) {
                Link(destination: url) {
                    Label("Notification Settings", systemImage: "arrow.up.forward.app")
                }
            }
        } header: {
            Text("Notifications")
        } footer: {
            // Provisional delivery is silent, so without saying this a user who
            // expects a banner concludes the feature is broken. Amounts are
            // named as absent on purpose — this text is also the promise not to
            // put them there.
            Text("Warranty expiry, payment due dates, and a monthly nudge to import statements. They arrive quietly in Notification Center and never show amounts.")
        }
    }

    // MARK: - Data

    private var dataSection: some View {
        Section {
            LabeledContent("Statements", value: statements.count.formatted())
            LabeledContent("Transactions", value: transactions.count.formatted())
            LabeledContent("Accounts", value: accounts.count.formatted())
            LabeledContent("Latest statement", value: latestStatementMonth)
            NavigationLink {
                StatementFilesView()
            } label: {
                Label("Stored Files", systemImage: "folder")
            }
        } header: {
            Text("Data")
        } footer: {
            Text("Everything here is built from the statements you've imported.")
        }
    }

    // MARK: - Backup

    private var backupSection: some View {
        Section {
            Button {
                startBackup()
            } label: {
                Label("Back Up", systemImage: "arrow.down.document")
            }
            Button {
                isRestorePresented = true
            } label: {
                Label("Restore", systemImage: "arrow.up.document")
            }

            if let destination = autoBackupDestination {
                LabeledContent("Automatic") {
                    Text(destination)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                LabeledContent("Last backup", value: lastAutoBackupText)
                Button("Turn Off Automatic Backup", role: .destructive) {
                    AutoBackupService.clearDestination()
                    autoBackupDestination = nil
                }
            } else {
                Button {
                    isFolderPickerPresented = true
                } label: {
                    Label("Set Up Automatic Backup", systemImage: "folder.badge.gearshape")
                }
            }
        } header: {
            Text("Backup")
        } footer: {
            // Naming what the file contains is the point. "Back Up" on its own
            // implies safety, and this file is plain readable JSON with every
            // transaction and account nickname in it — the app's privacy
            // promise covers what the app transmits, not what the user
            // deliberately exports.
            // "When you open Menej", not "daily": nothing runs in the
            // background, so a day the app isn't opened is a day with no
            // backup. Promising a schedule the app can't keep would be
            // discovered exactly once, at the worst possible moment.
            Text("Saves everything — accounts, transactions, inventory photos, and the balances you typed — to a file. The file is unencrypted and readable, so keep it somewhere you trust. Restoring replaces everything currently in the app.\n\nAutomatic backup writes to a folder you choose when you open Menej, at most once a day, keeping the last \(AutoBackupService.keepCount).")
        }
    }

    private var lastAutoBackupText: String {
        guard let lastRun = AutoBackupService.lastRunAt else { return "Not yet" }
        return lastRun.formatted(date: .abbreviated, time: .shortened)
    }

    /// The newest month any imported statement covers — the same staleness
    /// signal `ReminderService.importNudge` fires on, made visible.
    private var latestStatementMonth: String {
        guard let newest = statements.map(\.periodEnd).max() else { return "None yet" }
        return newest.formatted(.dateTime.month(.wide).year())
    }

    // MARK: - About

    private var aboutSection: some View {
        Section("About") {
            LabeledContent("Version", value: Self.versionString)
        }
    }

    /// "1.0 (1)". Both keys are populated by the build settings
    /// (MARKETING_VERSION / CURRENT_PROJECT_VERSION) rather than written into
    /// the checked-in Info.plist, so they're read defensively — an em dash
    /// here is the visible tell that the keys aren't where this expects.
    private static var versionString: String {
        let info = Bundle.main.infoDictionary
        guard let short = info?["CFBundleShortVersionString"] as? String else { return "—" }
        guard let build = info?["CFBundleVersion"] as? String else { return short }
        return "\(short) (\(build))"
    }

}

#Preview {
    SettingsView()
        .environment(AppState())
        .modelContainer(for: PersistenceService.modelTypes, inMemory: true)
}
