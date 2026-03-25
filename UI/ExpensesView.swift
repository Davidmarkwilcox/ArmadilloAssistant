// ExpensesView.swift
// ArmadilloAssistant
//
// Description:
// ExpensesView provides the Expenses screen UI and keeps the expense feature logic consolidated in one file.
// It currently supports:
// 1) Standard branded header
// 2) Filters section (Recent 30 Days / Current Year, Reimbursed toggle, Expenser multi-select)
// 3) Expenses list section
// 4) New Expense and Edit Expense sheets backed by Core Data
// 5) Expense detail pop-out
// 6) Expense deletion with confirmation from detail view and swipe actions
// 7) Empty states and pull-to-refresh
//

import SwiftUI
import CoreData
import UIKit

// MARK: - 1) ExpensesView

struct ExpensesView: View {

    // MARK: - 1.1 Models

    enum ExpenseRangeFilter: String, CaseIterable, Identifiable {
        case recent30Days = "Recent (30 days)"
        case currentYear = "Current Year"

        var id: String { rawValue }
    }

    enum Expenser: String, CaseIterable, Identifiable, Hashable {
        case bradWilson = "Brad Wilson"
        case christaWilson = "Christa Wilson"
        case corrinWilcox = "Corrin Wilcox"
        case davidWilcox = "David Wilcox"

        var id: String { rawValue }
    }

    struct ExpenseItem: Identifiable {
        let id: UUID
        let storageID: NSManagedObjectID
        let date: Date
        let property: String
        let category: String
        let description: String
        let amount: Decimal
        let expenser: Expenser
        let isReimbursed: Bool

        init(
            id: UUID = UUID(),
            storageID: NSManagedObjectID,
            date: Date,
            property: String,
            category: String,
            description: String,
            amount: Decimal,
            expenser: Expenser,
            isReimbursed: Bool
        ) {
            self.id = id
            self.storageID = storageID
            self.date = date
            self.property = property
            self.category = category
            self.description = description
            self.amount = amount
            self.expenser = expenser
            self.isReimbursed = isReimbursed
        }
    }

    struct ExpenseEditorDraft {
        var expenseType: String = "Direct Expense"
        var expenseDate: Date = Date()
        var projectName: String = ""
        var categoryName: String = ""
        var expenser: Expenser = .davidWilcox
        var isReimbursed: Bool = false
        var expenseAmountText: String = ""
        var mileageText: String = ""
        var mileageRateText: String = ""
        var notes: String = ""
    }

    enum ExpenseCSVExportError: LocalizedError {
        case failedToWriteFile

        var errorDescription: String? {
            switch self {
            case .failedToWriteFile:
                return "Unable to create the expenses CSV export file."
            }
        }
    }

    enum ExpenseCSVImportError: LocalizedError {
        case unreadableFile
        case invalidHeader
        case invalidDate(row: Int, value: String)
        case invalidBoolean(row: Int, value: String)
        case invalidNumber(row: Int, column: String, value: String)

        var errorDescription: String? {
            switch self {
            case .unreadableFile:
                return "Unable to read the selected CSV file."
            case .invalidHeader:
                return "The selected CSV file does not match the expected Expenses import template."
            case .invalidDate(let row, let value):
                return "Invalid Expense Date on row \(row): \(value)"
            case .invalidBoolean(let row, let value):
                return "Invalid Reimbursed? value on row \(row): \(value)"
            case .invalidNumber(let row, let column, let value):
                return "Invalid numeric value for \(column) on row \(row): \(value)"
            }
        }
    }

    enum ExpenseBulkDeleteError: LocalizedError {
        case failedToDelete

        var errorDescription: String? {
            switch self {
            case .failedToDelete:
                return "Unable to delete the stored expense records."
            }
        }
    }

    struct ExpenseCSVExporter {
        private static let headers: [String] = [
            "Expense Type",
            "Expense Date",
            "Project",
            "Category",
            "Expenser",
            "Reimbursed?",
            "Expense Amount",
            "Mileage",
            "Mileage Rate",
            "Reimbursement Amount",
            "Notes"
        ]

        private static let dateFormatter: DateFormatter = {
            let formatter = DateFormatter()
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone.current
            formatter.dateFormat = "yyyy-MM-dd"
            return formatter
        }()

        private static let twoDecimalFormatter: NumberFormatter = {
            let formatter = NumberFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.numberStyle = .decimal
            formatter.usesGroupingSeparator = false
            formatter.minimumFractionDigits = 2
            formatter.maximumFractionDigits = 2
            return formatter
        }()

