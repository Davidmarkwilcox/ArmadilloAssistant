//
//  AppLockManager.swift
//  ArmadilloAssistant
//
//  Created by David Wilcox on 3/4/26.
//

import Foundation
import Combine
import LocalAuthentication
import SwiftUI

// MARK: - AppLockManager
// Controls device-owner authentication for app access.

final class AppLockManager: ObservableObject {

    // MARK: - Singleton

    static let shared = AppLockManager()

    // MARK: - Unlock Timeout

    private let unlockTimeout: TimeInterval = 60 * 60
    private var lastUnlockDate: Date?

    // MARK: - Published State

    @Published var isLocked: Bool = true
    @Published var isAuthenticating: Bool = false
    @Published var authenticationErrorMessage: String = ""

    // MARK: - Init

    private init() {
    }

    // MARK: - Public Methods

    func lockIfNeeded() {
        guard let lastUnlockDate else {
            lock()
            return
        }

        if Date().timeIntervalSince(lastUnlockDate) >= unlockTimeout {
            lock()
        }
    }

    func lock() {
        isLocked = true
        authenticationErrorMessage = ""
    }

    func authenticate() {
        guard !isAuthenticating else { return }

        let context = LAContext()
        var error: NSError?

        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            authenticationErrorMessage = error?.localizedDescription ?? "Device authentication is unavailable."
            isLocked = true
            return
        }

        isAuthenticating = true
        authenticationErrorMessage = ""

        context.evaluatePolicy(
            .deviceOwnerAuthentication,
            localizedReason: "Unlock Armadillo Assistant"
        ) { success, authenticationError in
            DispatchQueue.main.async {
                self.isAuthenticating = false

                if success {
                    self.authenticationErrorMessage = ""
                    self.lastUnlockDate = Date()
                    self.isLocked = false
                } else {
                    self.isLocked = true
                    self.authenticationErrorMessage = authenticationError?.localizedDescription ?? "Authentication failed."
                }
            }
        }
    }
}
