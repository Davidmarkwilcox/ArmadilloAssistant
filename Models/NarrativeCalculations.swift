//
//  NarrativeCalculations.swift
//  ArmadilloAssistant
//
//  Created by David Wilcox on 3/1/26.
//

import Foundation
enum NarrativeCalculations {
    nonisolated private static let propertyOrder = ["Barndo", "Main Street", "Washington"]
    nonisolated private static let inquiryCountStatuses = ["Inquired", "Cancelled"]
    nonisolated private static let inquiredRevenueStatuses = ["Inquired", "Booked", "Completed"]
    nonisolated private static let stayCountStatuses = ["Booked", "Completed", "Blocked", "Gift"]
    nonisolated private static let bookedRevenueStatuses = ["Booked", "Completed"]
    nonisolated private static let bookingPercentDenominatorStatuses = ["Inquired", "Booked", "Completed"]
    nonisolated private static let bookingPercentNumeratorStatuses = ["Booked", "Completed"]
    nonisolated private static let leadTimeExcludedStatuses = ["Spam", "Blocked"]

    static func text(
        for narrativeID: String,
        bookings: [Booking],
        selectedProperties: Set<String>,
        selectedYears: Set<Int>,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> String {
        let normalizedSelectedProperties = normalizeSelectedProperties(selectedProperties)
        let propertyScopedBookings = bookings.compactMap { normalizedBooking(from: $0, calendar: calendar) }
            .filter { normalizedSelectedProperties.isEmpty || normalizedSelectedProperties.contains($0.property) }

        switch narrativeID {
        case "inquiries_this_month":
            return relativeMonthInquiryNarrative(for: .current, bookings: propertyScopedBookings, now: now, calendar: calendar)
        case "bookings_this_month":
            return relativeMonthBookingsNarrative(for: .current, bookings: propertyScopedBookings, now: now, calendar: calendar)
        case "booking_percent_this_month":
            return relativeMonthBookingPercentNarrative(for: .current, bookings: propertyScopedBookings, now: now, calendar: calendar)
        case "inquired_revenue_this_month":
            return relativeMonthInquiredRevenueNarrative(for: .current, bookings: propertyScopedBookings, now: now, calendar: calendar)
        case "booked_revenue_this_month":
            return relativeMonthBookedRevenueNarrative(for: .current, bookings: propertyScopedBookings, now: now, calendar: calendar)
        case "inquiries_last_month":
            return relativeMonthInquiryNarrative(for: .previous, bookings: propertyScopedBookings, now: now, calendar: calendar)
        case "bookings_last_month":
            return relativeMonthBookingsNarrative(for: .previous, bookings: propertyScopedBookings, now: now, calendar: calendar)
        case "booking_percent_last_month":
            return relativeMonthBookingPercentNarrative(for: .previous, bookings: propertyScopedBookings, now: now, calendar: calendar)
        case "inquired_revenue_last_month":
            return relativeMonthInquiredRevenueNarrative(for: .previous, bookings: propertyScopedBookings, now: now, calendar: calendar)
        case "booked_revenue_last_month":
            return relativeMonthBookedRevenueNarrative(for: .previous, bookings: propertyScopedBookings, now: now, calendar: calendar)
        case "bookings_overview":
            return bookingsOverviewNarrative(bookings: propertyScopedBookings, selectedYears: selectedYears, now: now, calendar: calendar)
        case "nights_booked_overview":
            return nightsOverviewNarrative(bookings: propertyScopedBookings, selectedYears: selectedYears, now: now, calendar: calendar)
        case "revenue_overview":
            return revenueOverviewNarrative(bookings: propertyScopedBookings, selectedYears: selectedYears, now: now, calendar: calendar)
        case "lead_time_general":
            return leadTimeNarrative(bookings: propertyScopedBookings, selectedYears: selectedYears, now: now, calendar: calendar)
        case let id where id.hasSuffix("_overview"):
            return monthlyOverviewNarrative(id: id, bookings: propertyScopedBookings, selectedYears: selectedYears, now: now, calendar: calendar)
        default:
            return "No narrative is available for this selection yet."
        }
    }
}

private extension NarrativeCalculations {
    nonisolated static let bookingPercentNarrativeInquiryStatuses = ["Inquired", "Booked", "Completed"]
    nonisolated static let bookingPercentNarrativeBookingStatuses = ["Booked", "Completed"]

