<?php
declare(strict_types=1);
// 运行：php test.php
require __DIR__ . '/lib.php';

$failed = 0;
function check(string $name, bool $ok): void
{
    global $failed;
    echo ($ok ? '通过  ' : '失败  ') . $name . PHP_EOL;
    if (!$ok) {
        $failed++;
    }
}

$cfg = ['allowed_hosts' => ['sub.example.com'], 'subscribe_path' => 's'];
$tok = str_repeat('a1', 16);
check('接受 /s/ 订阅链接', koyun_upstream_path("https://sub.example.com/s/$tok", $cfg) === "/s/$tok");
check('接受带 flag 参数的链接', koyun_upstream_path("https://sub.example.com/s/$tok?flag=clash", $cfg) === "/s/$tok");
check('接受 token 形式链接', koyun_upstream_path("https://SUB.example.com/api/v1/client/subscribe?token=$tok", $cfg) === "/api/v1/client/subscribe?token=$tok");
check('拒绝其它域名', koyun_upstream_path("https://evil.com/s/$tok", $cfg) === null);
check('拒绝用户名伪装域名', koyun_upstream_path("https://sub.example.com@evil.com/s/$tok", $cfg) === null);
check('拒绝内网地址', koyun_upstream_path("http://127.0.0.1/s/$tok", $cfg) === null);
check('拒绝 file 协议', koyun_upstream_path('file:///etc/passwd', $cfg) === null);
check('拒绝路径穿越', koyun_upstream_path("https://sub.example.com/s/../../$tok", $cfg) === null);
check('拒绝令牌含特殊字符', koyun_upstream_path("https://sub.example.com/api/v1/client/subscribe?token=$tok%26x=1", $cfg) === null);
check('拒绝空内容', koyun_upstream_path('', $cfg) === null);

$info = koyun_parse_userinfo('upload=1; download=2; total=30; expire=40');
check('解析流量信息', $info === ['upload' => 1, 'download' => 2, 'total' => 30, 'expire' => 40]);
check('没有流量信息时为 0', koyun_parse_userinfo(null)['total'] === 0);

$src = json_encode(['outbounds' => [
    ['type' => 'selector', 'tag' => 'proxy'],
    ['type' => 'direct', 'tag' => 'direct'],
    ['type' => 'anytls', 'tag' => '节点A', 'headers' => new stdClass()],
    ['type' => 'vless', 'tag' => '剩余流量：1GB'],
    ['type' => 'hysteria2', 'tag' => '节点B/https'],
]]);
$file = koyun_build_file($src, $info, 1000);
$doc = json_decode($file['content']);
check('只保留真实节点', $file['count'] === 2);
check('写入流量信息', $doc->koyun->total === 30 && $doc->koyun->created_at === 1000);
check('空对象不会变成数组', str_contains($file['content'], '"headers": {}'));
check('中文和斜杠不转义', str_contains($file['content'], '节点B/https'));
check('非 JSON 返回空', koyun_build_file('proxies: []', $info, 1) === null);
check('缺少节点列表返回空', koyun_build_file('{"dns":{}}', $info, 1) === null);

$rate = tempnam(sys_get_temp_dir(), 'koyun-rate');
check('限速内放行', koyun_rate_allowed($rate, '1.1.1.1', 2, 600) && koyun_rate_allowed($rate, '1.1.1.1', 2, 601));
check('超过限速拒绝', !koyun_rate_allowed($rate, '1.1.1.1', 2, 602));
check('其它 IP 不受影响', koyun_rate_allowed($rate, '2.2.2.2', 2, 603));
check('下一分钟恢复', koyun_rate_allowed($rate, '1.1.1.1', 2, 661));
unlink($rate);

echo $failed === 0 ? "全部通过\n" : "$failed 项失败\n";
exit($failed === 0 ? 0 : 1);
