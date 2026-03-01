// BookingsView.swift
// ArmadilloAssistant
// Standalone Bookings screen (theme-independent).
// - Shows Filters (in a sheet), Reservations (List), and Reservation Details (sheet).
// - Uses only vanilla SwiftUI components to avoid gesture/hit-testing issues from custom theming.

import SwiftUI

struct BookingsView: View {

    // MARK: - 1) Models (Prototype)

    enum Property: String, CaseIterable, Identifiable, Hashable {
        case barndo = "Barndo"
        case mainStreet = "Main Street"
        case washingtonHouse = "Washington House"

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

    // MARK: - 2) Prototype Data

    @State private var allReservations: [Reservation] = {
        let cal = Calendar.current
        func d(_ y: Int, _ m: Int, _ day: Int) -> Date {
            cal.date(from: DateComponents(year: y, month: m, day: day)) ?? Date()
        }

        return [
            Reservation(id: UUID(), property: .barndo, status: .booked, renterFirstName: "John", renterLastName: "Smith", startDate: d(2026, 3, 12), endDate: d(2026, 3, 15)),
            Reservation(id: UUID(), property: .mainStreet, status: .booked, renterFirstName: "Mia", renterLastName: "Garcia", startDate: d(2026, 2, 26), endDate: d(2026, 2, 28)),
            Reservation(id: UUID(), property: .washingtonHouse, status: .inquired, renterFirstName: "Evan", renterLastName: "Lee", startDate: d(2026, 4, 2), endDate: d(2026, 4, 6)),
            Reservation(id: UUID(), property: .barndo, status: .cancelled, renterFirstName: "Ava", renterLastName: "Johnson", startDate: d(2025, 12, 22), endDate: d(2025, 12, 27)),
            Reservation(id: UUID(), property: .mainStreet, status: .completed, renterFirstName: "Noah", renterLastName: "Brown", startDate: d(2025, 11, 10), endDate: d(2025, 11, 12)),
            Reservation(id: UUID(), property: .mainStreet, status: .completed, renterFirstName: "Frank", renterLastName: "Franky", startDate: d(2026, 11, 10), endDate: d(2026, 11, 12))
        ]
    }()

    // MARK: - 3) Filters

    /// Empty set == All
    @State private var selectedProperties: Set<Property> = []
    /// Empty set == All
    @State private var selectedYears: Set<Int> = []
    /// Empty set == All
    @State private var selectedStatuses: Set<ReservationStatus> = []

    // MARK: - 4) Selection + Sheets

    @State private var selectedReservationID: UUID? = nil
    @State private var draftReservation: Reservation? = nil

    @State private var isShowingFilters: Bool = false
    @State private var isShowingDetails: Bool = false

    // MARK: - 5) Derived

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

    // MARK: - 6) Body

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Text("Reservations")
                        Spacer()
                        Text("\(filteredReservations.count)")
                            .foregroundStyle(.secondary)
                        Button {
                            isShowingFilters = true
                        } label: {
                            Label("Filters", systemImage: "line.3.horizontal.decrease.circle")
                                .labelStyle(.iconOnly)
                        }
                        .buttonStyle(.plain)
                    }
                }

                if filteredReservations.isEmpty {
                    Section {
                        Text("No reservations match the current filters.")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Section {
                        ForEach(filteredReservations) { reservation in
                            ReservationRowBasic(reservation: reservation)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    selectReservation(reservation)
                                }
                        }
                    }
                }
            }
            .navigationTitle("Bookings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isShowingFilters = true
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                    }
                }
            }
            .sheet(isPresented: $isShowingFilters) {
                NavigationStack {
                    FiltersSheetBasic(
                        selectedProperties: $selectedProperties,
                        selectedYears: $selectedYears,
                        selectedStatuses: $selectedStatuses,
                        availableYears: availableYears
                    ) {
                        isShowingFilters = false
                    }
                    .navigationTitle("Filters")
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
                                Button("Close") {
                                    isShowingDetails = false
                                }
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

    // MARK: - 7) Actions

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

// MARK: - Basic UI Components (Theme-independent)

private struct ReservationRowBasic: View {
    let reservation: BookingsView.Reservation

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(reservation.renterDisplayName)
                .font(.headline)

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
    }
}

private struct FiltersSheetBasic: View {

    @Binding var selectedProperties: Set<BookingsView.Property>
    @Binding var selectedYears: Set<Int>
    @Binding var selectedStatuses: Set<BookingsView.ReservationStatus>

    let availableYears: [Int]
    let onDone: () -> Void

    var body: some View {
        List {
            Section("Properties") {
                ForEach(BookingsView.Property.allCases) { property in
                    Toggle(property.rawValue, isOn: Binding(
                        get: { selectedProperties.isEmpty ? true : selectedProperties.contains(property) },
                        set: { isOn in
                            if isOn {
                                if selectedProperties.isEmpty {
                                    selectedProperties = Set(BookingsView.Property.allCases)
                                }
                                selectedProperties.insert(property)
                            } else {
                                if selectedProperties.isEmpty {
                                    selectedProperties = Set(BookingsView.Property.allCases)
                                }
                                selectedProperties.remove(property)
                            }
                        }
                    ))
                }

                Button("Select All") { selectedProperties = [] }
            }

            Section("Years") {
                if availableYears.isEmpty {
                    Text("No years available")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(availableYears, id: \.self) { year in
                        Toggle(String(year), isOn: Binding(
                            get: { selectedYears.isEmpty ? true : selectedYears.contains(year) },
                            set: { isOn in
                                if isOn {
                                    if selectedYears.isEmpty { selectedYears = Set(availableYears) }
                                    selectedYears.insert(year)
                                } else {
                                    if selectedYears.isEmpty { selectedYears = Set(availableYears) }
                                    selectedYears.remove(year)
                                }
                            }
                        ))
                    }

                    Button("Select All") { selectedYears = [] }
                }
            }

            Section("Statuses") {
                ForEach(BookingsView.ReservationStatus.allCases) { status in
                    Toggle(status.rawValue, isOn: Binding(
                        get: { selectedStatuses.isEmpty ? true : selectedStatuses.contains(status) },
                        set: { isOn in
                            if isOn {
                                if selectedStatuses.isEmpty { selectedStatuses = Set(BookingsView.ReservationStatus.allCases) }
                                selectedStatuses.insert(status)
                            } else {
                                if selectedStatuses.isEmpty { selectedStatuses = Set(BookingsView.ReservationStatus.allCases) }
                                selectedStatuses.remove(status)
                            }
                        }
                    ))
                }

                Button("Select All") { selectedStatuses = [] }
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