    struct NormalizedBooking {
        let property: String
        let status: String
        let createdAt: Date?
        let inquiryDate: Date?
        let checkOutDate: Date?
        let revenue: Double
        let margin: Double
        let nights: Int
    }

    enum RelativeMonth {
        case current
        case previous

        var label: String {
            switch self {
            case .current:
                return "this month"
            case .previous:
                return "last month"
            }
        }
    }

    nonisolated static func normalizeSelectedProperties(_ selectedProperties: Set<String>) -> Set<String> {
        Set(selectedProperties.compactMap(canonicalPropertyToken(from:)))
    }

    static func normalizedBooking(from booking: Booking, calendar: Calendar) -> NormalizedBooking? {
        let relationshipShortName = booking.propertyRef?.shortName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let property: String?

        if let relationshipShortName, !relationshipShortName.isEmpty {
            property = canonicalPropertyToken(from: relationshipShortName)
        } else if let propertyName = booking.propertyName {
            property = canonicalPropertyToken(from: propertyName)
        } else {
            property = nil
        }

        guard let property else { return nil }

        let nights = stayNights(
            checkInDate: booking.checkInDate,
            checkOutDate: booking.checkOutDate,
            calendar: calendar
        )

        return NormalizedBooking(
            property: property,
            status: (booking.status ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
            createdAt: booking.createdAt,
            inquiryDate: booking.inquiryDate,
            checkOutDate: booking.checkOutDate,
            revenue: (booking.pricePerNight * Double(nights)) + booking.cleaningFee,
            margin: booking.pricePerNight * Double(nights),
            nights: nights
        )
    }

    nonisolated static func canonicalPropertyToken(from rawValue: String) -> String? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        switch trimmed.lowercased() {
        case "barndo", "barndominium":
            return "Barndo"
        case "main", "main street":
            return "Main Street"
        case "washington", "washington house":
            return "Washington"
        default:
            return propertyOrder.first { $0.localizedCaseInsensitiveCompare(trimmed) == .orderedSame }
        }
    }

    static func stayNights(checkInDate: Date?, checkOutDate: Date?, calendar: Calendar) -> Int {
        guard let checkInDate, let checkOutDate else { return 0 }
        return max(0, calendar.dateComponents([.day], from: checkInDate, to: checkOutDate).day ?? 0)
    }


    static func yearScope(from selectedYears: Set<Int>, now: Date, calendar: Calendar) -> Int {
        selectedYears.max() ?? calendar.component(.year, from: now)
    }

    static func yearScopes(from selectedYears: Set<Int>, now: Date, calendar: Calendar) -> [Int] {
        let years = selectedYears.isEmpty ? [calendar.component(.year, from: now)] : selectedYears.sorted()
        return years
    }


    static func bookingsForYear(_ year: Int, bookings: [NormalizedBooking], calendar: Calendar) -> [NormalizedBooking] {
        bookings.filter {
            guard let checkOutDate = $0.checkOutDate else { return false }
            return calendar.component(.year, from: checkOutDate) == year
        }
    }

    static func bookingsForYears(_ years: [Int], bookings: [NormalizedBooking], calendar: Calendar) -> [NormalizedBooking] {
        let yearSet = Set(years)
        return bookings.filter {
            guard let checkOutDate = $0.checkOutDate else { return false }
            return yearSet.contains(calendar.component(.year, from: checkOutDate))
        }
    }

    static func bookingsForMonth(_ month: Int, year: Int, bookings: [NormalizedBooking], calendar: Calendar) -> [NormalizedBooking] {
        bookings.filter {
            guard let checkOutDate = $0.checkOutDate else { return false }
            let components = calendar.dateComponents([.year, .month], from: checkOutDate)
            return components.year == year && components.month == month
        }
    }

    static func bookingsForRelativeMonth(_ relativeMonth: RelativeMonth, bookings: [NormalizedBooking], now: Date, calendar: Calendar) -> [NormalizedBooking] {
        let targetDate = relativeMonth == .current
            ? now
            : (calendar.date(byAdding: .month, value: -1, to: now) ?? now)
        let targetComponents = calendar.dateComponents([.year, .month], from: targetDate)

        return bookings.filter {
            guard let inquiryDate = $0.inquiryDate else { return false }
            let inquiryComponents = calendar.dateComponents([.year, .month], from: inquiryDate)
            return inquiryComponents.year == targetComponents.year && inquiryComponents.month == targetComponents.month
        }
    }

