//
//  ArmadilloAssistantApp.swift
//  ArmadilloAssistant
//
//  Created by David Wilcox on 2/26/26.
//

import SwiftUI
import CoreData
import CloudKit
import LocalAuthentication
import UIKit

// Section 1: CloudKit share acceptance bridge
// Handles CloudKit share links that iOS routes into the app and passes the accepted
// CKShare metadata into the Core Data + CloudKit shared persistent store.
final class CloudKitShareAcceptanceAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata) {
        let persistentContainer = PersistenceController.shared.container
        let persistentStores = persistentContainer.persistentStoreCoordinator.persistentStores

        let sharedStore = persistentStores.first { store in
            store.url?.lastPathComponent == "ArmadilloAssistant-Shared.sqlite"
        } ?? persistentStores.last

        guard let sharedStore else {
            print("[CloudKitShareAcceptance] Unable to locate shared persistent store for accepted share.")
            return
        }

        print("[CloudKitShareAcceptance] Accepting CloudKit share: \(cloudKitShareMetadata.share.recordID.recordName)")

        persistentContainer.acceptShareInvitations(from: [cloudKitShareMetadata], into: sharedStore) { acceptedMetadata, error in
            if let error {
                let nsError = error as NSError
                print("[CloudKitShareAcceptance] Failed to accept CloudKit share: \(nsError), \(nsError.userInfo)")
                return
            }

            print("[CloudKitShareAcceptance] Accepted CloudKit shares: \(acceptedMetadata?.count ?? 0)")
        }
    }
}

@main
struct ArmadilloAssistantApp: App {
    let persistenceController = PersistenceController.shared
    @UIApplicationDelegateAdaptor(CloudKitShareAcceptanceAppDelegate.self) private var cloudKitShareAcceptanceAppDelegate
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // Apply themed metallic red navigation bar appearance
        Theme.NavigationBar.applyAppearance()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
                .preferredColorScheme(.dark)
                .tint(Theme.Colors.crimson)
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .active {
                        AppLockManager.shared.lockIfNeeded()
                    }
                }
        }
    }
}