        private static let mileageFormatter: NumberFormatter = {
            let formatter = NumberFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.numberStyle = .decimal
            formatter.usesGroupingSeparator = false
            formatter.minimumFractionDigits = 0
            formatter.maximumFractionDigits = 2
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

        static func fetchExpenses(context: NSManagedObjectContext) throws -> [Expense] {
            let request: NSFetchRequest<Expense> = Expense.fetchRequest()
            request.sortDescriptors = [
                NSSortDescriptor(keyPath: \Expense.expenseDate, ascending: false),
                NSSortDescriptor(keyPath: \Expense.createdAt, ascending: false)
            ]
            return try context.fetch(request)
        }

        static func csvString(from expenses: [Expense]) -> String {
            let headerRow = headers.map(csvEscaped).joined(separator: ",")
            let rows = expenses.map { expense in
                let columns: [String] = [
                    expense.expenseType ?? "",
                    formattedDate(expense.expenseDate),
                    expense.project ?? "",
                    expense.category ?? "",
                    expense.expenser ?? "",
                    expense.reimbursed ? "Yes" : "No",
                    formattedCurrencyValue(expense.expenseAmount),
                    formattedMileageValue(expense.mileage),
                    formattedCurrencyValue(expense.mileageRate),
                    formattedCurrencyValue(expense.reimbursementAmount),
                    expense.notes ?? ""
                ]
                return columns.map(csvEscaped).joined(separator: ",")
            }

            return ([headerRow] + rows).joined(separator: "\n")
        }

        static func writeExportFile(context: NSManagedObjectContext) throws -> URL {
            let expenses = try fetchExpenses(context: context)
            let csv = csvString(from: expenses)
            let fileName = "Expenses_\(fileNameFormatter.string(from: Date())).csv"
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)

            do {
                try csv.write(to: url, atomically: true, encoding: .utf8)
                return url
            } catch {
                throw ExpenseCSVExportError.failedToWriteFile
            }
        }

        private static func formattedDate(_ date: Date?) -> String {
            guard let date else { return "" }
            return dateFormatter.string(from: date)
        }

        private static func formattedCurrencyValue(_ value: Double) -> String {
            twoDecimalFormatter.string(from: NSNumber(value: value)) ?? "0.00"
        }

        private static func formattedMileageValue(_ value: Double) -> String {
            mileageFormatter.string(from: NSNumber(value: value)) ?? "0"
        }

        private nonisolated static func csvEscaped(_ value: String) -> String {
            let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(escaped)\""
        }
    }

    struct ExpenseCSVImporter {
        static let headers: [String] = [
            "Expense Type",
            "Expense Date",
            "Project",
            "Category",
            "Expenser",
            "Reimbursed?",
            "Expense Amount",
            "Mileage",
            "Mileage Rate",
            "Reimbursement Amount",
            "Notes"
        ]

        private static let dateFormatter: DateFormatter = {
            let formatter = DateFormatter()
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone.current
            formatter.dateFormat = "yyyy-MM-dd"
            return formatter
        }()

        private struct ParsedExpenseRow {
            let expenseType: String
            let expenseDate: Date
            let project: String
            let category: String
            let expenser: String
            let reimbursed: Bool
            let expenseAmount: Double
            let mileage: Double
            let mileageRate: Double
            let reimbursementAmount: Double
            let notes: String
        }

        static func importFile(from url: URL, context: NSManagedObjectContext) throws -> Int {
            let csvText: String

            do {
                csvText = try String(contentsOf: url, encoding: .utf8)
            } catch {
                throw ExpenseCSVImportError.unreadableFile
            }

            let rows = parseCSVRows(csvText)
            guard let headerRow = rows.first else {
                throw ExpenseCSVImportError.invalidHeader
            }

            let normalizedHeader = normalizedHeaderRow(headerRow)
            let expectedHeader = normalizedHeaderRow(headers)
            guard Array(normalizedHeader.prefix(expectedHeader.count)) == expectedHeader else {
                throw ExpenseCSVImportError.invalidHeader
            }

            let parsedRows = try rows
                .dropFirst()
                .enumerated()
                .compactMap { offset, row in
                    try parsedExpenseRow(from: row, rowNumber: offset + 2)
                }

            if parsedRows.isEmpty {
                return 0
            }

            let now = Date()
            let trimmedProjects = fetchProjectMap(context: context)
            let trimmedCategories = fetchCategoryMap(context: context)

            for parsedRow in parsedRows {
                let expense = Expense(context: context)
                expense.id = UUID()
                expense.expenseType = parsedRow.expenseType
                expense.expenseDate = parsedRow.expenseDate
                expense.project = parsedRow.project
                expense.category = parsedRow.category
                expense.expenser = parsedRow.expenser
                expense.reimbursed = parsedRow.reimbursed
                expense.expenseAmount = parsedRow.expenseAmount
                expense.mileage = parsedRow.mileage
                expense.mileageRate = parsedRow.mileageRate
                expense.reimbursementAmount = parsedRow.reimbursementAmount
                expense.notes = parsedRow.notes
                expense.createdAt = now
                expense.createdBy = "CSV Import"
                expense.lastModifiedAt = now
                expense.lastModifiedBy = "CSV Import"
                expense.projectRef = trimmedProjects[parsedRow.project.trimmingCharacters(in: .whitespacesAndNewlines)]
                expense.categoryRef = trimmedCategories[parsedRow.category.trimmingCharacters(in: .whitespacesAndNewlines)]
            }

            do {
                try context.save()
            } catch {
                context.rollback()
                throw error
            }

            return parsedRows.count
        }