    static func count(for statuses: [String], in bookings: [NormalizedBooking]) -> Int {
        bookings.filter { statuses.contains($0.status) }.count
    }

    static func totalNights(for statuses: [String], in bookings: [NormalizedBooking]) -> Int {
        bookings.filter { statuses.contains($0.status) }.reduce(0) { $0 + $1.nights }
    }

    static func totalRevenue(for statuses: [String], in bookings: [NormalizedBooking]) -> Double {
        bookings.filter { statuses.contains($0.status) }.reduce(0) { $0 + $1.revenue }
    }

    static func totalMargin(for statuses: [String], in bookings: [NormalizedBooking]) -> Double {
        bookings.filter { statuses.contains($0.status) }.reduce(0) { $0 + $1.margin }
    }

    static func perPropertyCount(bookings: [NormalizedBooking], statuses: [String]) -> [(property: String, value: Int)] {
        propertyOrder.map { property in
            let total = bookings.filter { $0.property == property && statuses.contains($0.status) }.count
            return (property, total)
        }
    }

    static func perPropertyNights(bookings: [NormalizedBooking], statuses: [String]) -> [(property: String, value: Int)] {
        propertyOrder.map { property in
            let total = bookings
                .filter { $0.property == property && statuses.contains($0.status) }
                .reduce(0) { $0 + $1.nights }
            return (property, total)
        }
    }

    static func perPropertyRevenue(bookings: [NormalizedBooking], statuses: [String]) -> [(property: String, value: Double)] {
        propertyOrder.map { property in
            let total = bookings
                .filter { $0.property == property && statuses.contains($0.status) }
                .reduce(0) { $0 + $1.revenue }
            return (property, total)
        }
    }

    static func perPropertyMargin(bookings: [NormalizedBooking], statuses: [String]) -> [(property: String, value: Double)] {
        propertyOrder.map { property in
            let total = bookings
                .filter { $0.property == property && statuses.contains($0.status) }
                .reduce(0) { $0 + $1.margin }
            return (property, total)
        }
    }

    static func bookingPercent(for bookings: [NormalizedBooking]) -> Double? {
        let denominator = Double(count(for: bookingPercentDenominatorStatuses, in: bookings))
        guard denominator > 0 else { return nil }
        let numerator = Double(count(for: bookingPercentNumeratorStatuses, in: bookings))
        return numerator / denominator
    }

    static func averageLeadTime(bookings: [NormalizedBooking], calendar: Calendar) -> Double? {
        let leadTimes = bookings.compactMap { booking -> Int? in
            guard
                !leadTimeExcludedStatuses.contains(booking.status),
                let inquiryDate = booking.inquiryDate,
                let checkOutDate = booking.checkOutDate
            else {
                return nil
            }

            let days = calendar.dateComponents([.day], from: inquiryDate, to: checkOutDate).day ?? 0
            return days >= 0 ? days : nil
        }

        guard !leadTimes.isEmpty else { return nil }
        return Double(leadTimes.reduce(0, +)) / Double(leadTimes.count)
    }

    static func monthName(for month: Int) -> String {
        let formatter = DateFormatter()
        return formatter.monthSymbols[month - 1]
    }

    static func monthValue(from narrativeID: String) -> Int? {
        let monthMap: [String: Int] = [
            "january_overview": 1,
            "february_overview": 2,
            "march_overview": 3,
            "april_overview": 4,
            "may_overview": 5,
            "june_overview": 6,
            "july_overview": 7,
            "august_overview": 8,
            "september_overview": 9,
            "october_overview": 10,
            "november_overview": 11,
            "december_overview": 12
        ]

        return monthMap[narrativeID]
    }

    static func propertyReference(for property: String) -> String {
        property == "Barndo" ? "the Barndo" : property
    }

    static func formatCount(_ value: Int) -> String {
        value.formatted(.number.precision(.fractionLength(0)))
    }

    static func formatPercent(_ value: Double) -> String {
        (value * 100).formatted(.number.precision(.fractionLength(1))) + "%"
    }

    static func formatWholePercent(_ value: Double) -> String {
        (value * 100).formatted(.number.precision(.fractionLength(0))) + "%"
    }

    static func formatCurrency(_ value: Double) -> String {
        value.formatted(.currency(code: Locale.current.currency?.identifier ?? "USD").precision(.fractionLength(0)))
    }

