//
//  AppLockManager.swift
//  ArmadilloAssistant
//
//  Created by David Wilcox on 3/4/26.
//

import Foundation
import Combine
import Security

import LocalAuthentication
import SwiftUI

// MARK: - AppLockManager
// Controls biometric/passcode authentication and the 24‑hour unlock timeout

final class AppLockManager: ObservableObject {

    // MARK: - Singleton

    static let shared = AppLockManager()

    // MARK: - Published State

    @Published var isLocked: Bool = true

    // MARK: - Configuration

    private let unlockTimeout: TimeInterval = 60 * 60 * 24 // 24 hours

    // MARK: - Storage Key

    private let lastUnlockKey = "app_last_unlock_time"

    // MARK: - Init

    private init() {
        evaluateInitialLockState()
    }

    // MARK: - Public Methods

    func lockIfNeeded() {
        guard let lastUnlock = getLastUnlockDate() else {
            isLocked = true
            return
        }

        let elapsed = Date().timeIntervalSince(lastUnlock)

        if elapsed > unlockTimeout {
            isLocked = true
        }
    }

    func authenticate() {
        let context = LAContext()
        var error: NSError?

        // Preferred policy: biometrics
        if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {

            context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics,
                                   localizedReason: "Unlock Armadillo Assistant") { success, _ in

                DispatchQueue.main.async {
                    if success {
                        self.unlockSuccessful()
                    } else {
                        self.fallbackToPasscode()
                    }
                }
            }

        } else {
            fallbackToPasscode()
        }
    }

    // MARK: - Private Methods

    private func fallbackToPasscode() {

        let context = LAContext()

        context.evaluatePolicy(.deviceOwnerAuthentication,
                               localizedReason: "Unlock Armadillo Assistant") { success, _ in

            DispatchQueue.main.async {
                if success {
                    self.unlockSuccessful()
                }
            }
        }
    }

    private func unlockSuccessful() {
        saveLastUnlockDate(Date())
        isLocked = false
    }

    private func evaluateInitialLockState() {

        guard let lastUnlock = getLastUnlockDate() else {
            isLocked = true
            return
        }

        let elapsed = Date().timeIntervalSince(lastUnlock)

        isLocked = elapsed > unlockTimeout
    }

    // MARK: - Keychain Storage

    private func saveLastUnlockDate(_ date: Date) {
        var interval = date.timeIntervalSince1970
        let data = Data(bytes: &interval, count: MemoryLayout<TimeInterval>.size)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: lastUnlockKey,
            kSecValueData as String: data
        ]

        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }

    private func getLastUnlockDate() -> Date? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: lastUnlockKey,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              data.count == MemoryLayout<TimeInterval>.size else { return nil }

        var interval: TimeInterval = 0
        _ = withUnsafeMutableBytes(of: &interval) { intervalBytes in
            data.copyBytes(to: intervalBytes)
        }

        return Date(timeIntervalSince1970: interval)
    }
}
