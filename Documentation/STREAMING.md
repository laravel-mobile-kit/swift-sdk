# Streaming

Some responses are worth reading before they finish. A model writing an answer
token by token is the usual one: the whole body arrives eventually, but a user
staring at a spinner until then is a worse product than one watching the answer
appear.

```swift
for try await chunk in try await client.stream(.post, "/api/chat", body: prompt) {
    transcript += String(decoding: chunk, as: UTF8.self)
}
```

`stream` returns an `AsyncThrowingStream<Data, any Error>` of body chunks in
arrival order. Chunk boundaries are the ones the server produced; the kit does
not re-slice them.

## What is settled before the first chunk

The status code is validated, and retries are exhausted, before `stream`
returns. Holding a stream means the response head was already a success.

This matters more than it sounds. A server that answers `500` sends a body too,
and a client that yields bytes first and checks the status later hands that error
payload to the caller looking exactly like content — which, for a chat
transcript, means the words "Internal Server Error" appearing in the
conversation. Here a failing status throws instead, with the body attached to the
error:

```swift
do {
    let stream = try await client.stream(.post, "/api/chat", body: prompt)
    for try await chunk in stream { … }
} catch let error as LaravelValidationError {
    promptError = error.firstError(for: "prompt")
} catch let error as LaravelError {
    // error.httpError?.bodyText — the server's explanation
}
```

## Retries

Everything the buffered path retries, this retries too: transient statuses,
network failures, and a `401` that a `RetryDecider` recovers from. All of it
happens while the head is being validated, so it is always before the caller has
seen a byte.

Once the stream is returned, nothing is retried. A failure mid-body — a dropped
connection halfway through an answer — surfaces as an error from the iteration,
carrying whatever chunks already arrived. Repeating the request there would
duplicate the answer rather than repair it, and only the caller knows whether a
half-written reply is worth keeping.

## Middleware

Request middleware runs normally: authentication, versioning and tracing apply to
a streamed request exactly as they do to any other.

Response middleware runs **only on failure**, where the body is drained first —
that is what lets `.validationErrors` turn a streamed `422` into a
`LaravelValidationError`. On success it is skipped, because the alternatives are
to hand middleware an empty body, which is a lie, or a buffered one, which
defeats the streaming that was asked for.

## Transports

Streaming needs a transport that can deliver a body incrementally, declared by
conforming to `StreamingTransport`:

```swift
public protocol StreamingTransport: HTTPTransport {
    func stream(_ request: URLRequest) async throws -> HTTPResponseStream
}
```

`URLSessionTransport` conforms. A transport that only buffers — most test
doubles — does not, and `stream` reports `LaravelError.streamingUnsupported`
rather than quietly buffering a response the caller asked to receive as it
arrives.

`HTTPResponseStream` is the head and the body as separate values, which is the
shape that makes "validate before yielding" possible:

```swift
public struct HTTPResponseStream: Sendable {
    public let response: HTTPURLResponse
    public let body: AsyncThrowingStream<Data, any Error>
}
```

## Cancellation

Stopping the iteration cancels the request. Breaking out of the loop, or
cancelling the surrounding task, tears down the underlying `URLSessionTask` —
there is no need to signal it separately.

## Text, not bytes

The kit stays at `Data` because it does not know your framing: raw text,
newline-delimited JSON and server-sent events all arrive as chunks and are split
differently. Decoding incrementally is a few lines and belongs where the format
is known:

```swift
var buffer = Data()
for try await chunk in try await client.stream(.post, "/api/chat") {
    buffer.append(chunk)
    while let newline = buffer.firstIndex(of: 0x0A) {
        let line = buffer[..<newline]
        buffer.removeSubrange(...newline)
        handle(String(decoding: line, as: UTF8.self))
    }
}
```

A chunk is not guaranteed to end on a character boundary, which is why the
buffer lives outside the loop.
