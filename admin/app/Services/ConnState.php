<?php

namespace App\Services;

use App\Models\Device;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;

/**
 * 设备的连接状态：根据上报的事件推算。
 *
 * * connect_ok / heartbeat → 连接中（heartbeat 是 1.1.8 起 App 连接期间每 5 分钟发的，只更新状态，不存成事件）
 * * disconnect → 已断开；connect_fail → 连接失败；core_exit（内核意外退出）→ 已断开
 * * app_start → App 重新打开了，上一次的连接一定已经结束（App 退出时内核也会被结束）→ 已断开；
 *   旧版被直接关掉、没来得及上报“断开”的，下次打开时就会被纠正
 * * 旧版没有心跳：只能根据最后一次连接事件推测，App 被直接杀掉时会一直显示“连接中”，所以页面上分开标注
 */
class ConnState
{
    /** 认为“此刻在线”的心跳间隔：App 每 5 分钟发一次、最多攒 5 分钟才上报，留些余量 */
    public const HEARTBEAT_FRESH_MIN = 12;

    /** 没有心跳的旧版：最后一次连接事件超过这么久就不再算“推测在线” */
    public const LEGACY_MAX_HOURS = 72;

    /** 事件里的客户端时间（Unix 秒）合理就用它，否则用服务器时间 */
    private static function at(array $e, Carbon $now): Carbon
    {
        $ts = $e['ts'] ?? null;
        if (is_numeric($ts)) {
            $t = Carbon::createFromTimestamp((int) $ts);
            if ($t->between($now->copy()->subDays(2), $now->copy()->addMinutes(10))) return $t;
        }
        return $now->copy();
    }

    /**
     * 按顺序应用一批事件，返回要更新到 devices 的字段（没有连接相关事件时返回空数组）
     * @param array<int, array{type:string, data:array, ts?:mixed}> $events
     */
    public static function apply(Device $dev, array $events, Carbon $now): array
    {
        $u = [];
        $state = $dev->conn_state;
        foreach ($events as $e) {
            $d = $e['data'] ?? [];
            $at = self::at($e, $now);
            switch ($e['type']) {
                case 'connect_ok':
                case 'heartbeat':
                    $isHb = $e['type'] === 'heartbeat';
                    // 连接成功 = 新的一次连接；心跳只在之前不是“连接中”时才算新连接（比如断开事件丢了）。
                    // 心跳里带了 since（App 记录的连接开始时间）就用它
                    if (! $isHb || $state !== 'connected') {
                        $u['conn_since'] = $isHb && is_numeric($d['since'] ?? null)
                            ? Carbon::createFromTimestamp((int) $d['since']) : $at;
                        $u['conn_changed_at'] = $at;
                    }
                    $state = 'connected';
                    $u['conn_state'] = 'connected';
                    if (isset($d['node'])) $u['conn_node'] = mb_substr((string) $d['node'], 0, 191);
                    if (isset($d['tun'])) $u['conn_tun'] = (bool) $d['tun'];
                    if (isset($d['route'])) $u['conn_route'] = mb_substr((string) $d['route'], 0, 16);
                    if ($isHb) {
                        $u['heartbeat_at'] = $now->copy();
                        $u['hb_down'] = max(0, (int) ($d['down'] ?? 0));
                        $u['hb_up'] = max(0, (int) ($d['up'] ?? 0));
                    }
                    break;
                case 'app_start':
                    if ($state !== 'connected') break;
                    // no break：按断开处理
                case 'disconnect':
                case 'core_exit':
                    $state = 'disconnected';
                    $u['conn_state'] = 'disconnected';
                    $u['conn_changed_at'] = $at;
                    $u['heartbeat_at'] = null;
                    break;
                case 'connect_fail':
                    $state = 'failed';
                    $u['conn_state'] = 'failed';
                    $u['conn_changed_at'] = $at;
                    $u['heartbeat_at'] = null;
                    if (isset($d['node'])) $u['conn_node'] = mb_substr((string) $d['node'], 0, 191);
                    break;
            }
        }
        return $u;
    }

    /** 用已有事件推算每台设备的当前状态（部署时运行一次：php artisan koyun:conn-backfill） */
    public static function backfill(): int
    {
        $types = ['connect_ok', 'connect_fail', 'disconnect', 'core_exit', 'app_start'];
        $n = 0;
        $latest = DB::table('client_events')->whereIn('type', $types)
            ->selectRaw('device_id, MAX(id) id')->groupBy('device_id')->pluck('id', 'device_id');
        foreach ($latest->chunk(500) as $chunk) {
            $rows = DB::table('client_events')->whereIn('id', $chunk->values())->get();
            foreach ($rows as $r) {
                $dev = Device::find($r->device_id);
                if (! $dev) continue;
                $u = self::apply($dev, [['type' => $r->type, 'data' => json_decode($r->data, true) ?: [], 'ts' => $r->ts]],
                    Carbon::parse($r->created_at));
                unset($u['heartbeat_at']);
                if ($u) {
                    $dev->update($u);
                    $n++;
                }
            }
        }
        return $n;
    }
}
