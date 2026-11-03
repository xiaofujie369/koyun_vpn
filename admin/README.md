# Koyun 数据管理后台

Laravel 12（和 Xboard 同一套技术）+ MySQL + Redis。接收 App 的统计上报、用户反馈，提供远程配置。
接口格式见仓库 `docs/后台接口说明.md`。

## 功能
- 仪表盘：今日 / 7 日活跃设备、新增设备、连接成功率、近 14 天趋势、平台 / 版本分布、节点连接情况、失败原因排行
- 用户反馈：待处理 / 处理中 / 已处理，查看当时状态和运行日志，写备注
- 设备列表、设备详情（事件时间线）
- 事件日志、崩溃记录（按类型 / 设备 / 日期 / 内容筛选）
- 设置：App 更新信息（App「检查更新」优先读取）、修改密码

## 部署（宝塔）
1. 站点根目录指向 `public/`，伪静态：`location / { try_files $uri $uri/ /index.php?$query_string; }`
2. `public/.user.ini` 写 `open_basedir=站点目录/:/tmp/`（防跨站）
3. 上传代码后：`composer install --no-dev -o`，复制 `.env.example` 为 `.env` 并填写：
   数据库、`REDIS_DB` / `REDIS_CACHE_DB`（不要和 Xboard 用同一个库）、
   `ADMIN_PATH`（后台随机路径）、`CLIENT_KEY`（客户端密钥，和启动引导配置里的 stats.key 一致）
4. `php artisan key:generate && php artisan migrate --force`
5. `php artisan config:cache && php artisan route:cache && php artisan view:cache`
6. 创建管理员 / 重置密码：`php artisan koyun:admin 邮箱`（随机生成密码）
7. 过期事件每天自动清理（第一次收到上报时触发），也可手动：`php artisan koyun:prune`

站点在 Cloudflare 后面时，程序只信任 Cloudflare 的 IP 段来获取客户真实 IP（bootstrap/app.php）。
**注意：Cloudflare 防火墙不能拦截 `/api/v1/client/*`，否则 App 上报会失败。**
