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
            Tab("Net Worth", systemImage: "chart.line.uptrend.xyaxis") {
                NetWorthHomeView()
            }
            Tab("Import", systemImage: "square.and.arrow.down") {
                ImportFlowView()
            }
            Tab("Insights", systemImage: "sparkles") {
                InsightsView()
            }
            Tab("Ledger", systemImage: "list.bullet.rectangle") {
                TransactionListView()
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
