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

    var body: some View {
        TabView {
            Tab("Net Worth", systemImage: "chart.line.uptrend.xyaxis") {
                NetWorthHomeView()
            }
            Tab("Import", systemImage: "square.and.arrow.down") {
                ImportFlowView()
            }
            Tab("Ledger", systemImage: "list.bullet.rectangle") {
                TransactionListView()
            }
            Tab("Portfolio", systemImage: "chart.pie") {
                PortfolioView()
            }
            Tab("Insights", systemImage: "sparkles") {
                InsightsView()
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
    }
}

#Preview {
    ContentView()
        .environment(AppState())
        .modelContainer(for: PersistenceService.modelTypes, inMemory: true)
}
