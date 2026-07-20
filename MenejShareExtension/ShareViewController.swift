//
//  ShareViewController.swift
//  MenejShareExtension
//
//  NSExtension principal class (see Info.plist) — hosts ShareStatementView
//  directly rather than the SLComposeServiceViewController/storyboard
//  Xcode's template scaffolds, since this extension needs an arbitrary list
//  UI, not a text-compose one.
//

import UIKit
import SwiftUI
import UniformTypeIdentifiers

final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        Task { await presentShareView() }
    }

    private func presentShareView() async {
        let shareView = ShareStatementView(
            fileURLs: await extractedPDFURLs(),
            onImport: { [weak self] urls in self?.savePendingImports(urls) },
            onCancel: { [weak self] in self?.extensionContext?.cancelRequest(withError: CocoaError(.userCancelled)) }
        )
        let hosting = UIHostingController(rootView: shareView)
        addChild(hosting)
        hosting.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hosting.view)
        NSLayoutConstraint.activate([
            hosting.view.topAnchor.constraint(equalTo: view.topAnchor),
            hosting.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            hosting.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hosting.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        hosting.didMove(toParent: self)
    }

    /// The system hands back each shared PDF as a local temp-file URL, valid
    /// only for the extension's short lifetime — `savePendingImports` copies
    /// them somewhere durable before that lifetime ends.
    private func extractedPDFURLs() async -> [URL] {
        var urls: [URL] = []
        let items = (extensionContext?.inputItems as? [NSExtensionItem]) ?? []
        for item in items {
            for provider in item.attachments ?? [] {
                guard provider.hasItemConformingToTypeIdentifier(UTType.pdf.identifier) else { continue }
                if let url = try? await provider.loadItem(forTypeIdentifier: UTType.pdf.identifier) as? URL {
                    urls.append(url)
                }
            }
        }
        return urls
    }

    /// Copies into the shared App Group container so the main app can pick
    /// these up next time it's foregrounded — see SharedImportInbox.swift
    /// (duplicated on the app side rather than shared across targets, since
    /// this project uses Xcode 16 synchronized folder groups scoped
    /// one-to-one with their target).
    private func savePendingImports(_ urls: [URL]) {
        guard let inbox = SharedImportInbox.directory else {
            extensionContext?.cancelRequest(withError: CocoaError(.fileWriteUnknown))
            return
        }
        for url in urls {
            let destination = inbox.appendingPathComponent(UUID().uuidString + ".pdf")
            try? FileManager.default.copyItem(at: url, to: destination)
        }
        extensionContext?.completeRequest(returningItems: nil)
    }
}
