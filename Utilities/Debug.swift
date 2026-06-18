// Debug.swift
// Centralized session-only debug logging for app-routed diagnostics.

import Combine
import Foundation
import UIKit

enum DebugChannel: String, CaseIterable, Identifiable, Codable, Hashable {
    case sync
    case pendingLedger
    case expenseReconcile
    case bookingReconcile
    case uiRefresh
    case cloudKitEvents
    case importPipeline
    case exportPipeline

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .sync:
            return "Sync"
        case .pendingLedger:
            return "Pending Ledger"
        case .expenseReconcile:
            return "Expense Reconcile"
        case .bookingReconcile:
            return "Booking Reconcile"
        case .uiRefresh:
            return "UI Refresh"
        case .cloudKitEvents:
            return "CloudKit Events"
        case .importPipeline:
            return "Import Pipeline"
        case .exportPipeline:
            return "Export Pipeline"
        }
    }
}

struct DebugMessage: Identifiable, Equatable {
    let id = UUID()
    let timestamp: Date
    let channel: DebugChannel
    let source: String
    let message: String
}

private enum DebugSettingsStore {
    static let enabledKey = "debug.isEnabled"
    static let quietModeKey = "debug.quietModeEnabled"
    static let enabledChannelsKey = "debug.enabledChannels"

    static var isEnabled: Bool {
        get {
            UserDefaults.standard.bool(forKey: enabledKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: enabledKey)
        }
    }

    static var isQuietModeEnabled: Bool {
        get {
            UserDefaults.standard.bool(forKey: quietModeKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: quietModeKey)
        }
    }

    static var enabledChannels: Set<DebugChannel> {
        get {
            let rawValues = UserDefaults.standard.stringArray(forKey: enabledChannelsKey) ?? []
            return Set(rawValues.compactMap(DebugChannel.init(rawValue:)))
        }
        set {
            let rawValues = newValue.map(\.rawValue).sorted()
            UserDefaults.standard.set(rawValues, forKey: enabledChannelsKey)
        }
    }

    static func canCapture(channel: DebugChannel) -> Bool {
        isEnabled && enabledChannels.contains(channel)
    }
}

@MainActor
final class DebugManager: ObservableObject {
    static let shared = DebugManager()

    @Published var isEnabled: Bool {
        didSet {
            DebugSettingsStore.isEnabled = isEnabled
        }
    }

    @Published var isQuietModeEnabled: Bool {
        didSet {
            DebugSettingsStore.isQuietModeEnabled = isQuietModeEnabled
        }
    }

    @Published private(set) var enabledChannels: Set<DebugChannel> {
        didSet {
            DebugSettingsStore.enabledChannels = enabledChannels
        }
    }

    @Published private(set) var messages: [DebugMessage] = []

    private let maxMessageCount = 2_000
    private let timestampFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private init() {
        self.isEnabled = DebugSettingsStore.isEnabled
        self.isQuietModeEnabled = DebugSettingsStore.isQuietModeEnabled
        self.enabledChannels = DebugSettingsStore.enabledChannels
    }

    var activeChannelSummary: String {
        let activeChannels = DebugChannel.allCases.filter { enabledChannels.contains($0) }
        guard !activeChannels.isEmpty else { return "No channels active" }
        return activeChannels.map(\.displayName).joined(separator: ", ")
    }

    var hasMessages: Bool {
        !messages.isEmpty
    }

    func isChannelEnabled(_ channel: DebugChannel) -> Bool {
        enabledChannels.contains(channel)
    }

    func setChannel(_ channel: DebugChannel, enabled: Bool) {
        if enabled {
            enabledChannels.insert(channel)
        } else {
            enabledChannels.remove(channel)
        }
    }

    func enableAllChannels() {
        enabledChannels = Set(DebugChannel.allCases)
    }

    func disableAllChannels() {
        enabledChannels = []
    }

    func clear() {
        messages.removeAll()
    }

    func append(message: String, channel: DebugChannel, source: String) {
        messages.append(DebugMessage(
            timestamp: Date(),
            channel: channel,
            source: source,
            message: message
        ))

        if messages.count > maxMessageCount {
            messages.removeFirst(messages.count - maxMessageCount)
        }
    }

    func formattedLogText() -> String {
        let header = [
            "App: \(appName)",
            "Generated: \(timestampFormatter.string(from: Date()))",
            "Device: \(deviceLabel)",
            "Active Channels: \(activeChannelSummary)",
            ""
        ].joined(separator: "\n")

        guard !messages.isEmpty else {
            return header
        }

        let body = messages.map { message in
            let timestamp = timestampFormatter.string(from: message.timestamp)
            return "\(timestamp) [\(message.channel.displayName)] [\(message.source)] \(message.message)"
        }.joined(separator: "\n")

        return header + body
    }

    func makeTemporaryLogFile() throws -> URL {
        let timestamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ArmadilloAssistant-DebugLog-\(timestamp).txt")

        try formattedLogText().write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }

    private var appName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? "ArmadilloAssistant"
    }

    private var deviceLabel: String {
        let device = UIDevice.current
        return "\(device.model) \(device.systemName) \(device.systemVersion)"
    }
}

enum Debug {
    static func log(
        _ message: @autoclosure @escaping () -> String,
        channel: DebugChannel,
        source: String = "App"
    ) {
        guard DebugSettingsStore.canCapture(channel: channel) else { return }
        let evaluatedMessage = message()
        guard !(channel == .cloudKitEvents
                && evaluatedMessage.contains("status=not-succeeded")
                && evaluatedMessage.contains("end=nil")) else {
            return
        }

        if DebugSettingsStore.isQuietModeEnabled,
           shouldSuppressInQuietMode(evaluatedMessage, channel: channel) {
            return
        }

        Task { @MainActor in
            DebugManager.shared.append(
                message: evaluatedMessage,
                channel: channel,
                source: source
            )
        }
    }

    private static func shouldSuppressInQuietMode(_ message: String, channel: DebugChannel) -> Bool {
        switch channel {
        case .cloudKitEvents:
            return message.contains("status=succeeded")

        case .sync:
            return message.contains("Starting pending public CloudKit reconciliation")
                || message.contains("Completed pending public CloudKit reconciliation")

        case .uiRefresh:
            return message.contains("App-wide Core Data refresh completed")

        case .bookingReconcile:
            return message.contains("booking stale cleanup skipped by policy")

        case .expenseReconcile:
            return message.contains("local stale expenses removed=0")
                && message.contains("local missing expenses created=0")
                && message.contains("local expenses updated=0")
                && message.contains("pending-protected=0")
                && message.contains("missing-local-id=0")

        case .pendingLedger, .importPipeline, .exportPipeline:
            return false
        }
    }
}
