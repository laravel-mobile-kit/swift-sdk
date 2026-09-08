import Foundation

/// Date parsing and formatting for Laravel JSON payloads.
///
/// Laravel serializes dates as ISO8601 with microsecond precision
/// (`2024-01-15T10:30:00.000000Z`), but hand-written responses routinely use
/// second precision or the SQL-style `2024-01-15 10:30:00`. All three are
/// accepted on the way in; output always uses the ISO8601 form Laravel expects.
public enum LaravelDateFormat {
    // `ISO8601DateFormatter` is not marked `Sendable`, but these instances are
    // configured once and only ever read afterwards, which is safe to do
    // concurrently.

    /// ISO8601 with fractional seconds, used when encoding.
    nonisolated(unsafe) static let fractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    /// ISO8601 without fractional seconds.
    nonisolated(unsafe) static let internetDateTime: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    /// `2024-01-15 10:30:00`, the format `Y-m-d H:i:s` produces.
    static let sqlDateTime: DateFormatter = makeFormatter("yyyy-MM-dd HH:mm:ss")

    /// `2024-01-15`, the format a date-only column produces.
    static let dateOnly: DateFormatter = makeFormatter("yyyy-MM-dd")

    private static func makeFormatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .iso8601)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = format
        return formatter
    }

    /// Parses any of the supported representations, or returns `nil`.
    public static func date(from string: String) -> Date? {
        if let date = fractionalSeconds.date(from: normalizingFractionalSeconds(in: string)) {
            return date
        }
        if let date = internetDateTime.date(from: string) {
            return date
        }
        if let date = sqlDateTime.date(from: string) {
            return date
        }
        return dateOnly.date(from: string)
    }

    /// Formats a date as ISO8601 with fractional seconds.
    public static func string(from date: Date) -> String {
        fractionalSeconds.string(from: date)
    }

    /// Trims sub-millisecond digits, which `ISO8601DateFormatter` rejects.
    ///
    /// Laravel emits six fractional digits by default, so this is the common
    /// case rather than an edge case.
    private static func normalizingFractionalSeconds(in string: String) -> String {
        guard let dotIndex = string.firstIndex(of: ".") else { return string }

        var digitsEnd = string.index(after: dotIndex)
        while digitsEnd < string.endIndex, string[digitsEnd].isNumber {
            digitsEnd = string.index(after: digitsEnd)
        }
        let digitCount = string.distance(from: string.index(after: dotIndex), to: digitsEnd)
        guard digitCount > 3 else { return string }

        let keepEnd = string.index(dotIndex, offsetBy: 4)
        return String(string[string.startIndex ..< keepEnd]) + String(string[digitsEnd...])
    }
}