        private static func fetchProjectMap(context: NSManagedObjectContext) -> [String: ExpenseProject] {
            let request: NSFetchRequest<ExpenseProject> = ExpenseProject.fetchRequest()
            let projects = (try? context.fetch(request)) ?? []
            return Dictionary(uniqueKeysWithValues: projects.compactMap { project in
                guard let name = project.name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else {
                    return nil
                }
                return (name, project)
            })
        }

        private static func fetchCategoryMap(context: NSManagedObjectContext) -> [String: ExpenseCategory] {
            let request: NSFetchRequest<ExpenseCategory> = ExpenseCategory.fetchRequest()
            let categories = (try? context.fetch(request)) ?? []
            return Dictionary(uniqueKeysWithValues: categories.compactMap { category in
                guard let name = category.name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else {
                    return nil
                }
                return (name, category)
            })
        }

        private static func parsedExpenseRow(from row: [String], rowNumber: Int) throws -> ParsedExpenseRow? {
            let paddedRow = row + Array(repeating: "", count: max(0, headers.count - row.count))
            let normalized = Array(paddedRow.prefix(headers.count)).map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }

            let hasAnyValue = normalized.contains { !$0.isEmpty }
            guard hasAnyValue else { return nil }

            let expenseType = normalized[0].isEmpty ? "Direct Expense" : normalized[0]
            let expenseDateString = normalized[1]
            guard let expenseDate = dateFormatter.date(from: expenseDateString) else {
                throw ExpenseCSVImportError.invalidDate(row: rowNumber, value: expenseDateString)
            }

            let reimbursed = try parseBoolean(normalized[5], rowNumber: rowNumber)
            let expenseAmount = try parseNumber(normalized[6], rowNumber: rowNumber, column: "Expense Amount")
            let mileage = try parseNumber(normalized[7], rowNumber: rowNumber, column: "Mileage")
            let mileageRate = try parseNumber(normalized[8], rowNumber: rowNumber, column: "Mileage Rate")
            let reimbursementAmount = normalized[9].isEmpty
                ? (expenseAmount + (mileage * mileageRate))
                : try parseNumber(normalized[9], rowNumber: rowNumber, column: "Reimbursement Amount")

            return ParsedExpenseRow(
                expenseType: expenseType,
                expenseDate: expenseDate,
                project: normalized[2],
                category: normalized[3],
                expenser: normalized[4],
                reimbursed: reimbursed,
                expenseAmount: expenseAmount,
                mileage: mileage,
                mileageRate: mileageRate,
                reimbursementAmount: reimbursementAmount,
                notes: normalized[10]
            )
        }

        private static func parseBoolean(_ value: String, rowNumber: Int) throws -> Bool {
            if value.isEmpty { return false }

            switch value.lowercased() {
            case "yes", "y", "true", "1":
                return true
            case "no", "n", "false", "0":
                return false
            default:
                throw ExpenseCSVImportError.invalidBoolean(row: rowNumber, value: value)
            }
        }

