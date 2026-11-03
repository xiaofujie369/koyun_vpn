<?php

use App\Http\Controllers\Admin\AuthController;
use App\Http\Controllers\Admin\DashboardController;
use App\Http\Controllers\Admin\DeviceController;
use App\Http\Controllers\Admin\EventController;
use App\Http\Controllers\Admin\FeedbackController;
use App\Http\Controllers\Admin\SettingController;
use Illuminate\Support\Facades\Route;

// 首页不暴露任何信息
Route::get('/', fn () => response('OK', 200)->header('Content-Type', 'text/plain'));

// 后台：随机路径（.env 的 ADMIN_PATH），类似 Xboard 的安全入口
Route::prefix(config('koyun.admin_path'))->name('admin.')->group(function () {
    Route::middleware('guest')->group(function () {
        Route::get('login', [AuthController::class, 'show'])->name('login');
        Route::post('login', [AuthController::class, 'login'])->middleware('throttle:admin-login');
    });
    Route::middleware('auth')->group(function () {
        Route::get('/', [DashboardController::class, 'index'])->name('dashboard');
        Route::get('devices', [DeviceController::class, 'index'])->name('devices');
        Route::get('devices/{device}', [DeviceController::class, 'show'])->name('devices.show');
        Route::get('events', [EventController::class, 'index'])->name('events');
        Route::get('feedback', [FeedbackController::class, 'index'])->name('feedback');
        Route::get('feedback/{feedback}', [FeedbackController::class, 'show'])->name('feedback.show');
        Route::post('feedback/{feedback}', [FeedbackController::class, 'update'])->name('feedback.update');
        Route::get('settings', [SettingController::class, 'edit'])->name('settings');
        Route::post('settings', [SettingController::class, 'update'])->name('settings.update');
        Route::post('settings/password', [SettingController::class, 'password'])->name('settings.password');
        Route::post('logout', [AuthController::class, 'logout'])->name('logout');
    });
});
