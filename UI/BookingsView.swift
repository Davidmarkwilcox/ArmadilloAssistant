// BookingsView.swift
// ArmadilloAssistant
// Bookings screen
// - Shows an always-visible Filters section and a Reservations section.
// - Filters: 3 property chips (Barndo/Main/Washington), plus multi-select pickers for Years and Statuses.
// - Reservations: 15 placeholder rows filtered by selected filters.
// - Selection: selected row is visibly highlighted and shows a checkmark; tapping opens a detail sheet.

import SwiftUI
import CoreData

// MARK: - 1) BookingsView

struct BookingsView: View {
    @Environment(\.managedObjectContext) private var viewContext

    private static let bookingCSVHeaders: [String] = [
        "Property",
        "Check-In Date",
        "Check-Out Date",
        "Inquiry Date",
        "Booking Date",
        "Renter First Name",
        "Renter Last Name",
        "Price Per Night",
        "Cleaning Fee",
        "Cleaning Payment",
        "Service Fee",
        "Tax Amount",
        "Tax Rate Applied",
        "Discount Amount",
        "Status",
        "Booking Source",
        "Payment Status",
        "Phone Number",
        "Email Address",
        "Early Check-In Requested?",
        "Late Check-Out Requested?",
        "Platforms Blocked?",
        "Booking Reason",
        "Notes"
    ]

    // MARK: - 1.1 Models (Prototype)

    struct PropertyOption: Identifiable, Hashable {
        let id: UUID
        let name: String
        let shortName: String
        let pricePerNightDefault: Double
        let cleaningFeeDefault: Double
        let cleaningPaymentDefault: Double
        let serviceFeeDefault: Double
        let taxRateDefault: Double
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
        var propertyName: String
        var status: ReservationStatus
        var renterFirstName: String
        var renterLastName: String
        var startDate: Date
        var endDate: Date
        var inquiryDate: Date?
        var bookingDate: Date?
        var pricePerNight: Double
        var cleaningFee: Double
        var cleaningPayment: Double
        var serviceFee: Double
        var taxAmount: Double
        var taxRateApplied: Double
        var discountAmount: Double
        var bookingSource: String
        var paymentStatus: String
        var phoneNumber: String
        var emailAddress: String
        var earlyCheckInRequested: Bool
        var lateCheckOutRequested: Bool
        var platformsBlocked: Bool
        var bookingReason: String
        var notes: String

        var year: Int {
            Calendar.current.component(.year, from: startDate)
        }

        var renterDisplayName: String {
            let combined = "\(renterFirstName) \(renterLastName)".trimmingCharacters(in: .whitespacesAndNewlines)
            return combined.isEmpty ? "Unnamed Reservation" : combined
        }

        var dateRangeDisplay: String {
            let f = DateFormatter()
            f.dateStyle = .medium
            return "\(f.string(from: startDate)) – \(f.string(from: endDate))"
        }
    }

    enum BookingCSVExportError: LocalizedError {
        case failedToWriteFile

        var errorDescription: String? {
            switch self {
            case .failedToWriteFile:
                return "Unable to create the bookings CSV export file."
            }
        }
    }

    enum BookingCSVImportError: LocalizedError {
        case unreadableFile
        case invalidHeader
        case invalidDate(row: Int, column: String, value: String)
        case invalidBoolean(row: Int, value: String)
        case invalidNumber(row: Int, column: String, value: String)

        var errorDescription: String? {
            switch self {
            case .unreadableFile:
                return "Unable to read the selected CSV file."
            case .invalidHeader:
                return "The selected CSV file does not match the expected Bookings import template."
            case .invalidDate(let row, let column, let value):
                return "Invalid date for \(column) on row \(row): \(value)"
            case .invalidBoolean(let row, let value):
                return "Invalid boolean value on row \(row): \(value)"
            case .invalidNumber(let row, let column, let value):
                return "Invalid numeric value for \(column) on row \(row): \(value)"
            }
        }
    }

    enum BookingBulkDeleteError: LocalizedError {
        case failedToDelete

        var errorDescription: String? {
            switch self {
            case .failedToDelete:
                return "Unable to delete the stored booking records."
            }
        }
    }

    struct BookingCSVExporter {
        private static let headers = BookingsView.bookingCSVHeaders

        private static let dateFormatter: DateFormatter = {
            let formatter = DateFormatter()
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone.current
            formatter.dateFormat = "yyyy-MM-dd"
            return formatter
        }()

        private static func derivedTaxRateApplied(
            taxAmount: Double,
            pricePerNight: Double,
            checkInDate: Date,
            checkOutDate: Date,
            cleaningFee: Double
        ) -> Double {
            let nights = max(0, Calendar.current.dateComponents([.day], from: checkInDate, to: checkOutDate).day ?? 0)
            let revenue = (pricePerNight * Double(nights)) + cleaningFee
            guard revenue != 0 else { return 0 }
            return taxAmount / revenue
        }

        private static let decimalFormatter: NumberFormatter = {
            let formatter = NumberFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.numberStyle = .decimal
            formatter.usesGroupingSeparator = false
            formatter.minimumFractionDigits = 0
            formatter.maximumFractionDigits = 2
            return formatter
        }()

        private static let taxRateFormatter: NumberFormatter = {
            let formatter = NumberFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.numberStyle = .decimal
            formatter.usesGroupingSeparator = false
            formatter.minimumFractionDigits = 0
            formatter.maximumFractionDigits = 4
            return formatter
        }()

        private static let fileNameFormatter: DateFormatter = {
            let formatter = DateFormatter()
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone.current
            formatter.dateFormat = "yyyyMMdd-HHmm"
            return formatter
        }()

        static func fetchBookings(context: NSManagedObjectContext) throws -> [Booking] {
            let request: NSFetchRequest<Booking> = Booking.fetchRequest()
            request.sortDescriptors = [
                NSSortDescriptor(keyPath: \Booking.checkInDate, ascending: false),
                NSSortDescriptor(keyPath: \Booking.createdAt, ascending: false)
            ]
            return try context.fetch(request)
        }

