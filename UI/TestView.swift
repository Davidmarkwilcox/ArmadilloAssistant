// TestView.swift
// ArmadilloAssistant
// Minimal, theme-free prototype: filters at top + scrollable reservations list.

import SwiftUI

struct TestView: View {

    // MARK: - 1) Models

    enum Property: String, CaseIterable, Identifiable, Hashable {
        case any = "All"
        case barndo = "Barndo"
        case mainStreet = "Main Street"
        case washingtonHouse = "Washington House"

        var id: String { rawValue }
    }

    enum ReservationStatus: String, CaseIterable, Identifiable, Hashable {
        case any = "All"
        case inquired = "Inquired"
        case booked = "Booked"
        case completed = "Completed"
        case cancelled = "Cancelled"
        case blocked = "Blocked"

        var id: String { rawValue }
    }

    struct Reservation: Identifiable, Hashable {
        let id: UUID
        var property: Property
        var status: ReservationStatus
        var renterName: String
        var startDate: Date
        var endDate: Date

        var year: Int {
            Calendar.current.component(.year, from: startDate)
        }

        var dateRangeDisplay: String {
            let f = DateFormatter()
            f.dateStyle = .medium
            return "\(f.string(from: startDate)) – \(f.string(from: endDate))"
        }
    }

    // MARK: - 2) Sample Data

    @State private var reservations: [Reservation] = {
        let cal = Calendar.current
        func d(_ y: Int, _ m: Int, _ day: Int) -> Date {
            cal.date(from: DateComponents(year: y, month: m, day: day)) ?? Date()
        }

        return [
            Reservation(id: UUID(), property: .barndo, status: .booked, renterName: "John Smith", startDate: d(2026, 3, 12), endDate: d(2026, 3, 15)),
            Reservation(id: UUID(), property: .mainStreet, status: .booked, renterName: "Mia Garcia", startDate: d(2026, 2, 26), endDate: d(2026, 2, 28)),
            Reservation(id: UUID(), property: .washingtonHouse, status: .inquired, renterName: "Evan Lee", startDate: d(2026, 4, 2), endDate: d(2026, 4, 6)),
            Reservation(id: UUID(), property: .barndo, status: .cancelled, renterName: "Ava Johnson", startDate: d(2025, 12, 22), endDate: d(2025, 12, 27)),
            Reservation(id: UUID(), property: .mainStreet, status: .completed, renterName: "Noah Brown", startDate: d(2025, 11, 10), endDate: d(2025, 11, 12)),
            Reservation(id: UUID(), property: .washingtonHouse, status: .blocked, renterName: "Owner Block", startDate: d(2026, 6, 1), endDate: d(2026, 6, 3)),
            Reservation(id: UUID(), property: .barndo, status: .booked, renterName: "Olivia Davis", startDate: d(2026, 1, 5), endDate: d(2026, 1, 7)),
            Reservation(id: UUID(), property: .mainStreet, status: .inquired, renterName: "Liam Wilson", startDate: d(2026, 5, 18), endDate: d(2026, 5, 20)),
            Reservation(id: UUID(), property: .washingtonHouse, status: .booked, renterName: "Sophia Martinez", startDate: d(2026, 7, 9), endDate: d(2026, 7, 12)),
            Reservation(id: UUID(), property: .barndo, status: .completed, renterName: "James Anderson", startDate: d(2025, 10, 3), endDate: d(2025, 10, 6)),
            Reservation(id: UUID(), property: .mainStreet, status: .cancelled, renterName: "Isabella Thomas", startDate: d(2025, 9, 14), endDate: d(2025, 9, 16)),
            Reservation(id: UUID(), property: .washingtonHouse, status: .booked, renterName: "Benjamin Taylor", startDate: d(2026, 8, 21), endDate: d(2026, 8, 24)),
            Reservation(id: UUID(), property: .barndo, status: .inquired, renterName: "Amelia Moore", startDate: d(2026, 9, 2), endDate: d(2026, 9, 5)),
            Reservation(id: UUID(), property: .mainStreet, status: .blocked, renterName: "Maintenance Block", startDate: d(2026, 3, 29), endDate: d(2026, 3, 30)),
            Reservation(id: UUID(), property: .washingtonHouse, status: .completed, renterName: "Lucas Jackson", startDate: d(2025, 8, 7), endDate: d(2025, 8, 10)),
            Reservation(id: UUID(), property: .barndo, status: .booked, renterName: "Charlotte White", startDate: d(2026, 10, 14), endDate: d(2026, 10, 17))
        ]
    }()

    // MARK: - 3) Filter State

    @State private var selectedProperty: Property = .any
    @State private var selectedStatus: ReservationStatus = .any
    @State private var selectedYear: Int? = nil  // nil == All

