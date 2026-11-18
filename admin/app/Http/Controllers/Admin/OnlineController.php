<?php

namespace App\Http\Controllers\Admin;

use App\Http\Controllers\Controller;
use App\Models\Device;
use Illuminate\Http\Request;

/** 实时在线：正在连接的设备 */
class OnlineController extends Controller
{
    public function index(Request $request)
    {
        $base = Device::online();
        if (! $request->boolean('test')) $base->real();
        if (! $request->boolean('legacy', true)) $base->whereNotNull('heartbeat_at');

        $all = (clone $base)->get(['id', 'platform', 'app_version', 'conn_node', 'conn_tun', 'heartbeat_at']);
        $summary = [
            'total' => $all->count(),
            'confirmed' => $all->filter->online_confirmed->count(),
            'tun' => $all->where('conn_tun', true)->count(),
            'platforms' => $all->countBy('platform')->sortDesc(),
            'nodes' => $all->countBy(fn ($d) => $d->conn_node ?: '（未知）')->sortDesc()->take(12),
            'versions' => $all->countBy('app_version')->sortKeysDesc(),
        ];

        $q = clone $base;
        if ($p = $request->query('platform')) $q->where('platform', $p);
        if ($n = $request->query('node')) $q->where('conn_node', $n);
        $devices = $q->orderByDesc('conn_since')->paginate(50)->withQueryString();

        return view('admin.online', compact('devices', 'summary'));
    }
}