        static func csvString(from bookings: [Booking]) -> String {
            let headerRow = headers.map(csvEscaped).joined(separator: ",")
            let rows = bookings.map { booking in
                let columns: [String] = [
                    booking.propertyName ?? "",
                    formattedDate(booking.checkInDate),
                    formattedDate(booking.checkOutDate),
                    formattedDate(booking.inquiryDate),
                    formattedDate(booking.bookingDate),
                    booking.renterFirstName ?? "",
                    booking.renterLastName ?? "",
                    formattedDecimalValue(booking.pricePerNight),
                    formattedDecimalValue(booking.cleaningFee),
                    formattedDecimalValue(booking.cleaningPayment),
                    formattedDecimalValue(booking.serviceFee),
                    formattedDecimalValue(booking.taxAmount),
                    formattedTaxRateApplied(for: booking),
                    formattedDecimalValue(booking.discountAmount),
                    booking.status ?? "",
                    booking.bookingSource ?? "",
                    booking.paymentStatus ?? "",
                    booking.phoneNumber ?? "",
                    booking.emailAddress ?? "",
                    booking.earlyCheckInRequested ? "Yes" : "No",
                    booking.lateCheckOutRequested ? "Yes" : "No",
                    booking.platformsBlocked ? "Yes" : "No",
                    booking.bookingReason ?? "",
                    booking.notes ?? ""
                ]
                return columns.map(csvEscaped).joined(separator: ",")
            }

            return ([headerRow] + rows).joined(separator: "\n")
        }

        static func writeExportFile(context: NSManagedObjectContext) throws -> URL {
            let bookings = try fetchBookings(context: context)
            let csv = csvString(from: bookings)
            let fileName = "Bookings_\(fileNameFormatter.string(from: Date())).csv"
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)

            do {
                try csv.write(to: url, atomically: true, encoding: .utf8)
                return url
            } catch {
                throw BookingCSVExportError.failedToWriteFile
            }
        }

        private static func formattedDate(_ date: Date?) -> String {
            guard let date else { return "" }
            return dateFormatter.string(from: date)
        }

        private static func formattedDecimalValue(_ value: Double) -> String {
            decimalFormatter.string(from: NSNumber(value: value)) ?? "0"
        }

        private static func formattedTaxRateApplied(for booking: Booking) -> String {
            let nights = max(
                0,
                Calendar.current.dateComponents(
                    [.day],
                    from: booking.checkInDate ?? Date(),
                    to: booking.checkOutDate ?? Date()
                ).day ?? 0
            )
            let revenue = (booking.pricePerNight * Double(nights)) + booking.cleaningFee
            guard revenue != 0 else { return "0" }

            let derivedTaxRate = booking.taxAmount / revenue
            return taxRateFormatter.string(from: NSNumber(value: derivedTaxRate)) ?? "0"
        }

