// ExpensesView.swift
// ArmadilloAssistant
//
// Description:
// ExpensesView is a prototype screen that mirrors the Bookings-style layout:
// 1) Standard branded header
// 2) Filters section (Recent 30 Days / Current Year, Reimbursed toggle, Expenser multi-select)
// 3) Expenses list section (Bookings-style rows)
//

import SwiftUI

// MARK: - 1) ExpensesView

struct ExpensesView: View {

    // MARK: - 1.1 Models (Prototype)

    enum ExpenseRangeFilter: String, CaseIterable, Identifiable {
        case recent30Days = "Recent (30 days)"
        case currentYear = "Current Year"

        var id: String { rawValue }
    }

    enum Expenser: String, CaseIterable, Identifiable, Hashable {
        case david = "David"
        case corrin = "Corrin"
        case cleaner = "Cleaner"
        case handyman = "Handyman"
        case contractor = "Contractor"

        var id: String { rawValue }
    }

    struct ExpenseItem: Identifiable {
        let id = UUID()
        let date: Date
        let property: String
        let category: String
        let description: String
        let amount: Decimal
        let expenser: Expenser
        let isReimbursed: Bool
    }

    // MARK: - 1.2 State

    @State private var rangeFilter: ExpenseRangeFilter = .recent30Days
    @State private var reimbursedOnly: Bool = false
    @State private var selectedExpensers: Set<Expenser> = []

    @State private var isShowingExpenserPicker: Bool = false
    @State private var selectedExpenseID: UUID?
    @State private var draftExpense: ExpenseItem?
    @State private var isShowingDetails: Bool = false

    // MARK: - 1.3 Placeholder Data

    private let placeholderExpenses: [ExpenseItem] = {
        let calendar = Calendar.current
        let now = Date()

        func daysAgo(_ days: Int) -> Date {
            calendar.date(byAdding: .day, value: -days, to: now) ?? now
        }

        return [
            ExpenseItem(date: daysAgo(2),  property: "Main Street", category: "Supplies",    description: "Paper towels + trash bags", amount: 34.27, expenser: .david,      isReimbursed: false),
            ExpenseItem(date: daysAgo(4),  property: "Barndo",      category: "Repairs",     description: "Door latch replacement",    amount: 18.99, expenser: .handyman,  isReimbursed: true),
            ExpenseItem(date: daysAgo(6),  property: "Alamo",       category: "Cleaning",    description: "Turnover cleaning",        amount: 155.00, expenser: .cleaner,   isReimbursed: false),
            ExpenseItem(date: daysAgo(7),  property: "Main Street", category: "Utilities",   description: "Internet service",         amount: 79.99, expenser: .david,      isReimbursed: false),
            ExpenseItem(date: daysAgo(9),  property: "Barndo",      category: "Supplies",    description: "Light bulbs (LED)",        amount: 22.48, expenser: .corrin,     isReimbursed: true),
            ExpenseItem(date: daysAgo(11), property: "Alamo",       category: "Repairs",     description: "HVAC air filter",          amount: 28.14, expenser: .corrin,     isReimbursed: false),
            ExpenseItem(date: daysAgo(13), property: "Main Street", category: "Maintenance", description: "Yard service",             amount: 60.00, expenser: .contractor, isReimbursed: false),
            ExpenseItem(date: daysAgo(15), property: "Barndo",      category: "Cleaning",    description: "Deep clean add-on",        amount: 85.00, expenser: .cleaner,   isReimbursed: false),
            ExpenseItem(date: daysAgo(18), property: "Alamo",       category: "Supplies",    description: "Toiletries restock",       amount: 41.62, expenser: .david,    isReimbursed: true),
            ExpenseItem(date: daysAgo(20), property: "Main Street", category: "Repairs",     description: "Faucet aerator",           amount: 9.75,  expenser: .handyman, isReimbursed: false),
            ExpenseItem(date: daysAgo(22), property: "Barndo",      category: "Utilities",   description: "Electric bill",            amount: 128.44, expenser: .david,   isReimbursed: false),
            ExpenseItem(date: daysAgo(24), property: "Alamo",       category: "Maintenance", description: "Pest control",             amount: 45.00, expenser: .contractor, isReimbursed: true),
            ExpenseItem(date: daysAgo(26), property: "Main Street", category: "Supplies",    description: "Coffee + creamer",         amount: 19.38, expenser: .corrin,  isReimbursed: false),
            ExpenseItem(date: daysAgo(28), property: "Barndo",      category: "Repairs",     description: "Smoke detector battery",   amount: 7.19,  expenser: .david,   isReimbursed: false),
            ExpenseItem(date: daysAgo(30), property: "Alamo",       category: "Utilities",   description: "Water bill",               amount: 52.10, expenser: .corrin,  isReimbursed: false)
        ]
    }()

