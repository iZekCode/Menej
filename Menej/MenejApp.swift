//
//  MenejApp.swift
//  Menej
//
//  Created by Filbert Naldo Wijaya on 19/07/26.
//

import SwiftUI
import SwiftData

@main
struct MenejApp: App {
    private let persistenceService = PersistenceService()
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
        }
        .modelContainer(persistenceService.modelContainer)
    }
}
