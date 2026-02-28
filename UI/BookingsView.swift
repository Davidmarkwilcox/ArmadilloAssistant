//
//  BookingsView.swift
//  ArmadilloAssistant
//
//  Bookings screen prototype.
//  3 vertical sections:
//   1) Filters (property thumbnails + multi-select year + multi-select status)
//   2) Filtered reservations list
//   3) Reservation detail editor + Save
//

import SwiftUI

struct BookingsView: View {

    // MARK: - 1) Models (Prototype)

    enum Property: String, CaseIterable, Identifiable, Hashable {
        case barndo = "Barndo"
        case mainStreet = "Main Street"
        case washingtonHouse = "Washington House"

        var id: String { rawValue }

        var systemImageName: String {
            switch self {
            case .barndo: return "house.lodge"
            case .mainStreet: return "building.2"
            case .washingtonHouse: return "house"
            }
        }
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

        var badgeText: String {
            switch self {
            case .inquired: return "Inquired"
            case .booked: return "Booked"
            case .completed: return "Completed"
            case .cancelled: return "Cancelled"
            case .gift: return "Gift"
            case .blocked: return "Blocked"
            case .spam: return "Spam"
            }
        }
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
        ]
    }()

    // MARK: - 3) Filters

    @State private var selectedProperties: Set<Property> = Set(Property.allCases) // default: all
    @State private var selectedYears: Set<Int> = [] // default: all
    @State private var selectedStatuses: Set<ReservationStatus> = [] // default: all

    // MARK: - 4) Selection + Editing

    @State private var selectedReservationID: UUID? = nil
    @State private var draftReservation: Reservation? = nil

    // MARK: - 5) Derived

    private var availableYears: [Int] {
        let years = Set(allReservations.map { $0.year })
        return years.sorted(by: >)
    }

    private var filteredReservations: [Reservation] {
        allReservations
            .filter { selectedProperties.contains($0.property) }
            .filter { selectedYears.isEmpty ? true : selectedYears.contains($0.year) }
            .filter { selectedStatuses.isEmpty ? true : selectedStatuses.contains($0.status) }
            .sorted { $0.startDate > $1.startDate }
    }

    var body: some View {
        VStack(spacing: 0) {
            Theme.CrimsonHeaderView(title: "Bookings")

            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.l) {

                // MARK: - 6) Section 1: Filters

                VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                    Text("Filters")
                        .font(Theme.Typography.headline(.bold))
                        .foregroundStyle(Theme.Colors.textPrimary)

                    // Properties
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: Theme.Spacing.m) {
                            ForEach(Property.allCases) { property in
                                PropertyChip(
                                    property: property,
                                    isSelected: selectedProperties.contains(property)
                                ) {
                                    toggleProperty(property)
                                }
                            }
                        }
                        .padding(.vertical, 2)
                    }

                    HStack(spacing: Theme.Spacing.m) {
                        // Years multi-select
                        FilterMenu(
                            title: "Year",
                            subtitle: selectedYearsSummary,
                            isActive: !selectedYears.isEmpty
                        ) {
                            ForEach(availableYears, id: \.self) { year in
                                Button {
                                    toggleYear(year)
                                } label: {
                                    HStack {
                                        Image(systemName: selectedYears.contains(year) ? "checkmark.circle.fill" : "circle")
                                        Text(String(year))
                                        Spacer()
                                    }
                                }
                            }
                            Divider()
                            Button("Clear") { selectedYears.removeAll() }
                        }

                        // Status multi-select
                        FilterMenu(
                            title: "Status",
                            subtitle: selectedStatusSummary,
                            isActive: !selectedStatuses.isEmpty
                        ) {
                            ForEach(ReservationStatus.allCases) { status in
                                Button {
                                    toggleStatus(status)
                                } label: {
                                    HStack {
                                        Image(systemName: selectedStatuses.contains(status) ? "checkmark.circle.fill" : "circle")
                                        Text(status.rawValue)
                                        Spacer()
                                    }
                                }
                            }
                            Divider()
                            Button("Clear") { selectedStatuses.removeAll() }
                        }
                    }
                }
                .themeCard(elevated: true)

                // MARK: - 7) Section 2: Reservation List

                VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                    HStack {
                        Text("Reservations")
                            .font(Theme.Typography.headline(.bold))
                            .foregroundStyle(Theme.Colors.textPrimary)

                        Spacer()

                        Text("\(filteredReservations.count)")
                            .font(Theme.Typography.caption(.semibold))
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Theme.Colors.elevated)
                            .clipShape(Capsule())
                            .overlay(
                                Capsule().stroke(Theme.Colors.stroke, lineWidth: Theme.Stroke.hairline)
                            )
                    }

                    if filteredReservations.isEmpty {
                        Text("No reservations match the current filters.")
                            .font(Theme.Typography.body())
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .padding(.vertical, Theme.Spacing.s)
                    } else {
                        VStack(spacing: Theme.Spacing.s) {
                            ForEach(filteredReservations) { reservation in
                                ReservationRow(
                                    reservation: reservation,
                                    isSelected: reservation.id == selectedReservationID
                                ) {
                                    selectReservation(reservation)
                                }
                            }
                        }
                    }
                }
                .themeCard()

                // MARK: - 8) Section 3: Detail Editor

                VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                    Text("Details")
                        .font(Theme.Typography.headline(.bold))
                        .foregroundStyle(Theme.Colors.textPrimary)

                    if let draft = draftReservation {
                        ReservationEditor(
                            reservation: binding(for: draft.id),
                            onSave: saveDraft
                        )
                    } else {
                        Text("Select a reservation to view/edit details.")
                            .font(Theme.Typography.body())
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .padding(.vertical, Theme.Spacing.s)
                    }
                }
                .themeCard(elevated: true)

                Spacer(minLength: 0)
            }
                .padding(Theme.Spacing.m)
            }
            .scrollIndicators(.hidden)
        }
        .navigationBarHidden(true)
    }

    // MARK: - 9) Filter Helpers

    private var selectedYearsSummary: String {
        if selectedYears.isEmpty { return "All" }
        return selectedYears.sorted(by: >).map(String.init).joined(separator: ", ")
    }

    private var selectedStatusSummary: String {
        if selectedStatuses.isEmpty { return "All" }
        return selectedStatuses.map { $0.rawValue }.sorted().joined(separator: ", ")
    }

    private func toggleProperty(_ property: Property) {
        if selectedProperties.contains(property) {
            if selectedProperties.count > 1 {
                selectedProperties.remove(property)
            }
        } else {
            selectedProperties.insert(property)
        }
    }

    private func toggleYear(_ year: Int) {
        if selectedYears.contains(year) {
            selectedYears.remove(year)
        } else {
            selectedYears.insert(year)
        }
    }

    private func toggleStatus(_ status: ReservationStatus) {
        if selectedStatuses.contains(status) {
            selectedStatuses.remove(status)
        } else {
            selectedStatuses.insert(status)
        }
    }

    // MARK: - 10) Selection + Save

    private func selectReservation(_ reservation: Reservation) {
        selectedReservationID = reservation.id
        draftReservation = reservation
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

        // Update in-memory list (prototype). Later this becomes Core Data / CloudKit.
        if let idx = allReservations.firstIndex(where: { $0.id == draft.id }) {
            allReservations[idx] = draft
        }

        // Keep selection stable
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

// MARK: - UI Components

private struct PropertyChip: View {
    let property: BookingsView.Property
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: Theme.Spacing.s) {
                Image(systemName: property.systemImageName)
                    .font(.system(size: 16, weight: .semibold))

                Text(property.rawValue)
                    .font(Theme.Typography.body(.semibold))
            }
            .foregroundStyle(isSelected ? Theme.Colors.textPrimary : Theme.Colors.textSecondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(isSelected ? Theme.Colors.elevated.opacity(0.95) : Theme.Colors.surface.opacity(0.75))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.s)
                    .stroke(isSelected ? Theme.Colors.strokeStrong : Theme.Colors.stroke, lineWidth: Theme.Stroke.hairline)
            )
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.s))
        }
        .buttonStyle(.plain)
    }
}