        private static func parseNumber(_ value: String, rowNumber: Int, column: String) throws -> Double {
            if value.isEmpty { return 0 }

            let sanitized = value
                .replacingOccurrences(of: "$", with: "")
                .replacingOccurrences(of: ",", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            guard let parsed = Double(sanitized) else {
                throw ExpenseCSVImportError.invalidNumber(row: rowNumber, column: column, value: value)
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

    // MARK: - 1.2 State

    @Environment(\.managedObjectContext) private var viewContext

    @FetchRequest(
        sortDescriptors: [
            NSSortDescriptor(keyPath: \Expense.expenseDate, ascending: false),
            NSSortDescriptor(keyPath: \Expense.createdAt, ascending: false)
        ],
        animation: .default
    ) private var storedExpenses: FetchedResults<Expense>

    @FetchRequest(
        sortDescriptors: [
            NSSortDescriptor(keyPath: \ExpenseProject.sortOrder, ascending: true),
            NSSortDescriptor(keyPath: \ExpenseProject.name, ascending: true)
        ],
        animation: .default
    ) private var storedProjects: FetchedResults<ExpenseProject>

    @FetchRequest(
        sortDescriptors: [
            NSSortDescriptor(keyPath: \ExpenseCategory.sortOrder, ascending: true),
            NSSortDescriptor(keyPath: \ExpenseCategory.name, ascending: true)
        ],
        animation: .default
    ) private var storedCategories: FetchedResults<ExpenseCategory>

    @AppStorage("expense_currentMileageRate") private var storedMileageRate: Double = 0.67

    @State private var rangeFilter: ExpenseRangeFilter? = .recent30Days
    @State private var reimbursedOnly: Bool = false
    @State private var selectedExpensers: Set<Expenser> = []

    @State private var isShowingExpenserPicker: Bool = false
    @State private var isShowingNewExpenseSheet: Bool = false
    @State private var editingExpenseItem: ExpenseItem?
    @State private var selectedExpenseID: UUID?
    @State private var draftExpense: ExpenseItem?
    @State private var editingExpenseID: NSManagedObjectID?
    @State private var pendingSwipeDeleteExpense: ExpenseItem?
    @State private var isShowingDetails: Bool = false

    // MARK: - 1.3 Derived

    private var activeProjects: [ExpenseProject] {
        storedProjects.filter { $0.isActive }
    }

    private var activeCategories: [ExpenseCategory] {
        storedCategories.filter { $0.isActive }
    }

    private var coreDataExpenseItems: [ExpenseItem] {
        storedExpenses.map { expense in
            ExpenseItem(
                id: expense.id ?? UUID(),
                storageID: expense.objectID,
                date: expense.expenseDate ?? Date(),
                property: expense.project ?? "",
                category: expense.category ?? "",
                description: expense.notes ?? "",
                amount: Decimal(expense.reimbursementAmount),
                expenser: expenserValue(from: expense.expenser),
                isReimbursed: expense.reimbursed
            )
        }
    }

    private var filteredExpenses: [ExpenseItem] {
        coreDataExpenseItems
            .filter { expense in
                switch rangeFilter {
                case .recent30Days:
                    guard let cutoffDate = Calendar.current.date(byAdding: .day, value: -30, to: Date()) else {
                        return true
                    }
                    return expense.date >= cutoffDate
                case .currentYear:
                    return Calendar.current.isDate(expense.date, equalTo: Date(), toGranularity: .year)
                case nil:
                    return true
                }
            }
            .filter { !reimbursedOnly || $0.isReimbursed }
            .filter { selectedExpensers.isEmpty ? true : selectedExpensers.contains($0.expenser) }
    }

    private var isShowingEmptyState: Bool {
        storedExpenses.isEmpty
    }

    // MARK: - 1.4 Helpers

    static func makeExpensesCSVExportFile(context: NSManagedObjectContext) throws -> URL {
        try ExpenseCSVExporter.writeExportFile(context: context)
    }

    static func importExpensesCSV(from url: URL, context: NSManagedObjectContext) throws -> Int {
        try ExpenseCSVImporter.importFile(from: url, context: context)
    }

    static func deleteAllExpenseData(context: NSManagedObjectContext) throws -> Int {
        let fetchRequest: NSFetchRequest<NSFetchRequestResult> = Expense.fetchRequest()
        let countRequest: NSFetchRequest<Expense> = Expense.fetchRequest()
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
            throw ExpenseBulkDeleteError.failedToDelete
        }
    }

    private func refreshExpenseData() {
        viewContext.refreshAllObjects()
        viewContext.processPendingChanges()
    }

    private func expenserValue(from rawValue: String?) -> Expenser {
        guard let rawValue else { return .davidWilcox }
        return Expenser(rawValue: rawValue) ?? .davidWilcox
    }

    private func decimalValue(from text: String) -> Double {
        Double(text.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
    }

    private func makeDefaultDraft() -> ExpenseEditorDraft {
        ExpenseEditorDraft(
            expenseType: "Direct Expense",
            expenseDate: Date(),
            projectName: activeProjects.first?.name ?? "",
            categoryName: activeCategories.first?.name ?? "",
            expenser: .davidWilcox,
            isReimbursed: false,
            expenseAmountText: "",
            mileageText: "",
            mileageRateText: String(format: "%.2f", storedMileageRate),
            notes: ""
        )
    }

    private func makeEditDraft(from expenseItem: ExpenseItem) -> ExpenseEditorDraft {
        guard let storedExpense = storedExpenses.first(where: { $0.objectID == expenseItem.storageID }) else {
            return ExpenseEditorDraft(
                expenseType: "Direct Expense",
                expenseDate: expenseItem.date,
                projectName: expenseItem.property,
                categoryName: expenseItem.category,
                expenser: expenseItem.expenser,
                isReimbursed: expenseItem.isReimbursed,
                expenseAmountText: NSDecimalNumber(decimal: expenseItem.amount).stringValue,
                mileageText: "",
                mileageRateText: String(format: "%.2f", storedMileageRate),
                notes: expenseItem.description
            )
        }

        return ExpenseEditorDraft(
            expenseType: storedExpense.expenseType ?? "Direct Expense",
            expenseDate: storedExpense.expenseDate ?? expenseItem.date,
            projectName: (storedExpense.project ?? expenseItem.property).trimmingCharacters(in: .whitespacesAndNewlines),
            categoryName: (storedExpense.category ?? expenseItem.category).trimmingCharacters(in: .whitespacesAndNewlines),
            expenser: expenserValue(from: storedExpense.expenser),
            isReimbursed: storedExpense.reimbursed,
            expenseAmountText: storedExpense.expenseAmount == 0 ? "" : String(format: "%.2f", storedExpense.expenseAmount),
            mileageText: storedExpense.mileage == 0 ? "" : String(format: "%.1f", storedExpense.mileage),
            mileageRateText: storedExpense.mileageRate == 0 ? String(format: "%.2f", storedMileageRate) : String(format: "%.2f", storedExpense.mileageRate),
            notes: storedExpense.notes ?? expenseItem.description
        )
    }

    private func addExpense(from draft: ExpenseEditorDraft) {
        let now = Date()
        let expenseAmount = decimalValue(from: draft.expenseAmountText)
        let mileage = decimalValue(from: draft.mileageText)
        let mileageRate = decimalValue(from: draft.mileageRateText)
        let reimbursementAmount = expenseAmount + (mileage * mileageRate)

        let expense = Expense(context: viewContext)
        expense.id = UUID()
        expense.expenseType = draft.expenseType
        expense.expenseDate = draft.expenseDate
        expense.project = draft.projectName
        expense.category = draft.categoryName
        expense.expenser = draft.expenser.rawValue
        expense.reimbursed = draft.isReimbursed
        expense.expenseAmount = expenseAmount
        expense.mileage = mileage
        expense.mileageRate = mileageRate
        expense.reimbursementAmount = reimbursementAmount
        expense.notes = draft.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        expense.createdAt = now
        expense.createdBy = "System"
        expense.lastModifiedAt = now
        expense.lastModifiedBy = "System"
        expense.projectRef = activeProjects.first(where: { $0.name == draft.projectName })
        expense.categoryRef = activeCategories.first(where: { $0.name == draft.categoryName })

        do {
            try viewContext.save()
        } catch {
            viewContext.rollback()
        }
    }

    private func updateExpense(from draft: ExpenseEditorDraft, expenseID: NSManagedObjectID) {
        guard let storedExpense = storedExpenses.first(where: { $0.objectID == expenseID }) else { return }

        let now = Date()
        let expenseAmount = decimalValue(from: draft.expenseAmountText)
        let mileage = decimalValue(from: draft.mileageText)
        let mileageRate = decimalValue(from: draft.mileageRateText)
        let reimbursementAmount = expenseAmount + (mileage * mileageRate)

        storedExpense.expenseType = draft.expenseType
        storedExpense.expenseDate = draft.expenseDate
        storedExpense.project = draft.projectName
        storedExpense.category = draft.categoryName
        storedExpense.expenser = draft.expenser.rawValue
        storedExpense.reimbursed = draft.isReimbursed
        storedExpense.expenseAmount = expenseAmount
        storedExpense.mileage = mileage
        storedExpense.mileageRate = mileageRate
        storedExpense.reimbursementAmount = reimbursementAmount
        storedExpense.notes = draft.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        storedExpense.lastModifiedAt = now
        storedExpense.lastModifiedBy = "System"
        storedExpense.projectRef = activeProjects.first(where: { $0.name == draft.projectName })
        storedExpense.categoryRef = activeCategories.first(where: { $0.name == draft.categoryName })

        do {
            try viewContext.save()
        } catch {
            viewContext.rollback()
        }
    }

    private func deleteExpense(_ expenseItem: ExpenseItem) {
        guard let storedExpense = storedExpenses.first(where: { $0.objectID == expenseItem.storageID }) else {
            selectedExpenseID = nil
            draftExpense = nil
            editingExpenseID = nil
            editingExpenseItem = nil
            pendingSwipeDeleteExpense = nil
            isShowingDetails = false
            return
        }

        viewContext.delete(storedExpense)

        do {
            try viewContext.save()
            selectedExpenseID = nil
            draftExpense = nil
            editingExpenseID = nil
            editingExpenseItem = nil
            pendingSwipeDeleteExpense = nil
            isShowingDetails = false
        } catch {
            viewContext.rollback()
        }
    }

    private func beginEditing(_ expenseItem: ExpenseItem) {
        editingExpenseID = expenseItem.storageID
        editingExpenseItem = expenseItem
        isShowingDetails = false
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

    private var availableExpensers: [Expenser] {
        Expenser.allCases
    }

    private var expenserButtonSubtitle: String {
        let all = Set(availableExpensers)
        if selectedExpensers.isEmpty { return "All" }
        if selectedExpensers == all { return "All" }
        return availableExpensers
            .filter { selectedExpensers.contains($0) }
            .map { $0.rawValue }
            .joined(separator: ", ")
    }

    // MARK: - 1.5 Body

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Theme.BrandedHeaderView(title: "Expenses")

                List {
                    Section {
                        VStack(alignment: .leading, spacing: 12) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Date Range")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)

                                HStack(spacing: 10) {
                                    filterChip(
                                        title: ExpenseRangeFilter.recent30Days.rawValue,
                                        isSelected: rangeFilter == .recent30Days
                                    ) {
                                        rangeFilter = (rangeFilter == .recent30Days) ? nil : .recent30Days
                                    }

                                    filterChip(
                                        title: ExpenseRangeFilter.currentYear.rawValue,
                                        isSelected: rangeFilter == .currentYear
                                    ) {
                                        rangeFilter = (rangeFilter == .currentYear) ? nil : .currentYear
                                    }
                                }

                                Text(rangeFilter == nil ? "All Expenses" : "")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Toggle(isOn: $reimbursedOnly) {
                                Text("Reimbursed?")
                                    .font(.subheadline)
                            }
                            .toggleStyle(.switch)

                            Button {
                                isShowingExpenserPicker = true
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Expenser")
                                            .font(.subheadline)
                                        Text(expenserButtonSubtitle)
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

                    Section {
                        if isShowingEmptyState {
                            VStack(spacing: 10) {
                                Image(systemName: "dollarsign.circle")
                                    .font(.system(size: 28))
                                    .foregroundStyle(.secondary)

                                Text("No Expenses Yet")
                                    .font(.headline)

                                Text("Tap New Expense to add your first record.")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 24)
                            .listRowBackground(Color.clear)
                        } else if filteredExpenses.isEmpty {
                            VStack(spacing: 8) {
                                Text("No Matching Expenses")
                                    .font(.headline)

                                Text("Adjust your filters to see more results.")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 20)
                            .listRowBackground(Color.clear)
                        } else {
                            ForEach(filteredExpenses) { expense in
                                ExpenseRowBasic(
                                    expense: expense,
                                    isSelected: expense.id == selectedExpenseID
                                )
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    selectExpense(expense)
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    if storedExpenses.contains(where: { $0.objectID == expense.storageID }) {
                                        Button(role: .destructive) {
                                            pendingSwipeDeleteExpense = expense
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    }
                                }
                                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                            }
                        }
                    } header: {
                        HStack {
                            Text("Expenses")
                            Spacer()
                            Text("\(filteredExpenses.count)")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .refreshable {
                    refreshExpenseData()
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .bottom) {
                HStack {
                    Spacer()
                    Button {
                        isShowingNewExpenseSheet = true
                    } label: {
                        Label("New Expense", systemImage: "plus")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(Color.accentColor)
                            .overlay(
                                Capsule()
                                    .stroke(.white.opacity(0.9), lineWidth: 1)
                            )
                            .clipShape(Capsule())
                    }
                    .padding(.trailing, 16)
                    .padding(.bottom, 8)
                }
            }
            .sheet(isPresented: $isShowingNewExpenseSheet) {
                NavigationStack {
                    ExpenseEditorSheet(
                        draft: makeDefaultDraft(),
                        projects: activeProjects.compactMap(\.name),
                        categories: activeCategories.compactMap(\.name)
                    ) { draft in
                        addExpense(from: draft)
                        isShowingNewExpenseSheet = false
                    } onCancel: {
                        isShowingNewExpenseSheet = false
                    }
                    .navigationTitle("New Expense")
                    .navigationBarTitleDisplayMode(.inline)
                }
            }
            .sheet(item: $editingExpenseItem, onDismiss: {
                editingExpenseID = nil
                editingExpenseItem = nil
            }) { expenseItem in
                NavigationStack {
                    ExpenseEditorSheet(
                        draft: makeEditDraft(from: expenseItem),
                        projects: activeProjects.compactMap(\.name),
                        categories: activeCategories.compactMap(\.name)
                    ) { draft in
                        updateExpense(from: draft, expenseID: expenseItem.storageID)
                        editingExpenseID = nil
                        editingExpenseItem = nil
                    } onCancel: {
                        editingExpenseID = nil
                        editingExpenseItem = nil
                    }
                    .navigationTitle("Edit Expense")
                    .navigationBarTitleDisplayMode(.inline)
                }
            }
            .sheet(isPresented: $isShowingExpenserPicker) {
                NavigationStack {
                    ExpenserPickerSheet(
                        selectedExpensers: $selectedExpensers,
                        availableExpensers: availableExpensers
                    ) {
                        isShowingExpenserPicker = false
                    }
                    .navigationTitle("Expenser")
                    .navigationBarTitleDisplayMode(.inline)
                }
            }
            .sheet(isPresented: $isShowingDetails) {
                NavigationStack {
                    if let expense = draftExpense {
                        ExpenseDetailView(
                            expense: expense,
                            canEdit: storedExpenses.contains(where: { $0.objectID == expense.storageID }),
                            canDelete: storedExpenses.contains(where: { $0.objectID == expense.storageID }),
                            onEdit: {
                                beginEditing(expense)
                            },
                            onDelete: {
                                deleteExpense(expense)
                            }
                        )
                        .navigationTitle("Expense")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .topBarLeading) {
                                Button("Close") { isShowingDetails = false }
                                    .foregroundStyle(.primary)
                            }
                        }
                    } else {
                        Text("No expense selected.")
                            .foregroundStyle(.secondary)
                            .padding()
                    }
                }
            }
            .alert("Delete Expense?", isPresented: Binding(
                get: { pendingSwipeDeleteExpense != nil },
                set: { isPresented in
                    if !isPresented {
                        pendingSwipeDeleteExpense = nil
                    }
                }
            )) {
                Button("Cancel", role: .cancel) {
                    pendingSwipeDeleteExpense = nil
                }
                Button("Delete", role: .destructive) {
                    if let pendingSwipeDeleteExpense {
                        deleteExpense(pendingSwipeDeleteExpense)
                    }
                }
            } message: {
                Text("This expense will be permanently deleted.")
            }
        }
    }

    // MARK: - 1.6 Selection

    private func selectExpense(_ expense: ExpenseItem) {
        selectedExpenseID = expense.id
        draftExpense = expense
        isShowingDetails = true
    }
}

// MARK: - 2) Expense Editor Sheet

private struct ExpenseEditorSheet: View {
    @State var draft: ExpensesView.ExpenseEditorDraft
    let projects: [String]
    let categories: [String]
    let onSave: (ExpensesView.ExpenseEditorDraft) -> Void
    let onCancel: () -> Void

    @FocusState private var focusedField: Field?
    @State private var lastCommittedMileageText: String = ""

    private enum Field: Hashable {
        case expenseAmount
        case mileage
        case mileageRate
        case notes
    }

    private var expenseTypeOptions: [String] {
        var options = ["Direct Expense", "Mileage Expense", "Combined Expense"]
        let trimmedCurrent = draft.expenseType.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedCurrent.isEmpty && !options.contains(trimmedCurrent) {
            options.append(trimmedCurrent)
        }
        return options
    }

    private var projectOptions: [String] {
        let trimmedCurrent = draft.projectName.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = projects.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        if trimmedCurrent.isEmpty || base.contains(trimmedCurrent) {
            return base
        }
        return [trimmedCurrent] + base
    }

    private var categoryOptions: [String] {
        let trimmedCurrent = draft.categoryName.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = categories.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        if trimmedCurrent.isEmpty || base.contains(trimmedCurrent) {
            return base
        }
        return [trimmedCurrent] + base
    }

    private func normalizeMileageRateAfterMileageEditing() {
        let normalizedExpenseType = draft.expenseType.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedExpenseType == "Mileage" || normalizedExpenseType == "Mileage Expense" else { return }
        let trimmedMileage = draft.mileageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedMileage.isEmpty, trimmedMileage != lastCommittedMileageText else { return }

        let mileageValue = Double(trimmedMileage) ?? 0
        if mileageValue > 0 {
            let trimmedRate = draft.mileageRateText.trimmingCharacters(in: .whitespacesAndNewlines)
            let rateValue = Double(trimmedRate) ?? 0
            draft.expenseAmountText = String(format: "%.2f", mileageValue * rateValue)
        } else {
            draft.expenseAmountText = ""
        }

        lastCommittedMileageText = trimmedMileage
    }

    private func currencyBinding(_ text: Binding<String>) -> Binding<Double?> {
        Binding<Double?>(
            get: {
                let trimmed = text.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines)
                return Double(trimmed)
            },
            set: { newValue in
                if let newValue {
                    text.wrappedValue = String(format: "%.2f", newValue)
                } else {
                    text.wrappedValue = ""
                }
            }
        )
    }

    var body: some View {
        Form {
            Section("Basics") {
                Picker("Expense Type", selection: $draft.expenseType) {
                    ForEach(expenseTypeOptions, id: \.self) { expenseType in
                        Text(expenseType).tag(expenseType)
                    }
                }

                DatePicker("Expense Date", selection: $draft.expenseDate, displayedComponents: .date)

                Picker("Project", selection: $draft.projectName) {
                    ForEach(projectOptions, id: \.self) { project in
                        Text(project).tag(project)
                    }
                }

                Picker("Category", selection: $draft.categoryName) {
                    ForEach(categoryOptions, id: \.self) { category in
                        Text(category).tag(category)
                    }
                }

                Picker("Expenser", selection: $draft.expenser) {
                    ForEach(ExpensesView.Expenser.allCases) { expenser in
                        Text(expenser.rawValue).tag(expenser)
                    }
                }

                Toggle("Reimbursed?", isOn: $draft.isReimbursed)
            }

            Section("Amounts") {
                LabeledContent("Expense Amount") {
                    TextField(
                        "0.00",
                        value: currencyBinding($draft.expenseAmountText),
                        format: .currency(code: Locale.current.currency?.identifier ?? "USD")
                    )
                    .multilineTextAlignment(.trailing)
                    .keyboardType(.decimalPad)
                    .focused($focusedField, equals: .expenseAmount)
                }

                LabeledContent("Mileage") {
                    TextField("0.0", text: $draft.mileageText)
                        .multilineTextAlignment(.trailing)
                        .keyboardType(.decimalPad)
                        .focused($focusedField, equals: .mileage)
                }

                LabeledContent("Mileage Rate") {
                    TextField(
                        "0.00",
                        value: currencyBinding($draft.mileageRateText),
                        format: .currency(code: Locale.current.currency?.identifier ?? "USD")
                    )
                    .multilineTextAlignment(.trailing)
                    .keyboardType(.decimalPad)
                    .focused($focusedField, equals: .mileageRate)
                }
            }

            Section("Notes") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Notes")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    TextField("Notes", text: $draft.notes, axis: .vertical)
                        .lineLimit(3...6)
                        .focused($focusedField, equals: .notes)
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Cancel") { onCancel() }
                    .foregroundStyle(.primary)
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button("Save") { onSave(draft) }
                    .foregroundStyle(.primary)
                    .disabled(draft.projectName.isEmpty || draft.categoryName.isEmpty)
            }
        }
        .onAppear {
            lastCommittedMileageText = draft.mileageText.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        .onChange(of: focusedField) { _, newValue in
            if newValue != .mileage {
                normalizeMileageRateAfterMileageEditing()
            }
        }
    }
}

// MARK: - 3) Expense Row (Bookings-style)

private struct ExpenseRowBasic: View {
    let expense: ExpensesView.ExpenseItem
    let isSelected: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(expense.property) • \(expense.category)")
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text("\(formatDate(expense.date)) • \(expense.description)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                Text("Expenser: \(expense.expenser.rawValue)\(expense.isReimbursed ? " • Reimbursed" : "")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(formatCurrency(expense.amount))
                    .font(.subheadline)
                    .foregroundStyle(.primary)

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
        .listRowBackground(isSelected ? Color.accentColor.opacity(0.14) : Color.clear)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isSelected ? Color.accentColor.opacity(0.35) : Color.clear, lineWidth: 1)
        )
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    private func formatCurrency(_ amount: Decimal) -> String {
        let number = NSDecimalNumber(decimal: amount)
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        return formatter.string(from: number) ?? "$0.00"
    }
}

// MARK: - 4) Expense Detail Pop-out

private struct ExpenseDetailView: View {
    let expense: ExpensesView.ExpenseItem
    let canEdit: Bool
    let canDelete: Bool
    let onEdit: () -> Void
    let onDelete: () -> Void

    @State private var isShowingDeleteConfirmation: Bool = false

    var body: some View {
        List {
            Section {
                LabeledContent("Property", value: expense.property)
                LabeledContent("Category", value: expense.category)
                LabeledContent("Date", value: formatDate(expense.date))
                LabeledContent("Expenser", value: expense.expenser.rawValue)
                LabeledContent("Reimbursed", value: expense.isReimbursed ? "Yes" : "No")
            }

            Section("Description") {
                Text(expense.description)
                    .foregroundStyle(.primary)
            }

            Section {
                LabeledContent("Amount", value: formatCurrency(expense.amount))
            }

            if canEdit || canDelete {
                Section("Actions") {
                    if canEdit {
                        Button {
                            onEdit()
                        } label: {
                            Label("Edit Expense", systemImage: "pencil")
                        }
                    }

                    if canDelete {
                        Button(role: .destructive) {
                            isShowingDeleteConfirmation = true
                        } label: {
                            Label("Delete Expense", systemImage: "trash")
                        }
                    }
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: shareText(for: expense)) {
                    Text("Share")
                        .foregroundStyle(.white)
                }
                .tint(.white)
            }
        }
        .alert("Delete Expense?", isPresented: $isShowingDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                onDelete()
            }
        } message: {
            Text("This expense will be permanently deleted.")
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    private func formatCurrency(_ amount: Decimal) -> String {
        let number = NSDecimalNumber(decimal: amount)
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        return formatter.string(from: number) ?? "$0.00"
    }

    private func shareText(for expense: ExpensesView.ExpenseItem) -> String {
        "Expense • \(formatDate(expense.date))\n\(expense.property) • \(expense.category)\n\(expense.description)\nAmount: \(formatCurrency(expense.amount))\nExpenser: \(expense.expenser.rawValue)\nReimbursed: \(expense.isReimbursed ? "Yes" : "No")"
    }
}

// MARK: - 5) Expenser Picker Sheet (Bookings-style)

private struct ExpenserPickerSheet: View {

    @Binding var selectedExpensers: Set<ExpensesView.Expenser>
    let availableExpensers: [ExpensesView.Expenser]
    let onDone: () -> Void

    var body: some View {
        let allSet = Set(availableExpensers)
        let isAllSelected = !availableExpensers.isEmpty && selectedExpensers == allSet

        List {
            if availableExpensers.isEmpty {
                Text("No expensers available")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(availableExpensers) { expenser in
                    Toggle(
                        expenser.rawValue,
                        isOn: Binding(
                            get: { selectedExpensers.contains(expenser) },
                            set: { isOn in
                                if isOn {
                                    selectedExpensers.insert(expenser)
                                } else {
                                    selectedExpensers.remove(expenser)
                                }
                            }
                        )
                    )
                }

                Button(isAllSelected ? "Clear All" : "Select All") {
                    if isAllSelected {
                        selectedExpensers = []
                    } else {
                        selectedExpensers = allSet
                    }
                }
            }
        }
        .onAppear {
            if selectedExpensers.isEmpty {
                selectedExpensers = allSet
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
    ExpensesView()
}

// ExpensesView.swift
