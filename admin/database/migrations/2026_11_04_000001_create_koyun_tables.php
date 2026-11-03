<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        // 后台管理员
        Schema::create('admins', function (Blueprint $t) {
            $t->id();
            $t->string('email')->unique();
            $t->string('password');
            $t->rememberToken();
            $t->timestamp('last_login_at')->nullable();
            $t->string('last_login_ip', 64)->nullable();
            $t->timestamps();
        });

        // 设备（App 首次启动随机生成的匿名编号）
        Schema::create('devices', function (Blueprint $t) {
            $t->char('id', 32)->primary();
            $t->string('platform', 16)->index();
            $t->string('os_version', 191)->nullable();
            $t->string('app_version', 32)->nullable()->index();
            $t->string('core_version', 32)->nullable();
            $t->string('locale', 32)->nullable();
            $t->string('first_ip', 64)->nullable();
            $t->string('last_ip', 64)->nullable();
            $t->unsignedInteger('events_count')->default(0);
            $t->timestamp('first_seen_at')->nullable();
            $t->timestamp('last_seen_at')->nullable()->index();
        });

        // 事件（启动 / 连接成功失败 / 断开 / 崩溃）
        Schema::create('client_events', function (Blueprint $t) {
            $t->id();
            $t->char('device_id', 32)->index();
            $t->string('type', 32);
            $t->unsignedInteger('ts')->nullable(); // 客户端时间（Unix 秒）
            $t->json('data')->nullable();
            $t->string('ip', 64)->nullable();
            $t->timestamp('created_at')->useCurrent();
            $t->index(['type', 'created_at']);
            $t->index('created_at');
        });

        // 用户反馈
        Schema::create('feedback', function (Blueprint $t) {
            $t->id();
            $t->char('device_id', 32)->index();
            $t->text('content');
            $t->string('contact', 191)->nullable();
            $t->string('email', 191)->nullable()->index();
            $t->mediumText('logs')->nullable();
            $t->json('extra')->nullable();
            $t->json('device')->nullable();
            $t->string('ip', 64)->nullable();
            $t->string('status', 16)->default('new')->index(); // new 待处理 / doing 处理中 / done 已处理
            $t->text('admin_note')->nullable();
            $t->timestamps();
        });

        // 简单的键值设置（更新信息等）
        Schema::create('settings', function (Blueprint $t) {
            $t->string('key', 64)->primary();
            $t->json('value')->nullable();
            $t->timestamp('updated_at')->nullable();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('settings');
        Schema::dropIfExists('feedback');
        Schema::dropIfExists('client_events');
        Schema::dropIfExists('devices');
        Schema::dropIfExists('admins');
    }
};
