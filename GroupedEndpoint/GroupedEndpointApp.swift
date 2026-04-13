//
//  GroupedEndpointApp.swift
//  GroupedEndpoint
//
//  Created by Martin Mitrevski on 13/04/2026.
//

import SwiftUI

@main
struct GroupedEndpointApp: App {
    @StateObject private var chatManager = ChatManager.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(chatManager)
        }
    }
}
