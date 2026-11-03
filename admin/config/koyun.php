<?php

return [
    // 后台管理路径（随机，类似 Xboard 的 secure_path），在 .env 设置 ADMIN_PATH
    'admin_path' => env('ADMIN_PATH', 'admin-' . substr(md5((string) env('APP_KEY')), 0, 8)),

    // 客户端密钥：App 编译参数 KOYUN_STATS_KEY 必须和它一致（请求头 X-Koyun-Key）
    'client_key' => env('CLIENT_KEY', ''),

    // 事件保留天数（每天自动清理更早的事件；反馈不会自动删除）
    'retention_days' => (int) env('EVENT_RETENTION_DAYS', 90),
];
