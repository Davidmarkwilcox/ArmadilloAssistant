//  Persistence.swift
//  ArmadilloAssistant
//
//  Created by David Wilcox on 2/26/26.
//

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

    init(inMemory: Bool = false) {
        container = NSPersistentCloudKitContainer(name: "ArmadilloAssistant")
        // CloudKit container binding
        // NOTE: Keep previews/in-memory stores from attempting CloudKit sync.
        let storeDescription = container.persistentStoreDescriptions.first
        if inMemory {
            storeDescription?.cloudKitContainerOptions = nil
        } else {
            storeDescription?.cloudKitContainerOptions =
                NSPersistentCloudKitContainerOptions(containerIdentifier: "iCloud.com.DavidMWilcox.ArmadilloAssistant")
        }
        // Enable persistent history tracking and remote change notifications.
        // These are required for reliable CloudKit syncing and future CKShare
        // collaboration features (team workspace sharing).
        storeDescription?.setOption(true as NSNumber,
                                    forKey: NSPersistentHistoryTrackingKey)

        storeDescription?.setOption(true as NSNumber,
                                    forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
        if inMemory {
            container.persistentStoreDescriptions.first!.url = URL(fileURLWithPath: "/dev/null")
        }
        container.loadPersistentStores(completionHandler: { (storeDescription, error) in
            if let error = error as NSError? {
                // Replace this implementation with code to handle the error appropriately.
                // fatalError() causes the application to generate a crash log and terminate. You should not use this function in a shipping application, although it may be useful during development.

                /*
                 Typical reasons for an error here include:
                 * The parent directory does not exist, cannot be created, or disallows writing.
                 * The persistent store is not accessible, due to permissions or data protection when the device is locked.
                 * The device is out of space.
                 * The store could not be migrated to the current model version.
                 Check the error message to determine what the actual problem was.
                 */
                fatalError("Unresolved error \(error), \(error.userInfo)")
            }
        })
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        seedExpenseReferenceDataIfNeeded(context: container.viewContext)
    }
    private func seedExpenseReferenceDataIfNeeded(context: NSManagedObjectContext) {
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
}
