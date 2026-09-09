import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Reads the `Retry-After` header a server sends with 429 and 503.
///
/// The header is the server stating how long it wants to be left alone. Ignoring
/// it and falling back to a client-side schedule is how a rate limit turns into
/// a longer rate limit: the client spends the remaining budget faster than it
/// refills.
///
/// Both wire forms are accepted — RFC 9110 allows delay-seconds or an HTTP-date,
/// and real servers send both.
enum RetryAfter {
    /// Seconds to wait, or `nil` when the response carries no usable header.
    ///
    /// A date already in the past yields `0` rather than a negative interval:
    /// the server's clock is not ours, and "wait no time" is the sane reading.
    static func seconds(from response: HTTPURLResponse, now: Date = Date()) -> TimeInterval? {
        guard let raw = response.value(forHTTPHeaderField: "Retry-After") else { return nil }
        let value = raw.trimmingCharacters(in: .whitespaces)
        guard !value.isEmpty else { return nil }

        // delay-seconds is the common form and the cheap one, so try it first.
        if let delay = TimeInterval(value) {
            return delay.isFinite ? max(0, delay) : nil
        }

        guard let date = httpDate(value) else { return nil }
        return max(0, date.timeIntervalSince(now))
    }

    /// Parses the three date formats HTTP permits, newest first.
    private static func httpDate(_ value: String) -> Date? {
        // Formatters are built per call rather than cached: they are mutable
        // class instances, this path runs only on a retry that carried a
        // date-form header, and a shared one would be the same data race the
        // credential store just had.
        for format in formats {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(identifier: "GMT")
            formatter.dateFormat = format
            if let date = formatter.date(from: value) { return date }
        }
        return nil
    }

    private static let formats = [
        "EEE, dd MMM yyyy HH:mm:ss zzz",  // RFC 1123 — what servers should send
        "EEEE, dd-MMM-yy HH:mm:ss zzz",   // RFC 850 — obsolete, still seen
        "EEE MMM d HH:mm:ss yyyy",        // asctime — obsolete, still seen
    ]
}
