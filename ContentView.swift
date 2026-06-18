import SwiftUI
import CoreData
import Combine

// Custom tab-based root navigation (no NavigationStack) to avoid opaque container backgrounds.
struct ContentView: View {
    @AppStorage("selected_root_tab") private var storedSelectedTabRawValue: String = Tab.expenses.rawValue
    @Environment(\.managedObjectContext) private var viewContext

    @StateObject private var appLock = AppLockManager.shared
    @State private var isShowingGlobalSearch: Bool = false
    @State private var pendingGlobalSearchDestination: GlobalSearchDestination?
    @State private var lastAppWideRefreshDate = Date.distantPast
    @State private var appRefreshToken = UUID()

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

    enum SettingsSubsectionDestination: String, CaseIterable, Identifiable, Hashable {
        case profile = "Profile"
        case property = "Property"
        case expenses = "Expenses"
        case dataManagement = "Data Management"
        case debug = "Debug"

        var id: String { rawValue }

        var systemImageName: String {
            switch self {
            case .profile: return "person.crop.circle"
            case .property: return "house"
            case .expenses: return "dollarsign.circle"
            case .dataManagement: return "tray.2"
            case .debug: return "ladybug"
            }
        }
    }

    enum GlobalSearchDestination: Hashable {
        case screen(Tab)
        case settingsSubsection(SettingsSubsectionDestination)
        case booking(UUID)
        case expense(UUID)
        case narrative(String)
    }

    struct GlobalSearchResult: Identifiable, Hashable {
        enum Section: String, CaseIterable {
            case screens = "Screens"
            case settings = "Settings"
            case bookings = "Reservations"
            case expenses = "Expenses"
            case narratives = "Narratives"
        }

        let id: String
        let section: Section
        let title: String
        let subtitle: String
        let systemImageName: String
        let destination: GlobalSearchDestination
    }

    struct StaticSearchEntry: Identifiable {
        let id: String
        let title: String
        let subtitle: String
        let systemImageName: String
        let matchTerms: [String]
        let destination: GlobalSearchDestination
    }

    private static let screenEntries: [StaticSearchEntry] = Tab.allCases.map { tab in
        let aliases: [String]
        switch tab {
        case .expenses:
            aliases = ["Expenses"]
        case .bookings:
            aliases = ["Bookings", "Reservations"]
        case .narrative:
            aliases = ["Narrative", "Narratives"]
        case .settings:
            aliases = ["Settings"]
        }

        return StaticSearchEntry(
            id: "screen-\(tab.rawValue)",
            title: tab.rawValue,
            subtitle: "Screen",
            systemImageName: tab.systemImageName,
            matchTerms: aliases,
            destination: .screen(tab)
        )
    }

    private static let settingsEntries: [StaticSearchEntry] = SettingsSubsectionDestination.allCases.map { destination in
        StaticSearchEntry(
            id: "settings-\(destination.rawValue)",
            title: destination.rawValue,
            subtitle: "Settings",
            systemImageName: destination.systemImageName,
            matchTerms: [destination.rawValue, "Settings"],
            destination: .settingsSubsection(destination)
        )
    }

    init() {
        UITabBar.appearance().tintColor = UIColor.white
        UITabBar.appearance().unselectedItemTintColor = UIColor(Theme.Colors.crimson)
    }

    private var selectedTab: Binding<Tab> {
        Binding(
            get: { Tab(rawValue: storedSelectedTabRawValue) ?? .expenses },
            set: { storedSelectedTabRawValue = $0.rawValue }
        )
    }

    private var pendingExpenseSelectionID: UUID? {
        guard case .expense(let id) = pendingGlobalSearchDestination else { return nil }
        return id
    }

    private var pendingBookingSelectionID: UUID? {
        guard case .booking(let id) = pendingGlobalSearchDestination else { return nil }
        return id
    }

    private var pendingNarrativeSelectionID: String? {
        guard case .narrative(let id) = pendingGlobalSearchDestination else { return nil }
        return id
    }

    private var pendingSettingsDestination: SettingsSubsectionDestination? {
        guard case .settingsSubsection(let destination) = pendingGlobalSearchDestination else { return nil }
        return destination
    }

    private func handleGlobalSearchSelection(_ destination: GlobalSearchDestination) {
        switch destination {
        case .screen(let tab):
            pendingGlobalSearchDestination = nil
            storedSelectedTabRawValue = tab.rawValue
        case .settingsSubsection:
            pendingGlobalSearchDestination = destination
            storedSelectedTabRawValue = Tab.settings.rawValue
        case .booking:
            pendingGlobalSearchDestination = destination
            storedSelectedTabRawValue = Tab.bookings.rawValue
        case .expense:
            pendingGlobalSearchDestination = destination
            storedSelectedTabRawValue = Tab.expenses.rawValue
        case .narrative:
            pendingGlobalSearchDestination = destination
            storedSelectedTabRawValue = Tab.narrative.rawValue
        }

        isShowingGlobalSearch = false
    }

