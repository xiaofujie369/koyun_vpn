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
    ];

    public function device()
    {
        return $this->belongsTo(Device::class, 'device_id');
    }
}
