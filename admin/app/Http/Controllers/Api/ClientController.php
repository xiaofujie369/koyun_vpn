<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\ClientEvent;
use App\Models\Device;
use App\Models\Feedback;
use App\Models\Setting;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Artisan;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\DB;

/**
 * App 调用的接口（格式见 koyun_vpn 仓库 docs/后台接口说明.md）
 */
class ClientController extends Controller
{
    /** 校验并更新设备信息，返回设备编号 */
    private function touchDevice(Request $request): ?string
    {
        $d = $request->input('device');
        if (! is_array($d) || ! preg_match('/^[0-9a-f]{32}$/', (string) ($d['id'] ?? ''))) {
            return null;
        }
        $now = now();
        $ip = $request->ip();
        $attrs = [
            'platform' => mb_substr((string) ($d['platform'] ?? 'unknown'), 0, 16),
            'os_version' => mb_substr((string) ($d['os_version'] ?? ''), 0, 191),
            'app_version' => mb_substr((string) ($d['app_version'] ?? ''), 0, 32),
            'core_version' => mb_substr((string) ($d['core_version'] ?? ''), 0, 32),
            'locale' => mb_substr((string) ($d['locale'] ?? ''), 0, 32),
            'last_ip' => $ip,
            'last_seen_at' => $now,
        ];
        $dev = Device::find($d['id']);
        if ($dev) {
            $dev->update($attrs);
        } else {
            Device::create($attrs + ['id' => $d['id'], 'first_ip' => $ip, 'first_seen_at' => $now]);
        }
        return $d['id'];
    }

    /** POST /api/v1/client/events */
    public function events(Request $request)
    {
        $id = $this->touchDevice($request);
        if (! $id) {
            return response()->json(['message' => 'invalid device'], 422);
        }
        $events = $request->input('events');
        if (! is_array($events)) {
            return response()->json(['message' => 'invalid events'], 422);
        }
        $rows = [];
        $now = now();
        foreach (array_slice($events, 0, 50) as $e) {
            if (! is_array($e)) continue;
            $type = (string) ($e['type'] ?? '');
            if (! preg_match('/^[a-z_]{1,32}$/', $type)) continue;
            $data = is_array($e['data'] ?? null) ? $e['data'] : [];
            $json = json_encode($data, JSON_UNESCAPED_UNICODE);
            if ($json === false || strlen($json) > 16000) $json = '{}';
            $rows[] = [
                'device_id' => $id,
                'type' => $type,
                'ts' => is_numeric($e['ts'] ?? null) ? (int) $e['ts'] : null,
                'data' => $json,
                'ip' => $request->ip(),
                'created_at' => $now,
            ];
        }
        if ($rows) {
            DB::table('client_events')->insert($rows);
            Device::whereKey($id)->increment('events_count', count($rows));
        }
        // 每天第一次收到上报时，顺便清理过期事件（在返回响应之后执行，不影响 App；不需要系统定时任务）
        if (Cache::add('koyun_prune_' . now()->toDateString(), 1, now()->addDays(2))) {
            app()->terminating(fn () => Artisan::call('koyun:prune'));
        }
        return response()->json(['ok' => true, 'accepted' => count($rows)]);
    }

    /** POST /api/v1/client/feedback */
    public function feedback(Request $request)
    {
        $id = $this->touchDevice($request);
        if (! $id) {
            return response()->json(['message' => 'invalid device'], 422);
        }
        $content = trim((string) $request->input('content'));
        if ($content === '') {
            return response()->json(['message' => 'empty content'], 422);
        }
        $extra = $request->input('extra');
        Feedback::create([
            'device_id' => $id,
            'content' => mb_substr($content, 0, 2000),
            'contact' => mb_substr((string) $request->input('contact'), 0, 191) ?: null,
            'email' => mb_substr((string) $request->input('email'), 0, 191) ?: null,
            'logs' => ($l = $request->input('logs')) ? mb_substr((string) $l, 0, 200000) : null,
            'extra' => is_array($extra) ? $extra : null,
            'device' => $request->input('device'),
            'ip' => $request->ip(),
            'status' => 'new',
        ]);
        return response()->json(['ok' => true]);
    }

    /** GET /api/v1/client/config —— 最新版本等远程配置 */
    public function config(Request $request)
    {
        $out = [];
        $latest = Setting::val('latest');
        if (is_array($latest) && ! empty($latest['enabled']) && ! empty($latest['version'])) {
            $out['latest'] = [
                'version' => $latest['version'],
                'notes' => $latest['notes'] ?? '',
                'page' => $latest['page'] ?? '',
                'downloads' => array_filter($latest['downloads'] ?? []),
            ];
        }
        return response()->json((object) $out);
    }
}