    private func refreshAllAppData(force: Bool = false) {
        let now = Date()
        let minimumRefreshInterval: TimeInterval = force ? 0 : 5

        guard force || now.timeIntervalSince(lastAppWideRefreshDate) >= minimumRefreshInterval else {
            return
        }

        lastAppWideRefreshDate = now

        PersistenceController.shared.reconcilePendingPublicCloudKitChanges {
            DispatchQueue.main.async {
                self.viewContext.refreshAllObjects()
                self.viewContext.processPendingChanges()
                self.updateDebugSessionSummary(refreshDate: Date())
                self.appRefreshToken = UUID()

                Debug.log(
                    "App-wide Core Data refresh completed token=\(self.appRefreshToken)",
                    channel: .uiRefresh,
                    source: "ContentView"
                )
            }
        }
    }

    private func updateDebugSessionSummary(refreshDate: Date) {
        let expenseCount = fetchEntityCount(entityName: "Expense")
        let bookingCount = fetchEntityCount(entityName: "Booking")
        let selectedTabName = selectedTab.wrappedValue.rawValue

        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .medium

        DebugManager.shared.updateSessionSummary([
            "Selected tab: \(selectedTabName)",
            "Local Expense count: \(expenseCount.map(String.init) ?? "Unavailable")",
            "Local Booking count: \(bookingCount.map(String.init) ?? "Unavailable")",
            "Last app-wide refresh: \(formatter.string(from: refreshDate))",
            "CloudKit reached: see CloudKit Events / Reconcile entries for latest result"
        ])
    }

    private func fetchEntityCount(entityName: String) -> Int? {
        let request = NSFetchRequest<NSFetchRequestResult>(entityName: entityName)
        request.includesSubentities = false

        do {
            return try viewContext.count(for: request)
        } catch {
            Debug.log(
                "Failed to fetch \(entityName) count for debug summary: \(error.localizedDescription)",
                channel: .uiRefresh,
                source: "ContentView"
            )
            return nil
        }
    }