private struct FilterMenu<Content: View>: View {
    let title: String
    let subtitle: String
    let isActive: Bool
    @ViewBuilder var content: () -> Content

    var body: some View {
        Menu {
            content()
        } label: {
            HStack(spacing: Theme.Spacing.s) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(Theme.Typography.caption(.semibold))
                        .foregroundStyle(Theme.Colors.textTertiary)

                    Text(subtitle)
                        .font(Theme.Typography.body(.semibold))
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(isActive ? Theme.Colors.elevated.opacity(0.95) : Theme.Colors.surface.opacity(0.75))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.s)
                    .stroke(isActive ? Theme.Colors.strokeStrong : Theme.Colors.stroke, lineWidth: Theme.Stroke.hairline)
            )
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.s))
        }
    }
}

private struct ReservationRow: View {
    let reservation: BookingsView.Reservation
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: Theme.Spacing.m) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(reservation.dateRangeDisplay)
                        .font(Theme.Typography.body(.semibold))
                        .foregroundStyle(Theme.Colors.textPrimary)

                    Text(reservation.renterDisplayName)
                        .font(Theme.Typography.body())
                        .foregroundStyle(Theme.Colors.textSecondary)
                }

                Spacer(minLength: 0)

                Text(reservation.status.badgeText)
                    .font(Theme.Typography.caption(.semibold))
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Theme.Colors.elevated)
                    .clipShape(Capsule())
                    .overlay(
                        Capsule().stroke(Theme.Colors.stroke, lineWidth: Theme.Stroke.hairline)
                    )
            }
            .padding(Theme.Spacing.m)
            .background(isSelected ? Theme.Colors.elevated.opacity(0.90) : Theme.Colors.surface.opacity(0.70))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.s)
                    .stroke(isSelected ? Theme.Colors.strokeStrong : Theme.Colors.stroke, lineWidth: Theme.Stroke.hairline)
            )
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.s))
        }
        .buttonStyle(.plain)
    }
}

