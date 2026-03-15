import SwiftUI

// Custom tab-based root navigation (no NavigationStack) to avoid opaque container backgrounds.
struct ContentView: View {

    // MARK: - 0) App Lock
    // Use a StateObject so the view updates when `isLocked` changes.
    @StateObject private var appLock = AppLockManager.shared

    // MARK: - 1) Tabs
    enum Tab: String, CaseIterable, Identifiable {
        case expenses = "Expenses"
        case bookings = "Bookings"
        case narrative = "Narrative"
        case settings = "Settings"

        var id: String { rawValue }

        var systemImageName: String {
            switch self {
            case .expenses: return "dollarsign.circle"
            case .bookings: return "calendar"
            case .narrative: return "doc.text"
            case .settings: return "gearshape"
            }
        }
    }

    init() {
        // Selected tab (active) = white
        UITabBar.appearance().tintColor = UIColor.white

        // Inactive tab = crimson
        UITabBar.appearance().unselectedItemTintColor = UIColor(Theme.Colors.crimson)
    }

    var body: some View {
        ZStack {
            TabView {
                ExpensesView()
                    .tabItem {
                        Label("Expenses", systemImage: Tab.expenses.systemImageName)
                    }

                BookingsView()
                    .tabItem {
                        Label("Bookings", systemImage: Tab.bookings.systemImageName)
                    }

                NarrativeView()
                    .tabItem {
                        Label("Narrative", systemImage: Tab.narrative.systemImageName)
                    }

                SettingsView()
                    .tabItem {
                        Label("Settings", systemImage: Tab.settings.systemImageName)
                    }
            }
            .tint(Theme.Colors.crimson)

            // App Lock Overlay
            if appLock.isLocked {
                VStack(spacing: Theme.Spacing.l) {

                    Image(systemName: "lock.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(Theme.Colors.textPrimary)

                    Text("Unlock Armadillo Assistant")
                        .font(Theme.Typography.headline())
                        .foregroundStyle(Theme.Colors.textPrimary)

                    Button("Unlock") {
                        appLock.authenticate()
                    }
                    .buttonStyle(.borderedProminent)
                    .onAppear {
                        // Auto-prompt on lock screen appearance (Face ID first, passcode fallback).
                        appLock.authenticate()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black.opacity(0.9))
                .ignoresSafeArea()
            }
        }
    }
}

// MARK: - Placeholder Screen

private struct PlaceholderScreen: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 0) {
            Theme.CrimsonHeaderView(title: title)

            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.l) {

                    Text(subtitle)
                        .font(Theme.Typography.body())
                        .foregroundStyle(Theme.Colors.textSecondary)

                    VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                        Text("Next")
                            .font(Theme.Typography.headline())
                            .foregroundStyle(Theme.Colors.textPrimary)

                        Text("We’ll design this screen’s layout and actions next.")
                            .font(Theme.Typography.body())
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                    .themeCard(elevated: true)

                    Spacer(minLength: 0)
                }
                .padding(Theme.Spacing.m)
            }
            .scrollIndicators(.hidden)
        }
    }
}

#Preview {
    ContentView()
}
