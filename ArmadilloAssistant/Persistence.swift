//  Persistence.swift
//  ArmadilloAssistant
//
//  Created by David Wilcox on 2/26/26.
//

import CloudKit
import CoreData
import Foundation

struct PersistenceController {
    static let shared = PersistenceController()
    static let cloudKitContainerIdentifier = "iCloud.com.DavidMWilcox.ArmadilloAssistant"

#if DEBUG
    // Section 0A: Development-only Public CloudKit schema initializer
    // Set this to true only while validating Public CloudKit schema/index creation in Development.
    // Do not use this in production builds.
    private static let shouldInitializePublicCloudKitSchema = true
#endif

    @MainActor
    static let preview: PersistenceController = {
        let result = PersistenceController(inMemory: true)
        let viewContext = result.container.viewContext
        viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        return result
    }()

    let container: NSPersistentCloudKitContainer

    var cloudKitContainer: CKContainer {
        CKContainer(identifier: Self.cloudKitContainerIdentifier)
    }

    enum PendingCloudKitOperation: String, Codable, Hashable {
        case add
        case update
        case delete
    }

    enum PendingCloudKitSyncStatus: String, Codable, Hashable {
        case pending
        case applied
        case failed
    }

    struct PendingCloudKitChange: Codable, Identifiable {
        let id: UUID
        let entityName: String
        let entityID: UUID
        let operation: PendingCloudKitOperation
        let timestamp: Date
        var syncStatus: PendingCloudKitSyncStatus
        var errorMessage: String?
        var payloadSnapshot: Data?
    }

    private struct PublicCloudKitRecordState {
        let ids: Set<UUID>
        let lastModifiedAtByID: [UUID: Date]
        let recordsByID: [UUID: CKRecord]
    }

    private final class PendingCloudKitChangeLedger {
        private let queue = DispatchQueue(label: "ArmadilloAssistant.PendingCloudKitChangeLedger")
        private let fileManager: FileManager
        private let fileURL: URL

        init(fileManager: FileManager = .default) {
            self.fileManager = fileManager
            let applicationSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? fileManager.temporaryDirectory
            let directoryURL = applicationSupportURL.appendingPathComponent("ArmadilloAssistant", isDirectory: true)
            self.fileURL = directoryURL.appendingPathComponent("PendingPublicCloudKitChanges.json")
        }

        @discardableResult
        func record(entityName: String,
                    entityID: UUID,
                    operation: PendingCloudKitOperation,
                    timestamp: Date = Date(),
                    payloadSnapshot: Data? = nil) -> UUID {
            queue.sync {
                var changes = loadChanges()

                if operation == .update,
                   changes.contains(where: {
                       $0.entityName == entityName
                           && $0.entityID == entityID
                           && $0.operation == .add
                           && $0.syncStatus == .pending
                   }) {
                    saveChanges(changes)
                    return changes.first {
                        $0.entityName == entityName
                            && $0.entityID == entityID
                            && $0.operation == .add
                            && $0.syncStatus == .pending
                    }?.id ?? UUID()
                }

                if operation == .add,
                   let existingAdd = changes.first(where: {
                       $0.entityName == entityName
                           && $0.entityID == entityID
                           && $0.operation == .add
                           && $0.syncStatus == .pending
                   }) {
                    saveChanges(changes)
                    return existingAdd.id
                }

                let change = PendingCloudKitChange(
                    id: UUID(),
                    entityName: entityName,
                    entityID: entityID,
                    operation: operation,
                    timestamp: timestamp,
                    syncStatus: .pending,
                    errorMessage: nil,
                    payloadSnapshot: payloadSnapshot
                )
                changes.append(change)
                saveChanges(changes)
                Debug.log(
                    "Recorded pending \(operation.rawValue) entity=\(entityName) entityID=\(entityID) changeID=\(change.id)",
                    channel: .pendingLedger,
                    source: "Persistence"
                )
                return change.id
            }
        }

        func markApplied(id: UUID) {
            Debug.log(
                "Marked pending change applied changeID=\(id)",
                channel: .pendingLedger,
                source: "Persistence"
            )
            updateChange(id: id, status: .applied, errorMessage: nil)
        }

        func markFailed(id: UUID, errorMessage: String) {
            Debug.log(
                "Marked pending change failed changeID=\(id) error=\(errorMessage)",
                channel: .pendingLedger,
                source: "Persistence"
            )
            updateChange(id: id, status: .failed, errorMessage: errorMessage)
        }

        func unresolvedChanges(entityName: String? = nil) -> [PendingCloudKitChange] {
            queue.sync {
                loadChanges().filter { change in
                    change.syncStatus == .pending && (entityName == nil || change.entityName == entityName)
                }
            }
        }

        func hasUnresolvedChange(entityName: String, entityID: UUID) -> Bool {
            queue.sync {
                loadChanges().contains {
                    $0.entityName == entityName
                        && $0.entityID == entityID
                        && $0.syncStatus == .pending
                }
            }
        }

        func markApplied(entityName: String, entityID: UUID, operations: Set<PendingCloudKitOperation>) {
            queue.sync {
                var changes = loadChanges()
                var appliedOperations: [String] = []
                for index in changes.indices {
                    guard changes[index].entityName == entityName,
                          changes[index].entityID == entityID,
                          operations.contains(changes[index].operation),
                          changes[index].syncStatus == .pending else {
                        continue
                    }

                    changes[index].syncStatus = .applied
                    changes[index].errorMessage = nil
                    appliedOperations.append(changes[index].operation.rawValue)
                }
                saveChanges(changes)

                if !appliedOperations.isEmpty {
                    Debug.log(
                        "Marked pending changes applied entity=\(entityName) entityID=\(entityID) operations=\(appliedOperations.sorted().joined(separator: ","))",
                        channel: .pendingLedger,
                        source: "Persistence"
                    )
                }
            }
        }

        private func updateChange(id: UUID, status: PendingCloudKitSyncStatus, errorMessage: String?) {
            queue.sync {
                var changes = loadChanges()
                guard let index = changes.firstIndex(where: { $0.id == id }) else { return }
                changes[index].syncStatus = status
                changes[index].errorMessage = errorMessage
                saveChanges(changes)
            }
        }

        private func loadChanges() -> [PendingCloudKitChange] {
            guard fileManager.fileExists(atPath: fileURL.path) else { return [] }

            do {
                let data = try Data(contentsOf: fileURL)
                return try JSONDecoder().decode([PendingCloudKitChange].self, from: data)
            } catch {
                preserveCorruptLedger()
                Debug.log(
                    "Failed to read pending-change ledger error=\(error)",
                    channel: .pendingLedger,
                    source: "Persistence"
                )
                return []
            }
        }

