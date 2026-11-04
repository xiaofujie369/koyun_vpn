<?php
declare(strict_types=1);

// 转换接口。不保存、不记录客户的订阅链接和节点内容。
require __DIR__ . '/../lib.php';

header('Content-Type: application/json; charset=utf-8');
header('Cache-Control: no-store');
header('X-Content-Type-Options: nosniff');

function respond(int $status, array $data): never
{
    http_response_code($status);
    echo json_encode($data, JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE);
    exit;
}

function fail(int $status, string $code): never
{
    respond($status, ['ok' => false, 'error' => $code]);
}

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    fail(405, 'method');
}

$cfg = require __DIR__ . '/../config.php';

$ip = $_SERVER['REMOTE_ADDR'] ?? '';
if (!empty($cfg['behind_cloudflare']) && !empty($_SERVER['HTTP_CF_CONNECTING_IP'])) {
    $ip = $_SERVER['HTTP_CF_CONNECTING_IP'];
}
$rateFile = sys_get_temp_dir() . '/koyun-convert-rate.json';
if (!koyun_rate_allowed($rateFile, $ip, (int) $cfg['rate_limit_per_minute'], time())) {
    fail(429, 'rate');
}

$input = json_decode((string) file_get_contents('php://input', false, null, 0, 4096), true);
$path = koyun_upstream_path(is_string($input['link'] ?? null) ? $input['link'] : '', $cfg);
if ($path === null) {
    fail(400, 'link');
}
$formatKey = $input['format'] ?? 'koyun';
if (!is_string($formatKey) || !isset(KOYUN_FORMATS[$formatKey])) {
    fail(400, 'format');
}
$format = KOYUN_FORMATS[$formatKey];

// 最多接收 5 MB，防止异常响应占满内存
$body = '';
$userinfo = null;
$ch = curl_init(rtrim($cfg['upstream'], '/') . $path . (str_contains($path, '?') ? '&' : '?') . 'flag=' . $format['flag']);
curl_setopt_array($ch, [
    CURLOPT_USERAGENT => $format['ua'] ?? $cfg['user_agent'],
    CURLOPT_CONNECTTIMEOUT => 5,
    CURLOPT_TIMEOUT => 25,
    CURLOPT_FOLLOWLOCATION => false,
    CURLOPT_PROTOCOLS => CURLPROTO_HTTPS | CURLPROTO_HTTP,
    CURLOPT_HEADERFUNCTION => function ($c, string $line) use (&$userinfo): int {
        if (stripos($line, 'subscription-userinfo:') === 0) {
            $userinfo = trim(substr($line, strlen('subscription-userinfo:')));
        }
        return strlen($line);
    },
    CURLOPT_WRITEFUNCTION => function ($c, string $chunk) use (&$body): int {
        $body .= $chunk;
        return strlen($body) > 5242880 ? 0 : strlen($chunk);
    },
]);
if (!empty($cfg['resolve'])) {
    curl_setopt($ch, CURLOPT_RESOLVE, [$cfg['resolve']]);
}
$done = curl_exec($ch);
$status = (int) curl_getinfo($ch, CURLINFO_RESPONSE_CODE);
curl_close($ch);

if ($done === false) {
    fail(502, 'upstream');
}
if (in_array($status, [401, 403, 404], true)) {
    fail(403, 'unavailable');
}
if ($status !== 200) {
    fail(502, 'upstream');
}

$info = koyun_parse_userinfo($userinfo);
$now = time();
$file = koyun_build($formatKey, $body, $info, $now);
if ($file === null) {
    fail(502, 'upstream');
}
if ($file['count'] === 0) {
    fail(422, 'empty');
}

respond(200, [
    'ok' => true,
    'filename' => $format['name'] . '-' . gmdate('Ymd', $now) . '.' . $format['ext'],
    'count' => $file['count'],
    'info' => $info,
    'content' => $file['content'],
]);
