<?php

namespace App\Http\Controllers\Admin;

use App\Http\Controllers\Controller;
use App\Models\Device;
use Illuminate\Http\Request;

class DeviceController extends Controller
{
    public function index(Request $request)
    {
        $q = Device::query();
        if ($s = trim((string) $request->query('q'))) {
            $q->where(fn ($w) => $w->where('id', 'like', "$s%")->orWhere('last_ip', $s));
        }
        if ($p = $request->query('platform')) $q->where('platform', $p);
        if ($v = $request->query('version')) $q->where('app_version', $v);
        if ($request->query('state') === 'online') $q->online();
        if ($request->query('state') === 'test') $q->where('is_test', true);
        $devices = $q->orderByDesc('last_seen_at')->paginate(30)->withQueryString();
        $platforms = Device::distinct()->orderBy('platform')->pluck('platform');
        $versions = Device::distinct()->orderByDesc('app_version')->pluck('app_version');
        return view('admin.devices', compact('devices', 'platforms', 'versions'));
    }

    /** 标记 / 取消测试机：测试机（CI 自动测试等）不计入统计 */
    public function toggleTest(Device $device)
    {
        $device->update(['is_test' => ! $device->is_test]);
        return back()->with('ok', $device->is_test ? '已标记为测试机，统计中不再计入' : '已取消测试机标记');
    }

    public function show(Device $device)
    {
        $events = $device->events()->orderByDesc('id')->paginate(50);
        $feedback = $device->feedback()->orderByDesc('id')->limit(20)->get();
        return view('admin.device', compact('device', 'events', 'feedback'));
    }
}
