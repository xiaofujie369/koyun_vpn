# 订阅文件转换网站

把订阅链接转换成 Koyun 可导入的 JSON 文件（sing-box 节点格式）。纯 PHP，不需要数据库，不保存任何客户数据。

## 部署

1. 建站：网站根目录设为 `public/`，PHP 8.1 及以上，需要 curl 扩展。
2. 把本目录的 `public/`、`lib.php`、`config.example.php` 上传到站点目录。
3. 在站点目录把 `config.example.php` 复制成 `config.php` 并填写（放在 `public/` 外面，不进仓库）。
4. 运行 `php test.php` 检查转换逻辑。

## 缓存

Cloudflare 和浏览器会缓存 js、css、字体。改了这些文件后，要把 `index.html` 和 `style.css` 里的 `?v=` 数字加 1，否则部分访客会继续拿到旧文件。

## 字体

网站使用 HarmonyOS Sans，`public/fonts/` 里是只含网站用字的裁剪版。改了 `index.html` 或 `app.js` 的文案后，运行 `python3 make_fonts.py` 重新生成。

## 文件格式

```json
{
  "koyun": { "format": 1, "created_at": 0, "upload": 0, "download": 0, "total": 0, "expire": 0, "sub": "" },
  "outbounds": []
}
```

`koyun.sub` 是 App 以后刷新用的订阅地址。`outbounds` 是 Xboard `flag=sing-box` 输出的节点，内容原样保留。`koyun` 是 App 用来显示流量和到期时间的附加信息。

## 支持的格式

| 选项 | Xboard flag | 文件 | 内容 |
|---|---|---|---|
| Koyun | `sing-box` | `.json` | 节点原样，附带 `koyun` 信息 |
| 小火箭 | `shadowrocket` | `.txt` | 解开 Base64，一行一个节点链接，去掉状态行和假节点 |
| Clash / FlClash | `clashmeta` | `.yaml` | 原样提供（策略组引用了全部节点，不能删改） |

`flag=clash` 不含新协议节点，不要用。增加格式：在 `lib.php` 的 `KOYUN_FORMATS` 和 `koyun_build` 里加一项，再到 `index.html`、`app.js` 加选项和文案。