        private func saveChanges(_ changes: [PendingCloudKitChange]) {
            do {
                try fileManager.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                let data = try encoder.encode(changes)
                try data.write(to: fileURL, options: .atomic)
            } catch {
                Debug.log(
                    "Failed to write pending-change ledger error=\(error)",
                    channel: .pendingLedger,
                    source: "Persistence"
                )
            }
        }

        private func preserveCorruptLedger() {
            guard fileManager.fileExists(atPath: fileURL.path) else { return }

            let timestamp = ISO8601DateFormatter().string(from: Date())
                .replacingOccurrences(of: ":", with: "-")
            let corruptURL = fileURL.deletingLastPathComponent()
                .appendingPathComponent("PendingPublicCloudKitChanges.corrupt-\(timestamp).json")

            do {
                try fileManager.moveItem(at: fileURL, to: corruptURL)
            } catch {
                Debug.log(
                    "Failed to preserve corrupt ledger error=\(error)",
                    channel: .pendingLedger,
                    source: "Persistence"
                )
            }
        }
    }

    private static let pendingChangeLedger = PendingCloudKitChangeLedger()

    @discardableResult
    func recordPendingAdd(entityName: String, entityID: UUID, timestamp: Date = Date()) -> UUID {
        Self.pendingChangeLedger.record(entityName: entityName, entityID: entityID, operation: .add, timestamp: timestamp)
    }

    @discardableResult
    func recordPendingUpdate(entityName: String, entityID: UUID, timestamp: Date = Date()) -> UUID {
        Self.pendingChangeLedger.record(entityName: entityName, entityID: entityID, operation: .update, timestamp: timestamp)
    }

    @discardableResult
    func recordPendingDelete(entityName: String, entityID: UUID, timestamp: Date = Date()) -> UUID {
        Self.pendingChangeLedger.record(entityName: entityName, entityID: entityID, operation: .delete, timestamp: timestamp)
    }

    func markPendingChangeApplied(_ id: UUID) {
        Self.pendingChangeLedger.markApplied(id: id)
    }

    func markPendingChangeFailed(_ id: UUID, errorMessage: String) {
        Self.pendingChangeLedger.markFailed(id: id, errorMessage: errorMessage)
    }

    func hasUnresolvedPendingChange(entityName: String, entityID: UUID) -> Bool {
        Self.pendingChangeLedger.hasUnresolvedChange(entityName: entityName, entityID: entityID)
    }

