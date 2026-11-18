<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class Device extends Model
{
    public $incrementing = false;
    protected $keyType = 'string';
    public $timestamps = false;
    protected $guarded = [];
    protected $casts = [
        'first_seen_at' => 'datetime', 'last_seen_at' => 'datetime', 'conn_since' => 'datetime',
        'conn_changed_at' => 'datetime', 'heartbeat_at' => 'datetime', 'conn_tun' => 'boolean', 'is_test' => 'boolean',
    ];

    /** 统计时排除测试机（CI 等） */
    public function scopeReal($q)
    {
        return $q->where('is_test', false);
    }

    /** 实时在线：有新鲜心跳（1.1.8+），或旧版最后一次连接事件是“连接成功”且不太久 */
    public function scopeOnline($q)
    {
        return $q->where('conn_state', 'connected')->where(fn ($w) => $w
            ->where('heartbeat_at', '>=', now()->subMinutes(\App\Services\ConnState::HEARTBEAT_FRESH_MIN))
            ->orWhere(fn ($x) => $x->whereNull('heartbeat_at')
                ->where('conn_changed_at', '>=', now()->subHours(\App\Services\ConnState::LEGACY_MAX_HOURS))));
    }

    /** 这台设备的在线状态是心跳确认的，还是旧版推测的 */
    public function getOnlineConfirmedAttribute(): bool
    {
        return $this->heartbeat_at !== null
            && $this->heartbeat_at->gte(now()->subMinutes(\App\Services\ConnState::HEARTBEAT_FRESH_MIN));
    }

    public function events()
    {
        return $this->hasMany(ClientEvent::class, 'device_id');
    }

    public function feedback()
    {
        return $this->hasMany(Feedback::class, 'device_id');
    }
}
