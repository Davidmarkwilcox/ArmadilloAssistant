import SwiftUI

// Custom tab-based root navigation (no NavigationStack) to avoid opaque container backgrounds.
struct ContentView: View {

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
        TabView {
            PlaceholderScreen(title: "Expenses", subtitle: "Track expenses by property, category, and period.")
                .tabItem {
                    Label("Expenses", systemImage: Tab.expenses.systemImageName)
                }

            BookingsView()
                .tabItem {
                    Label("Bookings", systemImage: Tab.bookings.systemImageName)
                }

            PlaceholderScreen(title: "Narrative", subtitle: "Write notes, operational logs, and property narratives.")
                .tabItem {
                    Label("Narrative", systemImage: Tab.narrative.systemImageName)
                }

            PlaceholderScreen(title: "Settings", subtitle: "Partners, notifications, and app preferences.")
                .tabItem {
                    Label("Settings", systemImage: Tab.settings.systemImageName)
                }
        }
        .tint(Theme.Colors.crimson)
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