    static func formatCompactCurrency(_ value: Double) -> String {
        if abs(value) >= 1000 {
            return "$" + (value / 1000).formatted(.number.precision(.fractionLength(1))) + "k"
        }
        return formatCurrency(value)
    }

    static func oxfordJoin(_ phrases: [String]) -> String {
        switch phrases.count {
        case 0:
            return ""
        case 1:
            return phrases[0]
        case 2:
            return phrases.joined(separator: " and ")
        default:
            let head = phrases.dropLast().joined(separator: ", ")
            return "\(head), and \(phrases.last ?? "")"
        }
    }

    static func countBreakdownSentence(total: Int, values: [(property: String, value: Int)]) -> String {
        let nonZeroValues = values.filter { $0.value > 0 }
        guard !nonZeroValues.isEmpty, total > 0 else { return "" }

        let phrases = nonZeroValues.map { item in
            let share = Double(item.value) / Double(total)
            return "\(formatCount(item.value)) at \(propertyReference(for: item.property)) (\(formatPercent(share)))"
        }
        return oxfordJoin(phrases)
    }

    static func revenueBreakdownSentence(total: Double, values: [(property: String, value: Double)]) -> String {
        let nonZeroValues = values.filter { $0.value > 0 }
        guard !nonZeroValues.isEmpty, total > 0 else { return "" }

        let phrases = nonZeroValues.map { item in
            let share = item.value / total
            let label = bookingsNarrativePropertyLabel(for: item.property)
            let preposition = item.property == "Barndo" ? "for" : "at"
            return "\(formatCompactCurrency(item.value)) \(preposition) \(label) (\(formatPercent(share)))"
        }
        return oxfordJoin(phrases)
    }

    static func bookingsNarrativePropertyLabel(for property: String) -> String {
        switch property {
        case "Barndo":
            return "the Barndo"
        case "Main Street":
            return "Main/Alamo"
        default:
            return property
        }
    }

    static func inquiryCountPhrase(_ value: Int) -> String {
        "\(formatCount(value)) " + (value == 1 ? "inquiry" : "inquiries")
    }

    static func noDataInScopeSentence() -> String {
        "For the selected filters, there are no bookings to summarize yet."
    }

    static func relativeMonthInquiryNarrative(for relativeMonth: RelativeMonth, bookings: [NormalizedBooking], now: Date, calendar: Calendar) -> String {
        let scopedBookings = bookingsForRelativeMonth(relativeMonth, bookings: bookings, now: now, calendar: calendar)
        guard !scopedBookings.isEmpty else { return noDataInScopeSentence() }

        let total = scopedBookings.count
        let barndoCount = scopedBookings.filter { $0.property == "Barndo" }.count
        let mainAlamoCount = scopedBookings.filter { $0.property == "Main Street" }.count
        let washingtonCount = scopedBookings.filter { $0.property == "Washington" }.count

        let barndoPercent = formatPercent(total > 0 ? Double(barndoCount) / Double(total) : 0)
        let mainAlamoPercent = formatPercent(total > 0 ? Double(mainAlamoCount) / Double(total) : 0)
        let washingtonPercent = formatPercent(total > 0 ? Double(washingtonCount) / Double(total) : 0)

        let lead: String
        switch relativeMonth {
        case .current:
            lead = "So far this month, we've had a total of \(formatCount(total)) inquiries."
        case .previous:
            lead = "Last month, we had a total of \(formatCount(total)) inquiries."
        }

        return "\(lead) \(formatCount(barndoCount)) at the Barndo (\(barndoPercent)), \(formatCount(mainAlamoCount)) at Main/Alamo (\(mainAlamoPercent)), and \(formatCount(washingtonCount)) at Washington (\(washingtonPercent))."
    }

