<?php

use Illuminate\Support\Facades\Route;

Route::get('/health', fn () => [
    'status' => 'ok',
    'time' => now()->toISOString(),
]);

Route::get('/env', fn () => [
    'app' => config('app.name'),
    'url' => config('app.url'),
]);
