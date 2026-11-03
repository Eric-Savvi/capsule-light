import AppKit
import SwiftUI

@main
struct CapsuleApp: App {
    var body: some Scene {
        Window("Capsule", id: "main") {
            ContentView()
                // Dock icon only while the window is open; the menu-bar item keeps running.
                .onAppear { NSApp.setActivationPolicy(.regular) }
                .onDisappear { NSApp.setActivationPolicy(.accessory) }
        }
        .windowResizability(.contentSize)

        MenuBarExtra("Capsule", systemImage: "mic.fill") {
            MenuBarView()
        }
        .menuBarExtraStyle(.window)
    }
}
