<?php
// 复制成 config.php 后填写。config.php 只放在服务器上，不进仓库（仓库是公开的）。
return [
    // 接受哪些域名开头的订阅链接（小写）。其它链接一律拒绝。
    'allowed_hosts' => ['sub.example.com'],
    // 服务器实际去哪里取订阅。只用这个固定地址，绝不访问客户填写的域名。
    'upstream' => 'https://panel.example.com',
    // 直接连本机面板，不绕外网和 Cloudflare。格式 域名:端口:IP；留空则走正常解析。
    'resolve' => 'panel.example.com:443:127.0.0.1',
    // Xboard 后台的「订阅路径」
    'subscribe_path' => 's',
    // 和 App 内置的 sing-box 版本一致，Xboard 才会下发全部节点
    'user_agent' => 'sing-box/1.14.4',
    // 网站在 Cloudflare 后面时为 true，用真实访客 IP 限速
    'behind_cloudflare' => true,
    // 每个 IP 每分钟最多转换几次
    'rate_limit_per_minute' => 10,
];
