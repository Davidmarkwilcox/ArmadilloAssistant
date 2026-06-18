//
//  DebugView.swift
//  ArmadilloAssistant
//
//  Standalone in-app debug module for SwiftUI apps.
//
//  What this file does:
//  - Provides a session-only in-app debug log for app-generated diagnostic messages.
//  - Persists Debug On/Off, Quiet Mode, and channel selections locally with UserDefaults.
//  - Keeps actual log contents in memory only, so logs start empty on each fresh app launch.
//  - Provides a SwiftUI DebugView with Debug, Quiet Mode, Copy, Share Log, Clear Log,
//    Enable All, Disable All, and per-channel toggles.
//  - Supports temporary .txt file sharing for ChatGPT review.
//
//  Quiet Mode:
//  - Suppresses routine/no-op messages while preserving errors, pending changes, and meaningful events.
//  - Domain-specific Quiet Mode filters live in Debug.shouldSuppressInQuietMode(_:channel:).
//
//  Adding a channel:
//  - Add a case to DebugChannel.
//  - Add its displayName mapping.
//  - Log from app code with: Debug.log("message", channel: .sync, source: "SomeFile")
//
//  Session summary:
//  - Update contextual header lines with: DebugManager.shared.updateSessionSummary([...])
//  - ArmadilloAssistant also injects the current user from these project-specific AppStorage keys:
//    profile_firstName, profile_lastName, profile_email.
//
//  Reuse notes for other projects:
//  - Reconfigure the app name/device header if needed.
//  - Replace or remove the current user summary AppStorage keys.
//  - Customize DebugChannel cases.
//  - Add a Settings/navigation entry point that presents DebugView().
//  - Review domain-specific Quiet Mode filters.
//