    // Section 0B: CloudKit mirroring diagnostics
    // Logs import/export lifecycle events from NSPersistentCloudKitContainer so we can distinguish
    // between UI refresh issues and CloudKit mirroring delays or failures.
    private func configureCloudKitEventLogging() {
        NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification,
            object: container,
            queue: .main
        ) { notification in
            guard let event = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                    as? NSPersistentCloudKitContainer.Event else {
                Debug.log(
                    "Received event notification without event payload",
                    channel: .cloudKitEvents,
                    source: "Persistence"
                )
                return
            }

            let typeDescription: String
            switch event.type {
            case .setup:
                typeDescription = "setup"
            case .import:
                typeDescription = "import"
            case .export:
                typeDescription = "export"
            @unknown default:
                typeDescription = "unknown"
            }

            let successDescription = event.succeeded ? "succeeded" : "not-succeeded"
            let errorDescription = event.error.map { " error=\($0)" } ?? ""

            Debug.log(
                "type=\(typeDescription) status=\(successDescription) start=\(event.startDate) end=\(String(describing: event.endDate))\(errorDescription)",
                channel: .cloudKitEvents,
                source: "Persistence"
            )
        }
    }

    // Section 0C: Public CloudKit reconciliation
    // Reconciles confirmed Public CloudKit state with local records while preserving local
    // pending changes that NSPersistentCloudKitContainer has not exported/imported yet.
    func reconcileLocalExpensesWithPublicCloudKit(completion: (() -> Void)? = nil) {
        reconcilePendingPublicCloudKitChanges(completion: completion)
    }

    func reconcilePendingPublicCloudKitChanges(completion: (() -> Void)? = nil) {
        Debug.log(
            "Starting pending public CloudKit reconciliation",
            channel: .sync,
            source: "Persistence"
        )
        fetchPublicRecordState(recordType: "CD_Expense") { expenseResult in
            self.fetchPublicRecordState(recordType: "CD_Booking") { bookingResult in
                self.applyPendingChangeReconciliation(expenseResult: expenseResult,
                                                      bookingResult: bookingResult,
                                                      completion: completion)
            }
        }
    }

    private func fetchPublicRecordState(recordType: String,
                                        completion: @escaping (Result<PublicCloudKitRecordState, Error>) -> Void) {
        let database = cloudKitContainer.publicCloudDatabase
        let lock = NSLock()
        var ids = Set<UUID>()
        var lastModifiedAtByID: [UUID: Date] = [:]
        var recordsByID: [UUID: CKRecord] = [:]
        var recordReadErrors: [Error] = []

        func addOperation(_ operation: CKQueryOperation) {
            operation.desiredKeys = [
                "CD_id",
                "CD_lastModifiedAt",
                "CD_createdAt",
                "CD_createdBy",
                "CD_lastModifiedBy",
                "CD_project",
                "CD_category",
                "CD_notes",
                "CD_reimbursementAmount",
                "CD_expenseDate",
                "CD_date",
                "CD_isReimbursed",
                "CD_propertyName"
            ]
            operation.resultsLimit = CKQueryOperation.maximumResults

            operation.recordMatchedBlock = { _, result in
                lock.lock()
                defer { lock.unlock() }

                switch result {
                case .success(let record):
                    guard let uuid = Self.uuidValue(from: record["CD_id"]) else { return }
                    ids.insert(uuid)
                    recordsByID[uuid] = record
                    if let lastModifiedAt = record["CD_lastModifiedAt"] as? Date {
                        lastModifiedAtByID[uuid] = lastModifiedAt
                    }
                case .failure(let error):
                    recordReadErrors.append(error)
                }
            }

            operation.queryResultBlock = { result in
                lock.lock()
                let errors = recordReadErrors
                lock.unlock()

                if !errors.isEmpty {
                    completion(.failure(NSError(
                        domain: "ArmadilloAssistant.PublicCloudKitReconcile",
                        code: 1001,
                        userInfo: [NSLocalizedDescriptionKey: "\(recordType) query had record read errors: \(errors)"]
                    )))
                    return
                }

                switch result {
                case .success(let cursor):
                    if let cursor {
                        addOperation(CKQueryOperation(cursor: cursor))
                    } else {
                        lock.lock()
                        let state = PublicCloudKitRecordState(
                            ids: ids,
                            lastModifiedAtByID: lastModifiedAtByID,
                            recordsByID: recordsByID
                        )
                        lock.unlock()
                        completion(.success(state))
                    }
                case .failure(let error):
                    completion(.failure(error))
                }
            }

            database.add(operation)
        }

        let query = CKQuery(recordType: recordType, predicate: NSPredicate(value: true))
        addOperation(CKQueryOperation(query: query))
    }

    private static func uuidValue(from value: CKRecordValue?) -> UUID? {
        if let uuid = value as? UUID {
            return uuid
        }

        if let stringValue = value as? String {
            return UUID(uuidString: stringValue)
        }

        return nil
    }

    private func applyPendingChangeReconciliation(expenseResult: Result<PublicCloudKitRecordState, Error>,
                                                  bookingResult: Result<PublicCloudKitRecordState, Error>,
                                                  completion: (() -> Void)?) {
        let completionGroup = DispatchGroup()

        switch expenseResult {
        case .success(let expenseState):
            reconcilePendingLedgerEntries(entityName: "Expense", publicState: expenseState)
            completionGroup.enter()
            reconcileLocalExpensesAgainstPublicState(publicState: expenseState) {
                completionGroup.leave()
            }
        case .failure(let error):
            Debug.log(
                "Expense reconciliation skipped due to CloudKit query error=\(error)",
                channel: .expenseReconcile,
                source: "Persistence"
            )
        }

        switch bookingResult {
        case .success(let bookingState):
            reconcilePendingLedgerEntries(entityName: "Booking", publicState: bookingState)
            Debug.log(
                "Public CD_Booking count=\(bookingState.ids.count); booking stale cleanup skipped by policy",
                channel: .bookingReconcile,
                source: "Persistence"
            )
        case .failure(let error):
            Debug.log(
                "Booking pending reconciliation skipped due to CloudKit query error=\(error)",
                channel: .bookingReconcile,
                source: "Persistence"
            )
        }

        completionGroup.notify(queue: .main) {
            Debug.log(
                "Completed pending public CloudKit reconciliation",
                channel: .sync,
                source: "Persistence"
            )
            completion?()
        }
    }

    private func reconcilePendingLedgerEntries(entityName: String, publicState: PublicCloudKitRecordState) {
        let pendingChanges = Self.pendingChangeLedger.unresolvedChanges(entityName: entityName)

        for change in pendingChanges {
            let publicRecordExists = publicState.ids.contains(change.entityID)

            switch change.operation {
            case .add:
                if publicRecordExists {
                    Debug.log(
                        "Pending add confirmed in public state entity=\(entityName) entityID=\(change.entityID) changeID=\(change.id)",
                        channel: .pendingLedger,
                        source: "Persistence"
                    )
                    Self.pendingChangeLedger.markApplied(id: change.id)
                }
            case .update:
                if let publicLastModifiedAt = publicState.lastModifiedAtByID[change.entityID],
                   publicLastModifiedAt >= change.timestamp {
                    Debug.log(
                        "Pending update confirmed in public state entity=\(entityName) entityID=\(change.entityID) changeID=\(change.id)",
                        channel: .pendingLedger,
                        source: "Persistence"
                    )
                    Self.pendingChangeLedger.markApplied(id: change.id)
                }
            case .delete:
                if !publicRecordExists {
                    Debug.log(
                        "Pending delete confirmed absent from public state entity=\(entityName) entityID=\(change.entityID) changeID=\(change.id)",
                        channel: .pendingLedger,
                        source: "Persistence"
                    )
                    Self.pendingChangeLedger.markApplied(id: change.id)
                    Self.pendingChangeLedger.markApplied(
                        entityName: entityName,
                        entityID: change.entityID,
                        operations: [.add, .update]
                    )
                }
            }
        }
    }

    private func reconcileLocalExpensesAgainstPublicState(publicState: PublicCloudKitRecordState,
                                                          completion: @escaping () -> Void) {
        let context = container.viewContext
        context.perform {
            defer { completion() }

            let request: NSFetchRequest<Expense> = Expense.fetchRequest()
            request.sortDescriptors = [
                NSSortDescriptor(key: "createdAt", ascending: true)
            ]

            do {
                let localExpenses = try context.fetch(request)
                let localExpenseIDs = Set(localExpenses.compactMap { $0.id })
                var removedCount = 0
                var createdCount = 0
                var protectedPendingCount = 0
                var missingIDCount = 0
                var updatedCount = 0

                for expense in localExpenses {
                    guard let localID = expense.id else {
                        missingIDCount += 1
                        continue
                    }

                    guard !publicState.ids.contains(localID) else { continue }

                    guard !Self.pendingChangeLedger.hasUnresolvedChange(entityName: "Expense", entityID: localID) else {
                        protectedPendingCount += 1
                        continue
                    }

                    context.delete(expense)
                    removedCount += 1
                }

                for expense in localExpenses {
                    guard let localID = expense.id,
                          publicState.ids.contains(localID),
                          let record = publicState.recordsByID[localID] else {
                        continue
                    }

                    guard !Self.pendingChangeLedger.hasUnresolvedChange(entityName: "Expense", entityID: localID) else {
                        protectedPendingCount += 1
                        continue
                    }

                    let beforeLastModifiedAt = expense.value(forKey: "lastModifiedAt") as? Date
                    let publicLastModifiedAt = Self.dateValue(from: record["CD_lastModifiedAt"])

                    if let publicLastModifiedAt,
                       let beforeLastModifiedAt,
                       publicLastModifiedAt <= beforeLastModifiedAt {
                        continue
                    }

                    updateLocalExpense(expense, from: record, context: context)
                    updatedCount += 1
                }

                for publicID in publicState.ids where !localExpenseIDs.contains(publicID) {
                    guard !Self.pendingChangeLedger.hasUnresolvedChange(entityName: "Expense", entityID: publicID) else {
                        protectedPendingCount += 1
                        continue
                    }

                    guard let record = publicState.recordsByID[publicID] else { continue }
                    createLocalExpense(from: record, id: publicID, context: context)
                    createdCount += 1
                }

                if (removedCount > 0 || createdCount > 0 || updatedCount > 0), context.hasChanges {
                    try context.save()
                }

                Debug.log(
                    "Public CD_Expense count=\(publicState.ids.count) local stale expenses removed=\(removedCount) local missing expenses created=\(createdCount) local expenses updated=\(updatedCount) pending-protected=\(protectedPendingCount) missing-local-id=\(missingIDCount)",
                    channel: .expenseReconcile,
                    source: "Persistence"
                )
            } catch {
                Debug.log(
                    "Expense reconciliation failed error=\(error)",
                    channel: .expenseReconcile,
                    source: "Persistence"
                )
            }
        }
    }

    private func updateLocalExpense(_ expense: Expense, from record: CKRecord, context: NSManagedObjectContext) {
        expense.project = Self.stringValue(from: record["CD_project"])
            ?? Self.stringValue(from: record["project"])
            ?? expense.project
        expense.category = Self.stringValue(from: record["CD_category"])
            ?? Self.stringValue(from: record["category"])
            ?? expense.category
        expense.notes = Self.stringValue(from: record["CD_notes"])
            ?? Self.stringValue(from: record["notes"])
            ?? expense.notes
        expense.reimbursementAmount = Self.doubleValue(from: record["CD_reimbursementAmount"])
            ?? Self.doubleValue(from: record["reimbursementAmount"])
            ?? expense.reimbursementAmount

        if let expenseDate = Self.dateValue(from: record["CD_expenseDate"]) ?? Self.dateValue(from: record["CD_date"]) {
            setIfAttributeExists("expenseDate", value: expenseDate, object: expense)
            setIfAttributeExists("date", value: expenseDate, object: expense)
        }

        if let isReimbursed = Self.boolValue(from: record["CD_isReimbursed"]) {
            setIfAttributeExists("isReimbursed", value: isReimbursed, object: expense)
        }

        if let propertyName = Self.stringValue(from: record["CD_propertyName"]) {
            setIfAttributeExists("propertyName", value: propertyName, object: expense)
        }

        if let createdAt = Self.dateValue(from: record["CD_createdAt"]) {
            setIfAttributeExists("createdAt", value: createdAt, object: expense)
        }

        if let lastModifiedAt = Self.dateValue(from: record["CD_lastModifiedAt"]) {
            setIfAttributeExists("lastModifiedAt", value: lastModifiedAt, object: expense)
        }

        if let createdBy = Self.stringValue(from: record["CD_createdBy"]) {
            setIfAttributeExists("createdBy", value: createdBy, object: expense)
        }

        if let lastModifiedBy = Self.stringValue(from: record["CD_lastModifiedBy"]) {
            setIfAttributeExists("lastModifiedBy", value: lastModifiedBy, object: expense)
        }

        attachWorkspaceReferences(to: expense, context: context)
        attachExpenseReferenceData(to: expense, context: context)
    }

    private func createLocalExpense(from record: CKRecord, id: UUID, context: NSManagedObjectContext) {
        let expense = Expense(context: context)
        let now = Date()

        expense.id = id
        expense.project = Self.stringValue(from: record["CD_project"])
            ?? Self.stringValue(from: record["project"])
            ?? ""
        expense.category = Self.stringValue(from: record["CD_category"])
            ?? Self.stringValue(from: record["category"])
            ?? ""
        expense.notes = Self.stringValue(from: record["CD_notes"])
            ?? Self.stringValue(from: record["notes"])
            ?? ""
        expense.reimbursementAmount = Self.doubleValue(from: record["CD_reimbursementAmount"])
            ?? Self.doubleValue(from: record["reimbursementAmount"])
            ?? 0

        setIfAttributeExists("expenseDate", value: Self.dateValue(from: record["CD_expenseDate"]) ?? Self.dateValue(from: record["CD_date"]) ?? now, object: expense)
        setIfAttributeExists("date", value: Self.dateValue(from: record["CD_date"]) ?? Self.dateValue(from: record["CD_expenseDate"]) ?? now, object: expense)
        setIfAttributeExists("isReimbursed", value: Self.boolValue(from: record["CD_isReimbursed"]) ?? false, object: expense)
        setIfAttributeExists("propertyName", value: Self.stringValue(from: record["CD_propertyName"]) ?? "", object: expense)

        setIfAttributeExists("createdAt", value: Self.dateValue(from: record["CD_createdAt"]) ?? now, object: expense)
        setIfAttributeExists("lastModifiedAt", value: Self.dateValue(from: record["CD_lastModifiedAt"]) ?? now, object: expense)
        setIfAttributeExists("createdBy", value: Self.stringValue(from: record["CD_createdBy"]) ?? "Public CloudKit", object: expense)
        setIfAttributeExists("lastModifiedBy", value: Self.stringValue(from: record["CD_lastModifiedBy"]) ?? "Public CloudKit", object: expense)

        attachWorkspaceReferences(to: expense, context: context)
        attachExpenseReferenceData(to: expense, context: context)
    }

    private func attachWorkspaceReferences(to expense: Expense, context: NSManagedObjectContext) {
        do {
            if let workspace = try fetchCanonicalWorkspace(context: context) {
                expense.setValue(workspace, forKey: "workspaceRef")
            }
        } catch {
            Debug.log(
                "Failed to attach imported Expense to workspace error=\(error)",
                channel: .expenseReconcile,
                source: "Persistence"
            )
        }
    }

    private func attachExpenseReferenceData(to expense: Expense, context: NSManagedObjectContext) {
        do {
            let projectKey = normalizedLookupKey(expense.project)
            if !projectKey.isEmpty {
                let projectRequest: NSFetchRequest<ExpenseProject> = ExpenseProject.fetchRequest()
                projectRequest.fetchLimit = 1
                projectRequest.predicate = NSPredicate(format: "name =[c] %@", expense.project ?? "")
                if let project = try context.fetch(projectRequest).first {
                    expense.projectRef = project
                }
            }

            let categoryKey = normalizedLookupKey(expense.category)
            if !categoryKey.isEmpty {
                let categoryRequest: NSFetchRequest<ExpenseCategory> = ExpenseCategory.fetchRequest()
                categoryRequest.fetchLimit = 1
                categoryRequest.predicate = NSPredicate(format: "name =[c] %@", expense.category ?? "")
                if let category = try context.fetch(categoryRequest).first {
                    expense.categoryRef = category
                }
            }
        } catch {
            Debug.log(
                "Failed to attach imported Expense reference data error=\(error)",
                channel: .expenseReconcile,
                source: "Persistence"
            )
        }
    }

    private static func stringValue(from value: CKRecordValue?) -> String? {
        if let stringValue = value as? String {
            return stringValue
        }

        if let numberValue = value as? NSNumber {
            return numberValue.stringValue
        }

        return nil
    }

    private static func doubleValue(from value: CKRecordValue?) -> Double? {
        if let doubleValue = value as? Double {
            return doubleValue
        }

        if let numberValue = value as? NSNumber {
            return numberValue.doubleValue
        }

        if let stringValue = value as? String {
            return Double(stringValue)
        }

        return nil
    }

    private static func boolValue(from value: CKRecordValue?) -> Bool? {
        if let boolValue = value as? Bool {
            return boolValue
        }

        if let numberValue = value as? NSNumber {
            return numberValue.boolValue
        }

        if let stringValue = value as? String {
            return Bool(stringValue)
        }

        return nil
    }

    private static func dateValue(from value: CKRecordValue?) -> Date? {
        if let dateValue = value as? Date {
            return dateValue
        }

        return nil
    }

    private func setIfAttributeExists(_ key: String, value: Any, object: NSManagedObject) {
        guard object.entity.attributesByName[key] != nil else { return }
        object.setValue(value, forKey: key)
    }

    init(inMemory: Bool = false) {
        container = NSPersistentCloudKitContainer(name: "ArmadilloAssistant")
        // Section 1: CloudKit store configuration
        // The app uses a single public CloudKit-backed persistent store.

        let persistentContainer = container

        if inMemory {
            let previewStoreDescription = container.persistentStoreDescriptions.first
            previewStoreDescription?.url = URL(fileURLWithPath: "/dev/null")
            previewStoreDescription?.cloudKitContainerOptions = nil
            previewStoreDescription?.setOption(true as NSNumber,
                                               forKey: NSPersistentHistoryTrackingKey)
            previewStoreDescription?.setOption(true as NSNumber,
                                               forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
        } else {
            let publicStoreDescription = container.persistentStoreDescriptions.first ?? NSPersistentStoreDescription()

            let defaultDirectory = NSPersistentContainer.defaultDirectoryURL()
            publicStoreDescription.url = defaultDirectory.appendingPathComponent("ArmadilloAssistant-Public.sqlite")

            let publicOptions = NSPersistentCloudKitContainerOptions(containerIdentifier: Self.cloudKitContainerIdentifier)
            publicOptions.databaseScope = .public
            publicStoreDescription.cloudKitContainerOptions = publicOptions
            publicStoreDescription.setOption(true as NSNumber,
                                              forKey: NSPersistentHistoryTrackingKey)
            publicStoreDescription.setOption(true as NSNumber,
                                              forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)

            container.persistentStoreDescriptions = [publicStoreDescription]
        }
        container.loadPersistentStores(completionHandler: { (storeDescription, error) in
            if let error = error as NSError? {
                fatalError("Unresolved error \(error), \(error.userInfo)")
            }

            print("[Persistence] Loaded persistent store: \(storeDescription.url?.lastPathComponent ?? "unknown")")
            print("[Persistence] CloudKit database scope: public")

            #if DEBUG
            if !inMemory && Self.shouldInitializePublicCloudKitSchema {
                do {
                    try persistentContainer.initializeCloudKitSchema(options: [])
                    print("[Persistence] Public CloudKit schema initialization completed")
                } catch {
                    print("[Persistence] Public CloudKit schema initialization failed: \(error)")
                }
            }
            #endif
        })
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        configureCloudKitEventLogging()
        seedReferenceDataIfNeeded(context: container.viewContext)
    }

    func fetchOrCreateWorkspace(context: NSManagedObjectContext) throws -> AppWorkspace {
        let request: NSFetchRequest<AppWorkspace> = AppWorkspace.fetchRequest()
        request.sortDescriptors = [
            NSSortDescriptor(key: "createdAt", ascending: true)
        ]
        request.fetchLimit = 2

        let workspaces = try context.fetch(request)

        if let workspace = workspaces.first {
            return workspace
        }

        let now = Date()
        let workspace = AppWorkspace(context: context)
        workspace.id = UUID()
        workspace.name = "12 Armadillos Workspace"
        workspace.createdAt = now
        workspace.createdBy = "System"
        workspace.lastModifiedAt = now
        workspace.lastModifiedBy = "System"

        try context.save()
        return workspace
    }

    private func seedReferenceDataIfNeeded(context: NSManagedObjectContext) {
        seedRentalPropertiesIfNeeded(context: context)
        cleanupDuplicateRentalPropertiesIfNeeded(context: context)
        seedWorkspaceIfNeeded(context: context)
        cleanupDuplicateWorkspacesIfNeeded(context: context)
        // attachRentalPropertiesToWorkspaceIfNeeded(context: context)
        backfillBookingPropertyRefsIfNeeded(context: context)
        cleanupDuplicateExpenseReferenceDataIfNeeded(context: context)
        attachExpenseGraphToWorkspaceIfNeeded(context: context)

        let projectFetchRequest: NSFetchRequest<ExpenseProject> = ExpenseProject.fetchRequest()
        projectFetchRequest.fetchLimit = 1

        do {
            let existingProjectCount = try context.count(for: projectFetchRequest)
            guard existingProjectCount == 0 else { return }

            let now = Date()
            let seedUser = "System"

            let defaultProjects = [
                "General - 12 Armadillos",
                "General - Barndominium",
                "General - Main Street",
                "General - Washington"
            ]

            let defaultCategories = [
                "Supplies",
                "Transportation",
                "Meals & Expenses",
                "Marketing",
                "Vendor Payments"
            ]

            for (index, name) in defaultProjects.enumerated() {
                let project = ExpenseProject(context: context)
                project.id = UUID()
                project.name = name
                project.isActive = true
                project.sortOrder = Int32(index)
                project.createdAt = now
                project.createdBy = seedUser
                project.lastModifiedAt = now
                project.lastModifiedBy = seedUser
            }

            for (index, name) in defaultCategories.enumerated() {
                let category = ExpenseCategory(context: context)
                category.id = UUID()
                category.name = name
                category.isActive = true
                category.sortOrder = Int32(index)
                category.createdAt = now
                category.createdBy = seedUser
                category.lastModifiedAt = now
                category.lastModifiedBy = seedUser
            }

            if context.hasChanges {
                try context.save()
            }
        } catch {
            let nsError = error as NSError
            fatalError("Failed to seed expense reference data: \(nsError), \(nsError.userInfo)")
        }
    }

    
    // Section 3A: RentalProperty duplicate cleanup
    // Keeps one canonical RentalProperty per normalized property name and deletes duplicate
    // property records created during CloudKit/TestFlight reset testing. This assumes booking
    // records have already been deleted or are safe to detach before reservation re-import.
    private func cleanupDuplicateRentalPropertiesIfNeeded(context: NSManagedObjectContext) {
        let request: NSFetchRequest<RentalProperty> = RentalProperty.fetchRequest()
        request.sortDescriptors = [
            NSSortDescriptor(keyPath: \RentalProperty.sortOrder, ascending: true),
            NSSortDescriptor(keyPath: \RentalProperty.createdAt, ascending: true),
            NSSortDescriptor(keyPath: \RentalProperty.name, ascending: true)
        ]

        do {
            let properties = try context.fetch(request)
            guard properties.count > 3 else { return }

            var canonicalByKey: [String: RentalProperty] = [:]
            var duplicateProperties: [RentalProperty] = []

            for property in properties {
                let key = canonicalPropertyKey(for: property)

                guard !key.isEmpty else {
                    duplicateProperties.append(property)
                    continue
                }

                if canonicalByKey[key] == nil {
                    canonicalByKey[key] = property
                } else {
                    duplicateProperties.append(property)
                }
            }

            guard !duplicateProperties.isEmpty else { return }

            for duplicateProperty in duplicateProperties {
                context.delete(duplicateProperty)
            }

            if context.hasChanges {
                try context.save()
            }

            print("[Persistence] Duplicate RentalProperty cleanup removed: \(duplicateProperties.count)")
            print("[Persistence] Canonical RentalProperty count after cleanup: \(canonicalByKey.count)")
        } catch {
            let nsError = error as NSError
            fatalError("Failed to clean up duplicate RentalProperty records: \(nsError), \(nsError.userInfo)")
        }
    }

    private func canonicalPropertyKey(for property: RentalProperty) -> String {
        let shortName = normalizedLookupKey(property.shortName)
        let fullName = normalizedLookupKey(property.name)
        let rawKey = shortName.isEmpty ? fullName : shortName

        switch rawKey {
        case "main street", "main", "alamo", "main/alamo", "main and alamo":
            return "main"
        case "barndominium", "barndo":
            return "barndo"
        case "washington", "washington house":
            return "washington"
        default:
            return rawKey
        }
    }

    private func seedWorkspaceIfNeeded(context: NSManagedObjectContext) {
        let workspaceFetchRequest = NSFetchRequest<NSManagedObject>(entityName: "AppWorkspace")
        workspaceFetchRequest.sortDescriptors = [
            NSSortDescriptor(key: "createdAt", ascending: true),
            NSSortDescriptor(key: "name", ascending: true)
        ]

        do {
            let existingWorkspaces = try context.fetch(workspaceFetchRequest)

            if let existingWorkspace = existingWorkspaces.first {
                let workspaceName = existingWorkspace.value(forKey: "name") as? String ?? "Unnamed Workspace"
                print("[Persistence] AppWorkspace reused: \(workspaceName) (\(existingWorkspaces.count) found)")
                return
            }

            let now = Date()
            let workspace = NSEntityDescription.insertNewObject(forEntityName: "AppWorkspace", into: context)
            workspace.setValue(UUID(), forKey: "id")
            workspace.setValue("12 Armadillos Workspace", forKey: "name")
            workspace.setValue(now, forKey: "createdAt")
            workspace.setValue("System", forKey: "createdBy")
            workspace.setValue(now, forKey: "lastModifiedAt")
            workspace.setValue("System", forKey: "lastModifiedBy")

            try context.save()
            print("[Persistence] AppWorkspace created: \(workspace.value(forKey: "name") as? String ?? "12 Armadillos Workspace")")
        } catch {
            let nsError = error as NSError
            fatalError("Failed to seed AppWorkspace data: \(nsError), \(nsError.userInfo)")
        }
    }

    // Section 3B: Workspace duplicate cleanup
    // Keeps the oldest AppWorkspace as the canonical public workspace and removes duplicate
    // private AppWorkspace records created during early sharing experiments.
    private func cleanupDuplicateWorkspacesIfNeeded(context: NSManagedObjectContext) {
        let request = NSFetchRequest<NSManagedObject>(entityName: "AppWorkspace")
        request.sortDescriptors = [
            NSSortDescriptor(key: "createdAt", ascending: true),
            NSSortDescriptor(key: "name", ascending: true)
        ]

        do {
            let workspaces = try context.fetch(request)
            guard workspaces.count > 1,
                  let canonicalWorkspace = workspaces.first else {
                return
            }

            let duplicateWorkspaces = Array(workspaces.dropFirst())

            for duplicateWorkspace in duplicateWorkspaces {
                let expenseRequest: NSFetchRequest<Expense> = Expense.fetchRequest()
                expenseRequest.predicate = NSPredicate(format: "workspaceRef == %@", duplicateWorkspace)
                let duplicateExpenses = try context.fetch(expenseRequest)
                for expense in duplicateExpenses {
                    expense.setValue(canonicalWorkspace, forKey: "workspaceRef")
                }

                let categoryRequest: NSFetchRequest<ExpenseCategory> = ExpenseCategory.fetchRequest()
                categoryRequest.predicate = NSPredicate(format: "workspaceRef == %@", duplicateWorkspace)
                let duplicateCategories = try context.fetch(categoryRequest)
                for category in duplicateCategories {
                    category.setValue(canonicalWorkspace, forKey: "workspaceRef")
                }

                let projectRequest: NSFetchRequest<ExpenseProject> = ExpenseProject.fetchRequest()
                projectRequest.predicate = NSPredicate(format: "workspaceRef == %@", duplicateWorkspace)
                let duplicateProjects = try context.fetch(projectRequest)
                for project in duplicateProjects {
                    project.setValue(canonicalWorkspace, forKey: "workspaceRef")
                }

                let propertyRequest: NSFetchRequest<RentalProperty> = RentalProperty.fetchRequest()
                propertyRequest.predicate = NSPredicate(format: "workspaceRef == %@", duplicateWorkspace)
                let duplicateProperties = try context.fetch(propertyRequest)
                for property in duplicateProperties {
                    property.setValue(canonicalWorkspace, forKey: "workspaceRef")
                }

                context.delete(duplicateWorkspace)
            }

            if context.hasChanges {
                try context.save()
            }

            print("[Persistence] Duplicate AppWorkspace cleanup removed: \(duplicateWorkspaces.count)")
        } catch {
            let nsError = error as NSError
            fatalError("Failed to clean up duplicate AppWorkspace records: \(nsError), \(nsError.userInfo)")
        }
    }

    // Section 3D: Expense reference duplicate cleanup
    // Public CloudKit can briefly import local seed records and public records before merges settle.
    // These helpers keep one canonical active ExpenseProject and ExpenseCategory per normalized name,
    // reassign dependent Expense records, attach the canonical record to the canonical workspace,
    // and remove duplicate reference records before the graph is exported again.
    private func cleanupDuplicateExpenseReferenceDataIfNeeded(context: NSManagedObjectContext) {
        cleanupDuplicateExpenseProjectsIfNeeded(context: context)
        cleanupDuplicateExpenseCategoriesIfNeeded(context: context)
    }

    private func cleanupDuplicateExpenseProjectsIfNeeded(context: NSManagedObjectContext) {
        let request: NSFetchRequest<ExpenseProject> = ExpenseProject.fetchRequest()
        request.sortDescriptors = [
            NSSortDescriptor(key: "sortOrder", ascending: true),
            NSSortDescriptor(key: "createdAt", ascending: true),
            NSSortDescriptor(key: "name", ascending: true)
        ]

        do {
            let projects = try context.fetch(request)
            guard projects.count > 1 else { return }

            let workspace = try fetchCanonicalWorkspace(context: context)
            var canonicalByName: [String: ExpenseProject] = [:]
            var removedCount = 0

            for project in projects {
                let key = normalizedLookupKey(project.name)
                guard !key.isEmpty else { continue }

                if let canonical = canonicalByName[key] {
                    reassignExpenses(from: project, to: canonical, context: context)

                    if canonical.value(forKey: "workspaceRef") == nil, let workspace {
                        canonical.setValue(workspace, forKey: "workspaceRef")
                    }

                    if project.isActive {
                        canonical.isActive = true
                    }

                    context.delete(project)
                    removedCount += 1
                } else {
                    if project.value(forKey: "workspaceRef") == nil, let workspace {
                        project.setValue(workspace, forKey: "workspaceRef")
                    }
                    canonicalByName[key] = project
                }
            }

            if removedCount > 0, context.hasChanges {
                try context.save()
                print("[Persistence] Duplicate ExpenseProject cleanup removed: \(removedCount)")
            }
        } catch {
            let nsError = error as NSError
            fatalError("Failed to clean up duplicate ExpenseProject records: \(nsError), \(nsError.userInfo)")
        }
    }

    private func cleanupDuplicateExpenseCategoriesIfNeeded(context: NSManagedObjectContext) {
        let request: NSFetchRequest<ExpenseCategory> = ExpenseCategory.fetchRequest()
        request.sortDescriptors = [
            NSSortDescriptor(key: "sortOrder", ascending: true),
            NSSortDescriptor(key: "createdAt", ascending: true),
            NSSortDescriptor(key: "name", ascending: true)
        ]

        do {
            let categories = try context.fetch(request)
            guard categories.count > 1 else { return }

            let workspace = try fetchCanonicalWorkspace(context: context)
            var canonicalByName: [String: ExpenseCategory] = [:]
            var removedCount = 0

            for category in categories {
                let key = normalizedLookupKey(category.name)
                guard !key.isEmpty else { continue }

                if let canonical = canonicalByName[key] {
                    reassignExpenses(from: category, to: canonical, context: context)

                    if canonical.value(forKey: "workspaceRef") == nil, let workspace {
                        canonical.setValue(workspace, forKey: "workspaceRef")
                    }

                    if category.isActive {
                        canonical.isActive = true
                    }

                    context.delete(category)
                    removedCount += 1
                } else {
                    if category.value(forKey: "workspaceRef") == nil, let workspace {
                        category.setValue(workspace, forKey: "workspaceRef")
                    }
                    canonicalByName[key] = category
                }
            }

            if removedCount > 0, context.hasChanges {
                try context.save()
                print("[Persistence] Duplicate ExpenseCategory cleanup removed: \(removedCount)")
            }
        } catch {
            let nsError = error as NSError
            fatalError("Failed to clean up duplicate ExpenseCategory records: \(nsError), \(nsError.userInfo)")
        }
    }

    private func reassignExpenses(from duplicateProject: ExpenseProject,
                                  to canonicalProject: ExpenseProject,
                                  context: NSManagedObjectContext) {
        let request: NSFetchRequest<Expense> = Expense.fetchRequest()
        request.predicate = NSPredicate(format: "projectRef == %@", duplicateProject)

        do {
            let expenses = try context.fetch(request)
            for expense in expenses {
                expense.projectRef = canonicalProject
                if normalizedLookupKey(expense.project).isEmpty {
                    expense.project = canonicalProject.name ?? ""
                }
            }
        } catch {
            print("[Persistence] Expense project reassignment failed: \(error)")
        }
    }

    private func reassignExpenses(from duplicateCategory: ExpenseCategory,
                                  to canonicalCategory: ExpenseCategory,
                                  context: NSManagedObjectContext) {
        let request: NSFetchRequest<Expense> = Expense.fetchRequest()
        request.predicate = NSPredicate(format: "categoryRef == %@", duplicateCategory)

        do {
            let expenses = try context.fetch(request)
            for expense in expenses {
                expense.categoryRef = canonicalCategory
                if normalizedLookupKey(expense.category).isEmpty {
                    expense.category = canonicalCategory.name ?? ""
                }
            }
        } catch {
            print("[Persistence] Expense category reassignment failed: \(error)")
        }
    }

    // Section 4: Expense workspace attachment
    // Attaches low-risk expense-related objects to the AppWorkspace public workspace graph.
    // This intentionally does not attach RentalProperty or Booking records yet.
    // Public CloudKit conversion keeps this staged behavior unchanged.
    private func attachExpenseGraphToWorkspaceIfNeeded(context: NSManagedObjectContext) {
        do {
            guard let workspace = try fetchCanonicalWorkspace(context: context) else {
                print("[Persistence] Expense workspace attachment skipped: no AppWorkspace found")
                return
            }

            let expenseFetchRequest: NSFetchRequest<Expense> = Expense.fetchRequest()
            expenseFetchRequest.predicate = NSPredicate(format: "workspaceRef == nil")
            let unattachedExpenses = try context.fetch(expenseFetchRequest)

            for expense in unattachedExpenses {
                expense.setValue(workspace, forKey: "workspaceRef")
            }

            let categoryFetchRequest: NSFetchRequest<ExpenseCategory> = ExpenseCategory.fetchRequest()
            categoryFetchRequest.predicate = NSPredicate(format: "workspaceRef == nil")
            let unattachedCategories = try context.fetch(categoryFetchRequest)

            for category in unattachedCategories {
                category.setValue(workspace, forKey: "workspaceRef")
            }

            let projectFetchRequest: NSFetchRequest<ExpenseProject> = ExpenseProject.fetchRequest()
            projectFetchRequest.predicate = NSPredicate(format: "workspaceRef == nil")
            let unattachedProjects = try context.fetch(projectFetchRequest)

            for project in unattachedProjects {
                project.setValue(workspace, forKey: "workspaceRef")
            }

            if context.hasChanges {
                try context.save()
            }

            print("[Persistence] Expenses attached to AppWorkspace: \(unattachedExpenses.count)")
            print("[Persistence] ExpenseCategories attached to AppWorkspace: \(unattachedCategories.count)")
            print("[Persistence] ExpenseProjects attached to AppWorkspace: \(unattachedProjects.count)")
        } catch {
            let nsError = error as NSError
            fatalError("Failed to attach expense graph to AppWorkspace: \(nsError), \(nsError.userInfo)")
        }
    }

    private func attachRentalPropertiesToWorkspaceIfNeeded(context: NSManagedObjectContext) {
        do {
            guard let workspace = try fetchCanonicalWorkspace(context: context) else {
                print("[Persistence] RentalProperty workspace attachment skipped: no AppWorkspace found")
                return
            }

            let propertyFetchRequest: NSFetchRequest<RentalProperty> = RentalProperty.fetchRequest()
            propertyFetchRequest.predicate = NSPredicate(format: "workspaceRef == nil")

            let unattachedProperties = try context.fetch(propertyFetchRequest)

            for property in unattachedProperties {
                property.setValue(workspace, forKey: "workspaceRef")
            }

            if context.hasChanges {
                try context.save()
            }

            print("[Persistence] RentalProperties attached to AppWorkspace: \(unattachedProperties.count)")
        } catch {
            let nsError = error as NSError
            fatalError("Failed to attach RentalProperty records to AppWorkspace: \(nsError), \(nsError.userInfo)")
        }
    }

    private func backfillBookingPropertyRefsIfNeeded(context: NSManagedObjectContext) {
        do {
            let propertyFetchRequest: NSFetchRequest<RentalProperty> = RentalProperty.fetchRequest()
            let properties = try context.fetch(propertyFetchRequest)
            let propertyLookup = rentalPropertyLookup(from: properties)

            let bookingFetchRequest: NSFetchRequest<Booking> = Booking.fetchRequest()
            bookingFetchRequest.predicate = NSPredicate(format: "propertyRef == nil")

            let bookingsMissingPropertyRef = try context.fetch(bookingFetchRequest)
            var backfilledCount = 0

            for booking in bookingsMissingPropertyRef {
                guard let propertyName = booking.propertyName else { continue }
                let lookupKey = normalizedLookupKey(propertyName)
                guard !lookupKey.isEmpty,
                      let property = propertyLookup[lookupKey] else {
                    continue
                }

                booking.propertyRef = property
                backfilledCount += 1
            }

            if context.hasChanges {
                try context.save()
            }

            print("[Persistence] Booking propertyRef records backfilled: \(backfilledCount)")
        } catch {
            let nsError = error as NSError
            fatalError("Failed to backfill Booking propertyRef values: \(nsError), \(nsError.userInfo)")
        }
    }

    private func fetchCanonicalWorkspace(context: NSManagedObjectContext) throws -> NSManagedObject? {
        let workspaceFetchRequest = NSFetchRequest<NSManagedObject>(entityName: "AppWorkspace")
        workspaceFetchRequest.fetchLimit = 1
        workspaceFetchRequest.sortDescriptors = [
            NSSortDescriptor(key: "createdAt", ascending: true),
            NSSortDescriptor(key: "name", ascending: true)
        ]

        let workspaces = try context.fetch(workspaceFetchRequest)

        if workspaces.first != nil {
            print("[Persistence] Canonical workspace selected from oldest fallback workspace")
        }

        return workspaces.first
    }

    private func rentalPropertyLookup(from properties: [RentalProperty]) -> [String: RentalProperty] {
        var lookup: [String: RentalProperty] = [:]

        for property in properties {
            let names = [
                property.name,
                property.shortName
            ]

            for name in names {
                let lookupKey = normalizedLookupKey(name)
                guard !lookupKey.isEmpty, lookup[lookupKey] == nil else { continue }
                lookup[lookupKey] = property
            }
        }

        return lookup
    }

    private func normalizedLookupKey(_ value: String?) -> String {
        (value ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .localizedLowercase
    }

    private func seedRentalPropertiesIfNeeded(context: NSManagedObjectContext) {
        let propertyFetchRequest: NSFetchRequest<RentalProperty> = RentalProperty.fetchRequest()
        propertyFetchRequest.fetchLimit = 1

        do {
            let existingPropertyCount = try context.count(for: propertyFetchRequest)
            guard existingPropertyCount == 0 else { return }

            let now = Date()
            let seedUser = "System"

            let defaultProperties: [(name: String, shortName: String, sortOrder: Int32)] = [
                ("Barndo", "Barndo", 0),
                ("Main", "Main", 1),
                ("Washington", "Washington", 2)
            ]

            for propertySeed in defaultProperties {
                let property = RentalProperty(context: context)
                property.id = UUID()
                property.name = propertySeed.name
                property.shortName = propertySeed.shortName
                property.isActive = true
                property.sortOrder = propertySeed.sortOrder
                property.streetAddress = ""
                property.city = ""
                property.state = ""
                property.postalCode = ""
                property.propertyDescription = ""
                property.bedroomCount = 0
                property.bathroomCount = 0
                property.colorHex = "#B31B1B"
                property.cleaningFeeDefault = 0
                property.cleaningPaymentDefault = 0
                property.taxRateDefault = 0
                property.createdAt = now
                property.createdBy = seedUser
                property.lastModifiedAt = now
                property.lastModifiedBy = seedUser
            }

            if context.hasChanges {
                try context.save()
            }
        } catch {
            let nsError = error as NSError
            fatalError("Failed to seed rental property data: \(nsError), \(nsError.userInfo)")
        }
    }
}
