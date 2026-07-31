import SwiftUI

@main
struct ClarityVideoApp: App {
    @State private var state = AppState()
    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(state)
                .preferredColorScheme(.dark)
        }
    }
}
