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
        let date: Date
        let property: String
        let category: String
        let description: String
        let amount: Decimal
        let expenser: Expenser
        let isReimbursed: Bool

        init(
            id: UUID = UUID(),
            date: Date,
            property: String,
            category: String,
            description: String,
            amount: Decimal,
            expenser: Expenser,
            isReimbursed: Bool
        ) {
            self.id = id
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

        private static func csvEscaped(_ value: String) -> String {
            let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(escaped)\""
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

    @State private var rangeFilter: ExpenseRangeFilter = .recent30Days
    @State private var reimbursedOnly: Bool = false
    @State private var selectedExpensers: Set<Expenser> = []

    @State private var isShowingExpenserPicker: Bool = false
    @State private var isShowingNewExpenseSheet: Bool = false
    @State private var isShowingEditExpenseSheet: Bool = false
    @State private var selectedExpenseID: UUID?
    @State private var draftExpense: ExpenseItem?
    @State private var editDraft: ExpenseEditorDraft = ExpenseEditorDraft()
    @State private var editingExpenseID: UUID?
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
        guard let storedExpense = storedExpenses.first(where: { $0.id == expenseItem.id }) else {
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
            projectName: storedExpense.project ?? expenseItem.property,
            categoryName: storedExpense.category ?? expenseItem.category,
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

    private func updateExpense(from draft: ExpenseEditorDraft, expenseID: UUID) {
        guard let storedExpense = storedExpenses.first(where: { $0.id == expenseID }) else { return }

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
        guard let storedExpense = storedExpenses.first(where: { $0.id == expenseItem.id }) else {
            selectedExpenseID = nil
            draftExpense = nil
            editingExpenseID = nil
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
            pendingSwipeDeleteExpense = nil
            isShowingDetails = false
        } catch {
            viewContext.rollback()
        }
    }

    private func beginEditing(_ expenseItem: ExpenseItem) {
        editDraft = makeEditDraft(from: expenseItem)
        editingExpenseID = expenseItem.id
        isShowingDetails = false
        DispatchQueue.main.async {
            isShowingEditExpenseSheet = true
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
                                        rangeFilter = .recent30Days
                                    }

                                    filterChip(
                                        title: ExpenseRangeFilter.currentYear.rawValue,
                                        isSelected: rangeFilter == .currentYear
                                    ) {
                                        rangeFilter = .currentYear
                                    }
                                }
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
                                    if storedExpenses.contains(where: { $0.id == expense.id }) {
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
            .sheet(isPresented: $isShowingEditExpenseSheet) {
                NavigationStack {
                    ExpenseEditorSheet(
                        draft: editDraft,
                        projects: activeProjects.compactMap(\.name),
                        categories: activeCategories.compactMap(\.name)
                    ) { draft in
                        if let editingExpenseID {
                            updateExpense(from: draft, expenseID: editingExpenseID)
                        }
                        isShowingEditExpenseSheet = false
                    } onCancel: {
                        isShowingEditExpenseSheet = false
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
                            canEdit: storedExpenses.contains(where: { $0.id == expense.id }),
                            canDelete: storedExpenses.contains(where: { $0.id == expense.id }),
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

    private func normalizeMileageRateAfterMileageEditing() {
        guard draft.expenseType == "Mileage" else { return }
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
                    Text("Direct Expense").tag("Direct Expense")
                    Text("Mileage").tag("Mileage")
                }

                DatePicker("Expense Date", selection: $draft.expenseDate, displayedComponents: .date)

                Picker("Project", selection: $draft.projectName) {
                    ForEach(projects, id: \.self) { project in
                        Text(project).tag(project)
                    }
                }

                Picker("Category", selection: $draft.categoryName) {
                    ForEach(categories, id: \.self) { category in
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
