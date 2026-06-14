//
//  ArmadilloAssistantApp.swift
//  ArmadilloAssistant
//
//  Created by David Wilcox on 2/26/26.
//

import SwiftUI
import CoreData

@main
struct ArmadilloAssistantApp: App {
    let persistenceController = PersistenceController.shared
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
                    // Only re-lock when the prior unlock is older than the allowed timeout.
                    // Cold-launch authentication is handled by ContentView's lock overlay.
                    // Avoid directly presenting Face ID from the scenePhase callback because
                    // LocalAuthentication can report error 6 while the app is still transitioning active.
                    if newPhase == .active {
                        AppLockManager.shared.lockIfNeeded()
                    }
                }
        }
    }
}
