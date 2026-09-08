<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Support\Str;

/**
 * Sanctum has no refresh tokens, so the fixture issues its own.
 *
 * The kit does not care how they are produced — the refresh call is supplied by
 * the application — but a real refresh endpoint is needed to test the 401 flow
 * end to end.
 */
class RefreshToken extends Model
{
    protected $fillable = ['user_id', 'token_hash', 'expires_at'];

    protected function casts(): array
    {
        return ['expires_at' => 'datetime'];
    }

    public function user(): BelongsTo
    {
        return $this->belongsTo(User::class);
    }

    public static function issue(User $user, int $lifetimeSeconds = 1209600): string
    {
        $token = Str::random(64);

        static::create([
            'user_id' => $user->id,
            'token_hash' => hash('sha256', $token),
            'expires_at' => now()->addSeconds($lifetimeSeconds),
        ]);

        return $token;
    }

    public static function findValid(string $token): ?self
    {
        return static::query()
            ->where('token_hash', hash('sha256', $token))
            ->where('expires_at', '>', now())
            ->first();
    }
}