    static func relativeMonthBookingsNarrative(for relativeMonth: RelativeMonth, bookings: [NormalizedBooking], now: Date, calendar: Calendar) -> String {
        let scopedBookings = bookingsForRelativeMonth(relativeMonth, bookings: bookings, now: now, calendar: calendar)
        guard !scopedBookings.isEmpty else { return noDataInScopeSentence() }

        let total = count(for: stayCountStatuses, in: scopedBookings)
        let barndoCount = count(for: stayCountStatuses, in: scopedBookings.filter { $0.property == "Barndo" })
        let mainAlamoCount = count(for: stayCountStatuses, in: scopedBookings.filter { $0.property == "Main Street" })
        let washingtonCount = count(for: stayCountStatuses, in: scopedBookings.filter { $0.property == "Washington" })

        let shouldUseDecimalPercentages = relativeMonth == .previous
        let percentFormatter: (Double) -> String = { value in
            if shouldUseDecimalPercentages {
                return formatPercent(value)
            }
            return formatWholePercent(value)
        }

        let barndoPercent = total > 0 ? percentFormatter(Double(barndoCount) / Double(total)) : percentFormatter(0)
        let mainAlamoPercent = total > 0 ? percentFormatter(Double(mainAlamoCount) / Double(total)) : percentFormatter(0)
        let washingtonPercent = total > 0 ? percentFormatter(Double(washingtonCount) / Double(total)) : percentFormatter(0)

        let lead: String
        switch relativeMonth {
        case .current:
            lead = "So far this month, we've had a total of \(formatCount(total)) bookings."
        case .previous:
            lead = "Last month, we had a total of \(formatCount(total)) bookings."
        }

        return "\(lead) \(formatCount(barndoCount)) at \(bookingsNarrativePropertyLabel(for: "Barndo")) (\(barndoPercent)), \(formatCount(mainAlamoCount)) at \(bookingsNarrativePropertyLabel(for: "Main Street")) (\(mainAlamoPercent)), and \(formatCount(washingtonCount)) at \(bookingsNarrativePropertyLabel(for: "Washington")) (\(washingtonPercent))."
    }

    static func relativeMonthBookingPercentNarrative(for relativeMonth: RelativeMonth, bookings: [NormalizedBooking], now: Date, calendar: Calendar) -> String {
        let scopedBookings = bookingsForRelativeMonth(relativeMonth, bookings: bookings, now: now, calendar: calendar)
        guard !scopedBookings.isEmpty else { return noDataInScopeSentence() }

        let totalInquiries = count(for: bookingPercentNarrativeInquiryStatuses, in: scopedBookings)
        guard totalInquiries > 0 else {
            return "There were no qualifying reservations \(relativeMonth.label) to calculate a booking percentage."
        }

        let totalBookings = count(for: bookingPercentNarrativeBookingStatuses, in: scopedBookings)
        let rate = Double(totalBookings) / Double(totalInquiries)

        let propertyBreakdowns = ["Barndo", "Main Street", "Washington"].map { property in
            let propertyBookings = scopedBookings.filter { $0.property == property }
            let bookingCount = count(for: bookingPercentNarrativeBookingStatuses, in: propertyBookings)
            let inquiryCount = count(for: bookingPercentNarrativeInquiryStatuses, in: propertyBookings)
            let propertyRate = inquiryCount > 0 ? Double(bookingCount) / Double(inquiryCount) : 0

            return "\(formatCount(bookingCount)) \(bookingCount == 1 ? "booking" : "bookings") at \(bookingsNarrativePropertyLabel(for: property)) from \(inquiryCountPhrase(inquiryCount)) (\(formatPercent(propertyRate)))"
        }

        let lead: String
        switch relativeMonth {
        case .current:
            lead = "So far this month, our booking rate is \(formatPercent(rate)), with \(formatCount(totalBookings)) bookings from \(inquiryCountPhrase(totalInquiries))."
        case .previous:
            lead = "Last month, our booking rate was \(formatPercent(rate)), with \(formatCount(totalBookings)) bookings from \(inquiryCountPhrase(totalInquiries))."
        }

        return "\(lead) \(oxfordJoin(propertyBreakdowns))."
    }

