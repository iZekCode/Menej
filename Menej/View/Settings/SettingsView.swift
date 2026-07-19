//
//  SettingsView.swift
//  Menej
//
//  Grouped List insets for settings — see PRD §7 Layout & motion.
//

import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    #if DEBUG
    @State private var seedResult: SeedResult?
    #endif

    var body: some View {
        @Bindable var appState = appState
        NavigationStack {
            List {
                Section("Security") {
                    Toggle("Require Face ID / Touch ID", isOn: $appState.isFaceIDEnabled)
                }
                Section("Widget") {
                    Toggle("Hide amounts when locked", isOn: $appState.isWidgetPrivacyModeEnabled)
                }
                Section("Privacy") {
                    Text("Your financial data never leaves this device. Only parser rule updates, asset prices, and FX rates are fetched over the network — none of them carry your data.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                #if DEBUG
                Section("Developer") {
                    Button("Reload Sample Statements") {
                        seedResult = SeedDataService.resetAndSeed(modelContext: modelContext)
                    }
                    Text("Wipes the ledger and reimports the 15 real sample statements bundled with the app. Debug builds only — never ships to release.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if let seedResult {
                        Text(seedResult.description)
                            .font(.footnote.monospaced())
                            .foregroundStyle(seedResult.transactionsImported > 0 ? .secondary : AppColor.loss)
                            .textSelection(.enabled)
                    }
                }
                #endif
            }
            .listStyle(.grouped)
            .navigationTitle("Settings")
        }
    }
}

#Preview {
    SettingsView()
        .environment(AppState())
}