import Combine
import Foundation
import SwiftUI
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
    @Published private(set) var sessionSummaryLines: [String] = []

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

    func updateSessionSummary(_ lines: [String]) {
        sessionSummaryLines = lines.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
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
        var headerLines = [
            "App: \(appName)",
            "Generated: \(timestampFormatter.string(from: Date()))",
            "Device: \(deviceLabel)",
            "Active Channels: \(activeChannelSummary)"
        ]

        if !sessionSummaryLines.isEmpty {
            headerLines.append("")
            headerLines.append("Session Summary:")
            headerLines.append(contentsOf: sessionSummaryLines.map { "- \($0)" })
        }

        headerLines.append("")
        let header = headerLines.joined(separator: "\n")

        guard !messages.isEmpty else {
            return header
        }

        let body = messages.enumerated().map { index, message in
            let timestamp = timestampFormatter.string(from: message.timestamp)
            let entryNumber = index + 1
            return "\(entryNumber)) \(timestamp) [\(message.channel.displayName)] [\(message.source)] \(message.message)"
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

        case .uiRefresh:
            return false

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

struct DebugView: View {
    @ObservedObject private var debugManager = DebugManager.shared
    @AppStorage("profile_firstName") private var storedFirstName: String = ""
    @AppStorage("profile_lastName") private var storedLastName: String = ""
    @AppStorage("profile_email") private var storedEmail: String = ""
    @State private var debugShareItem: DebugShareItem?

    private struct DebugShareItem: Identifiable {
        let id = UUID()
        let url: URL
    }

    private var channelSummaryText: String {
        debugManager.activeChannelSummary
    }

    private var logText: String {
        formattedLogTextIncludingCurrentUser()
    }

    private var currentUserSummaryText: String {
        let displayName = [storedFirstName, storedLastName]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        if !displayName.isEmpty {
            return displayName
        }

        let email = storedEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        if !email.isEmpty {
            return email
        }

        return "Not set"
    }

    private func formattedLogTextIncludingCurrentUser() -> String {
        let baseText = debugManager.formattedLogText()
        let currentUserLine = "- Current user: \(currentUserSummaryText)"

        if baseText.contains("- Current user:") {
            return baseText
        }

        if baseText.contains("Session Summary:\n") {
            return baseText.replacingOccurrences(
                of: "Session Summary:\n",
                with: "Session Summary:\n\(currentUserLine)\n",
                options: [],
                range: baseText.range(of: "Session Summary:\n")
            )
        }

        if let activeChannelsRange = baseText.range(of: "Active Channels:") {
            let lineEnd = baseText[activeChannelsRange.upperBound...].firstIndex(of: "\n") ?? baseText.endIndex
            var updatedText = baseText
            updatedText.insert(contentsOf: "\n\nSession Summary:\n\(currentUserLine)", at: lineEnd)
            return updatedText
        }

        return "Session Summary:\n\(currentUserLine)\n\n\(baseText)"
    }

    private func binding(for channel: DebugChannel) -> Binding<Bool> {
        Binding(
            get: { debugManager.isChannelEnabled(channel) },
            set: { debugManager.setChannel(channel, enabled: $0) }
        )
    }

    private func copyLog() {
        updateDebugCurrentUserSummary()
        UIPasteboard.general.string = formattedLogTextIncludingCurrentUser()
    }

    private func shareLog() {
        updateDebugCurrentUserSummary()

        do {
            let url = try debugManager.makeTemporaryLogFile()
            debugShareItem = DebugShareItem(url: url)
        } catch {
            print("[DebugView] Failed to create debug log file: \(error.localizedDescription)")
        }
    }

    private func updateDebugCurrentUserSummary() {
        var summaryLines = debugManager.sessionSummaryLines.filter { !$0.hasPrefix("Current user:") }
        summaryLines.insert("Current user: \(currentUserSummaryText)", at: 0)
        debugManager.updateSessionSummary(summaryLines)
    }

    var body: some View {
        List {
            Section {
                Toggle("Debug", isOn: $debugManager.isEnabled)

                Toggle("Quiet Mode", isOn: $debugManager.isQuietModeEnabled)
                    .disabled(!debugManager.isEnabled)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Active Channels")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(channelSummaryText)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                }
                .padding(.vertical, 4)
            } footer: {
                Text("Debug messages are captured only when Debug is on and the message channel is enabled. Quiet Mode hides routine no-change sync messages while preserving errors, pending changes, and meaningful reconciliation activity.")
            }

            Section {
                Group {
                    if debugManager.hasMessages {
                        ScrollView {
                            Text(logText)
                                .font(.caption.monospaced())
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                                .padding(10)
                        }
                    } else {
                        Text("No debug messages this session.")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                    }
                }
                .frame(minHeight: 220, alignment: .topLeading)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            } header: {
                Text("Session Log")
            } footer: {
                Text("The log starts empty on each fresh app launch and is not saved between sessions.")
            }

            Section {
                Button {
                    copyLog()
                } label: {
                    Label("Copy to Clipboard", systemImage: "doc.on.doc")
                }
                .disabled(!debugManager.hasMessages)

                Button {
                    shareLog()
                } label: {
                    Label("Share Log", systemImage: "square.and.arrow.up")
                }
                .disabled(!debugManager.hasMessages)

                Button(role: .destructive) {
                    debugManager.clear()
                } label: {
                    Label("Clear Log", systemImage: "trash")
                }
                .disabled(!debugManager.hasMessages)
            }

            Section {
                Button {
                    debugManager.enableAllChannels()
                } label: {
                    Label("Enable All Channels", systemImage: "checkmark.circle")
                }

                Button {
                    debugManager.disableAllChannels()
                } label: {
                    Label("Disable All Channels", systemImage: "xmark.circle")
                }

                ForEach(DebugChannel.allCases) { channel in
                    Toggle(channel.displayName, isOn: binding(for: channel))
                }
            } header: {
                Text("Channels")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Debug")
        .sheet(item: $debugShareItem) { item in
            ActivityViewSheet(activityItems: [item.url])
        }
        .onAppear {
            updateDebugCurrentUserSummary()
        }
        .onChange(of: storedFirstName) { _, _ in
            updateDebugCurrentUserSummary()
        }
        .onChange(of: storedLastName) { _, _ in
            updateDebugCurrentUserSummary()
        }
        .onChange(of: storedEmail) { _, _ in
            updateDebugCurrentUserSummary()
        }
    }
}

struct ActivityViewSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(
            activityItems: activityItems,
            applicationActivities: nil
        )
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {
        // No live update needed. Each export uses a fresh sheet item.
    }
}