    static func relativeMonthInquiredRevenueNarrative(for relativeMonth: RelativeMonth, bookings: [NormalizedBooking], now: Date, calendar: Calendar) -> String {
        let scopedBookings = bookingsForRelativeMonth(relativeMonth, bookings: bookings, now: now, calendar: calendar)
        guard !scopedBookings.isEmpty else { return noDataInScopeSentence() }

        let total = totalRevenue(for: inquiredRevenueStatuses, in: scopedBookings)
        let barndoRevenue = totalRevenue(for: inquiredRevenueStatuses, in: scopedBookings.filter { $0.property == "Barndo" })
        let mainAlamoRevenue = totalRevenue(for: inquiredRevenueStatuses, in: scopedBookings.filter { $0.property == "Main Street" })
        let washingtonRevenue = totalRevenue(for: inquiredRevenueStatuses, in: scopedBookings.filter { $0.property == "Washington" })

        let totalMarginAmount = totalMargin(for: inquiredRevenueStatuses, in: scopedBookings)
        let barndoMargin = totalMargin(for: inquiredRevenueStatuses, in: scopedBookings.filter { $0.property == "Barndo" })
        let mainAlamoMargin = totalMargin(for: inquiredRevenueStatuses, in: scopedBookings.filter { $0.property == "Main Street" })
        let washingtonMargin = totalMargin(for: inquiredRevenueStatuses, in: scopedBookings.filter { $0.property == "Washington" })

        let barndoPercent = total > 0 ? formatPercent(barndoRevenue / total) : formatPercent(0)
        let mainAlamoPercent = total > 0 ? formatPercent(mainAlamoRevenue / total) : formatPercent(0)
        let washingtonPercent = total > 0 ? formatPercent(washingtonRevenue / total) : formatPercent(0)

        let barndoMarginPercent = totalMarginAmount > 0 ? formatPercent(barndoMargin / totalMarginAmount) : formatPercent(0)
        let mainAlamoMarginPercent = totalMarginAmount > 0 ? formatPercent(mainAlamoMargin / totalMarginAmount) : formatPercent(0)
        let washingtonMarginPercent = totalMarginAmount > 0 ? formatPercent(washingtonMargin / totalMarginAmount) : formatPercent(0)

        let revenueParagraph: String
        let marginParagraph: String

        switch relativeMonth {
        case .current:
            revenueParagraph = "So far for this month, the potential revenue from our inquiries and bookings is \(formatCompactCurrency(total)). \(formatCompactCurrency(barndoRevenue)) at the Barndo (\(barndoPercent)), \(formatCompactCurrency(mainAlamoRevenue)) at Main/Alamo (\(mainAlamoPercent)), and \(formatCompactCurrency(washingtonRevenue)) at Washington (\(washingtonPercent))."

            marginParagraph = "So far for this month, the potential margins from our inquiries and bookings are \(formatCompactCurrency(totalMarginAmount)). \(formatCompactCurrency(barndoMargin)) at the Barndo (\(barndoMarginPercent)), \(formatCompactCurrency(mainAlamoMargin)) at Main/Alamo (\(mainAlamoMarginPercent)), and \(formatCompactCurrency(washingtonMargin)) at Washington (\(washingtonMarginPercent))."

        case .previous:
            revenueParagraph = "Last month, the potential revenue from our inquiries and bookings was \(formatCompactCurrency(total)). \(formatCompactCurrency(barndoRevenue)) at the Barndo (\(barndoPercent)), \(formatCompactCurrency(mainAlamoRevenue)) at Main/Alamo (\(mainAlamoPercent)), and \(formatCompactCurrency(washingtonRevenue)) at Washington (\(washingtonPercent))."

            marginParagraph = "Last month, the potential margins from our inquiries and bookings were \(formatCompactCurrency(totalMarginAmount)). \(formatCompactCurrency(barndoMargin)) at the Barndo (\(barndoMarginPercent)), \(formatCompactCurrency(mainAlamoMargin)) at Main/Alamo (\(mainAlamoMarginPercent)), and \(formatCompactCurrency(washingtonMargin)) at Washington (\(washingtonMarginPercent))."
        }

        return "\(revenueParagraph)\n\n\(marginParagraph)"
    }

