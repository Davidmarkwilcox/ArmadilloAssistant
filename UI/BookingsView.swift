// BookingsView.swift
// ArmadilloAssistant
// Bookings screen
// - Shows an always-visible Filters section and a Reservations section.
// - Filters: 3 property chips (Barndo/Main/Washington), plus multi-select pickers for Years and Statuses.
// - Reservations: 15 placeholder rows filtered by selected filters.
// - Selection: selected row is visibly highlighted and shows a checkmark; tapping opens a detail sheet.

import SwiftUI

// MARK: - 1) BookingsView

struct BookingsView: View {

    // MARK: - 1.1 Models (Prototype)

    enum Property: String, CaseIterable, Identifiable, Hashable {
        case barndo = "Barndo"
        case main = "Main"
        case washington = "Washington"

        var id: String { rawValue }
    }

    enum ReservationStatus: String, CaseIterable, Identifiable, Hashable {
        case inquired = "Inquired"
        case booked = "Booked"
        case completed = "Completed"
        case cancelled = "Cancelled"
        case gift = "Gift"
        case blocked = "Blocked"
        case spam = "Spam"

        var id: String { rawValue }
    }

    struct Reservation: Identifiable, Hashable {
        let id: UUID
        var property: Property
        var status: ReservationStatus
        var renterFirstName: String
        var renterLastName: String
        var startDate: Date
        var endDate: Date

        var year: Int {
            Calendar.current.component(.year, from: startDate)
        }

        var renterDisplayName: String {
            "\(renterFirstName) \(renterLastName)"
        }

        var dateRangeDisplay: String {
            let f = DateFormatter()
            f.dateStyle = .medium
            return "\(f.string(from: startDate)) – \(f.string(from: endDate))"
        }
    }

    // MARK: - 1.2 Prototype Data (15 placeholders)

    @State private var allReservations: [Reservation] = {
        let cal = Calendar.current
        func d(_ y: Int, _ m: Int, _ day: Int) -> Date {
            cal.date(from: DateComponents(year: y, month: m, day: day)) ?? Date()
        }

        return [
            Reservation(id: UUID(), property: .barndo, status: .booked, renterFirstName: "John", renterLastName: "Smith", startDate: d(2026, 3, 12), endDate: d(2026, 3, 15)),
            Reservation(id: UUID(), property: .main, status: .booked, renterFirstName: "Mia", renterLastName: "Garcia", startDate: d(2026, 2, 26), endDate: d(2026, 2, 28)),
            Reservation(id: UUID(), property: .washington, status: .inquired, renterFirstName: "Evan", renterLastName: "Lee", startDate: d(2026, 4, 2), endDate: d(2026, 4, 6)),
            Reservation(id: UUID(), property: .barndo, status: .cancelled, renterFirstName: "Ava", renterLastName: "Johnson", startDate: d(2025, 12, 22), endDate: d(2025, 12, 27)),
            Reservation(id: UUID(), property: .main, status: .completed, renterFirstName: "Noah", renterLastName: "Brown", startDate: d(2025, 11, 10), endDate: d(2025, 11, 12)),
            Reservation(id: UUID(), property: .washington, status: .blocked, renterFirstName: "Owner", renterLastName: "Hold", startDate: d(2026, 5, 10), endDate: d(2026, 5, 12)),
            Reservation(id: UUID(), property: .barndo, status: .gift, renterFirstName: "Liam", renterLastName: "Walker", startDate: d(2026, 6, 3), endDate: d(2026, 6, 7)),
            Reservation(id: UUID(), property: .main, status: .spam, renterFirstName: "Spam", renterLastName: "Request", startDate: d(2026, 1, 5), endDate: d(2026, 1, 6)),
            Reservation(id: UUID(), property: .washington, status: .booked, renterFirstName: "Sophia", renterLastName: "Davis", startDate: d(2026, 7, 18), endDate: d(2026, 7, 21)),
            Reservation(id: UUID(), property: .barndo, status: .completed, renterFirstName: "Olivia", renterLastName: "Martinez", startDate: d(2024, 10, 14), endDate: d(2024, 10, 18)),
            Reservation(id: UUID(), property: .main, status: .inquired, renterFirstName: "Ethan", renterLastName: "Moore", startDate: d(2025, 3, 9), endDate: d(2025, 3, 12)),
            Reservation(id: UUID(), property: .washington, status: .cancelled, renterFirstName: "Isabella", renterLastName: "Hall", startDate: d(2025, 8, 2), endDate: d(2025, 8, 4)),
            Reservation(id: UUID(), property: .barndo, status: .blocked, renterFirstName: "Maintenance", renterLastName: "Block", startDate: d(2026, 9, 1), endDate: d(2026, 9, 3)),
            Reservation(id: UUID(), property: .main, status: .gift, renterFirstName: "Charlotte", renterLastName: "Allen", startDate: d(2024, 12, 24), endDate: d(2024, 12, 27)),
            Reservation(id: UUID(), property: .washington, status: .completed, renterFirstName: "James", renterLastName: "Young", startDate: d(2026, 11, 10), endDate: d(2026, 11, 12))
        ]
    }()

