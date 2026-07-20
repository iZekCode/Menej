//
//  ShareStatementView.swift
//  MenejShareExtension
//
//  Hosted by ShareViewController — users share a PDF from Mail, Files, or
//  WhatsApp straight into Menej without opening the app first, see PRD §6 F2.
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
                        .disabled(fileURLs.isEmpty)
                }
            }
        }
    }
}

#Preview {
    ShareStatementView(fileURLs: [])
}
