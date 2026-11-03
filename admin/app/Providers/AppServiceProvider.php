<?php

namespace App\Providers;

use Illuminate\Cache\RateLimiting\Limit;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\RateLimiter;
use Illuminate\Support\ServiceProvider;

class AppServiceProvider extends ServiceProvider
{
    public function register(): void
    {
    }

    public function boot(): void
    {
        // 防刷：按设备 + IP 限制频率
        $who = fn (Request $r) => substr((string) $r->header('X-Koyun-Device'), 0, 32) . '|' . $r->ip();
        RateLimiter::for('client-events', fn (Request $r) => Limit::perMinute(30)->by($who($r)));
        RateLimiter::for('client-feedback', fn (Request $r) => [
            Limit::perMinutes(10, 5)->by($who($r)),
            Limit::perDay(30)->by($r->ip()),
        ]);
        RateLimiter::for('admin-login', fn (Request $r) => Limit::perMinute(5)->by($r->ip()));
    }
}
