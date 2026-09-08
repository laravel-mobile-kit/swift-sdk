<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\RefreshToken;
use App\Models\User;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Http\Response;
use Illuminate\Support\Facades\Hash;
use Illuminate\Validation\ValidationException;

/**
 * Token authentication in the shape a hand-written Laravel API usually takes:
 * a Sanctum personal access token for calls, plus a rotating refresh token so
 * the 401-and-refresh flow can be exercised.
 */
class AuthController extends Controller
{
    private const ACCESS_TOKEN_LIFETIME = 3600;

    public function register(Request $request): JsonResponse
    {
        $data = $request->validate([
            'name' => ['required', 'string', 'max:255'],
            'email' => ['required', 'email', 'unique:users,email'],
            'password' => ['required', 'string', 'min:8'],
        ]);

        $user = User::query()->create([
            'name' => $data['name'],
            'email' => $data['email'],
            'password' => Hash::make($data['password']),
        ]);

        return response()->json($this->tokenPayload($user, $request), 201);
    }

    public function login(Request $request): JsonResponse
    {
        $data = $request->validate([
            'email' => ['required', 'email'],
            'password' => ['required', 'string'],
        ]);

        $user = User::query()->where('email', $data['email'])->first();

        if (! $user || ! Hash::check($data['password'], $user->password)) {
            // Laravel's own convention for rejected credentials: a 422 whose
            // errors bag names the field, not a bare 401.
            throw ValidationException::withMessages([
                'email' => [__('auth.failed')],
            ]);
        }

        return response()->json($this->tokenPayload($user, $request));
    }

    public function refresh(Request $request): JsonResponse
    {
        $data = $request->validate([
            'refresh_token' => ['required', 'string'],
        ]);

        $refreshToken = RefreshToken::findValid($data['refresh_token']);

        if (! $refreshToken) {
            return response()->json(['message' => 'Unauthenticated.'], 401);
        }

        $user = $refreshToken->user;
        // Rotation: a refresh token is spent by the exchange.
        $refreshToken->delete();
        $user->tokens()->delete();

        return response()->json($this->tokenPayload($user, $request));
    }

    public function user(Request $request): JsonResponse
    {
        return response()->json($this->userPayload($request->user()));
    }

    public function logout(Request $request): Response
    {
        $user = $request->user();
        $user->currentAccessToken()->delete();
        RefreshToken::query()->where('user_id', $user->id)->delete();

        return response()->noContent();
    }

    /**
     * Invalidates the access token while leaving the refresh token usable, so a
     * test can produce a genuine 401 on the next call.
     */
    public function revokeAccessToken(Request $request): Response
    {
        $request->user()->currentAccessToken()->delete();

        return response()->noContent();
    }

    public function forgotPassword(Request $request): JsonResponse
    {
        $request->validate(['email' => ['required', 'email']]);

        return response()->json(['status' => 'We have emailed your password reset link.']);
    }

    /**
     * @return array<string, mixed>
     */
    private function tokenPayload(User $user, Request $request): array
    {
        $deviceName = (string) ($request->input('device_name') ?: 'integration-tests');

        $accessToken = $user->createToken(
            $deviceName,
            ['*'],
            now()->addSeconds(self::ACCESS_TOKEN_LIFETIME)
        );

        return [
            'access_token' => $accessToken->plainTextToken,
            'refresh_token' => RefreshToken::issue($user),
            'token_type' => 'Bearer',
            'expires_in' => self::ACCESS_TOKEN_LIFETIME,
            'user' => $this->userPayload($user),
        ];
    }

    /**
     * @return array<string, mixed>
     */
    private function userPayload(User $user): array
    {
        return [
            'id' => $user->id,
            'name' => $user->name,
            'email' => $user->email,
            'email_verified_at' => $user->email_verified_at,
            'created_at' => $user->created_at,
        ];
    }
}
