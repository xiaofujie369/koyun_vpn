<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

// 实时在线：设备当前的连接状态（由上报的事件推算；1.1.8 起 App 连接中每 5 分钟发心跳）
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('devices', function (Blueprint $t) {
            $t->string('conn_state', 16)->nullable()->index(); // connected / disconnected / failed
            $t->string('conn_node', 191)->nullable();
            $t->boolean('conn_tun')->nullable();
            $t->string('conn_route', 16)->nullable();
            $t->timestamp('conn_since')->nullable();
            $t->timestamp('conn_changed_at')->nullable();
            $t->timestamp('heartbeat_at')->nullable()->index();
            $t->unsignedBigInteger('hb_down')->nullable(); // 心跳时的下载速度 B/s
            $t->unsignedBigInteger('hb_up')->nullable();
            $t->boolean('is_test')->default(false)->index(); // 测试机（CI 等），统计时排除
        });
    }

    public function down(): void
    {
        Schema::table('devices', function (Blueprint $t) {
            $t->dropColumn(['conn_state', 'conn_node', 'conn_tun', 'conn_route', 'conn_since', 'conn_changed_at',
                'heartbeat_at', 'hb_down', 'hb_up', 'is_test']);
        });
    }
};
