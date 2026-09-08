import SwiftUI

import LaravelMobileKit

/// Sign-in, with Laravel's validation errors rendered under the fields they
/// belong to.
///
/// A 422 arrives as a ``LaravelValidationError`` with the errors bag intact, so
/// the view never parses JSON: it asks the error which fields failed.
struct LoginView: View {
    @EnvironmentObject private var environment: AppEnvironment

    @State private var email = "test@example.com"
    @State private var password = "password"
    @State private var validation: LaravelValidationError?
    @State private var failure: String?
    @State private var isSubmitting = false

    var body: some View {
        Form {
            Section("Sign in") {
                TextField("Email", text: $email)
                    .disableAutocorrection(true)
                fieldErrors(for: "email")

                SecureField("Password", text: $password)
                fieldErrors(for: "password")
            }

            if let failure {
                Text(failure)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Button(isSubmitting ? "Signing in…" : "Sign in") {
                Task { await signIn() }
            }
            .disabled(isSubmitting || email.isEmpty || password.isEmpty)
        }
        .formStyle(.grouped)
        .frame(minWidth: 320, minHeight: 260)
    }

    @ViewBuilder
    private func fieldErrors(for field: String) -> some View {
        if let messages = validation?[field] {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(messages, id: \.self) { message in
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
    }

    private func signIn() async {
        isSubmitting = true
        validation = nil
        failure = nil
        defer { isSubmitting = false }

        do {
            try await environment.signIn(email: email, password: password)
        } catch let error as LaravelValidationError {
            // Laravel answers wrong credentials with a 422 whose errors bag
            // names the field — exactly what the form wants.
            validation = error
        } catch let error as LaravelError {
            failure = error.errorDescription ?? "Sign-in failed"
        } catch {
            failure = error.localizedDescription
        }
    }
}
