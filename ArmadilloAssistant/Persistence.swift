//  Persistence.swift
//  ArmadilloAssistant
//
//  Created by David Wilcox on 2/26/26.
//

import CloudKit
import CoreData

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
                print("[Persistence][CloudKitEvent] Received event notification without event payload")
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

            print("[Persistence][CloudKitEvent] type=\(typeDescription) status=\(successDescription) start=\(event.startDate) end=\(String(describing: event.endDate))\(errorDescription)")
        }
    }

    // Section 0C: Public CloudKit reconciliation
    // Public CloudKit mirroring may leave a stale local Expense if another owner deletes the public record.
    // This method queries the Public Database for current CD_Expense CD_id values and removes local
    // Expense records whose UUID no longer exists in CloudKit. It only deletes after a successful
    // CloudKit query so temporary network/auth failures do not remove local data.
    func reconcileLocalExpensesWithPublicCloudKit(completion: (() -> Void)? = nil) {
        let database = cloudKitContainer.publicCloudDatabase
        let query = CKQuery(recordType: "CD_Expense", predicate: NSPredicate(value: true))
        let operation = CKQueryOperation(query: query)
        operation.desiredKeys = ["CD_id"]
        operation.resultsLimit = CKQueryOperation.maximumResults

        var publicExpenseIDs = Set<String>()
        var recordReadErrors: [Error] = []

        operation.recordMatchedBlock = { _, result in
            switch result {
            case .success(let record):
                if let uuid = record["CD_id"] as? UUID {
                    publicExpenseIDs.insert(uuid.uuidString.uppercased())
                } else if let stringValue = record["CD_id"] as? String,
                          let uuid = UUID(uuidString: stringValue) {
                    publicExpenseIDs.insert(uuid.uuidString.uppercased())
                } else if let stringValue = record["CD_id"] as? String {
                    publicExpenseIDs.insert(stringValue.uppercased())
                }
            case .failure(let error):
                recordReadErrors.append(error)
            }
        }

        operation.queryResultBlock = { result in
            if !recordReadErrors.isEmpty {
                print("[Persistence][PublicReconcile] Expense reconciliation skipped due to record read errors: \(recordReadErrors)")
                DispatchQueue.main.async {
                    completion?()
                }
                return
            }

            switch result {
            case .success(let cursor):
                if cursor != nil {
                    print("[Persistence][PublicReconcile] Expense reconciliation skipped because query pagination is not yet handled")
                    DispatchQueue.main.async {
                        completion?()
                    }
                    return
                }

                let context = container.viewContext
                context.perform {
                    let request: NSFetchRequest<Expense> = Expense.fetchRequest()
                    request.sortDescriptors = [
                        NSSortDescriptor(key: "createdAt", ascending: true)
                    ]

                    do {
                        let localExpenses = try context.fetch(request)
                        var removedCount = 0

                        for expense in localExpenses {
                            guard let localID = expense.id?.uuidString.uppercased() else { continue }
                            guard !publicExpenseIDs.contains(localID) else { continue }

                            context.delete(expense)
                            removedCount += 1
                        }

                        if removedCount > 0, context.hasChanges {
                            try context.save()
                        }

                        print("[Persistence][PublicReconcile] Public CD_Expense count=\(publicExpenseIDs.count) local stale expenses removed=\(removedCount)")
                    } catch {
                        print("[Persistence][PublicReconcile] Expense reconciliation failed: \(error)")
                    }

                    DispatchQueue.main.async {
                        completion?()
                    }
                }
            case .failure(let error):
                print("[Persistence][PublicReconcile] Expense reconciliation skipped due to CloudKit query error: \(error)")
                DispatchQueue.main.async {
                    completion?()
                }
            }
        }

        database.add(operation)
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
