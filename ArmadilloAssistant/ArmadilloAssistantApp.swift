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
        }
    }
}
