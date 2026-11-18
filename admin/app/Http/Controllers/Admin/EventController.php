<?php

namespace App\Http\Controllers\Admin;

use App\Http\Controllers\Controller;
use App\Models\ClientEvent;
use Illuminate\Http\Request;

class EventController extends Controller
{
    public function index(Request $request)
    {
        $q = ClientEvent::query();
        if ($t = $request->query('type')) $q->where('type', $t);
        if ($d = trim((string) $request->query('device'))) $q->where('device_id', 'like', "$d%");
        if ($date = $request->query('date')) $q->whereDate('created_at', $date);
        $p = $request->query('platform');
        $v = $request->query('version');
        if ($p || $v) {
            $q->whereIn('device_id', \App\Models\Device::query()
                ->when($p, fn ($w) => $w->where('platform', $p))
                ->when($v, fn ($w) => $w->where('app_version', $v))->select('id'));
        }
        if ($s = trim((string) $request->query('q'))) {
            $q->where('data', 'like', '%' . str_replace(['%', '_'], ['\%', '\_'], $s) . '%');
        }
        $events = $q->orderByDesc('id')->paginate(50)->withQueryString();
        return view('admin.events', [
            'events' => $events,
            'types' => ClientEvent::TYPES,
            'platforms' => \App\Models\Device::distinct()->orderBy('platform')->pluck('platform'),
            'versions' => \App\Models\Device::distinct()->orderByDesc('app_version')->pluck('app_version'),
        ]);
    }
}
