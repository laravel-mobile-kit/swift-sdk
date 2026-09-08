<?php

/*
 * Forces the settings the fixture depends on into a generated .env, leaving
 * everything the Laravel skeleton wrote alone.
 */

$path = $argv[1] ?? null;

if ($path === null) {
    fwrite(STDERR, "usage: configure-env.php <path-to-.env> [KEY=VALUE …]\n");
    exit(1);
}

$settings = [
    'DB_CONNECTION' => 'sqlite',
    'CACHE_STORE' => 'file',
    'SESSION_DRIVER' => 'file',
    'QUEUE_CONNECTION' => 'sync',
    'MAIL_MAILER' => 'log',
    'APP_DEBUG' => 'true',
];

// Anything passed on the command line is applied on top.
foreach (array_slice($argv, 2) as $pair) {
    [$key, $value] = array_pad(explode('=', $pair, 2), 2, '');
    $settings[$key] = $value;
}

$lines = file_exists($path) ? file($path, FILE_IGNORE_NEW_LINES) : [];

// A DB_DATABASE left over from a MySQL default would break sqlite migrations.
$lines = array_values(array_filter(
    $lines,
    fn (string $line): bool => ! str_starts_with($line, 'DB_DATABASE=')
));

foreach ($settings as $key => $value) {
    $found = false;

    foreach ($lines as $index => $line) {
        if (str_starts_with($line, $key.'=')) {
            $lines[$index] = $key.'='.$value;
            $found = true;
        }
    }

    if (! $found) {
        $lines[] = $key.'='.$value;
    }
}

file_put_contents($path, implode(PHP_EOL, $lines).PHP_EOL);