    static func relativeMonthBookedRevenueNarrative(for relativeMonth: RelativeMonth, bookings: [NormalizedBooking], now: Date, calendar: Calendar) -> String {
        let scopedBookings = bookingsForRelativeMonth(relativeMonth, bookings: bookings, now: now, calendar: calendar)
        guard !scopedBookings.isEmpty else { return noDataInScopeSentence() }

        let total = totalRevenue(for: bookedRevenueStatuses, in: scopedBookings)
        let barndoRevenue = totalRevenue(for: bookedRevenueStatuses, in: scopedBookings.filter { $0.property == "Barndo" })
        let mainAlamoRevenue = totalRevenue(for: bookedRevenueStatuses, in: scopedBookings.filter { $0.property == "Main Street" })
        let washingtonRevenue = totalRevenue(for: bookedRevenueStatuses, in: scopedBookings.filter { $0.property == "Washington" })

        let totalMarginAmount = totalMargin(for: bookedRevenueStatuses, in: scopedBookings)
        let barndoMargin = totalMargin(for: bookedRevenueStatuses, in: scopedBookings.filter { $0.property == "Barndo" })
        let mainAlamoMargin = totalMargin(for: bookedRevenueStatuses, in: scopedBookings.filter { $0.property == "Main Street" })
        let washingtonMargin = totalMargin(for: bookedRevenueStatuses, in: scopedBookings.filter { $0.property == "Washington" })

        let barndoPercent = total > 0 ? formatPercent(barndoRevenue / total) : formatPercent(0)
        let mainAlamoPercent = total > 0 ? formatPercent(mainAlamoRevenue / total) : formatPercent(0)
        let washingtonPercent = total > 0 ? formatPercent(washingtonRevenue / total) : formatPercent(0)

        let barndoMarginPercent = totalMarginAmount > 0 ? formatPercent(barndoMargin / totalMarginAmount) : formatPercent(0)
        let mainAlamoMarginPercent = totalMarginAmount > 0 ? formatPercent(mainAlamoMargin / totalMarginAmount) : formatPercent(0)
        let washingtonMarginPercent = totalMarginAmount > 0 ? formatPercent(washingtonMargin / totalMarginAmount) : formatPercent(0)

        let revenueParagraph: String
        let marginParagraph: String

        switch relativeMonth {
        case .current:
            revenueParagraph = "So far for this month, the potential revenue that has been booked from inquiries is \(formatCompactCurrency(total)). \(formatCompactCurrency(barndoRevenue)) at the Barndo (\(barndoPercent)), \(formatCompactCurrency(mainAlamoRevenue)) at Main/Alamo (\(mainAlamoPercent)), and \(formatCompactCurrency(washingtonRevenue)) at Washington (\(washingtonPercent))."

            marginParagraph = "So far for this month, the potential margins that have been booked from inquiries are \(formatCompactCurrency(totalMarginAmount)). \(formatCompactCurrency(barndoMargin)) at the Barndo (\(barndoMarginPercent)), \(formatCompactCurrency(mainAlamoMargin)) at Main/Alamo (\(mainAlamoMarginPercent)), and \(formatCompactCurrency(washingtonMargin)) at Washington (\(washingtonMarginPercent))."

        case .previous:
            revenueParagraph = "Last month, the potential revenue that was booked from inquiries was \(formatCompactCurrency(total)). \(formatCompactCurrency(barndoRevenue)) at the Barndo (\(barndoPercent)), \(formatCompactCurrency(mainAlamoRevenue)) at Main/Alamo (\(mainAlamoPercent)), and \(formatCompactCurrency(washingtonRevenue)) at Washington (\(washingtonPercent))."

            marginParagraph = "Last month, the potential margins that were booked from inquiries were \(formatCompactCurrency(totalMarginAmount)). \(formatCompactCurrency(barndoMargin)) at the Barndo (\(barndoMarginPercent)), \(formatCompactCurrency(mainAlamoMargin)) at Main/Alamo (\(mainAlamoMarginPercent)), and \(formatCompactCurrency(washingtonMargin)) at Washington (\(washingtonMarginPercent))."
        }

        return "\(revenueParagraph)\n\n\(marginParagraph)"
    }

    static func bookingsOverviewNarrative(bookings: [NormalizedBooking], selectedYears: Set<Int>, now: Date, calendar: Calendar) -> String {
        let year = yearScope(from: selectedYears, now: now, calendar: calendar)
        let scopedBookings = bookingsForYear(year, bookings: bookings, calendar: calendar)
        guard !scopedBookings.isEmpty else { return noDataInScopeSentence() }

        let total = count(for: stayCountStatuses, in: scopedBookings)
        let breakdown = countBreakdownSentence(total: total, values: perPropertyCount(bookings: scopedBookings, statuses: stayCountStatuses))

        if breakdown.isEmpty {
            return "So far for \(year), we have a total of \(formatCount(total)) stays."
        }

        return "So far for \(year), we have a total of \(formatCount(total)) stays. \(breakdown)."
    }

    static func nightsOverviewNarrative(bookings: [NormalizedBooking], selectedYears: Set<Int>, now: Date, calendar: Calendar) -> String {
        let year = yearScope(from: selectedYears, now: now, calendar: calendar)
        let scopedBookings = bookingsForYear(year, bookings: bookings, calendar: calendar)
        guard !scopedBookings.isEmpty else { return noDataInScopeSentence() }

        let total = totalNights(for: stayCountStatuses, in: scopedBookings)
        let breakdown = countBreakdownSentence(total: total, values: perPropertyNights(bookings: scopedBookings, statuses: stayCountStatuses))

        if breakdown.isEmpty {
            return "So far for \(year), we have a total of \(formatCount(total)) nights booked."
        }

        return "So far for \(year), we have a total of \(formatCount(total)) nights booked. \(breakdown)."
    }

