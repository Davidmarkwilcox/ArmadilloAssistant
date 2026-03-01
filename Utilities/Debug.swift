// Debug.swift
// Centralized debug toggle + logging helpers used throughout the app.
// Uses Xcode console only (no file output).

import Foundation
import os

enum Debug {
    // 1) Global Toggle (default: Off)
    static var enabled: Bool = false

    // 2) Optional: subsystem/category for clean filtering in Console.app / Xcode
    private static let subsystem = Bundle.main.bundleIdentifier ?? "ArmadilloAssistant"
    private static let logger = Logger(subsystem: subsystem, category: "Debug")

    // 3) Convenience overload to reduce string interpolation noise at call sites
    static func log(_ message: @autoclosure @escaping () -> String) {
        guard enabled else { return }
        let evaluated = message()
        logger.debug("\(evaluated, privacy: .public)")
    }
}
