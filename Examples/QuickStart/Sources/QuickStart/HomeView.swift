import SwiftUI

/// What a signed-in user sees: the paginated collection, the upload demo, and
/// the account screen.
struct HomeView: View {
    let user: AppUser

    var body: some View {
        TabView {
            NavigationStack { EventsListView() }
                .tabItem { Label("Events", systemImage: "list.bullet") }

            NavigationStack { UploadView() }
                .tabItem { Label("Upload", systemImage: "arrow.up.circle") }

            NavigationStack { AccountView(user: user) }
                .tabItem { Label("Account", systemImage: "person.crop.circle") }
        }
        .frame(minWidth: 420, minHeight: 480)
    }
}

/// The current user, plus sign-out.
struct AccountView: View {
    @EnvironmentObject private var environment: AppEnvironment
    let user: AppUser

    @State private var isSigningOut = false

    var body: some View {
        Form {
            Section("Signed in as") {
                LabeledContent("Name", value: user.name)
                LabeledContent("Email", value: user.email)
                if let createdAt = user.createdAt {
                    LabeledContent("Member since", value: createdAt.formatted(date: .abbreviated, time: .omitted))
                }
            }

            Section {
                Button(isSigningOut ? "Signing out…" : "Sign out", role: .destructive) {
                    Task {
                        isSigningOut = true
                        // Signing out tells the server first, but a failure
                        // there never blocks the local sign-out.
                        await environment.signOut()
                        isSigningOut = false
                    }
                }
                .disabled(isSigningOut)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Account")
    }
}