private struct ReservationEditor: View {
    @Binding var reservation: BookingsView.Reservation
    let onSave: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {

            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                Text("Guest")
                    .font(Theme.Typography.caption(.semibold))
                    .foregroundStyle(Theme.Colors.textTertiary)

                HStack(spacing: Theme.Spacing.s) {
                    TextField("First", text: $reservation.renterFirstName)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .padding(12)
                        .background(Theme.Colors.surface.opacity(0.75))
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.s))
                        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.s).stroke(Theme.Colors.stroke, lineWidth: Theme.Stroke.hairline))

                    TextField("Last", text: $reservation.renterLastName)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .padding(12)
                        .background(Theme.Colors.surface.opacity(0.75))
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.s))
                        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.s).stroke(Theme.Colors.stroke, lineWidth: Theme.Stroke.hairline))
                }
                .foregroundStyle(Theme.Colors.textPrimary)
            }

            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                Text("Stay")
                    .font(Theme.Typography.caption(.semibold))
                    .foregroundStyle(Theme.Colors.textTertiary)

                DatePicker("Check-in", selection: $reservation.startDate, displayedComponents: .date)
                    .tint(Theme.Colors.crimson)
                DatePicker("Check-out", selection: $reservation.endDate, displayedComponents: .date)
                    .tint(Theme.Colors.crimson)
            }
            .foregroundStyle(Theme.Colors.textPrimary)

            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                Text("Property & Status")
                    .font(Theme.Typography.caption(.semibold))
                    .foregroundStyle(Theme.Colors.textTertiary)

                Picker("Property", selection: $reservation.property) {
                    ForEach(BookingsView.Property.allCases) { p in
                        Text(p.rawValue).tag(p)
                    }
                }
                .pickerStyle(.menu)
                .tint(Theme.Colors.textPrimary)

                Picker("Status", selection: $reservation.status) {
                    ForEach(BookingsView.ReservationStatus.allCases) { s in
                        Text(s.rawValue).tag(s)
                    }
                }
                .pickerStyle(.menu)
                .tint(Theme.Colors.textPrimary)
            }

            Button {
                onSave()
            } label: {
                HStack {
                    Image(systemName: "square.and.arrow.down")
                    Text("Save")
                    Spacer()
                }
            }
            .buttonStyle(Theme.PrimaryButtonStyle())
            .padding(.top, Theme.Spacing.s)
        }
    }
}

#Preview {
    NavigationStack {
        BookingsView()
    }
}
