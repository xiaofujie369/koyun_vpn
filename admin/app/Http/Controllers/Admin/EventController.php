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
        if ($s = trim((string) $request->query('q'))) {
            $q->where('data', 'like', '%' . str_replace(['%', '_'], ['\%', '\_'], $s) . '%');
        }
        $events = $q->orderByDesc('id')->paginate(50)->withQueryString();
        return view('admin.events', ['events' => $events, 'types' => ClientEvent::TYPES]);
    }
}
