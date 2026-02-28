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

    @State private var selectedTab: Tab = .bookings

    var body: some View {
        ZStack {
            Theme.MetallicBackground()

            VStack(spacing: 0) {
                // MARK: - 2) Active Screen
                Group {
                    switch selectedTab {
                    case .expenses:
                        PlaceholderScreen(title: "Expenses", subtitle: "Track expenses by property, category, and period.")
                    case .bookings:
                        NavigationStack {
                            BookingsView()
                        }
                    case .narrative:
                        PlaceholderScreen(title: "Narrative", subtitle: "Write notes, operational logs, and property narratives.")
                    case .settings:
                        PlaceholderScreen(title: "Settings", subtitle: "Partners, notifications, and app preferences.")
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                // MARK: - 3) Tab Bar
                TabBar(selectedTab: $selectedTab)
            }
        }
    }
}

// MARK: - Tab Bar

private struct TabBar: View {
    @Binding var selectedTab: ContentView.Tab

    var body: some View {
        HStack {
            ForEach(ContentView.Tab.allCases) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: tab.systemImageName)
                            .font(.system(size: 18, weight: .semibold))

                        Text(tab.rawValue)
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .foregroundStyle(selectedTab == tab ? Theme.Colors.textPrimary : Theme.Colors.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, Theme.Spacing.m)
        .padding(.bottom, 10)
        .background(
            ZStack {
                // Industrial red steel base (near full opacity, heavier contrast)
                LinearGradient(
                    stops: [
                        .init(color: Theme.Colors.crimson.opacity(0.98), location: 0.00),
                        .init(color: Theme.Colors.crimson.opacity(0.92), location: 0.20),
                        .init(color: Theme.Colors.crimson.opacity(0.88), location: 0.72),
                        .init(color: Theme.Colors.crimson.opacity(0.99), location: 1.00)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                // Sharper steel sheen (harder highlight)
                LinearGradient(
                    stops: [
                        .init(color: .white.opacity(0.00), location: 0.00),
                        .init(color: .white.opacity(0.28), location: 0.18),
                        .init(color: .white.opacity(0.00), location: 0.36),
                        .init(color: .white.opacity(0.20), location: 0.58),
                        .init(color: .white.opacity(0.00), location: 1.00)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .rotationEffect(.degrees(-22))
                .blendMode(.screen)

                // Subtle brushed horizontal steel texture
                LinearGradient(
                    gradient: Gradient(stops: [
                        .init(color: .white.opacity(0.00), location: 0.00),
                        .init(color: .white.opacity(0.06), location: 0.50),
                        .init(color: .white.opacity(0.00), location: 1.00)
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .scaleEffect(x: 1.0, y: 14.0, anchor: .center)
                .opacity(0.75)
                .blendMode(.overlay)

                // Heavier bottom depth shadow
                LinearGradient(
                    colors: [
                        Color.black.opacity(0.35),
                        Color.clear
                    ],
                    startPoint: .bottom,
                    endPoint: .top
                )
                .blendMode(.multiply)

                // Stronger top separator
                Rectangle()
                    .frame(height: 1)
                    .foregroundStyle(Theme.Colors.strokeStrong.opacity(0.95))
                    .frame(maxHeight: .infinity, alignment: .top)
            }
        )
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