    // MARK: - 1.4 Derived

    private var filteredExpenses: [ExpenseItem] {
        // Prototype: only apply reimbursed + expenser filters; date range is represented by the selected rangeFilter.
        // (We will wire real calculations later.)
        return placeholderExpenses
            .filter { !reimbursedOnly || $0.isReimbursed }
            .filter { selectedExpensers.isEmpty ? true : selectedExpensers.contains($0.expenser) }
    }

    // MARK: - 1.5 UI Helpers (Bookings-style)

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


    // MARK: - Expenser Picker Derived Helpers
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

    // MARK: - 1.6 Body

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Theme.BrandedHeaderView(title: "Expenses")

                List {
                    // MARK: - 2) Filters
                    Section {
                        VStack(alignment: .leading, spacing: 12) {
                            // Range filter (mutually exclusive)
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Date Range")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)

                                HStack(spacing: 10) {
                                    filterChip(title: ExpenseRangeFilter.recent30Days.rawValue, isSelected: rangeFilter == .recent30Days) {
                                        rangeFilter = .recent30Days
                                    }
                                    filterChip(title: ExpenseRangeFilter.currentYear.rawValue, isSelected: rangeFilter == .currentYear) {
                                        rangeFilter = .currentYear
                                    }
                                }
                            }

                            // Reimbursed toggle
                            Toggle(isOn: $reimbursedOnly) {
                                Text("Reimbursed?")
                                    .font(.subheadline)
                            }
                            .toggleStyle(.switch)

                            // Expenser (multi-select) — modeled after Bookings Reservation Status filter
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

                    // MARK: - 3) Expenses List
                    Section {
                        ForEach(filteredExpenses) { expense in
                            ExpenseRowBasic(
                                expense: expense,
                                isSelected: expense.id == selectedExpenseID
                            )
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectExpense(expense)
                            }
                            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
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
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $isShowingExpenserPicker) {
                NavigationStack {
                    ExpenserPickerSheet(selectedExpensers: $selectedExpensers, availableExpensers: availableExpensers) {
                        isShowingExpenserPicker = false
                    }
                    .navigationTitle("Expenser")
                    .navigationBarTitleDisplayMode(.inline)
                }
            }
            .sheet(isPresented: $isShowingDetails) {
                NavigationStack {
                    if let expense = draftExpense {
                        ExpenseDetailView(expense: expense)
                            .navigationTitle("Expense")
                            .navigationBarTitleDisplayMode(.inline)
                            .toolbar {
                                ToolbarItem(placement: .topBarLeading) {
                                    Button("Close") { isShowingDetails = false }
                                }
                            }
                    } else {
                        Text("No expense selected.")
                            .foregroundStyle(.secondary)
                            .padding()
                    }
                }
            }
        }
    }
    // MARK: - 1.6.1 Selection

    private func selectExpense(_ expense: ExpenseItem) {
        selectedExpenseID = expense.id
        draftExpense = expense
        isShowingDetails = true
    }

    // MARK: - 1.7 Formatting

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

// MARK: - 1.8 Expense Row (Bookings-style)

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

// MARK: - 2) Expense Detail Pop-out

private struct ExpenseDetailView: View {
    let expense: ExpensesView.ExpenseItem

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
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: shareText(for: expense)) {
                    Image(systemName: "square.and.arrow.up")
                }
            }
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
        return "Expense • \(formatDate(expense.date))\n\(expense.property) • \(expense.category)\n\(expense.description)\nAmount: \(formatCurrency(expense.amount))\nExpenser: \(expense.expenser.rawValue)\nReimbursed: \(expense.isReimbursed ? "Yes" : "No")"
    }
}

// MARK: - 3) Expenser Picker Sheet (Bookings-style)

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
                    Toggle(expenser.rawValue, isOn: Binding(
                        get: { selectedExpensers.contains(expenser) },
                        set: { isOn in
                            if isOn {
                                selectedExpensers.insert(expenser)
                            } else {
                                selectedExpensers.remove(expenser)
                            }
                        }
                    ))
                }

                Button(isAllSelected ? "Clear All" : "Select All") {
                    if isAllSelected {
                        // Main view interprets empty as All
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
