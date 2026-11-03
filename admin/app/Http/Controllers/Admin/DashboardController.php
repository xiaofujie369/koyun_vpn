<?php

namespace App\Http\Controllers\Admin;

use App\Http\Controllers\Controller;
use App\Models\Device;
use App\Models\Feedback;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\DB;

class DashboardController extends Controller
{
    public function index()
    {
        // 统计结果缓存 2 分钟，避免频繁扫表
        $s = Cache::remember('koyun_dashboard', 120, fn () => $this->stats());
        $s['feedback_new'] = Feedback::where('status', 'new')->count();
        return view('admin.dashboard', $s);
    }

    private function stats(): array
    {
        $today = now()->startOfDay();
        $d7 = now()->subDays(7);
        $d30 = now()->subDays(30);

        $active = fn ($since) => DB::table('client_events')->where('created_at', '>=', $since)->distinct()->count('device_id');
        $byType = DB::table('client_events')->where('created_at', '>=', $today)
            ->selectRaw('type, COUNT(*) c')->groupBy('type')->pluck('c', 'type');
        $ok = (int) ($byType['connect_ok'] ?? 0);
        $fail = (int) ($byType['connect_fail'] ?? 0);

        // 近 14 天每日活跃设备 / 新设备
        $start = now()->subDays(13)->startOfDay();
        $dau = DB::table('client_events')->where('created_at', '>=', $start)
            ->selectRaw('DATE(created_at) d, COUNT(DISTINCT device_id) c')->groupBy('d')->pluck('c', 'd');
        $newDev = DB::table('devices')->where('first_seen_at', '>=', $start)
            ->selectRaw('DATE(first_seen_at) d, COUNT(*) c')->groupBy('d')->pluck('c', 'd');
        $days = [];
        for ($i = 0; $i < 14; $i++) {
            $d = $start->copy()->addDays($i)->toDateString();
            $days[] = ['d' => substr($d, 5), 'active' => (int) ($dau[$d] ?? 0), 'new' => (int) ($newDev[$d] ?? 0)];
        }

        // 近 30 天活跃设备的平台 / 版本分布
        $platforms = Device::where('last_seen_at', '>=', $d30)->selectRaw('platform k, COUNT(*) c')
            ->groupBy('platform')->orderByDesc('c')->pluck('c', 'k');
        $versions = Device::where('last_seen_at', '>=', $d30)->selectRaw('app_version k, COUNT(*) c')
            ->groupBy('app_version')->orderByDesc('c')->limit(8)->pluck('c', 'k');

        // 近 7 天各节点连接情况（失败多的排前面）
        $nodes = DB::table('client_events')->whereIn('type', ['connect_ok', 'connect_fail'])->where('created_at', '>=', $d7)
            ->selectRaw("JSON_UNQUOTE(JSON_EXTRACT(data, '$.node')) node,
                SUM(type = 'connect_ok') ok, SUM(type = 'connect_fail') fail,
                ROUND(AVG(CASE WHEN type = 'connect_ok' THEN JSON_EXTRACT(data, '$.ms') END)) ms")
            ->groupBy('node')->orderByDesc('fail')->orderByDesc('ok')->limit(15)->get();

        // 近 7 天连接失败原因排行
        $errors = DB::table('client_events')->where('type', 'connect_fail')->where('created_at', '>=', $d7)
            ->selectRaw("LEFT(JSON_UNQUOTE(JSON_EXTRACT(data, '$.error')), 160) e, COUNT(*) c")
            ->groupBy('e')->orderByDesc('c')->limit(8)->get();

        return [
            'active_today' => $active($today),
            'active_7d' => $active($d7),
            'devices_total' => Device::count(),
            'new_today' => Device::where('first_seen_at', '>=', $today)->count(),
            'conn_ok' => $ok,
            'conn_fail' => $fail,
            'conn_rate' => $ok + $fail > 0 ? round($ok * 100 / ($ok + $fail), 1) : null,
            'crash_today' => (int) ($byType['crash'] ?? 0),
            'days' => $days,
            'platforms' => $platforms,
            'versions' => $versions,
            'nodes' => $nodes,
            'fail_reasons' => $errors,
            'generated_at' => now()->format('H:i:s'),
        ];
    }
}
