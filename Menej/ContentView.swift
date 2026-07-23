//
//  ContentView.swift
//  Menej
//
//  Root tab bar — standard TabView per PRD §7 Native-first.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppState.self) private var appState
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView {
            // Ordered by how often a tab is opened, not by how data flows
            // through the app: Net Worth is the summary the app opens on,
            // Insights and Ledger are the two you reach for whenever you
            // wonder about a number. Import sits second-to-last because it's
            // an occasional task rather than a destination — and its main
            // entry point is the share sheet anyway (see
            // ImportFlowView.importPendingSharedFiles), not this tab.
            Tab("Net Worth", systemImage: "chart.line.uptrend.xyaxis") {
                NetWorthHomeView()
            }
            Tab("Insights", systemImage: "sparkles") {
                InsightsView()
            }
            Tab("Ledger", systemImage: "list.bullet.rectangle") {
                TransactionListView()
            }
            Tab("Import", systemImage: "square.and.arrow.down") {
                ImportFlowView()
            }
            Tab("Settings", systemImage: "gearshape") {
                SettingsView()
            }
        }
        .tint(AppColor.accent)
        #if DEBUG
        .task {
            SeedDataService.seedIfNeeded(modelContext: modelContext)
        }
        #endif
        // Rebuilt on every launch. Nothing runs in the background, so this is
        // the only thing that keeps the import nudge pointed at the right
        // month after the app has been closed for a while — and it repairs a
        // reinstall, where pending notifications are gone but the data isn't.
        .task {
            await ReminderScheduler.sync(
                modelContext: modelContext,
                isEnabled: appState.areRemindersEnabled
            )
            // Only runs if a destination is set and a day has passed — see
            // AutoBackupService. Nothing runs in the background, so app launch
            // is the only trigger there is.
            await AutoBackupService().runIfDue(modelContext: modelContext)
        }
        // Biometric gate (PRD §8). Opaque overlay so nothing shows until the
        // user authenticates; re-locks whenever the app leaves the foreground.
        .overlay {
            if appState.isFaceIDEnabled && !appState.isUnlocked {
                AppLockView()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background && appState.isFaceIDEnabled {
                appState.isUnlocked = false
            }
        }
    }
}

#Preview {
    ContentView()
        .environment(AppState())
        .modelContainer(for: PersistenceService.modelTypes, inMemory: true)
}
