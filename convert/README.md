# 订阅文件转换网站

把订阅链接转换成 Koyun 可导入的 JSON 文件（sing-box 节点格式）。纯 PHP，不需要数据库，不保存任何客户数据。

## 部署

1. 建站：网站根目录设为 `public/`，PHP 8.1 及以上，需要 curl 扩展。
2. 把本目录的 `public/`、`lib.php`、`config.example.php` 上传到站点目录。
3. 在站点目录把 `config.example.php` 复制成 `config.php` 并填写（放在 `public/` 外面，不进仓库）。
4. 运行 `php test.php` 检查转换逻辑。

## 字体

网站使用 HarmonyOS Sans，`public/fonts/` 里是只含网站用字的裁剪版。改了 `index.html` 或 `app.js` 的文案后，运行 `python3 make_fonts.py` 重新生成。

## 文件格式

```json
{
  "koyun": { "format": 1, "created_at": 0, "upload": 0, "download": 0, "total": 0, "expire": 0 },
  "outbounds": []
}
```

`outbounds` 是 Xboard `flag=sing-box` 输出的节点，内容原样保留。`koyun` 是 App 用来显示流量和到期时间的附加信息。

## 以后增加其它软件的格式

Xboard 本身就能输出这些格式，服务器按 `flag` 取回后原样提供下载即可，不需要自己转换节点：

| 软件 | flag | 内容 | 文件 |
|---|---|---|---|
| 小火箭 | `shadowrocket` | Base64 节点链接列表 | `.txt` |
| Clash Meta / FlClash | `clashmeta` | YAML | `.yaml` |

要改的地方：`app.js` 加格式选项并把选择传给 `convert.php`；`convert.php` 用白名单校验格式，再决定 `flag` 和文件名。注意 `flag=clash` 不含新协议节点，不要用。
