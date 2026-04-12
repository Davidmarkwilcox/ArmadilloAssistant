//  NarrativeView.swift
//  ArmadilloAssistant
//
//  Description:
//  NarrativeView presents high-level narrative reporting options for the user.
//  This prototype version includes:
//  1) Branding Header (mirrors BookingsView pattern)
//  2) Filter Section (Properties + Years multi-select placeholders)
//  3) Narrative List Section
//  4) Detail modal with Share functionality
//  
//  NOTE: Calculations will be sourced from NarrativeCalculations.swift in a later step.
//

import SwiftUI

// MARK: - 1. NarrativeView

// MARK: - 1.0 Models (Prototype)

enum Property: String, CaseIterable, Identifiable, Hashable {
    case mainStreet = "Main Street"
    case barndo = "Barndo"
    case alamo = "Alamo"

    var id: String { rawValue }
}

struct NarrativeView: View {
    private static let recentSearchesKey = "recent_searches_narrative"
    static let allNarratives: [NarrativeItem] = [
        NarrativeItem(id: "inquiries_this_month", title: "How many inquiries this month?"),
        NarrativeItem(id: "bookings_this_month", title: "How many bookings this month?"),
        NarrativeItem(id: "booking_percent_this_month", title: "What is our booking % this month?"),
        NarrativeItem(id: "inquired_revenue_this_month", title: "How much revenue was inquired about this month?"),
        NarrativeItem(id: "booked_revenue_this_month", title: "How much revenue has been booked this month?"),
        NarrativeItem(id: "bookings_overview", title: "What do bookings look like?"),
        NarrativeItem(id: "nights_booked_overview", title: "What do total nights booked look like?"),
        NarrativeItem(id: "revenue_overview", title: "What does revenue look like?"),
        NarrativeItem(id: "inquiries_last_month", title: "How many inquiries last month?"),
        NarrativeItem(id: "bookings_last_month", title: "How many bookings last month?"),
        NarrativeItem(id: "booking_percent_last_month", title: "What was our booking % last month?"),
        NarrativeItem(id: "inquired_revenue_last_month", title: "How much revenue was inquired about last month?"),
        NarrativeItem(id: "booked_revenue_last_month", title: "How much revenue was booked last month?"),
        NarrativeItem(id: "january_overview", title: "What does January look like?"),
        NarrativeItem(id: "february_overview", title: "What does February look like?"),
        NarrativeItem(id: "march_overview", title: "What does March look like?"),
        NarrativeItem(id: "april_overview", title: "What does April look like?"),
        NarrativeItem(id: "may_overview", title: "What does May look like?"),
        NarrativeItem(id: "june_overview", title: "What does June look like?"),
        NarrativeItem(id: "july_overview", title: "What does July look like?"),
        NarrativeItem(id: "august_overview", title: "What does August look like?"),
        NarrativeItem(id: "september_overview", title: "What does September look like?"),
        NarrativeItem(id: "october_overview", title: "What does October look like?"),
        NarrativeItem(id: "november_overview", title: "What does November look like?"),
        NarrativeItem(id: "december_overview", title: "What does December look like?"),
        NarrativeItem(id: "lead_time_general", title: "In general, how far ahead of the stay do people inquire?")
    ]

    let onSearchTapped: () -> Void
    let externalNarrativeSelectionID: String?
    let onHandledExternalNarrativeSelection: () -> Void
    
    // MARK: - 1.1 State
    
    @State private var selectedProperties: Set<Property> = []
    @State private var selectedYears: Set<Int> = []
    @State private var searchText: String = ""
    @State private var recentSearches: [String] = []
    @FocusState private var isSearchFieldFocused: Bool
    
    @State private var isShowingYearPicker: Bool = false
    
    @State private var selectedNarrative: NarrativeItem?
    
    // Placeholder options (prototype only)
    private let properties = Property.allCases
    private let years = [2023, 2024, 2025, 2026]
    
    private let narratives = Self.allNarratives

    init(
        onSearchTapped: @escaping () -> Void = {},
        externalNarrativeSelectionID: String? = nil,
        onHandledExternalNarrativeSelection: @escaping () -> Void = {}
    ) {
        self.onSearchTapped = onSearchTapped
        self.externalNarrativeSelectionID = externalNarrativeSelectionID
        self.onHandledExternalNarrativeSelection = onHandledExternalNarrativeSelection
    }
    
