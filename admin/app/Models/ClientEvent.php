<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class ClientEvent extends Model
{
    protected $table = 'client_events';
    public const UPDATED_AT = null;
    protected $guarded = [];
    protected $casts = ['data' => 'array', 'created_at' => 'datetime'];

    /** 事件类型中文名 */
    public const TYPES = [
        'app_start' => '启动',
        'connect_ok' => '连接成功',
        'connect_fail' => '连接失败',
        'disconnect' => '断开',
        'crash' => '崩溃',
        'core_exit' => '内核退出',
        'core_recover' => '自动恢复',
        'node_unreachable' => '节点不通',
        'proxy_guard' => '代理被改回',
        'net_reset' => '网络切换',
    ];

    /** 连接失败原因（1.1.7 起 App 上报 kind） */
    public const FAIL_KINDS = [
        'nodeUnreachable' => '节点连不通（可能被封）',
        'tunAdapter' => 'TUN 网卡创建失败',
        'macNotAdmin' => 'Mac 非管理员账号',
    ];

    public function device()
    {
        return $this->belongsTo(Device::class, 'device_id');
    }
}
