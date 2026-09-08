<?php

namespace Database\Seeders;

use App\Models\Event;
use App\Models\User;
use Illuminate\Database\Seeder;
use Illuminate\Support\Facades\Hash;

/**
 * Deterministic fixture data: the integration tests assert on these values, so
 * nothing here may be random.
 */
class DatabaseSeeder extends Seeder
{
    public const EVENT_COUNT = 45;

    public function run(): void
    {
        User::query()->updateOrCreate(
            ['email' => 'test@example.com'],
            ['name' => 'Test User', 'password' => Hash::make('password')]
        );

        if (Event::query()->count() > 0) {
            return;
        }

        $startsAt = now()->startOfDay()->addDays(1);

        foreach (range(1, self::EVENT_COUNT) as $number) {
            Event::query()->create([
                'title' => sprintf('Event %02d', $number),
                'description' => sprintf('Seeded fixture event number %d.', $number),
                'starts_at' => $startsAt->copy()->addHours($number),
                'is_published' => true,
            ]);
        }
    }
}
