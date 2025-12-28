//
//  cacheApp.swift
//  cache
//
//  Created by Johnston Liu on 2025-12-28.
//

import SwiftUI

@main
struct cacheApp: App {
    @StateObject private var router = AppRouter()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(router)
                .onOpenURL { url in
                    if let id = DeepLink.noteID(from: url) {
                        router.openNote(id: id)
                    }
                }
        }
    }
}
