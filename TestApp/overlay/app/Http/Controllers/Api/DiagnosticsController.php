<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Cache;

/**
 * Endpoints that exist purely so client behaviour — retries, timeouts,
 * cancellation, middleware, status mapping — can be observed from the outside.
 */
class DiagnosticsController extends Controller
{
    /** Reflects the request back, so header and versioning behaviour is visible. */
    public function echo(Request $request): JsonResponse
    {
        return response()->json([
            'method' => $request->method(),
            'path' => '/'.ltrim($request->path(), '/'),
            // Cast so an empty query is `{}` rather than PHP's `[]`.
            'query' => (object) $request->query(),
            'headers' => collect($request->headers->all())
                ->map(fn (array $values) => $values[0])
                ->all(),
        ]);
    }

    /** Answers after a delay, for timeout and cancellation tests. */
    public function slow(Request $request): JsonResponse
    {
        $seconds = min(10.0, max(0.0, (float) $request->query('seconds', 1)));
        usleep((int) round($seconds * 1_000_000));

        return response()->json(['slept' => $seconds]);
    }

    /**
     * Fails the first `failures` attempts with a 503, then succeeds.
     *
     * The attempt counter is keyed by `key`, so each test owns its own counter.
     */
    public function flaky(Request $request, string $key): JsonResponse
    {
        $failures = max(0, (int) $request->query('failures', 1));

        // `increment` cannot create the entry on every cache store, so the
        // counter is seeded first.
        Cache::add($this->cacheKey($key), 0, now()->addMinutes(10));
        $attempts = (int) Cache::increment($this->cacheKey($key));

        if ($attempts <= $failures) {
            return response()->json([
                'message' => 'Service Unavailable',
                'attempts' => $attempts,
            ], 503);
        }

        return response()->json([
            'attempts' => $attempts,
            'method' => $request->method(),
        ]);
    }

    /** Reports and clears the attempt counter for `key`. */
    public function resetFlaky(string $key): JsonResponse
    {
        $attempts = (int) Cache::get($this->cacheKey($key), 0);
        Cache::forget($this->cacheKey($key));

        return response()->json(['attempts' => $attempts]);
    }

    /** Answers with the requested status code and a JSON body. */
    public function status(Request $request, int $code): JsonResponse
    {
        $code = ($code >= 200 && $code <= 599) ? $code : 500;

        return response()->json([
            'message' => 'Status '.$code,
            'requested_status' => $code,
        ], $code);
    }

    private function cacheKey(string $key): string
    {
        return 'flaky:'.$key;
    }
}