    var body: some View {
        ZStack {
            TabView(selection: selectedTab) {
                ExpensesView(
                    onSearchTapped: {
                        isShowingGlobalSearch = true
                    },
                    externalExpenseSelectionID: pendingExpenseSelectionID,
                    onHandledExternalExpenseSelection: {
                        if case .expense = pendingGlobalSearchDestination {
                            pendingGlobalSearchDestination = nil
                        }
                    },
                    appRefreshToken: appRefreshToken
                )
                .tag(Tab.expenses)
                .tabItem {
                    Label("Expenses", systemImage: Tab.expenses.systemImageName)
                }

                BookingsView(
                    onSearchTapped: {
                        isShowingGlobalSearch = true
                    },
                    externalBookingSelectionID: pendingBookingSelectionID,
                    onHandledExternalBookingSelection: {
                        if case .booking = pendingGlobalSearchDestination {
                            pendingGlobalSearchDestination = nil
                        }
                    },
                    appRefreshToken: appRefreshToken
                )
                .tag(Tab.bookings)
                .tabItem {
                    Label("Bookings", systemImage: Tab.bookings.systemImageName)
                }

                NarrativeView(
                    onSearchTapped: {
                        isShowingGlobalSearch = true
                    },
                    externalNarrativeSelectionID: pendingNarrativeSelectionID,
                    onHandledExternalNarrativeSelection: {
                        if case .narrative = pendingGlobalSearchDestination {
                            pendingGlobalSearchDestination = nil
                        }
                    }
                )
                .tag(Tab.narrative)
                .tabItem {
                    Label("Narrative", systemImage: Tab.narrative.systemImageName)
                }

                SettingsView(
                    onSearchTapped: {
                        isShowingGlobalSearch = true
                    },
                    externalSettingsDestination: pendingSettingsDestination,
                    onHandledExternalSettingsDestination: {
                        if case .settingsSubsection = pendingGlobalSearchDestination {
                            pendingGlobalSearchDestination = nil
                        }
                    }
                )
                .tag(Tab.settings)
                .tabItem {
                    Label("Settings", systemImage: Tab.settings.systemImageName)
                }
            }
            .tint(Theme.Colors.crimson)
            .sheet(isPresented: $isShowingGlobalSearch) {
                GlobalSearchView(
                    screenEntries: Self.screenEntries,
                    settingsEntries: Self.settingsEntries,
                    onSelectDestination: handleGlobalSearchSelection
                )
            }
            .onReceive(
                NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)
                    .receive(on: RunLoop.main)
            ) { _ in
                refreshAllAppData()
            }
            .onReceive(
                NotificationCenter.default.publisher(for: .NSPersistentStoreRemoteChange)
                    .receive(on: RunLoop.main)
            ) { _ in
                refreshAllAppData()
            }
            .onReceive(
                NotificationCenter.default.publisher(for: .armadilloAssistantRefreshAllAppData)
                    .receive(on: RunLoop.main)
            ) { _ in
                refreshAllAppData(force: true)
            }

            if appLock.isLocked {
                VStack(spacing: Theme.Spacing.l) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(Theme.Colors.textPrimary)

                    Text("Unlock Armadillo Assistant")
                        .font(Theme.Typography.headline())
                        .foregroundStyle(Theme.Colors.textPrimary)

                    if appLock.isAuthenticating {
                        ProgressView()
                            .tint(Theme.Colors.textPrimary)
                    }

                    if !appLock.authenticationErrorMessage.isEmpty {
                        Text(appLock.authenticationErrorMessage)
                            .font(Theme.Typography.caption())
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, Theme.Spacing.xl)
                    }

                    Button("Unlock") {
                        appLock.authenticate()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(appLock.isAuthenticating)
                    .onAppear {
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

private struct GlobalSearchView: View {
    let screenEntries: [ContentView.StaticSearchEntry]
    let settingsEntries: [ContentView.StaticSearchEntry]
    let onSelectDestination: (ContentView.GlobalSearchDestination) -> Void

    @Environment(\.dismiss) private var dismiss

    @FetchRequest(
        sortDescriptors: [
            NSSortDescriptor(key: "checkInDate", ascending: false),
            NSSortDescriptor(key: "createdAt", ascending: false)
        ],
        animation: .default
    ) private var bookings: FetchedResults<Booking>

    @FetchRequest(
        sortDescriptors: [
            NSSortDescriptor(key: "expenseDate", ascending: false),
            NSSortDescriptor(key: "createdAt", ascending: false)
        ],
        animation: .default
    ) private var expenses: FetchedResults<Expense>

    @State private var query: String = ""

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter
    }()

    private static let currencyFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        return formatter
    }()

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var screenResults: [ContentView.GlobalSearchResult] {
        filteredStaticResults(from: screenEntries, section: .screens)
    }

    private var settingsResults: [ContentView.GlobalSearchResult] {
        filteredStaticResults(from: settingsEntries, section: .settings)
    }

    private var bookingResults: [ContentView.GlobalSearchResult] {
        guard !trimmedQuery.isEmpty else { return [] }

        return bookings.compactMap { booking in
            guard let id = booking.id else { return nil }

            let firstName = booking.renterFirstName ?? ""
            let lastName = booking.renterLastName ?? ""
            let fullName = "\(firstName) \(lastName)".trimmingCharacters(in: .whitespacesAndNewlines)
            let title = fullName.isEmpty ? "Unnamed Reservation" : fullName
            let searchTerms = [
                firstName,
                lastName,
                fullName,
                booking.emailAddress ?? "",
                booking.phoneNumber ?? "",
                booking.notes ?? "",
                booking.bookingReason ?? "",
                booking.propertyName ?? "",
                booking.bookingSource ?? "",
                booking.status ?? ""
            ]

            guard searchTerms.contains(where: { $0.localizedCaseInsensitiveContains(trimmedQuery) }) else {
                return nil
            }

            let checkIn = booking.checkInDate.map { Self.dateFormatter.string(from: $0) } ?? "Unknown"
            let checkOut = booking.checkOutDate.map { Self.dateFormatter.string(from: $0) } ?? "Unknown"
            let subtitleComponents = [
                nonEmpty(booking.propertyName),
                "\(checkIn) - \(checkOut)",
                nonEmpty(booking.status)
            ].compactMap { $0 }

            return ContentView.GlobalSearchResult(
                id: "booking-\(id.uuidString)",
                section: .bookings,
                title: title,
                subtitle: subtitleComponents.joined(separator: " • "),
                systemImageName: "calendar",
                destination: .booking(id)
            )
        }
    }

    private var expenseResults: [ContentView.GlobalSearchResult] {
        guard !trimmedQuery.isEmpty else { return [] }

        return expenses.compactMap { expense in
            guard let id = expense.id else { return nil }

            let project = expense.project ?? ""
            let category = expense.category ?? ""
            let title = nonEmpty(project) ?? nonEmpty(category) ?? "Expense"
            let searchTerms = [
                expense.notes ?? "",
                category,
                project,
                expense.expenser ?? "",
                expense.expenseType ?? ""
            ]

            guard searchTerms.contains(where: { $0.localizedCaseInsensitiveContains(trimmedQuery) }) else {
                return nil
            }

            let formattedDate = expense.expenseDate.map { Self.dateFormatter.string(from: $0) } ?? "Unknown Date"
            let formattedAmount = Self.currencyFormatter.string(from: NSNumber(value: expense.reimbursementAmount)) ?? "$0.00"
            let subtitleComponents = [
                nonEmpty(expense.expenser),
                formattedDate,
                formattedAmount
            ].compactMap { $0 }

            return ContentView.GlobalSearchResult(
                id: "expense-\(id.uuidString)",
                section: .expenses,
                title: title,
                subtitle: subtitleComponents.joined(separator: " • "),
                systemImageName: "dollarsign.circle",
                destination: .expense(id)
            )
        }
    }

    private var narrativeResults: [ContentView.GlobalSearchResult] {
        guard !trimmedQuery.isEmpty else { return [] }

        return NarrativeView.allNarratives.compactMap { narrative in
            guard narrative.title.localizedCaseInsensitiveContains(trimmedQuery) else { return nil }

            return ContentView.GlobalSearchResult(
                id: "narrative-\(narrative.id)",
                section: .narratives,
                title: narrative.title,
                subtitle: "Narrative",
                systemImageName: "doc.text",
                destination: .narrative(narrative.id)
            )
        }
    }

    private var hasVisibleResults: Bool {
        !screenResults.isEmpty
            || !settingsResults.isEmpty
            || !bookingResults.isEmpty
            || !expenseResults.isEmpty
            || !narrativeResults.isEmpty
    }

    var body: some View {
        NavigationStack {
            List {
                if trimmedQuery.isEmpty {
                    if !screenResults.isEmpty {
                        resultsSection(title: ContentView.GlobalSearchResult.Section.screens.rawValue, results: screenResults)
                    }

                    if !settingsResults.isEmpty {
                        resultsSection(title: "Settings", results: settingsResults)
                    }

                    Section {
                        Text("Search screens, settings, reservations, expenses, and narratives.")
                            .foregroundStyle(.secondary)
                    }
                } else if hasVisibleResults {
                    if !screenResults.isEmpty {
                        resultsSection(title: ContentView.GlobalSearchResult.Section.screens.rawValue, results: screenResults)
                    }

                    if !settingsResults.isEmpty {
                        resultsSection(title: "Settings", results: settingsResults)
                    }

                    if !bookingResults.isEmpty {
                        resultsSection(title: ContentView.GlobalSearchResult.Section.bookings.rawValue, results: bookingResults)
                    }

                    if !expenseResults.isEmpty {
                        resultsSection(title: ContentView.GlobalSearchResult.Section.expenses.rawValue, results: expenseResults)
                    }

                    if !narrativeResults.isEmpty {
                        resultsSection(title: ContentView.GlobalSearchResult.Section.narratives.rawValue, results: narrativeResults)
                    }
                } else {
                    Section {
                        Text("No results found for \"\(trimmedQuery)\".")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always))
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                }
            }
        }
    }

    @ViewBuilder
    private func resultsSection(title: String, results: [ContentView.GlobalSearchResult]) -> some View {
        Section(title) {
            ForEach(results) { result in
                Button {
                    onSelectDestination(result.destination)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: result.systemImageName)
                            .foregroundStyle(.secondary)
                            .frame(width: 20)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(result.title)
                                .foregroundStyle(.primary)

                            if !result.subtitle.isEmpty {
                                Text(result.subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Spacer()
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func filteredStaticResults(
        from entries: [ContentView.StaticSearchEntry],
        section: ContentView.GlobalSearchResult.Section
    ) -> [ContentView.GlobalSearchResult] {
        let filteredEntries: [ContentView.StaticSearchEntry]

        if trimmedQuery.isEmpty {
            filteredEntries = entries
        } else {
            filteredEntries = entries.filter { entry in
                entry.matchTerms.contains { $0.localizedCaseInsensitiveContains(trimmedQuery) }
            }
        }

        return filteredEntries.map { entry in
            ContentView.GlobalSearchResult(
                id: entry.id,
                section: section,
                title: entry.title,
                subtitle: entry.subtitle,
                systemImageName: entry.systemImageName,
                destination: entry.destination
            )
        }
    }

    private func nonEmpty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}

#Preview {
    ContentView()
}

extension Notification.Name {
    static let armadilloAssistantRefreshAllAppData = Notification.Name("ArmadilloAssistantRefreshAllAppData")
}