    // MARK: - 1.3 Filters

    /// Empty set == All
    @State private var selectedProperties: Set<Property> = []
    /// Empty set == All
    @State private var selectedYears: Set<Int> = []
    /// Empty set == All
    @State private var selectedStatuses: Set<ReservationStatus> = []

    // MARK: - 1.4 Selection + Sheets

    @State private var selectedReservationID: UUID? = nil
    @State private var draftReservation: Reservation? = nil

    @State private var isShowingYearPicker: Bool = false
    @State private var isShowingStatusPicker: Bool = false
    @State private var isShowingDetails: Bool = false

    // MARK: - 1.5 Derived

    private var availableYears: [Int] {
        let years = Set(allReservations.map { $0.year })
        return years.sorted(by: >)
    }

    private var filteredReservations: [Reservation] {
        allReservations
            .filter { selectedProperties.isEmpty ? true : selectedProperties.contains($0.property) }
            .filter { selectedYears.isEmpty ? true : selectedYears.contains($0.year) }
            .filter { selectedStatuses.isEmpty ? true : selectedStatuses.contains($0.status) }
            .sorted { $0.startDate > $1.startDate }
    }

    private var yearsButtonSubtitle: String {
        if selectedYears.isEmpty { return "All" }
        if Set(selectedYears) == Set(availableYears) { return "All" }
        return selectedYears.sorted(by: >).map(String.init).joined(separator: ", ")
    }

    private var statusesButtonSubtitle: String {
        if selectedStatuses.isEmpty { return "All" }
        if Set(selectedStatuses) == Set(ReservationStatus.allCases) { return "All" }
        return selectedStatuses.map { $0.rawValue }.sorted().joined(separator: ", ")
    }

    // MARK: - 1.6 Body

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Theme.BrandedHeaderView(title: "Bookings")

                List {
                    // 2) Filters
                    Section {
                        VStack(alignment: .leading, spacing: 12) {
                            // 2.1 Property chips
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Property")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)

                                HStack(spacing: 10) {
                                    filterChip(title: "Barndo", isSelected: isPropertySelected(.barndo)) { toggleProperty(.barndo) }
                                    filterChip(title: "Main", isSelected: isPropertySelected(.main)) { toggleProperty(.main) }
                                    filterChip(title: "Washington", isSelected: isPropertySelected(.washington)) { toggleProperty(.washington) }
                                }
                            }

                            // 2.2 Years (multi-select)
                            Button {
                                isShowingYearPicker = true
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Years").font(.subheadline)
                                        Text(yearsButtonSubtitle)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .buttonStyle(.plain)

                            // 2.3 Statuses (multi-select)
                            Button {
                                isShowingStatusPicker = true
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Statuses").font(.subheadline)
                                        Text(statusesButtonSubtitle)
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

                    // 3) Reservations
                    Section {
                        if filteredReservations.isEmpty {
                            Text("No reservations match the current filters.")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(filteredReservations) { reservation in
                                ReservationRowBasic(
                                    reservation: reservation,
                                    isSelected: reservation.id == selectedReservationID
                                )
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    selectReservation(reservation)
                                }
                            }
                        }
                    } header: {
                        HStack {
                            Text("Reservations")
                            Spacer()
                            Text("\(filteredReservations.count)")
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
                    YearsPickerSheet(
                        selectedYears: $selectedYears,
                        availableYears: availableYears
                    ) {
                        isShowingYearPicker = false
                    }
                    .navigationTitle("Years")
                    .navigationBarTitleDisplayMode(.inline)
                }
            }
            .sheet(isPresented: $isShowingStatusPicker) {
                NavigationStack {
                    StatusesPickerSheet(selectedStatuses: $selectedStatuses) {
                        isShowingStatusPicker = false
                    }
                    .navigationTitle("Statuses")
                    .navigationBarTitleDisplayMode(.inline)
                }
            }
            .sheet(isPresented: $isShowingDetails) {
                NavigationStack {
                    if let draft = draftReservation {
                        ReservationEditorBasic(reservation: binding(for: draft.id)) {
                            saveDraft()
                        }
                        .navigationTitle("Reservation")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .topBarLeading) {
                                Button("Close") { isShowingDetails = false }
                            }
                        }
                    } else {
                        Text("No reservation selected.")
                            .foregroundStyle(.secondary)
                            .padding()
                    }
                }
            }
        }
    }

    // MARK: - 1.7 Filter Helpers

    private func isPropertySelected(_ p: Property) -> Bool {
        selectedProperties.isEmpty ? true : selectedProperties.contains(p)
    }

    private func toggleProperty(_ p: Property) {
        // Empty == All. First tap moves from All -> just that one.
        if selectedProperties.isEmpty {
            selectedProperties = [p]
            return
        }

        if selectedProperties.contains(p) {
            selectedProperties.remove(p)
            // If user deselects everything, fall back to All.
            if selectedProperties.isEmpty {
                selectedProperties = []
            }
        } else {
            selectedProperties.insert(p)
        }
    }

    @ViewBuilder
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
        .accessibilityLabel(Text("Property \(title)"))
        .accessibilityHint(Text(isSelected ? "Selected" : "Not selected"))
    }

    // MARK: - 1.8 Selection + Draft

    private func selectReservation(_ reservation: Reservation) {
        selectedReservationID = reservation.id
        draftReservation = reservation
        isShowingDetails = true
    }

    private func binding(for id: UUID) -> Binding<Reservation> {
        Binding<Reservation>(
            get: {
                draftReservation ?? allReservations.first(where: { $0.id == id }) ?? fallbackReservation()
            },
            set: { newValue in
                draftReservation = newValue
            }
        )
    }

    private func saveDraft() {
        guard let draft = draftReservation else { return }
        if let idx = allReservations.firstIndex(where: { $0.id == draft.id }) {
            allReservations[idx] = draft
        }
        selectedReservationID = draft.id
    }

    private func fallbackReservation() -> Reservation {
        Reservation(
            id: UUID(),
            property: .barndo,
            status: .booked,
            renterFirstName: "",
            renterLastName: "",
            startDate: Date(),
            endDate: Date()
        )
    }
}

