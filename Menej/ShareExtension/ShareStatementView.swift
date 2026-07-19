//
//  ShareStatementView.swift
//  Menej
//
//  Share Extension: users share a PDF from Mail, Files, or WhatsApp straight
//  into Menej without opening the app — see PRD §6 F2.
//
//  NOTE: this file currently compiles into the main app target only. A real
//  share extension requires adding a Share Extension target in Xcode
//  (File > New > Target > Share Extension), giving it an App Group shared
//  with the main app (and PersistenceService's ModelConfiguration), and
//  moving this view into that target's SwiftUI entry point (NSExtension
//  principal class / `UIViewController` hosting this view). TODO(M2).
//

import SwiftUI

struct ShareStatementView: View {
    let fileURLs: [URL]
    var onImport: ([URL]) -> Void = { _ in }
    var onCancel: () -> Void = {}

    var body: some View {
        NavigationStack {
            List(fileURLs, id: \.self) { url in
                Label(url.lastPathComponent, systemImage: "doc.fill")
            }
            .navigationTitle("Import to Menej")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Import") { onImport(fileURLs) }
                }
            }
        }
    }
}

#Preview {
    ShareStatementView(fileURLs: [])
}
