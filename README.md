# Koyun 客户端（Windows / macOS / Android / iOS）

基于 **sing-box 1.14.4** 内核、对接 Xboard（ss.koyun520.com）与 xbord-node-v3 节点的跨平台客户端。
界面：Flutter，奶白主题，HarmonyOS Sans 字体，自动适配 7 种语言（简中 / 繁中 / 英 / 日 / 韩 / 俄 / 越）。

## 目录

| 路径 | 内容 |
|---|---|
| `app/lib/api/` | Xboard 接口（多域名自动切换、错误分类） |
| `app/lib/services/` | 账号与订阅（自动刷新、离线缓存、本地导入）、订阅解析 |
| `app/lib/core/` | sing-box 配置生成、内核启停、Clash API（切节点/测速/网速） |
| `app/lib/ui/` | 登录 / 注册 / 仪表盘 / 节点 / 套餐商城 / 用户中心 |
| `app/android/.../vpn/` | Android VpnService + libbox、通知栏快捷开关 |
| `app/ios/PacketTunnel/` | iOS NetworkExtension（需苹果开发者账号签名） |
| `tools/gen_l10n.py` | 所有界面文案与翻译（改文案只改这里） |
| `.github/workflows/build.yml` | Windows / macOS / iOS 自动编译 |

## 常改的配置：`app/lib/app_config.dart`

- `apiHosts`：面板接口域名，按顺序尝试，被墙自动切换。**建议再加 1~2 个备用域名**。
- `webRegisterUrl`：注册失败时引导的网页地址。
- `singBoxVersion`：内核版本（升级内核时同时改 CI 和编译机脚本）。

## 编译

- **Android**：编译机 `/opt/kvbuild/build-android.sh`，产物在 `/opt/kvbuild/dist/`。
  签名密钥 `/opt/kvbuild/keys/`（**务必备份**，丢失后老用户无法覆盖升级）。
- **Windows / macOS / iOS**：推送 `v*` 标签，GitHub Actions 自动编译并生成草稿 Release。

## 发版流程

1. 改 `app/pubspec.yaml` 的 `version:`（如 `1.0.1+2`，`+` 后的数字每次必须变大）。
2. 编译机跑 Android；`git tag v1.0.1 && git push --tags` 触发其它平台。
3. 在 GitHub Release 草稿里核对文件后发布。
