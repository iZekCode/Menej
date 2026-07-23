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

    #if DEBUG
    @State private var seedResult: SeedResult?
    #endif

    var body: some View {
        NavigationStack {
            List {
                privacySection
                notificationsSection
                dataSection
                aboutSection
                #if DEBUG
                developerSection
                #endif
            }
            .navigationTitle("Settings")
            // Switching off has to cancel now, not at next launch — otherwise
            // a user who just turned reminders off still gets one tomorrow.
            // Switching on reschedules from current data.
            .onChange(of: appState.areRemindersEnabled) { _, isEnabled in
                Task { await ReminderScheduler.sync(modelContext: modelContext, isEnabled: isEnabled) }
            }
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
        } header: {
            Text("Data")
        } footer: {
            Text("Everything here is built from the statements you've imported.")
        }
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

    // MARK: - Developer

    #if DEBUG
    private var developerSection: some View {
        Section {
            Button("Reload Sample Statements") {
                seedResult = SeedDataService.resetAndSeed(modelContext: modelContext)
            }
            if let seedResult {
                Text(seedResult.description)
                    .font(.footnote.monospaced())
                    .foregroundStyle(seedResult.transactionsImported > 0 ? .secondary : AppColor.loss)
                    .textSelection(.enabled)
            }
        } header: {
            Text("Developer")
        } footer: {
            Text("Wipes the ledger and reimports the 15 real sample statements bundled with the app. Debug builds only — never ships to release.")
        }
    }
    #endif
}

#Preview {
    SettingsView()
        .environment(AppState())
        .modelContainer(for: PersistenceService.modelTypes, inMemory: true)
}
