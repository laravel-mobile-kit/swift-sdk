import SwiftUI

/// Laravel Mobile Kit quick start.
///
/// The app is deliberately small: one screen per Definition-of-Done flow —
/// sign in, session restoration, paginated reads, uploads, validation errors,
/// token refresh, cancellation — and no architecture of its own to read past.
@main
struct QuickStartApp: App {
    @StateObject private var environment = AppEnvironment()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(environment)
                // Restoring here is what makes a returning user land straight
                // in the app rather than on the sign-in screen.
                .task { await environment.start() }
        }
    }
}
