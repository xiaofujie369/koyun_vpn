<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;

/** 校验 App 请求头 X-Koyun-Key（和 App 编译参数 KOYUN_STATS_KEY 一致） */
class ClientKey
{
    public function handle(Request $request, Closure $next)
    {
        $key = (string) config('koyun.client_key');
        if ($key === '' || ! hash_equals($key, (string) $request->header('X-Koyun-Key'))) {
            return response()->json(['message' => 'unauthorized'], 401);
        }
        return $next($request);
    }
}
