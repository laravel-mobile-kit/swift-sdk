import Foundation

/// Builds decoders configured for Laravel's JSON conventions.
///
/// Laravel serializes model attributes in `snake_case`; Swift models are
/// written in `camelCase`. The default decoder bridges the two so models do not
/// need `CodingKeys` for every property.
public enum LaravelJSONDecoder {
    /// A decoder using `snake_case` keys and Laravel's date formats.
    public static func makeDefault() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)

            guard let date = LaravelDateFormat.date(from: string) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Date '\(string)' is not in a supported format"
                )
            }
            return date
        }
        return decoder
    }
}

/// Builds encoders configured for Laravel's JSON conventions.
public enum LaravelJSONEncoder {
    /// An encoder using `snake_case` keys and ISO8601 dates.
    public static func makeDefault() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(LaravelDateFormat.string(from: date))
        }
        return encoder
    }
}
