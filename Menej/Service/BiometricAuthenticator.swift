//
//  BiometricAuthenticator.swift
//  Menej
//
//  Face ID / Touch ID gate for opening the app — see PRD §8. Uses
//  LocalAuthentication only; the user authenticates against their own device,
//  nothing leaves it. `.deviceOwnerAuthentication` allows the device passcode
//  as a fallback so the user is never locked out if biometrics fail or aren't
//  enrolled.
//

import Foundation
import LocalAuthentication

struct BiometricAuthenticator {
    /// True once the user passes biometrics (or the passcode fallback). Never
    /// throws — any failure or unavailability resolves to `false`, and the
    /// caller keeps showing the lock screen with a retry button.
    func authenticate(reason: String) async -> Bool {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            return false
        }
        return await withCheckedContinuation { continuation in
            context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { success, _ in
                continuation.resume(returning: success)
            }
        }
    }
}
