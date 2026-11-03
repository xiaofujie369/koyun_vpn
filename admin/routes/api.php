<?php

use App\Http\Controllers\Api\ClientController;
use App\Http\Middleware\ClientKey;
use Illuminate\Support\Facades\Route;

// App 调用的接口：/api/v1/client/...
Route::prefix('v1/client')->middleware(ClientKey::class)->group(function () {
    Route::post('events', [ClientController::class, 'events'])->middleware('throttle:client-events');
    Route::post('feedback', [ClientController::class, 'feedback'])->middleware('throttle:client-feedback');
    Route::get('config', [ClientController::class, 'config'])->middleware('throttle:client-events');
});
