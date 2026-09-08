<?php

use App\Http\Controllers\Api\AuthController;
use App\Http\Controllers\Api\DiagnosticsController;
use App\Http\Controllers\Api\EventController;
use App\Http\Controllers\Api\UploadController;
use Illuminate\Support\Facades\Route;

/*
|--------------------------------------------------------------------------
| Compatibility fixture for Laravel Mobile Kit
|--------------------------------------------------------------------------
|
| These routes exist to exercise the SDK against a real Laravel application:
| every contract the kit claims to support (§17 of the PRD) has an endpoint
| here. Authentication deliberately lives outside the version prefix, and the
| business API is published twice — unversioned and under /v1 — so the SDK's
| versioning middleware can be tested against both shapes.
|
*/

Route::post('/register', [AuthController::class, 'register']);
Route::post('/login', [AuthController::class, 'login']);
Route::post('/auth/refresh', [AuthController::class, 'refresh']);
Route::post('/forgot-password', [AuthController::class, 'forgotPassword']);

Route::middleware('auth:sanctum')->group(function () {
    Route::get('/user', [AuthController::class, 'user']);
    Route::post('/logout', [AuthController::class, 'logout']);
    // Test hook: makes the current access token stop working without touching
    // the refresh token, so a 401-then-refresh flow can be triggered on demand.
    Route::post('/auth/revoke-access-token', [AuthController::class, 'revokeAccessToken']);
});

// Storage stand-in for presigned direct uploads. It is unversioned because the
// API hands the client an absolute, signed URL for it.
Route::put('/uploads/storage/{uuid}', [UploadController::class, 'storage'])
    ->middleware('signed')
    ->name('uploads.storage');

foreach (['' => 'none', 'v1' => 'v1'] as $prefix => $version) {
    Route::prefix($prefix)->group(function () use ($version) {
        Route::get('/version', fn () => response()->json(['version' => $version]));

        Route::get('/echo', [DiagnosticsController::class, 'echo']);
        Route::get('/slow', [DiagnosticsController::class, 'slow']);
        Route::get('/status/{code}', [DiagnosticsController::class, 'status']);
        Route::match(['get', 'post'], '/flaky/{key}', [DiagnosticsController::class, 'flaky']);
        Route::delete('/flaky/{key}', [DiagnosticsController::class, 'resetFlaky']);

        Route::get('/events', [EventController::class, 'index']);
        Route::get('/events/resource', [EventController::class, 'resource']);
        Route::get('/events/simple', [EventController::class, 'simple']);
        Route::get('/events/cursor', [EventController::class, 'cursor']);
        Route::get('/events/{event}', [EventController::class, 'show']);

        Route::middleware('auth:sanctum')->group(function () {
            Route::post('/events', [EventController::class, 'store']);
            Route::delete('/events/{event}', [EventController::class, 'destroy']);

            Route::post('/avatar', [UploadController::class, 'avatar']);
            Route::post('/uploads/authorize', [UploadController::class, 'authorizeUpload']);
            Route::post('/uploads/complete', [UploadController::class, 'complete']);
        });
    });
}
