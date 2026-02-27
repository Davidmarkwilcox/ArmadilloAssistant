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

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
