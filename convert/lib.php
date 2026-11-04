<?php
declare(strict_types=1);

const KOYUN_PROXY_TYPES = [
    'vless', 'vmess', 'trojan', 'shadowsocks', 'hysteria2', 'hysteria',
    'tuic', 'anytls', 'socks', 'http', 'wireguard', 'shadowtls', 'ssh',
];

// 与 App 的 SubParser 保持一致：Xboard 把流量、到期等信息伪装成的假节点要去掉
const KOYUN_INFO_NODE = '/剩余流量|套餐到期|距离下次重置|过滤掉\d+条线路|到期时间|Traffic\s*:|Expire\s*:|官网|官方网址/iu';

// 客户可选的格式。ua 为 null 时用配置里的 sing-box 版本。
const KOYUN_FORMATS = [
    'koyun' => ['flag' => 'sing-box', 'ua' => null, 'name' => 'koyun-nodes', 'ext' => 'json'],
    'shadowrocket' => ['flag' => 'shadowrocket', 'ua' => 'Shadowrocket/2.2.65', 'name' => 'koyun-shadowrocket', 'ext' => 'txt'],
    'clash' => ['flag' => 'clashmeta', 'ua' => 'clash.meta', 'name' => 'koyun-clash', 'ext' => 'yaml'],
];

/**
 * 从客户粘贴的订阅链接里取出面板上的相对地址，不合法返回 null。
 * 只保留令牌，上游域名永远来自配置，所以客户无法让服务器去访问别的网址。
 */
function koyun_upstream_path(string $link, array $cfg): ?string
{
    $u = parse_url(trim($link));
    if (!is_array($u) || !in_array(strtolower($u['scheme'] ?? ''), ['http', 'https'], true)) {
        return null;
    }
    if (!in_array(strtolower($u['host'] ?? ''), $cfg['allowed_hosts'], true)) {
        return null;
    }
    $path = rtrim($u['path'] ?? '', '/');
    $sub = preg_quote(trim((string) $cfg['subscribe_path'], '/'), '#');
    if (preg_match('#^/' . $sub . '/([A-Za-z0-9]{16,128})$#D', $path, $m)) {
        return '/' . trim((string) $cfg['subscribe_path'], '/') . '/' . $m[1];
    }
    if ($path === '/api/v1/client/subscribe') {
        parse_str($u['query'] ?? '', $q);
        $token = $q['token'] ?? '';
        if (is_string($token) && preg_match('/^[A-Za-z0-9]{16,128}$/D', $token)) {
            return '/api/v1/client/subscribe?token=' . $token;
        }
    }
    return null;
}

/** 解析 subscription-userinfo 响应头 */
function koyun_parse_userinfo(?string $header): array
{
    $info = ['upload' => 0, 'download' => 0, 'total' => 0, 'expire' => 0];
    foreach (explode(';', (string) $header) as $part) {
        $kv = explode('=', $part, 2);
        $key = trim($kv[0]);
        if (count($kv) === 2 && array_key_exists($key, $info)) {
            $info[$key] = (int) trim($kv[1]);
        }
    }
    return $info;
}

/**
 * 把 Xboard 的 sing-box 订阅转换成导入文件。
 * 节点内容原样保留（用对象解码，空的 {} 不会变成 []，否则内核会报错）。
 * 返回 ['content' => 文件文本, 'count' => 节点数]；不是合法订阅返回 null。
 */
function koyun_build_file(string $body, array $info, int $now): ?array
{
    $doc = json_decode($body);
    if (!is_object($doc) || !isset($doc->outbounds) || !is_array($doc->outbounds)) {
        return null;
    }
    $nodes = [];
    foreach ($doc->outbounds as $o) {
        if (!is_object($o) || !in_array($o->type ?? '', KOYUN_PROXY_TYPES, true)) {
            continue;
        }
        $tag = is_string($o->tag ?? null) ? $o->tag : '';
        if ($tag === '' || preg_match(KOYUN_INFO_NODE, $tag)) {
            continue;
        }
        $nodes[] = $o;
    }
    $file = ['koyun' => ['format' => 1, 'created_at' => $now] + $info, 'outbounds' => $nodes];
    return [
        'content' => json_encode($file, JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE | JSON_PRETTY_PRINT),
        'count' => count($nodes),
    ];
}

/** 取分享链接里的节点名称 */
function koyun_link_name(string $line): string
{
    if (stripos($line, 'vmess://') === 0) {
        $json = json_decode((string) base64_decode(substr($line, 8)), true);
        return is_array($json) ? (string) ($json['ps'] ?? '') : '';
    }
    $hash = strrpos($line, '#');
    return $hash === false ? '' : rawurldecode(substr($line, $hash + 1));
}

/** 小火箭：Base64 解开后一行一个节点链接，去掉状态行和流量、到期假节点 */
function koyun_build_links(string $body): ?array
{
    $text = base64_decode(trim($body), true);
    if ($text === false || !str_contains($text, '://')) {
        return null;
    }
    $links = [];
    foreach (preg_split('/\R/', $text) as $line) {
        $line = trim($line);
        if (str_contains($line, '://') && !preg_match(KOYUN_INFO_NODE, koyun_link_name($line))) {
            $links[] = $line;
        }
    }
    return ['content' => implode("\n", $links) . "\n", 'count' => count($links)];
}

/** Clash：YAML 原样提供（策略组引用了全部节点，不能删改），只统计真实节点数 */
function koyun_build_clash(string $body): ?array
{
    if (!preg_match('/^proxies:\s*$(.*?)^proxy-groups:/ms', $body, $m)) {
        return null;
    }
    preg_match_all('/^\s*-\s*\{?\s*name:\s*(.+?)(?:,|$)/m', $m[1], $names);
    $count = 0;
    foreach ($names[1] as $name) {
        if (!preg_match(KOYUN_INFO_NODE, $name)) {
            $count++;
        }
    }
    return ['content' => $body, 'count' => $count];
}

/** 按格式生成文件内容；不是合法订阅返回 null */
function koyun_build(string $format, string $body, array $info, int $now): ?array
{
    return match ($format) {
        'shadowrocket' => koyun_build_links($body),
        'clash' => koyun_build_clash($body),
        default => koyun_build_file($body, $info, $now),
    };
}

/** 每个 IP 的固定窗口限速。记录文件读写失败时放行，不影响正常转换。 */
function koyun_rate_allowed(string $file, string $ip, int $limit, int $now): bool
{
    $fp = @fopen($file, 'c+');
    if ($fp === false) {
        return true;
    }
    flock($fp, LOCK_EX);
    $all = json_decode((string) stream_get_contents($fp), true);
    $window = (int) floor($now / 60);
    $hits = (is_array($all) && ($all['w'] ?? 0) === $window) ? ($all['h'] ?? []) : [];
    $key = hash('sha256', $ip);
    $hits[$key] = ($hits[$key] ?? 0) + 1;
    $allowed = $hits[$key] <= $limit;
    ftruncate($fp, 0);
    rewind($fp);
    fwrite($fp, json_encode(['w' => $window, 'h' => $hits]));
    flock($fp, LOCK_UN);
    fclose($fp);
    return $allowed;
}
