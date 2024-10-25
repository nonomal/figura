import SwiftUI
import AppKit

@main
struct FiguraApp: App {
    @AppStorage("isDarkMode") private var isDarkMode = false
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(isDarkMode ? .dark : .light)
                .background(WindowAccessor())
        }
        .windowStyle(HiddenTitleBarWindowStyle())
    }
}
