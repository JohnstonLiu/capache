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
    @StateObject private var auth = AuthViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(router)
                .environmentObject(auth)
                .appAnimationPolicy()
                .onOpenURL { url in
                    if let id = DeepLink.noteID(from: url) {
                        router.openNote(id: id)
                    }
                }
        }
    }
}
