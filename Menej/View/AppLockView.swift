//
//  AppLockView.swift
//  Menej
//
//  Full-screen biometric lock shown over the app until the user authenticates
//  — see PRD §8. Opaque so the financial data behind it is never briefly
//  visible (including in the app switcher). Auto-prompts on appear; a manual
//  Unlock button retries after a cancel or failure.
//

import SwiftUI

struct AppLockView: View {
    @Environment(AppState.self) private var appState
    private let authenticator = BiometricAuthenticator()

    @State private var isAuthenticating = false
    @State private var didFail = false

    var body: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()

            VStack(spacing: AppSpacing.margin) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(AppColor.accent)
                Text("Menej is locked")
                    .font(.headline)
                Text("Unlock with Face ID to view your finances.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Button {
                    unlock()
                } label: {
                    Label("Unlock", systemImage: "faceid")
                        .frame(maxWidth: 220)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isAuthenticating)
                .padding(.top, AppSpacing.grid)

                if didFail {
                    Text("Authentication failed. Try again.")
                        .font(.caption)
                        .foregroundStyle(AppColor.loss)
                }
            }
            .padding(AppSpacing.margin)
        }
        .task { unlock() }
    }

    private func unlock() {
        guard !isAuthenticating else { return }
        isAuthenticating = true
        didFail = false
        Task {
            let success = await authenticator.authenticate(reason: "Unlock Menej to view your finances.")
            isAuthenticating = false
            if success {
                appState.isUnlocked = true
            } else {
                didFail = true
            }
        }
    }
}

#Preview {
    AppLockView()
        .environment(AppState())
}
