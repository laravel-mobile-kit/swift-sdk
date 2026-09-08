import SwiftUI

import LaravelMobileKit

/// The whole app is a switch over the session state.
///
/// `AuthState` distinguishes "not checked yet" from "signed out" from "could
/// not check": an app that is merely offline must not throw away a valid
/// credential by showing a sign-in screen.
struct ContentView: View {
    @EnvironmentObject private var environment: AppEnvironment

    var body: some View {
        switch environment.session.state {
        case .unknown, .restoring:
            ProgressView("Restoring your session…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .unauthenticated:
            LoginView()
        case let .authenticated(user):
            HomeView(user: user)
        case .unverified:
            OfflineView()
        }
    }
}

/// A credential exists but could not be verified — the network failed, not the
/// user. The credential is kept, so retrying is all it takes.
struct OfflineView: View {
    @EnvironmentObject private var environment: AppEnvironment

    var body: some View {
        VStack(spacing: 16) {
            Text("We could not reach the server")
                .font(.headline)
            if let error = environment.session.lastError {
                Text(error.localizedDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Button("Try again") {
                Task { await environment.session.restore() }
            }
        }
        .padding()
    }
}