    static func revenueOverviewNarrative(bookings: [NormalizedBooking], selectedYears: Set<Int>, now: Date, calendar: Calendar) -> String {
        let years = yearScopes(from: selectedYears, now: now, calendar: calendar)
        let scopedBookings = bookingsForYears(years, bookings: bookings, calendar: calendar)
        guard !scopedBookings.isEmpty else { return noDataInScopeSentence() }

        let totalRevenue = totalRevenue(for: bookedRevenueStatuses, in: scopedBookings)
        let revenueBreakdown = revenueBreakdownSentence(total: totalRevenue, values: perPropertyRevenue(bookings: scopedBookings, statuses: bookedRevenueStatuses))
        let totalMargin = totalMargin(for: bookedRevenueStatuses, in: scopedBookings)
        let marginBreakdown = revenueBreakdownSentence(total: totalMargin, values: perPropertyMargin(bookings: scopedBookings, statuses: bookedRevenueStatuses))
        let yearLabel = years.map(String.init).joined(separator: ", ")

        let revenueParagraph: String
        if revenueBreakdown.isEmpty {
            revenueParagraph = "For \(yearLabel), booked revenue totals \(formatCompactCurrency(totalRevenue))."
        } else {
            revenueParagraph = "For \(yearLabel), booked revenue totals \(formatCompactCurrency(totalRevenue)). \(revenueBreakdown)."
        }

        let marginParagraph: String
        if marginBreakdown.isEmpty {
            marginParagraph = "For \(yearLabel), booked margins total \(formatCompactCurrency(totalMargin))."
        } else {
            marginParagraph = "For \(yearLabel), booked margins total \(formatCompactCurrency(totalMargin)). \(marginBreakdown)."
        }

        return "\(revenueParagraph)\n\n\(marginParagraph)"
    }

    static func leadTimeNarrative(bookings: [NormalizedBooking], selectedYears: Set<Int>, now: Date, calendar: Calendar) -> String {
        let year = yearScope(from: selectedYears, now: now, calendar: calendar)
        let scopedBookings = bookingsForYear(year, bookings: bookings, calendar: calendar)
        guard !scopedBookings.isEmpty else { return noDataInScopeSentence() }

        guard let averageLeadTime = averageLeadTime(bookings: scopedBookings, calendar: calendar) else {
            return "For \(year), there is not enough inquiry timing data to summarize lead time yet."
        }

        return "In \(year), guests inquired an average of \(formatCount(Int(averageLeadTime.rounded()))) days before check-in."
    }

    static func monthlyOverviewNarrative(id: String, bookings: [NormalizedBooking], selectedYears: Set<Int>, now: Date, calendar: Calendar) -> String {
        guard let month = monthValue(from: id) else {
            return "No narrative is available for this selection yet."
        }

        let year = yearScope(from: selectedYears, now: now, calendar: calendar)
        let scopedBookings = bookingsForMonth(month, year: year, bookings: bookings, calendar: calendar)
        guard !scopedBookings.isEmpty else { return noDataInScopeSentence() }

        let totalBookings = count(for: stayCountStatuses, in: scopedBookings)
        let totalBookedRevenue = totalRevenue(for: bookedRevenueStatuses, in: scopedBookings)
        let totalInquiries = scopedBookings.count

        var sentences = [
            "In \(monthName(for: month)), \(year): a total of \(formatCount(totalBookings)) bookings for \(formatCompactCurrency(totalBookedRevenue)) out of \(formatCount(totalInquiries)) inquiries."
        ]

        for property in propertyOrder {
            let propertyBookings = scopedBookings.filter { $0.property == property }
            let propertyBookingCount = count(for: stayCountStatuses, in: propertyBookings)
            let propertyRevenue = totalRevenue(for: bookedRevenueStatuses, in: propertyBookings)
            let propertyInquiryCount = propertyBookings.count

            guard propertyBookingCount > 0 || propertyRevenue > 0 || propertyInquiryCount > 0 else { continue }

            sentences.append(
                "For \(propertyReference(for: property)), \(formatCount(propertyBookingCount)) bookings for \(formatCompactCurrency(propertyRevenue)) out of \(formatCount(propertyInquiryCount)) inquiries."
            )
        }

        return sentences.joined(separator: " ")
    }
}

