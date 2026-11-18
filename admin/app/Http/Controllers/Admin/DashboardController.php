<?php

namespace App\Http\Controllers\Admin;

use App\Http\Controllers\Controller;
use App\Models\Device;
use App\Models\Feedback;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\DB;
use App\Services\Json;

class DashboardController extends Controller
{
    public function index()
    {
        // 统计结果缓存 2 分钟，避免频繁扫表
        $s = Cache::remember('koyun_dashboard', 120, fn () => $this->stats());
        $s['feedback_new'] = Feedback::where('status', 'new')->count();
        $s['online'] = Device::online()->real()->count();
        return view('admin.dashboard', $s);
    }

    private function stats(): array
    {
        $today = now()->startOfDay();
        $d7 = now()->subDays(7);
        $d30 = now()->subDays(30);

        // 测试机（CI 等）不计入
        $tests = DB::table('devices')->where('is_test', true)->pluck('id');
        $ev = fn () => DB::table('client_events')->whereNotIn('device_id', $tests);
        $active = fn ($since) => $ev()->where('created_at', '>=', $since)->distinct()->count('device_id');
        $byType = $ev()->where('created_at', '>=', $today)
            ->selectRaw('type, COUNT(*) c')->groupBy('type')->pluck('c', 'type');
        $ok = (int) ($byType['connect_ok'] ?? 0);
        $fail = (int) ($byType['connect_fail'] ?? 0);

        // 近 14 天每日活跃设备 / 新设备
        $start = now()->subDays(13)->startOfDay();
        $dau = $ev()->where('created_at', '>=', $start)
            ->selectRaw('DATE(created_at) d, COUNT(DISTINCT device_id) c')->groupBy('d')->pluck('c', 'd');
        $newDev = DB::table('devices')->where('is_test', false)->where('first_seen_at', '>=', $start)
            ->selectRaw('DATE(first_seen_at) d, COUNT(*) c')->groupBy('d')->pluck('c', 'd');
        $days = [];
        for ($i = 0; $i < 14; $i++) {
            $d = $start->copy()->addDays($i)->toDateString();
            $days[] = ['d' => substr($d, 5), 'active' => (int) ($dau[$d] ?? 0), 'new' => (int) ($newDev[$d] ?? 0)];
        }

        // 近 30 天活跃设备的平台 / 版本分布
        $platforms = Device::real()->where('last_seen_at', '>=', $d30)->selectRaw('platform k, COUNT(*) c')
            ->groupBy('platform')->orderByDesc('c')->pluck('c', 'k');
        $versions = Device::real()->where('last_seen_at', '>=', $d30)->selectRaw('app_version k, COUNT(*) c')
            ->groupBy('app_version')->orderByDesc('c')->limit(8)->pluck('c', 'k');

        // 近 7 天各节点连接情况（失败多的排前面）
        $nodeF = Json::field('node');
        $msF = Json::field('ms');
        $nodes = $ev()->whereIn('type', ['connect_ok', 'connect_fail'])->where('created_at', '>=', $d7)
            ->selectRaw("$nodeF node,
                SUM(CASE WHEN type = 'connect_ok' THEN 1 ELSE 0 END) ok, SUM(CASE WHEN type = 'connect_fail' THEN 1 ELSE 0 END) fail,
                ROUND(AVG(CASE WHEN type = 'connect_ok' THEN $msF END)) ms")
            ->groupBy('node')->orderByDesc('fail')->orderByDesc('ok')->limit(15)->get();

        // 近 7 天连接失败原因排行
        $errF = Json::field('error');
        $kindF = Json::field('kind');
        $errors = $ev()->where('type', 'connect_fail')->where('created_at', '>=', $d7)
            ->selectRaw("$kindF k, SUBSTR($errF, 1, 160) e, COUNT(*) c")
            ->groupBy('k', 'e')->orderByDesc('c')->limit(10)->get();

        // 节点健康（近 24 小时，1.1.7 起）：检测不通 = 连接前检测失败 + 连接中 / 切换后检测不通。
        // 不通的比例高、涉及设备多 → 很可能被封
        $h24 = now()->subDay();
        $health = $ev()->where('created_at', '>=', $h24)
            ->where(fn ($w) => $w->where('type', 'connect_ok')->orWhere('type', 'node_unreachable')
                ->orWhere(fn ($x) => $x->where('type', 'connect_fail')->whereRaw("$kindF = 'nodeUnreachable'")))
            ->selectRaw("$nodeF node,
                SUM(CASE WHEN type = 'connect_ok' THEN 1 ELSE 0 END) ok,
                SUM(CASE WHEN type <> 'connect_ok' THEN 1 ELSE 0 END) bad,
                COUNT(DISTINCT CASE WHEN type <> 'connect_ok' THEN device_id END) bad_dev")
            ->groupBy('node')->havingRaw("SUM(CASE WHEN type <> 'connect_ok' THEN 1 ELSE 0 END) > 0")
            ->orderByDesc('bad_dev')->orderByDesc('bad')->limit(15)->get();

        // 版本升级进度（近 7 天活跃）
        $adoption = Device::real()->where('last_seen_at', '>=', $d7)->selectRaw('platform, app_version, COUNT(*) c')
            ->groupBy('platform', 'app_version')->get()->groupBy('platform')
            ->map(fn ($rows) => $rows->sortByDesc('app_version', SORT_NATURAL)->pluck('c', 'app_version'));

        $guard = $ev()->where('type', 'proxy_guard')->where('created_at', '>=', $d7)->count();

        return [
            'active_today' => $active($today),
            'active_7d' => $active($d7),
            'devices_total' => Device::real()->count(),
            'new_today' => Device::real()->where('first_seen_at', '>=', $today)->count(),
            'conn_ok' => $ok,
            'conn_fail' => $fail,
            'conn_rate' => $ok + $fail > 0 ? round($ok * 100 / ($ok + $fail), 1) : null,
            'crash_today' => (int) ($byType['crash'] ?? 0),
            'days' => $days,
            'platforms' => $platforms,
            'versions' => $versions,
            'nodes' => $nodes,
            'fail_reasons' => $errors,
            'health' => $health,
            'adoption' => $adoption,
            'guard_7d' => $guard,
            'tests' => $tests->count(),
            'generated_at' => now()->format('H:i:s'),
        ];
    }
}
