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
    
    // MARK: - 1.1 State
    
    @State private var selectedProperties: Set<Property> = []
    @State private var selectedYears: Set<Int> = []
    
    @State private var isShowingYearPicker: Bool = false
    
    @State private var selectedNarrative: NarrativeItem?
    
    // Placeholder options (prototype only)
    private let properties = Property.allCases
    private let years = [2023, 2024, 2025, 2026]
    
    // Narrative options (from screenshots)
    private let narratives: [NarrativeItem] = [
        NarrativeItem(title: "How many inquiries this month?"),
        NarrativeItem(title: "How many bookings this month?"),
        NarrativeItem(title: "What is our booking % this month?"),
        NarrativeItem(title: "How much revenue was inquired about this month?"),
        NarrativeItem(title: "How much revenue has been booked this month?"),
        NarrativeItem(title: "What do bookings look like?"),
        NarrativeItem(title: "What do total nights booked look like?"),
        NarrativeItem(title: "What does revenue look like?"),
        NarrativeItem(title: "How many inquiries last month?"),
        NarrativeItem(title: "How many bookings last month?"),
        NarrativeItem(title: "What was our booking % last month?"),
        NarrativeItem(title: "How much revenue was inquired about last month?"),
        NarrativeItem(title: "How much revenue was booked last month?"),
        NarrativeItem(title: "What does January look like?"),
        NarrativeItem(title: "What does February look like?"),
        NarrativeItem(title: "What does March look like?"),
        NarrativeItem(title: "What does April look like?"),
        NarrativeItem(title: "What does May look like?"),
        NarrativeItem(title: "What does June look like?"),
        NarrativeItem(title: "What does July look like?"),
        NarrativeItem(title: "What does August look like?"),
        NarrativeItem(title: "What does September look like?"),
        NarrativeItem(title: "What does October look like?"),
        NarrativeItem(title: "What does November look like?"),
        NarrativeItem(title: "What does December look like?"),
        NarrativeItem(title: "In general, how far ahead of the stay do people inquire?")
    ]
    
    private var availableYears: [Int] {
        years.sorted(by: >)
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
                Theme.BrandedHeaderView(title: "Narratives")

                List {
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
                        ForEach(narratives) { narrative in
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
                            Text("\(narratives.count)")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
            // Hide the system nav bar so only the branded header is shown.
            .toolbar(.hidden, for: .navigationBar)
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

// MARK: - 4. NarrativeItem Model (Prototype)

struct NarrativeItem: Identifiable {
    let id = UUID()
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
