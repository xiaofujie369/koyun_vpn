<?php

namespace Tests\Feature;

use App\Models\Admin;
use App\Models\Device;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Tests\TestCase;

/** 实时在线 / 测试机 / 新事件在后台页面上的表现 */
class OnlineTest extends TestCase
{
    use RefreshDatabase;

    private function report(string $id, array $events, string $version = '1.1.7', string $platform = 'windows')
    {
        return $this->withHeader('X-Koyun-Key', 'k')->postJson('/api/v1/client/events', [
            'device' => ['id' => $id, 'platform' => $platform, 'app_version' => $version],
            'events' => $events,
        ]);
    }

    private function admin()
    {
        return $this->actingAs(Admin::create(['email' => 'a@example.com', 'password' => bcrypt('x')]));
    }

    public function test_connect_and_disconnect_update_state(): void
    {
        $id = str_repeat('a', 32);
        $this->report($id, [['type' => 'connect_ok', 'data' => ['node' => '香港01', 'tun' => true, 'route' => 'rule']]])->assertOk();
        $d = Device::find($id);
        $this->assertSame('connected', $d->conn_state);
        $this->assertSame('香港01', $d->conn_node);
        $this->assertTrue($d->conn_tun);
        $this->assertNotNull($d->conn_since);
        $this->assertSame(1, Device::online()->count(), '旧版（无心跳）连接成功后算“推测在线”');
        $this->assertFalse($d->online_confirmed);

        $this->report($id, [['type' => 'disconnect', 'data' => ['node' => '香港01']]])->assertOk();
        $this->assertSame('disconnected', Device::find($id)->conn_state);
        $this->assertSame(0, Device::online()->count());
    }

    public function test_heartbeat_marks_online_and_is_not_stored(): void
    {
        $id = str_repeat('b', 32);
        $since = now()->subHour()->timestamp;
        $this->report($id, [['type' => 'heartbeat', 'data' => ['node' => '日本02', 'tun' => false, 'down' => 2048, 'up' => 100, 'since' => $since]]], '1.1.8')
            ->assertOk()->assertJson(['accepted' => 1]);
        $this->assertSame(0, DB::table('client_events')->where('type', 'heartbeat')->count(), '心跳不存成事件');
        $d = Device::find($id);
        $this->assertTrue($d->online_confirmed);
        $this->assertSame(2048, (int) $d->hb_down);
        $this->assertSame($since, $d->conn_since->timestamp, '用 App 带来的连接开始时间');

        // 心跳过期：不再算在线
        $d->update(['heartbeat_at' => now()->subMinutes(30)]);
        $this->assertSame(0, Device::online()->count());
    }

    public function test_failed_connect_and_core_exit(): void
    {
        $id = str_repeat('c', 32);
        $this->report($id, [
            ['type' => 'connect_ok', 'data' => ['node' => 'A']],
            ['type' => 'connect_fail', 'data' => ['node' => 'B', 'kind' => 'nodeUnreachable', 'error' => 'node unreachable']],
        ])->assertOk();
        $this->assertSame('failed', Device::find($id)->conn_state);
        $this->report($id, [['type' => 'connect_ok', 'data' => ['node' => 'C']], ['type' => 'core_exit', 'data' => ['error' => 'x']]]);
        $this->assertSame('disconnected', Device::find($id)->conn_state);
    }

    public function test_backfill_from_existing_events(): void
    {
        $id = str_repeat('d', 32);
        Device::create(['id' => $id, 'platform' => 'android', 'app_version' => '1.1.6', 'last_seen_at' => now()]);
        DB::table('client_events')->insert([
            ['device_id' => $id, 'type' => 'connect_ok', 'data' => json_encode(['node' => 'X', 'tun' => true]), 'created_at' => now()->subMinutes(5)],
        ]);
        $this->artisan('koyun:conn-backfill')->assertSuccessful();
        $this->assertSame('connected', Device::find($id)->conn_state);
        $this->assertSame('X', Device::find($id)->conn_node);
    }

    public function test_admin_pages_render_and_test_devices_are_excluded(): void
    {
        $real = str_repeat('e', 32);
        $ci = str_repeat('f', 32);
        // 先连日本被封（不通），再换香港01 连上：最后的状态是“连接中 · 香港01”
        $this->report($real, [
            ['type' => 'node_unreachable', 'data' => ['node' => '日本被封', 'after' => 'switch']],
            ['type' => 'connect_fail', 'data' => ['node' => '日本被封', 'kind' => 'nodeUnreachable', 'error' => 'node unreachable']],
            ['type' => 'proxy_guard', 'data' => []],
            ['type' => 'connect_ok', 'data' => ['node' => '香港01', 'tun' => true]],
        ]);
        $this->report($ci, [['type' => 'connect_ok', 'data' => ['node' => 'CI节点']]], '1.1.7', 'macos');
        $this->admin();
        $this->post('/adm/devices/' . $ci . '/test')->assertRedirect();
        $this->assertTrue(Device::find($ci)->is_test);

        $this->get('/adm/online')->assertOk()->assertSee('香港01')->assertDontSee('CI节点')->assertSee('推测');
        $this->get('/adm/online?test=1')->assertOk()->assertSee('CI节点');
        $this->get('/adm')->assertOk()->assertSee('节点健康')->assertSee('日本被封')->assertSee('版本升级进度')
            ->assertSee('节点连不通（可能被封）')->assertSee('已排除 1 台测试机');
        $this->get('/adm/devices?state=online')->assertOk()->assertSee(substr($real, 0, 12));
        $this->get('/adm/devices/' . $real)->assertOk()->assertSee('标记为测试机');
        $this->get('/adm/events?platform=windows&version=1.1.7')->assertOk()->assertSee('切换后检测不通')
            ->assertSee('系统代理被其他软件改掉');
    }
}
