import Foundation
import Security

/// A failure reported by Keychain Services.
public enum KeychainError: Error, LocalizedError, Hashable {
    /// The credential could not be written.
    case unableToStore(OSStatus)
    /// The stored item could not be read.
    case unableToRetrieve(OSStatus)
    /// The stored item could not be removed.
    case unableToDelete(OSStatus)
    /// A stored item was found but its contents were not a credential.
    case corruptedCredential

    /// The underlying Keychain Services status, when there is one.
    public var status: OSStatus? {
        switch self {
        case let .unableToStore(status), let .unableToRetrieve(status), let .unableToDelete(status):
            status
        case .corruptedCredential:
            nil
        }
    }

    /// Whether the Keychain is unavailable to this process altogether.
    ///
    /// Unsigned binaries — command-line tools and some test runners — cannot
    /// reach the data protection Keychain. Callers can use this to fall back to
    /// another store instead of treating it as a lost credential.
    public var isKeychainUnavailable: Bool {
        guard let status else { return false }
        return status == errSecMissingEntitlement
            || status == errSecNotAvailable
            || status == errSecInteractionNotAllowed
    }

    public var errorDescription: String? {
        switch self {
        case let .unableToStore(status):
            "Could not store the credential in the Keychain: \(Self.message(for: status))"
        case let .unableToRetrieve(status):
            "Could not read the credential from the Keychain: \(Self.message(for: status))"
        case let .unableToDelete(status):
            "Could not remove the credential from the Keychain: \(Self.message(for: status))"
        case .corruptedCredential:
            "The stored Keychain item is not a valid credential"
        }
    }

    private static func message(for status: OSStatus) -> String {
        SecCopyErrorMessageString(status, nil).map { $0 as String } ?? "OSStatus \(status)"
    }
}