    private var availableYears: [Int] {
        years.sorted(by: >)
    }

    private var trimmedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var shouldShowRecentSearches: Bool {
        isSearchFieldFocused && trimmedSearchText.isEmpty && !recentSearches.isEmpty
    }

    private var filteredNarratives: [NarrativeItem] {
        let query = trimmedSearchText
        guard !query.isEmpty else { return narratives }

        return narratives.filter { narrative in
            narrative.title.localizedCaseInsensitiveContains(query)
        }
    }

    private func loadRecentSearches() {
        let savedSearches = UserDefaults.standard.stringArray(forKey: Self.recentSearchesKey) ?? []
        recentSearches = Array(savedSearches.prefix(5))
    }

    private func saveRecentSearches(_ searches: [String]) {
        let limitedSearches = Array(searches.prefix(5))
        recentSearches = limitedSearches
        UserDefaults.standard.set(limitedSearches, forKey: Self.recentSearchesKey)
    }

    private func recordRecentSearch(_ rawValue: String) {
        let trimmedValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedValue.isEmpty else { return }

        var updatedSearches = recentSearches.filter {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).localizedCaseInsensitiveCompare(trimmedValue) != .orderedSame
        }
        updatedSearches.insert(trimmedValue, at: 0)
        saveRecentSearches(updatedSearches)
    }

    private func commitSearchIfNeeded() {
        let trimmedValue = trimmedSearchText
        guard !trimmedValue.isEmpty else { return }
        searchText = trimmedValue
        recordRecentSearch(trimmedValue)
    }

    private func applyRecentSearch(_ search: String) {
        let trimmedValue = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedValue.isEmpty else { return }
        searchText = trimmedValue
        recordRecentSearch(trimmedValue)
        isSearchFieldFocused = true
    }

    private func clearRecentSearches() {
        recentSearches = []
        UserDefaults.standard.removeObject(forKey: Self.recentSearchesKey)
    }

    private func handleExternalNarrativeSelectionIfNeeded() {
        guard let externalNarrativeSelectionID else { return }
        defer { onHandledExternalNarrativeSelection() }

        guard let narrative = narratives.first(where: { $0.id == externalNarrativeSelectionID }) else {
            return
        }

        selectedNarrative = narrative
    }

    private var yearsButtonSubtitle: String {
        if selectedYears.isEmpty { return "All" }
        if Set(selectedYears) == Set(availableYears) { return "All" }
        return selectedYears.sorted(by: >).map(String.init).joined(separator: ", ")
    }

    private func isPropertySelected(_ property: Property) -> Bool {
        selectedProperties.isEmpty ? true : selectedProperties.contains(property)
    }

    private func toggleProperty(_ property: Property) {
        if selectedProperties.contains(property) {
            selectedProperties.remove(property)
        } else {
            selectedProperties.insert(property)
        }
    }

    private func filterChip(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .background(isSelected ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(isSelected ? Color.accentColor.opacity(0.55) : Color.primary.opacity(0.10), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Theme.BrandedHeaderView(title: "Narratives") {
                    Theme.HeaderActionButton(systemImageName: "magnifyingglass", action: onSearchTapped)
                }

                List {
                    Section {
                        VStack(alignment: .leading, spacing: 10) {
                            NarrativeInlineSearchField(
                                text: $searchText,
                                placeholder: "Search narrative",
                                isFocused: $isSearchFieldFocused,
                                onSubmit: commitSearchIfNeeded
                            )

                            if shouldShowRecentSearches {
                                VStack(alignment: .leading, spacing: 8) {
                                    ForEach(recentSearches, id: \.self) { recentSearch in
                                        Button {
                                            applyRecentSearch(recentSearch)
                                        } label: {
                                            HStack {
                                                Text(recentSearch)
                                                    .foregroundStyle(.primary)
                                                Spacer()
                                            }
                                        }
                                        .buttonStyle(.plain)
                                    }

                                    Button("Clear Recent Searches") {
                                        clearRecentSearches()
                                    }
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    }

                    // Filters
                    Section {
                        VStack(alignment: .leading, spacing: 12) {
                            // Property chips
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Property")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)

                                HStack(spacing: 10) {
                                    filterChip(title: Property.mainStreet.rawValue, isSelected: isPropertySelected(.mainStreet)) { toggleProperty(.mainStreet) }
                                    filterChip(title: Property.barndo.rawValue, isSelected: isPropertySelected(.barndo)) { toggleProperty(.barndo) }
                                    filterChip(title: Property.alamo.rawValue, isSelected: isPropertySelected(.alamo)) { toggleProperty(.alamo) }
                                }
                            }

                            // Years (multi-select)
                            Button {
                                isShowingYearPicker = true
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Years").font(.subheadline)
                                        Text(yearsButtonSubtitle)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(2)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.vertical, 4)
                    } header: {
                        Text("Filters")
                    }

                    // Narratives
                    Section {
                        ForEach(filteredNarratives) { narrative in
                            Button {
                                selectedNarrative = narrative
                            } label: {
                                HStack {
                                    Text(narrative.title)
                                        .font(.subheadline)
                                        .foregroundStyle(.primary)
                                        .lineLimit(2)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 4)
                            }
                            .buttonStyle(.plain)
                            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        }
                    } header: {
                        HStack {
                            Text("Narratives")
                            Spacer()
                            Text("\(filteredNarratives.count)")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
            // Hide the system nav bar so only the branded header is shown.
            .toolbar(.hidden, for: .navigationBar)
            .onAppear {
                loadRecentSearches()
                handleExternalNarrativeSelectionIfNeeded()
            }
            .onChange(of: externalNarrativeSelectionID) { _, _ in
                handleExternalNarrativeSelectionIfNeeded()
            }
            .sheet(isPresented: $isShowingYearPicker) {
                NavigationStack {
                    YearsPickerSheet(selectedYears: $selectedYears, availableYears: availableYears) {
                        isShowingYearPicker = false
                    }
                    .navigationTitle("Years")
                    .navigationBarTitleDisplayMode(.inline)
                }
            }
            .sheet(item: $selectedNarrative) { narrative in
                NarrativeDetailView(narrative: narrative)
            }
        }
    }
}

private struct NarrativeInlineSearchField: View {
    @Binding var text: String
    let placeholder: String
    @FocusState.Binding var isFocused: Bool
    let onSubmit: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField(placeholder, text: $text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .focused($isFocused)
                .onSubmit(onSubmit)

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.primary.opacity(0.06))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.primary.opacity(0.10), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - 4. NarrativeItem Model (Prototype)

struct NarrativeItem: Identifiable {
    let id: String
    let title: String
}

// MARK: - 5. Narrative Detail View

struct NarrativeDetailView: View {
    let narrative: NarrativeItem
    
    var body: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 20) {
                Text(narrative.title)
                    .font(.title2)
                    .bold()
                
                Text("Narrative calculations will be generated via NarrativeCalculations.swift.")
                    .foregroundColor(.secondary)
                
                Spacer()
            }
            .padding()
            .navigationTitle("Narrative Detail")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    ShareLink(
                        item: narrative.title,
                        subject: Text("Narrative Report")
                    ) {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
        }
    }
}

private struct YearsPickerSheet: View {

    @Binding var selectedYears: Set<Int>
    let availableYears: [Int]
    let onDone: () -> Void

    var body: some View {
        let allYearsSet = Set(availableYears)
        let isAllSelected = !availableYears.isEmpty && selectedYears == allYearsSet
        List {
            if availableYears.isEmpty {
                Text("No years available")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(availableYears, id: \.self) { year in
                    Toggle(String(year), isOn: Binding(
                        get: { selectedYears.contains(year) },
                        set: { isOn in
                            if isOn {
                                selectedYears.insert(year)
                            } else {
                                selectedYears.remove(year)
                            }
                        }
                    ))
                }

                Button(isAllSelected ? "Clear All" : "Select All") {
                    if isAllSelected {
                        // Clear filters (main view interprets empty as All)
                        selectedYears = []
                    } else {
                        selectedYears = allYearsSet
                    }
                }
            }
        }
        .onAppear {
            if selectedYears.isEmpty {
                selectedYears = allYearsSet
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { onDone() }
            }
        }
    }
}

#Preview {
    NarrativeView()
}
