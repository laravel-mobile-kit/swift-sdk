import Foundation

import LaravelMobileKit

/// Examples from `Documentation/STREAMING.md`.
enum StreamingSnippets {
    static func readingAsItArrives(client: LaravelClient, prompt: Data) async throws -> String {
        var transcript = ""
        for try await chunk in try await client.stream(.post, "/api/chat", body: prompt) {
            transcript += String(decoding: chunk, as: UTF8.self)
        }
        return transcript
    }

    static func handlingFailures(client: LaravelClient, prompt: Data) async -> String? {
        do {
            let stream = try await client.stream(.post, "/api/chat", body: prompt)
            for try await _ in stream {}
            return nil
        } catch let error as LaravelValidationError {
            return error.firstError(for: "prompt")
        } catch let error as LaravelError {
            return error.httpError?.bodyText
        } catch {
            return nil
        }
    }

    /// Line framing, which the kit deliberately leaves to the caller: a chunk is
    /// not guaranteed to end on a character boundary, so the buffer outlives the
    /// loop iteration.
    static func decodingLines(
        client: LaravelClient,
        handle: (String) -> Void
    ) async throws {
        var buffer = Data()
        for try await chunk in try await client.stream(.post, "/api/chat") {
            buffer.append(chunk)
            while let newline = buffer.firstIndex(of: 0x0A) {
                let line = buffer[..<newline]
                buffer.removeSubrange(...newline)
                handle(String(decoding: line, as: UTF8.self))
            }
        }
    }
}