        private nonisolated static func csvEscaped(_ value: String) -> String {
            let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(escaped)\""
        }
    }

    struct BookingCSVImporter {
        private static let headers = BookingsView.bookingCSVHeaders

        private static let dateFormatter: DateFormatter = {
            let formatter = DateFormatter()
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone.current
            formatter.dateFormat = "yyyy-MM-dd"
            return formatter
        }()

        private static func derivedTaxRateApplied(
            taxAmount: Double,
            pricePerNight: Double,
            checkInDate: Date,
            checkOutDate: Date,
            cleaningFee: Double
        ) -> Double {
            let nights = max(0, Calendar.current.dateComponents([.day], from: checkInDate, to: checkOutDate).day ?? 0)
            let revenue = (pricePerNight * Double(nights)) + cleaningFee
            guard revenue != 0 else { return 0 }
            return taxAmount / revenue
        }

        private struct ParsedBookingRow {
            let propertyName: String
            let checkInDate: Date
            let checkOutDate: Date
            let inquiryDate: Date?
            let bookingDate: Date?
            let renterFirstName: String
            let renterLastName: String
            let pricePerNight: Double
            let cleaningFee: Double
            let cleaningPayment: Double
            let serviceFee: Double
            let taxAmount: Double
            let taxRateApplied: Double
            let discountAmount: Double
            let status: String
            let bookingSource: String
            let paymentStatus: String
            let phoneNumber: String
            let emailAddress: String
            let earlyCheckInRequested: Bool
            let lateCheckOutRequested: Bool
            let platformsBlocked: Bool
            let bookingReason: String
            let notes: String
        }

        private struct BookingImportMatchKey: Hashable {
            let propertyName: String
            let checkInDate: Date
            let checkOutDate: Date
            let renterFirstName: String
            let renterLastName: String
            let status: String
            let bookingDate: Date?
        }

        static func importFile(from url: URL, context: NSManagedObjectContext) throws -> Int {
            let csvText: String
            print("[BookingCSVImport] Import entry")
            print("[BookingCSVImport] Selected file URL: \(url.path)")

            do {
                csvText = try String(contentsOf: url, encoding: .utf8)
            } catch {
                print("[BookingCSVImport] Failed to read CSV: \(error.localizedDescription)")
                throw BookingCSVImportError.unreadableFile
            }

            let rows = parseCSVRows(csvText)
            guard let headerRow = rows.first else {
                print("[BookingCSVImport] Missing header row")
                throw BookingCSVImportError.invalidHeader
            }

            let normalizedHeader = normalizedHeaderRow(headerRow)
            let expectedHeader = normalizedHeaderRow(headers)
            guard Array(normalizedHeader.prefix(expectedHeader.count)) == expectedHeader else {
                print("[BookingCSVImport] Header validation failed")
                throw BookingCSVImportError.invalidHeader
            }

            let parsedRows = try rows
                .dropFirst()
                .enumerated()
                .compactMap { offset, row in
                    try parsedBookingRow(from: row, rowNumber: offset + 2)
                }
            print("[BookingCSVImport] Parsed row count: \(parsedRows.count)")

            if parsedRows.isEmpty {
                print("[BookingCSVImport] Early return: no parsed booking rows")
                print("[BookingCSVImport] Returned import count: 0")
                return 0
            }

            let now = Date()
            let trimmedProperties = fetchPropertyMap(context: context)
            var existingKeys = Set(fetchExistingBookingKeys(context: context))
            var importedCount = 0
            var skippedDuplicateCount = 0

            for parsedRow in parsedRows {
                let importKey = makeMatchKey(
                    propertyName: parsedRow.propertyName,
                    checkInDate: parsedRow.checkInDate,
                    checkOutDate: parsedRow.checkOutDate,
                    renterFirstName: parsedRow.renterFirstName,
                    renterLastName: parsedRow.renterLastName,
                    status: parsedRow.status,
                    bookingDate: parsedRow.bookingDate
                )

                guard !existingKeys.contains(importKey) else {
                    skippedDuplicateCount += 1
                    continue
                }

                let booking = Booking(context: context)
                booking.id = UUID()
                booking.propertyName = parsedRow.propertyName
                booking.propertyRef = trimmedProperties[parsedRow.propertyName.trimmingCharacters(in: .whitespacesAndNewlines)]
                booking.checkInDate = parsedRow.checkInDate
                booking.checkOutDate = parsedRow.checkOutDate
                booking.inquiryDate = parsedRow.inquiryDate
                booking.bookingDate = parsedRow.bookingDate
                booking.renterFirstName = parsedRow.renterFirstName
                booking.renterLastName = parsedRow.renterLastName
                booking.pricePerNight = parsedRow.pricePerNight
                booking.cleaningFee = parsedRow.cleaningFee
                booking.cleaningPayment = parsedRow.cleaningPayment
                booking.serviceFee = parsedRow.serviceFee
                booking.taxAmount = parsedRow.taxAmount
                booking.taxRateApplied = parsedRow.taxRateApplied
                booking.discountAmount = parsedRow.discountAmount
                booking.status = parsedRow.status
                booking.bookingSource = parsedRow.bookingSource
                booking.paymentStatus = parsedRow.paymentStatus
                booking.phoneNumber = parsedRow.phoneNumber
                booking.emailAddress = parsedRow.emailAddress
                booking.earlyCheckInRequested = parsedRow.earlyCheckInRequested
                booking.lateCheckOutRequested = parsedRow.lateCheckOutRequested
                booking.platformsBlocked = parsedRow.platformsBlocked
                booking.bookingReason = parsedRow.bookingReason
                booking.notes = parsedRow.notes
                booking.createdAt = now
                booking.createdBy = "CSV Import"
                booking.lastModifiedAt = now
                booking.lastModifiedBy = "CSV Import"
                existingKeys.insert(importKey)
                importedCount += 1
            }

            print("[BookingCSVImport] Duplicate skip count: \(skippedDuplicateCount)")
            print("[BookingCSVImport] Created booking count: \(importedCount)")

            if importedCount == 0 {
                print("[BookingCSVImport] Early return: all parsed rows were duplicates")
                print("[BookingCSVImport] Returned import count: 0")
                return 0
            }

            do {
                try context.save()
                print("[BookingCSVImport] Save success")
            } catch {
                context.rollback()
                print("[BookingCSVImport] Save failure: \(error.localizedDescription)")
                throw error
            }

            print("[BookingCSVImport] Returned import count: \(importedCount)")
            return importedCount
        }

        private static func fetchPropertyMap(context: NSManagedObjectContext) -> [String: RentalProperty] {
            let request: NSFetchRequest<RentalProperty> = RentalProperty.fetchRequest()
            let properties = (try? context.fetch(request)) ?? []
            return Dictionary(uniqueKeysWithValues: properties.compactMap { property in
                guard let name = property.name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else {
                    return nil
                }
                return (name, property)
            })
        }

        private static func fetchExistingBookingKeys(context: NSManagedObjectContext) -> [BookingImportMatchKey] {
            let request: NSFetchRequest<Booking> = Booking.fetchRequest()
            let bookings = (try? context.fetch(request)) ?? []
            return bookings.map { booking in
                makeMatchKey(
                    propertyName: booking.propertyName ?? "",
                    checkInDate: booking.checkInDate ?? Date.distantPast,
                    checkOutDate: booking.checkOutDate ?? Date.distantPast,
                    renterFirstName: booking.renterFirstName ?? "",
                    renterLastName: booking.renterLastName ?? "",
                    status: booking.status ?? "",
                    bookingDate: booking.bookingDate
                )
            }
        }

        private static func makeMatchKey(
            propertyName: String,
            checkInDate: Date,
            checkOutDate: Date,
            renterFirstName: String,
            renterLastName: String,
            status: String,
            bookingDate: Date?
        ) -> BookingImportMatchKey {
            BookingImportMatchKey(
                propertyName: normalizedMatchString(propertyName),
                checkInDate: checkInDate,
                checkOutDate: checkOutDate,
                renterFirstName: normalizedMatchString(renterFirstName),
                renterLastName: normalizedMatchString(renterLastName),
                status: normalizedMatchString(status),
                bookingDate: bookingDate
            )
        }

        private static func normalizedMatchString(_ value: String) -> String {
            value.trimmingCharacters(in: .whitespacesAndNewlines).localizedLowercase
        }

        private static func parsedBookingRow(from row: [String], rowNumber: Int) throws -> ParsedBookingRow? {
            let paddedRow = row + Array(repeating: "", count: max(0, headers.count - row.count))
            let normalized = Array(paddedRow.prefix(headers.count)).map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }

            let hasAnyValue = normalized.contains { !$0.isEmpty }
            guard hasAnyValue else { return nil }

            let checkInDate = try parseRequiredDate(normalized[1], rowNumber: rowNumber, column: "Check-In Date")
            let checkOutDate = try parseRequiredDate(normalized[2], rowNumber: rowNumber, column: "Check-Out Date")
            let pricePerNight = try parseNumber(normalized[7], rowNumber: rowNumber, column: "Price Per Night")
            let cleaningFee = try parseNumber(normalized[8], rowNumber: rowNumber, column: "Cleaning Fee")
            let taxAmount = try parseNumber(normalized[11], rowNumber: rowNumber, column: "Tax Amount")

            return ParsedBookingRow(
                propertyName: normalized[0],
                checkInDate: checkInDate,
                checkOutDate: checkOutDate,
                inquiryDate: try parseOptionalDate(normalized[3], rowNumber: rowNumber, column: "Inquiry Date"),
                bookingDate: try parseOptionalDate(normalized[4], rowNumber: rowNumber, column: "Booking Date"),
                renterFirstName: normalized[5],
                renterLastName: normalized[6],
                pricePerNight: pricePerNight,
                cleaningFee: cleaningFee,
                cleaningPayment: try parseNumber(normalized[9], rowNumber: rowNumber, column: "Cleaning Payment"),
                serviceFee: try parseNumber(normalized[10], rowNumber: rowNumber, column: "Service Fee"),
                taxAmount: taxAmount,
                taxRateApplied: derivedTaxRateApplied(
                    taxAmount: taxAmount,
                    pricePerNight: pricePerNight,
                    checkInDate: checkInDate,
                    checkOutDate: checkOutDate,
                    cleaningFee: cleaningFee
                ),
                discountAmount: try parseNumber(normalized[13], rowNumber: rowNumber, column: "Discount Amount"),
                status: normalized[14],
                bookingSource: normalized[15],
                paymentStatus: normalized[16],
                phoneNumber: normalized[17],
                emailAddress: normalized[18],
                earlyCheckInRequested: try parseBoolean(normalized[19], rowNumber: rowNumber),
                lateCheckOutRequested: try parseBoolean(normalized[20], rowNumber: rowNumber),
                platformsBlocked: try parseBoolean(normalized[21], rowNumber: rowNumber),
                bookingReason: normalized[22],
                notes: normalized[23]
            )
        }

        private static func parseRequiredDate(_ value: String, rowNumber: Int, column: String) throws -> Date {
            guard let date = dateFormatter.date(from: value) else {
                throw BookingCSVImportError.invalidDate(row: rowNumber, column: column, value: value)
            }
            return date
        }

        private static func parseOptionalDate(_ value: String, rowNumber: Int, column: String) throws -> Date? {
            guard !value.isEmpty else { return nil }
            guard let date = dateFormatter.date(from: value) else {
                throw BookingCSVImportError.invalidDate(row: rowNumber, column: column, value: value)
            }
            return date
        }

        private static func parseBoolean(_ value: String, rowNumber: Int) throws -> Bool {
            if value.isEmpty { return false }

            switch value.lowercased() {
            case "yes", "y", "true", "1":
                return true
            case "no", "n", "false", "0":
                return false
            default:
                throw BookingCSVImportError.invalidBoolean(row: rowNumber, value: value)
            }
        }

        private static func parseNumber(_ value: String, rowNumber: Int, column: String) throws -> Double {
            if value.isEmpty { return 0 }

            let sanitized = value
                .replacingOccurrences(of: "$", with: "")
                .replacingOccurrences(of: ",", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            guard let parsed = Double(sanitized) else {
                throw BookingCSVImportError.invalidNumber(row: rowNumber, column: column, value: value)
            }

            return parsed
        }

        private static func normalizedHeaderRow(_ row: [String]) -> [String] {
            Array(row.prefix(headers.count)).enumerated().map { index, value in
                var normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if index == 0 {
                    normalized = normalized.replacingOccurrences(of: "\u{FEFF}", with: "")
                }
                return normalized
            }
        }

        private static func parseCSVRows(_ text: String) -> [[String]] {
            let normalizedText = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
            var rows: [[String]] = []
            var currentRow: [String] = []
            var currentField: String = ""
            var isInsideQuotes = false

            let characters = Array(normalizedText)
            var index = 0

            while index < characters.count {
                let character = characters[index]

                if isInsideQuotes {
                    if character == "\"" {
                        let nextIndex = index + 1
                        if nextIndex < characters.count, characters[nextIndex] == "\"" {
                            currentField.append("\"")
                            index += 1
                        } else {
                            isInsideQuotes = false
                        }
                    } else {
                        currentField.append(character)
                    }
                } else {
                    switch character {
                    case "\"":
                        isInsideQuotes = true
                    case ",":
                        currentRow.append(currentField)
                        currentField = ""
                    case "\n":
                        currentRow.append(currentField)
                        rows.append(currentRow)
                        currentRow = []
                        currentField = ""
                    default:
                        currentField.append(character)
                    }
                }

                index += 1
            }

            if !currentField.isEmpty || !currentRow.isEmpty {
                currentRow.append(currentField)
                rows.append(currentRow)
            }

            return rows
        }
    }

    // MARK: - 1.2 Prototype Data (15 placeholders)

    @FetchRequest(
        sortDescriptors: [
            NSSortDescriptor(key: "sortOrder", ascending: true),
            NSSortDescriptor(key: "name", ascending: true)
        ],
        predicate: NSPredicate(format: "isActive == YES"),
        animation: .default
    ) private var storedProperties: FetchedResults<RentalProperty>

    @FetchRequest(
        sortDescriptors: [
            NSSortDescriptor(key: "checkInDate", ascending: false),
            NSSortDescriptor(key: "createdAt", ascending: false)
        ],
        animation: .default
    ) private var storedBookings: FetchedResults<Booking>

    // MARK: - 1.3 Filters

    /// Empty set == All
    @State private var selectedPropertyNames: Set<String> = []
    private var propertyOptions: [PropertyOption] {
        storedProperties.compactMap { property in
            guard let id = property.id else { return nil }
            let trimmedName = (property.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedName.isEmpty else { return nil }
            return PropertyOption(
                id: id,
                name: trimmedName,
                shortName: ((property.shortName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)).isEmpty
                    ? trimmedName
                    : (property.shortName ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                pricePerNightDefault: property.pricePerNightDefault,
                cleaningFeeDefault: property.cleaningFeeDefault,
                cleaningPaymentDefault: property.cleaningPaymentDefault,
                serviceFeeDefault: property.serviceFeeDefault,
                taxRateDefault: property.taxRateDefault
            )
        }
    }
    /// Empty set == All
    @State private var selectedYears: Set<Int> = []
    /// Empty set == All
    @State private var selectedStatuses: Set<ReservationStatus> = []

    // MARK: - 1.4 Selection + Sheets

    struct PresentedReservation: Identifiable, Equatable {
        let id: UUID
    }
    @State private var selectedReservationID: UUID? = nil
    @State private var draftReservation: Reservation? = nil
    @State private var presentedReservation: PresentedReservation? = nil
    @State private var pendingDeleteReservation: Reservation? = nil

    @State private var isShowingYearPicker: Bool = false
    @State private var isShowingStatusPicker: Bool = false

    // MARK: - 1.5 Derived

    private var allReservations: [Reservation] {
        storedBookings.compactMap { booking in
            reservation(from: booking)
        }
    }

    private func reservation(from booking: Booking) -> Reservation? {
        guard let id = booking.id else { return nil }

        return Reservation(
            id: id,
            propertyName: booking.propertyName ?? "",
            status: ReservationStatus(rawValue: booking.status ?? "") ?? .booked,
            renterFirstName: booking.renterFirstName ?? "",
            renterLastName: booking.renterLastName ?? "",
            startDate: booking.checkInDate ?? Date(),
            endDate: booking.checkOutDate ?? Date(),
            inquiryDate: booking.inquiryDate,
            bookingDate: booking.bookingDate,
            pricePerNight: booking.pricePerNight,
            cleaningFee: booking.cleaningFee,
            cleaningPayment: booking.cleaningPayment,
            serviceFee: booking.serviceFee,
            taxAmount: booking.taxAmount,
            taxRateApplied: booking.taxRateApplied,
            discountAmount: booking.discountAmount,
            bookingSource: booking.bookingSource ?? "",
            paymentStatus: booking.paymentStatus ?? "",
            phoneNumber: booking.phoneNumber ?? "",
            emailAddress: booking.emailAddress ?? "",
            earlyCheckInRequested: booking.earlyCheckInRequested,
            lateCheckOutRequested: booking.lateCheckOutRequested,
            platformsBlocked: booking.platformsBlocked,
            bookingReason: booking.bookingReason ?? "",
            notes: booking.notes ?? ""
        )
    }

    private func bookingEntity(for reservationID: UUID) -> Booking? {
        storedBookings.first(where: { $0.id == reservationID })
    }

    private func rentalPropertyEntity(named propertyName: String) -> RentalProperty? {
        let trimmed = propertyName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        return storedProperties.first {
            let name = ($0.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let shortName = ($0.shortName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return name.localizedCaseInsensitiveCompare(trimmed) == .orderedSame
                || shortName.localizedCaseInsensitiveCompare(trimmed) == .orderedSame
        }
    }

    private func propertyOption(named propertyName: String) -> PropertyOption? {
        let trimmed = propertyName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        return propertyOptions.first {
            $0.name.localizedCaseInsensitiveCompare(trimmed) == .orderedSame
                || $0.shortName.localizedCaseInsensitiveCompare(trimmed) == .orderedSame
        }
    }

    private func propertyFilterToken(for propertyName: String) -> String {
        propertyOption(named: propertyName)?.name ?? propertyName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func calculatedTaxAmount(pricePerNight: Double, checkInDate: Date, checkOutDate: Date, taxRatePercent: Double) -> Double {
        let nights = max(0, Calendar.current.dateComponents([.day], from: checkInDate, to: checkOutDate).day ?? 0)
        let taxableBase = pricePerNight * Double(nights)
        return taxableBase * (taxRatePercent / 100.0)
    }

    private func applyPropertyDefaults(to reservation: inout Reservation, propertyName: String) {
        guard let option = propertyOption(named: propertyName) else { return }

        reservation.pricePerNight = option.pricePerNightDefault
        reservation.cleaningFee = option.cleaningFeeDefault
        reservation.cleaningPayment = option.cleaningPaymentDefault
        reservation.serviceFee = option.serviceFeeDefault
        reservation.taxRateApplied = option.taxRateDefault
        reservation.discountAmount = 0
        reservation.taxAmount = calculatedTaxAmount(
            pricePerNight: reservation.pricePerNight,
            checkInDate: reservation.startDate,
            checkOutDate: reservation.endDate,
            taxRatePercent: reservation.taxRateApplied
        )
    }

    private var availableYears: [Int] {
        let years = Set(allReservations.map { $0.year })
        return years.sorted(by: >)
    }

    private var filteredReservations: [Reservation] {
        allReservations
            .filter {
                selectedPropertyNames.isEmpty
                    ? true
                    : selectedPropertyNames.contains(propertyFilterToken(for: $0.propertyName))
            }
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

    static func makeBookingsCSVExportFile(context: NSManagedObjectContext) throws -> URL {
        try BookingCSVExporter.writeExportFile(context: context)
    }

    static func importBookingsCSV(from url: URL, context: NSManagedObjectContext) throws -> Int {
        print("[BookingCSVImport] Import entry")
        print("[BookingCSVImport] Selected file URL: \(url.path)")
        let importedCount = try BookingCSVImporter.importFile(from: url, context: context)
        print("[BookingCSVImport] Returned import count: \(importedCount)")
        return importedCount
    }

    static func deleteAllBookingData(context: NSManagedObjectContext) throws -> Int {
        let fetchRequest: NSFetchRequest<NSFetchRequestResult> = Booking.fetchRequest()
        let countRequest: NSFetchRequest<Booking> = Booking.fetchRequest()
        let existingCount = try context.count(for: countRequest)

        guard existingCount > 0 else { return 0 }

        let deleteRequest = NSBatchDeleteRequest(fetchRequest: fetchRequest)
        deleteRequest.resultType = .resultTypeObjectIDs

        do {
            let result = try context.execute(deleteRequest) as? NSBatchDeleteResult
            if let deletedObjectIDs = result?.result as? [NSManagedObjectID], !deletedObjectIDs.isEmpty {
                let changes: [AnyHashable: Any] = [NSDeletedObjectsKey: deletedObjectIDs]
                NSManagedObjectContext.mergeChanges(fromRemoteContextSave: changes, into: [context])
            } else {
                context.refreshAllObjects()
            }
            return existingCount
        } catch {
            throw BookingBulkDeleteError.failedToDelete
        }
    }

    // MARK: - 1.6 Body

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Theme.BrandedHeaderView(title: "Bookings")

                    Button {
                        beginNewReservation()
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 40, height: 40)
                            .background(Theme.Colors.crimson)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .padding(.trailing, 12)
                    .disabled(propertyOptions.isEmpty)
                }
                .background(Theme.Colors.crimson)

                List {
                    // 2) Filters
                    Section {
                        VStack(alignment: .leading, spacing: 12) {
                            // 2.1 Property chips
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Property")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)

                                if propertyOptions.isEmpty {
                                    Text("No active properties available")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                } else {
                                    HStack(spacing: 10) {
                                        ForEach(propertyOptions) { option in
                                            filterChip(
                                                title: option.shortName,
                                                isSelected: isPropertySelected(option.name)
                                            ) {
                                                toggleProperty(option.name)
                                            }
                                        }
                                    }
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
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button(role: .destructive) {
                                        pendingDeleteReservation = reservation
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
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
            .sheet(item: $presentedReservation, onDismiss: {
                draftReservation = nil
                presentedReservation = nil
            }) { presentedReservation in
                NavigationStack {
                    if let draft = draftReservation, draft.id == presentedReservation.id {
                        ReservationEditorBasic(
                            reservation: binding(for: draft.id),
                            propertyOptions: propertyOptions,
                            isExistingReservation: bookingEntity(for: draft.id) != nil,
                            onDeleteConfirmed: {
                                deleteReservation(draft)
                            },
                            onSave: {
                                saveDraft()
                                self.presentedReservation = nil
                            }
                        )
                        .navigationTitle("Reservation")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .topBarLeading) {
                                Button("Close") {
                                    self.presentedReservation = nil
                                }
                                .foregroundColor(.white)
                            }
                            ToolbarItem(placement: .topBarTrailing) {
                                Button("Save") {
                                    saveDraft()
                                    self.presentedReservation = nil
                                }
                                .foregroundColor(.white)
                            }
                        }
                    } else {
                        Text("No reservation selected.")
                            .foregroundStyle(.secondary)
                            .padding()
                    }
                }
            }
            .alert(item: $pendingDeleteReservation) { reservation in
                Alert(
                    title: Text("Delete Reservation"),
                    message: Text("Are you sure you want to delete this reservation? This cannot be undone."),
                    primaryButton: .destructive(Text("Delete")) {
                        deleteReservation(reservation)
                    },
                    secondaryButton: .cancel()
                )
            }
        }
    }

    // MARK: - 1.7 Filter Helpers

    private func isPropertySelected(_ propertyName: String) -> Bool {
        selectedPropertyNames.isEmpty ? true : selectedPropertyNames.contains(propertyName)
    }

    private func toggleProperty(_ propertyName: String) {
        if selectedPropertyNames.isEmpty {
            selectedPropertyNames = [propertyName]
            return
        }

        if selectedPropertyNames.contains(propertyName) {
            selectedPropertyNames.remove(propertyName)
            if selectedPropertyNames.isEmpty {
                selectedPropertyNames = []
            }
        } else {
            selectedPropertyNames.insert(propertyName)
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
        presentedReservation = PresentedReservation(id: reservation.id)
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

        let now = Date()
        let booking = bookingEntity(for: draft.id) ?? Booking(context: viewContext)
        let isNewBooking = booking.id == nil

        if isNewBooking {
            booking.id = draft.id
            booking.createdAt = now
            booking.createdBy = "System"
        }

        booking.propertyName = draft.propertyName
        booking.propertyRef = rentalPropertyEntity(named: draft.propertyName)
        booking.status = draft.status.rawValue
        booking.renterFirstName = draft.renterFirstName
        booking.renterLastName = draft.renterLastName
        booking.checkInDate = draft.startDate
        booking.checkOutDate = draft.endDate
        booking.inquiryDate = draft.inquiryDate ?? now
        if draft.status == .booked || draft.status == .completed {
            booking.bookingDate = draft.bookingDate ?? now
        } else {
            booking.bookingDate = nil
        }
        booking.pricePerNight = draft.pricePerNight
        booking.cleaningFee = draft.cleaningFee
        booking.cleaningPayment = draft.cleaningPayment
        booking.serviceFee = draft.serviceFee
        booking.taxAmount = draft.taxAmount
        booking.taxRateApplied = draft.taxRateApplied
        booking.discountAmount = draft.discountAmount
        booking.bookingSource = draft.bookingSource
        booking.paymentStatus = draft.paymentStatus
        booking.phoneNumber = draft.phoneNumber
        booking.emailAddress = draft.emailAddress
        booking.earlyCheckInRequested = draft.earlyCheckInRequested
        booking.lateCheckOutRequested = draft.lateCheckOutRequested
        booking.platformsBlocked = draft.platformsBlocked
        booking.bookingReason = draft.bookingReason
        booking.notes = draft.notes
        booking.lastModifiedAt = now
        booking.lastModifiedBy = "System"

        do {
            try viewContext.save()
            selectedReservationID = draft.id
        } catch {
            let nsError = error as NSError
            print("[BookingsView] Failed to save booking: \(nsError), \(nsError.userInfo)")
        }
    }

    private func beginNewReservation() {
        guard let firstPropertyName = propertyOptions.first?.name else { return }

        let today = Calendar.current.startOfDay(for: Date())
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today) ?? today

        var newReservation = Reservation(
            id: UUID(),
            propertyName: firstPropertyName,
            status: .inquired,
            renterFirstName: "",
            renterLastName: "",
            startDate: today,
            endDate: tomorrow,
            inquiryDate: today,
            bookingDate: nil,
            pricePerNight: 0,
            cleaningFee: 0,
            cleaningPayment: 0,
            serviceFee: 0,
            taxAmount: 0,
            taxRateApplied: 0,
            discountAmount: 0,
            bookingSource: "",
            paymentStatus: "",
            phoneNumber: "",
            emailAddress: "",
            earlyCheckInRequested: false,
            lateCheckOutRequested: false,
            platformsBlocked: false,
            bookingReason: "",
            notes: ""
        )

        applyPropertyDefaults(to: &newReservation, propertyName: firstPropertyName)

        selectedReservationID = nil
        draftReservation = newReservation
        presentedReservation = PresentedReservation(id: newReservation.id)
    }

    private func deleteReservation(_ reservation: Reservation) {
        guard let booking = bookingEntity(for: reservation.id) else {
            if draftReservation?.id == reservation.id {
                presentedReservation = nil
                draftReservation = nil
            }
            pendingDeleteReservation = nil
            return
        }

        if selectedReservationID == reservation.id {
            selectedReservationID = nil
        }

        if draftReservation?.id == reservation.id {
            presentedReservation = nil
            draftReservation = nil
        }

        viewContext.delete(booking)

        do {
            try viewContext.save()
        } catch {
            let nsError = error as NSError
            print("[BookingsView] Failed to delete booking: \(nsError), \(nsError.userInfo)")
        }

        pendingDeleteReservation = nil
    }

    private func fallbackReservation() -> Reservation {
        let today = Calendar.current.startOfDay(for: Date())
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today) ?? today

        var reservation = Reservation(
            id: UUID(),
            propertyName: propertyOptions.first?.name ?? "",
            status: .inquired,
            renterFirstName: "",
            renterLastName: "",
            startDate: today,
            endDate: tomorrow,
            inquiryDate: today,
            bookingDate: nil,
            pricePerNight: 0,
            cleaningFee: 0,
            cleaningPayment: 0,
            serviceFee: 0,
            taxAmount: 0,
            taxRateApplied: 0,
            discountAmount: 0,
            bookingSource: "",
            paymentStatus: "",
            phoneNumber: "",
            emailAddress: "",
            earlyCheckInRequested: false,
            lateCheckOutRequested: false,
            platformsBlocked: false,
            bookingReason: "",
            notes: ""
        )

        if let propertyName = propertyOptions.first?.name {
            applyPropertyDefaults(to: &reservation, propertyName: propertyName)
        }

        return reservation
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
                Text(reservation.propertyName)
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
    let propertyOptions: [BookingsView.PropertyOption]
    let isExistingReservation: Bool
    let onDeleteConfirmed: () -> Void
    let onSave: () -> Void

    @State private var isShowingDeleteConfirmation: Bool = false
    @FocusState private var focusedField: FocusField?

    private enum FocusField: Hashable {
        case pricePerNight
        case taxRateApplied
    }

    private static let bookingSourceOptions: [String] = [
        "AirBnb",
        "VRBO",
        "Wix/Informal",
        "Blocked",
        "Gift"
    ]

    private static let paymentStatusOptions: [String] = [
        "Paid in Full",
        "Partially Paid",
        "Unpaid",
        "Deposit Returned",
        "NA"
    ]

    private static let bookingReasonOptions: [String] = [
        "Athletic Tournament",
        "Charity/Armadillo Use",
        "Corporate Retreat",
        "Reunion/Family Gathering/Friends",
        "Round Top",
        "TBD",
        "Wedding"
    ]

    private var inquiryDateBinding: Binding<Date> {
        Binding<Date>(
            get: { reservation.inquiryDate ?? reservation.startDate },
            set: { reservation.inquiryDate = $0 }
        )
    }

    private var bookingDateBinding: Binding<Date> {
        Binding<Date>(
            get: { reservation.bookingDate ?? Date() },
            set: { reservation.bookingDate = $0 }
        )
    }

    private var shouldShowBookingDate: Bool {
        reservation.status == .booked || reservation.status == .completed
    }

    private func propertyOption(named propertyName: String) -> BookingsView.PropertyOption? {
        let trimmed = propertyName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        return propertyOptions.first {
            $0.name.localizedCaseInsensitiveCompare(trimmed) == .orderedSame
        }
    }

    private var selectedPropertyDisplayName: String {
        let trimmed = reservation.propertyName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        return propertyOption(named: trimmed)?.shortName ?? trimmed
    }

    private func recalculateTaxAmount() {
        let nights = max(0, Calendar.current.dateComponents([.day], from: reservation.startDate, to: reservation.endDate).day ?? 0)
        let taxableBase = reservation.pricePerNight * Double(nights)
        reservation.taxAmount = taxableBase * (reservation.taxRateApplied / 100.0)
    }

    private func applyPropertyDefaults(for propertyName: String) {
        guard let option = propertyOption(named: propertyName) else { return }

        reservation.pricePerNight = option.pricePerNightDefault
        reservation.cleaningFee = option.cleaningFeeDefault
        reservation.cleaningPayment = option.cleaningPaymentDefault
        reservation.serviceFee = option.serviceFeeDefault
        reservation.taxRateApplied = option.taxRateDefault
        reservation.discountAmount = 0
        recalculateTaxAmount()
    }

    private func syncBookingDateForStatus() {
        if shouldShowBookingDate {
            if reservation.bookingDate == nil {
                reservation.bookingDate = Date()
            }
        } else {
            reservation.bookingDate = nil
        }
    }

    var body: some View {
        Form {
            Section("Guest") {
                TextField("First", text: $reservation.renterFirstName)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                TextField("Last", text: $reservation.renterLastName)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                TextField("Phone Number", text: $reservation.phoneNumber)
                    .keyboardType(.phonePad)
                TextField("Email Address", text: $reservation.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }

            Section("Stay") {
                DatePicker("Check-in", selection: $reservation.startDate, displayedComponents: .date)
                DatePicker("Check-out", selection: $reservation.endDate, displayedComponents: .date)
                DatePicker("Inquiry Date", selection: inquiryDateBinding, displayedComponents: .date)

                if shouldShowBookingDate {
                    DatePicker("Booking Date", selection: bookingDateBinding, displayedComponents: .date)
                }
            }

            Section("Property") {
                if propertyOptions.isEmpty {
                    Text("No active properties available")
                        .foregroundStyle(.secondary)
                } else {
                    Picker("Property", selection: $reservation.propertyName) {
                        if propertyOption(named: reservation.propertyName) == nil,
                           !selectedPropertyDisplayName.isEmpty {
                            Text(selectedPropertyDisplayName).tag(reservation.propertyName)
                        }
                        ForEach(propertyOptions) { option in
                            Text(option.shortName).tag(option.name)
                        }
                    }
                }
            }

            Section("Status & Source") {
                Picker("Status", selection: $reservation.status) {
                    ForEach(BookingsView.ReservationStatus.allCases) { s in
                        Text(s.rawValue).tag(s)
                    }
                }

                Picker("Booking Source", selection: $reservation.bookingSource) {
                    Text("Select Booking Source").tag("")
                    ForEach(Self.bookingSourceOptions, id: \.self) { option in
                        Text(option).tag(option)
                    }
                }

                Picker("Payment Status", selection: $reservation.paymentStatus) {
                    Text("Select Payment Status").tag("")
                    ForEach(Self.paymentStatusOptions, id: \.self) { option in
                        Text(option).tag(option)
                    }
                }

                Picker("Booking Reason", selection: $reservation.bookingReason) {
                    Text("Select Booking Reason").tag("")
                    ForEach(Self.bookingReasonOptions, id: \.self) { option in
                        Text(option).tag(option)
                    }
                }
            }

            Section("Financial") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Price Per Night")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("$0.00", value: $reservation.pricePerNight, format: .currency(code: Locale.current.currency?.identifier ?? "USD"))
                        .keyboardType(.decimalPad)
                        .focused($focusedField, equals: .pricePerNight)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Cleaning Fee")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("$0.00", value: $reservation.cleaningFee, format: .currency(code: Locale.current.currency?.identifier ?? "USD"))
                        .keyboardType(.decimalPad)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Cleaning Payment")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("$0.00", value: $reservation.cleaningPayment, format: .currency(code: Locale.current.currency?.identifier ?? "USD"))
                        .keyboardType(.decimalPad)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Service Fee")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("$0.00", value: $reservation.serviceFee, format: .currency(code: Locale.current.currency?.identifier ?? "USD"))
                        .keyboardType(.decimalPad)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Tax Amount")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("$0.00", value: $reservation.taxAmount, format: .currency(code: Locale.current.currency?.identifier ?? "USD"))
                        .keyboardType(.decimalPad)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Tax Rate Applied")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("0.00%", value: $reservation.taxRateApplied, format: .number)
                        .keyboardType(.decimalPad)
                        .focused($focusedField, equals: .taxRateApplied)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Discount Amount")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("$0.00", value: $reservation.discountAmount, format: .currency(code: Locale.current.currency?.identifier ?? "USD"))
                        .keyboardType(.decimalPad)
                }
            }

            Section("Requests & Flags") {
                Toggle("Early Check-In Requested", isOn: $reservation.earlyCheckInRequested)
                Toggle("Late Check-Out Requested", isOn: $reservation.lateCheckOutRequested)
                Toggle("Platforms Blocked", isOn: $reservation.platformsBlocked)
            }

            Section("Notes") {
                TextField("Notes", text: $reservation.notes, axis: .vertical)
                    .lineLimit(4...8)
                    .textInputAutocapitalization(.sentences)
            }

            if isExistingReservation {
                Section {
                    Button("Delete", role: .destructive) {
                        isShowingDeleteConfirmation = true
                    }
                }
            }
        }
        .onAppear {
            if reservation.inquiryDate == nil {
                reservation.inquiryDate = Date()
            }
            syncBookingDateForStatus()
        }
        .onChange(of: reservation.status) { _, _ in
            syncBookingDateForStatus()
        }
        .onChange(of: reservation.propertyName) { _, newValue in
            applyPropertyDefaults(for: newValue)
        }
        .onChange(of: reservation.startDate) { _, _ in
            recalculateTaxAmount()
        }
        .onChange(of: reservation.endDate) { _, _ in
            recalculateTaxAmount()
        }
        .onChange(of: focusedField) { oldValue, newValue in
            if oldValue == .pricePerNight && newValue != .pricePerNight {
                recalculateTaxAmount()
            }
            if oldValue == .taxRateApplied && newValue != .taxRateApplied {
                recalculateTaxAmount()
            }
        }
        .alert("Delete Reservation", isPresented: $isShowingDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                onDeleteConfirmed()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Are you sure you want to delete this reservation? This cannot be undone.")
        }
    }
}

#Preview {
    BookingsView()
}