    @State private var selectedReservationID: UUID? = nil
    @State private var isShowingDetails: Bool = false

    private var selectedReservation: Reservation? {
        guard let id = selectedReservationID else { return nil }
        return reservations.first(where: { $0.id == id })
    }

    private var availableYears: [Int] {
        let years = Set(reservations.map { $0.year })
        return years.sorted(by: >)
    }

    private var filteredReservations: [Reservation] {
        reservations
            .filter { selectedProperty == .any ? true : $0.property == selectedProperty }
            .filter { selectedStatus == .any ? true : $0.status == selectedStatus }
            .filter { selectedYear == nil ? true : $0.year == selectedYear }
            .sorted { $0.startDate > $1.startDate }
    }

    // MARK: - 4) UI

    var body: some View {
        VStack(spacing: 0) {
            Theme.CrimsonHeaderView(title: "Test")
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: Theme.Spacing.l) {

                // MARK: - Filters (Top)

                VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                    Text("Filters")
                        .font(Theme.Typography.headline(.bold))
                        .foregroundStyle(Theme.Colors.textPrimary)

                    HStack(spacing: Theme.Spacing.m) {
                        Picker("Property", selection: $selectedProperty) {
                            ForEach(Property.allCases) { p in
                                Text(p.rawValue).tag(p)
                            }
                        }

                        Picker("Status", selection: $selectedStatus) {
                            ForEach(ReservationStatus.allCases) { s in
                                Text(s.rawValue).tag(s)
                            }
                        }
                    }

                    HStack(spacing: Theme.Spacing.m) {
                        Picker("Year", selection: Binding(
                            get: { selectedYear ?? -1 },
                            set: { newValue in
                                selectedYear = (newValue == -1) ? nil : newValue
                            }
                        )) {
                            Text("All").tag(-1)
                            ForEach(availableYears, id: \.self) { y in
                                Text(String(y)).tag(y)
                            }
                        }

                        Spacer()

                        Button("Clear") {
                            selectedProperty = .any
                            selectedStatus = .any
                            selectedYear = nil
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .themeCard(elevated: true)

                // MARK: - Reservations (Scrollable)

                List {
                    Section {
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
                        .padding(.vertical, Theme.Spacing.xs)
                    }
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)

                    if filteredReservations.isEmpty {
                        Text("No reservations match the current filters.")
                            .font(Theme.Typography.body())
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                    } else {
                        ForEach(filteredReservations) { r in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(r.renterName)
                                    .font(Theme.Typography.body(.semibold))
                                    .foregroundStyle(Theme.Colors.textPrimary)

                                Text(r.dateRangeDisplay)
                                    .font(Theme.Typography.body())
                                    .foregroundStyle(Theme.Colors.textSecondary)

                                HStack {
                                    Text(r.property.rawValue)
                                        .font(Theme.Typography.caption(.semibold))
                                        .foregroundStyle(Theme.Colors.textSecondary)

                                    Spacer()

                                    Text(r.status.rawValue)
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
                            }
                            .padding(Theme.Spacing.m)
                            .background(selectedReservationID == r.id ? Theme.Colors.elevated.opacity(0.90) : Theme.Colors.surface.opacity(0.70))
                            .overlay(
                                RoundedRectangle(cornerRadius: Theme.Radius.s)
                                    .stroke(selectedReservationID == r.id ? Theme.Colors.strokeStrong : Theme.Colors.stroke, lineWidth: Theme.Stroke.hairline)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.s))
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedReservationID = r.id
                                isShowingDetails = true
                            }
                            .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(Color.clear)
                .themeCard()
            }
            .padding(Theme.Spacing.m)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Theme.Colors.background)
            .sheet(isPresented: $isShowingDetails) {
                NavigationStack {
                    if let r = selectedReservation {
                        List {
                            Section("Guest") {
                                Text(r.renterName)
                            }

                            Section("Stay") {
                                Text("Check-in: \(r.startDate.formatted(date: .abbreviated, time: .omitted))")
                                Text("Check-out: \(r.endDate.formatted(date: .abbreviated, time: .omitted))")
                            }

                            Section("Property") {
                                Text(r.property.rawValue)
                            }

                            Section("Status") {
                                Text(r.status.rawValue)
                            }

                            Section("Year") {
                                Text(String(r.year))
                            }
                        }
                        .listStyle(.insetGrouped)
                        .scrollContentBackground(.hidden)
                        .background(Theme.Colors.background)
                    } else {
                        Text("No reservation selected")
                            .font(Theme.Typography.body())
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .padding(Theme.Spacing.m)
                            .background(Theme.Colors.background)
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { isShowingDetails = false }
                    }
                }
            }
        }
    }
}

#Preview {
    TestView()
}
