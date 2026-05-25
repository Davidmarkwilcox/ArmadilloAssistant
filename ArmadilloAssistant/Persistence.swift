//  Persistence.swift
//  ArmadilloAssistant
//
//  Created by David Wilcox on 2/26/26.
//

import CloudKit
import CoreData

struct PersistenceController {
    static let shared = PersistenceController()

    @MainActor
    static let preview: PersistenceController = {
        let result = PersistenceController(inMemory: true)
        let viewContext = result.container.viewContext
        viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        return result
    }()

    let container: NSPersistentCloudKitContainer

    var cloudKitContainer: CKContainer {
        CKContainer(identifier: "iCloud.com.DavidMWilcox.ArmadilloAssistant")
    }

    init(inMemory: Bool = false) {
        container = NSPersistentCloudKitContainer(name: "ArmadilloAssistant")
        // Section 1: CloudKit store configuration
        // The app uses two persistent stores so Core Data can participate in both
        // the owner's private CloudKit database and accepted CloudKit shared database records.
        // Private store: objects created by the owner, including RentalProperty root share objects.
        // Shared store: objects accepted through CloudKit sharing invitations.
        let cloudKitContainerIdentifier = "iCloud.com.DavidMWilcox.ArmadilloAssistant"

        if inMemory {
            let previewStoreDescription = container.persistentStoreDescriptions.first
            previewStoreDescription?.url = URL(fileURLWithPath: "/dev/null")
            previewStoreDescription?.cloudKitContainerOptions = nil
            previewStoreDescription?.setOption(true as NSNumber,
                                               forKey: NSPersistentHistoryTrackingKey)
            previewStoreDescription?.setOption(true as NSNumber,
                                               forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
        } else {
            let privateStoreDescription = container.persistentStoreDescriptions.first ?? NSPersistentStoreDescription()

            if privateStoreDescription.url == nil {
                let defaultDirectory = NSPersistentContainer.defaultDirectoryURL()
                privateStoreDescription.url = defaultDirectory.appendingPathComponent("ArmadilloAssistant.sqlite")
            }

            // TEMPORARY CLOUDKIT ROLLBACK STATE
            // - Private mirroring remains disabled.
            // - Shared store loading remains disabled.
            // - The app is intentionally running in local-only stabilization mode.
            // Rebuild and verify the CloudKit baseline before re-enabling either store path.
            let privateOptions = NSPersistentCloudKitContainerOptions(containerIdentifier: cloudKitContainerIdentifier)
            privateOptions.databaseScope = .private
            // Temporary rollback: disable private CloudKit mirroring while
            // rebuilding the CloudKit baseline from a clean state.
            // Local Core Data persistence remains fully functional.
            privateStoreDescription.cloudKitContainerOptions = nil
            privateStoreDescription.setOption(true as NSNumber,
                                              forKey: NSPersistentHistoryTrackingKey)
            privateStoreDescription.setOption(true as NSNumber,
                                              forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)

            let sharedStoreDescription = privateStoreDescription.copy() as! NSPersistentStoreDescription
            let sharedOptions = NSPersistentCloudKitContainerOptions(containerIdentifier: cloudKitContainerIdentifier)
            sharedOptions.databaseScope = .shared
            sharedStoreDescription.cloudKitContainerOptions = sharedOptions
            sharedStoreDescription.url = privateStoreDescription.url?.deletingLastPathComponent()
                .appendingPathComponent("ArmadilloAssistant-Shared.sqlite")
            sharedStoreDescription.setOption(true as NSNumber,
                                             forKey: NSPersistentHistoryTrackingKey)
            sharedStoreDescription.setOption(true as NSNumber,
                                             forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)

            // Temporary rollback: load only the private store while stale deleted-share-zone
            // metadata is being cleared from CloudKit. The shared store configuration above
            // remains available for reactivation after the private baseline is stable.
            container.persistentStoreDescriptions = [privateStoreDescription]
            // temporarilyResetEmptySharedStoreIfNeeded(sharedStoreURL: sharedStoreDescription.url)
        }
        container.loadPersistentStores(completionHandler: { (storeDescription, error) in
            if let error = error as NSError? {
                fatalError("Unresolved error \(error), \(error.userInfo)")
            }
        })
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        seedReferenceDataIfNeeded(context: container.viewContext)
    }

    // Section 2: Temporary shared-store metadata cleanup
    // Removes only the shared CloudKit store files when that store contains stale deleted-share-zone metadata.
    // This does not touch ArmadilloAssistant.sqlite, which contains the user's private/local app data.
    // Remove this helper and its startup call after the shared store has been rebuilt cleanly.
    private func temporarilyResetEmptySharedStoreIfNeeded(sharedStoreURL: URL?) {
        guard let sharedStoreURL else {
            print("[Persistence] Shared-store reset skipped: missing shared store URL")
            return
        }

        let resetFlagKey = "TemporarySharedStoreResetCompleted-20260524"
        guard UserDefaults.standard.bool(forKey: resetFlagKey) == false else {
            print("[Persistence] Shared-store reset skipped: already completed")
            return
        }

        let fileManager = FileManager.default
        let sharedStorePath = sharedStoreURL.path
        let relatedPaths = [
            sharedStorePath,
            sharedStorePath + "-wal",
            sharedStorePath + "-shm"
        ]

        for path in relatedPaths {
            guard fileManager.fileExists(atPath: path) else { continue }

            do {
                try fileManager.removeItem(atPath: path)
                print("[Persistence] Removed stale shared-store file: \(URL(fileURLWithPath: path).lastPathComponent)")
            } catch {
                let nsError = error as NSError
                print("[Persistence] Failed removing shared-store file \(path): \(nsError), \(nsError.userInfo)")
            }
        }

        UserDefaults.standard.set(true, forKey: resetFlagKey)
        print("[Persistence] Temporary shared-store reset completed")
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

    func createShare(for workspace: AppWorkspace,
                     completion: @escaping (Result<(share: CKShare, container: CKContainer), Error>) -> Void) {
        let workspaceName = workspace.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let shareTitle = workspaceName.isEmpty ? "12 Armadillos Workspace" : workspaceName

        container.share([workspace], to: nil) { _, share, cloudKitContainer, error in
            if let error {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
                return
            }

            guard let share,
                  let cloudKitContainer else {
                let missingShareError = NSError(
                    domain: "ArmadilloAssistant.CloudKitSharing",
                    code: 1001,
                    userInfo: [NSLocalizedDescriptionKey: "CloudKit did not return a share for the workspace."]
                )
                DispatchQueue.main.async {
                    completion(.failure(missingShareError))
                }
                return
            }

            share[CKShare.SystemFieldKey.title] = shareTitle as CKRecordValue
            share.publicPermission = .none

            DispatchQueue.main.async {
                completion(.success((share: share, container: cloudKitContainer)))
            }
        }
    }


    private func seedReferenceDataIfNeeded(context: NSManagedObjectContext) {
        seedRentalPropertiesIfNeeded(context: context)
        cleanupDuplicateRentalPropertiesIfNeeded(context: context)
        seedWorkspaceIfNeeded(context: context)
        cleanupDuplicateWorkspacesIfNeeded(context: context)
        // Temporary containment: pause AppWorkspace -> RentalProperty attachment while
        // CloudKit has stale share-zone metadata from an earlier share attempt.
        // Re-enable this after the CloudKit metadata is cleaned.
        // attachRentalPropertiesToWorkspaceIfNeeded(context: context)
        backfillBookingPropertyRefsIfNeeded(context: context)
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
    // Keeps the oldest AppWorkspace as the canonical private workspace and removes duplicate
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

    // Section 4: Expense workspace attachment
    // Attaches low-risk expense-related objects to the AppWorkspace share graph.
    // This intentionally does not attach RentalProperty or Booking records yet.
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

        for workspace in workspaces {
            do {
                let shares = try container.fetchShares(matching: [workspace.objectID])

                if shares[workspace.objectID] != nil {
                    print("[Persistence] Canonical workspace selected from active CKShare")
                    return workspace
                }
            } catch {
                let nsError = error as NSError
                print("[Persistence] Workspace share lookup failed during canonical selection: \(nsError), \(nsError.userInfo)")
            }
        }

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