// MARK: - 2) Basic UI Components (Theme-independent)

private struct ReservationRowBasic: View {
    let reservation: BookingsView.Reservation
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(reservation.renterDisplayName)
                    .font(.headline)

                Spacer()
            }

            Text(reservation.dateRangeDisplay)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack {
                Text(reservation.property.rawValue)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Text(reservation.status.rawValue)
                    .font(.caption)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(.thinMaterial)
                    .clipShape(Capsule())
            }
        }
        .padding(.vertical, 6)
        .listRowBackground(isSelected ? Color.accentColor.opacity(0.14) : Color.clear)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isSelected ? Color.accentColor.opacity(0.35) : Color.clear, lineWidth: 1)
        )
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

private struct StatusesPickerSheet: View {

    @Binding var selectedStatuses: Set<BookingsView.ReservationStatus>
    let onDone: () -> Void

    var body: some View {
        let allStatusesSet = Set(BookingsView.ReservationStatus.allCases)
        let isAllSelected = selectedStatuses == allStatusesSet
        List {
            ForEach(BookingsView.ReservationStatus.allCases) { status in
                Toggle(status.rawValue, isOn: Binding(
                    get: { selectedStatuses.contains(status) },
                    set: { isOn in
                        if isOn {
                            selectedStatuses.insert(status)
                        } else {
                            selectedStatuses.remove(status)
                        }
                    }
                ))
            }

            Button(isAllSelected ? "Clear All" : "Select All") {
                if isAllSelected {
                    // Clear filters (main view interprets empty as All)
                    selectedStatuses = []
                } else {
                    selectedStatuses = allStatusesSet
                }
            }
        }
        .onAppear {
            if selectedStatuses.isEmpty {
                selectedStatuses = allStatusesSet
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { onDone() }
            }
        }
    }
}

private struct ReservationEditorBasic: View {

    @Binding var reservation: BookingsView.Reservation
    let onSave: () -> Void

    var body: some View {
        Form {
            Section("Guest") {
                TextField("First", text: $reservation.renterFirstName)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                TextField("Last", text: $reservation.renterLastName)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
            }

            Section("Stay") {
                DatePicker("Check-in", selection: $reservation.startDate, displayedComponents: .date)
                DatePicker("Check-out", selection: $reservation.endDate, displayedComponents: .date)
            }

            Section("Property") {
                Picker("Property", selection: $reservation.property) {
                    ForEach(BookingsView.Property.allCases) { p in
                        Text(p.rawValue).tag(p)
                    }
                }
            }

            Section("Status") {
                Picker("Status", selection: $reservation.status) {
                    ForEach(BookingsView.ReservationStatus.allCases) { s in
                        Text(s.rawValue).tag(s)
                    }
                }
            }

            Section {
                Button("Save") { onSave() }
            }
        }
    }
}

#Preview {
    BookingsView()
}


