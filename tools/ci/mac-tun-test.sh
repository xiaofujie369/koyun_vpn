#!/bin/bash
# CI（GitHub mac 机器）：验证 macOS “授权一次后以普通用户开 TUN”。
# 授权命令和 App 里 DesktopBackend._ensureMacHelper 的脚本一致（App 用 osascript 弹密码框，这里用 sudo）。
set -uo pipefail
APP=${1:-/Applications/Koyun.app}
BIN="$APP/Contents/Resources/sing-box"
D='/Library/Application Support/Koyun'
H="$D/sing-box"
failed=0
check() { if eval "$1"; then echo "✅ $2"; else echo "❌ $2"; failed=$((failed+1)); fi; }

check 'id -Gn | tr " " "\n" | grep -qx admin' "当前用户在 admin 组（App 只给管理员账号授权）"
sudo sh -c "set -e; mkdir -p '$D'; chown root:wheel '$D'; chmod 755 '$D'; cp -f '$BIN' '$H.tmp'; chown root:admin '$H.tmp'; chmod 4750 '$H.tmp'; xattr -c '$H.tmp' || true; mv -f '$H.tmp' '$H'"
st=$(stat -f '%Su:%Sg %Sp' "$H"); echo "$st"
check '[[ "$st" == "root:admin -rwsr-x---" ]]' "内核归 root:admin 且带 setuid（App 用同样的 stat 判断是否已授权）"
check '[ "$(shasum -a 256 "$BIN" | cut -d" " -f1)" = "$(shasum -a 256 "$H" | cut -d" " -f1)" ]' "和 App 里的内核完全一致"

W=$(mktemp -d); touch "$W/cache.db"
cat > "$W/tun.json" <<'JSON'
{"log":{"level":"info"},
 "inbounds":[{"type":"tun","tag":"tun-in","address":["172.19.0.1/30"],"auto_route":false,"stack":"mixed"},
             {"type":"mixed","listen":"127.0.0.1","listen_port":17998}],
 "outbounds":[{"type":"direct"}]}
JSON
before=$(ifconfig -l)
# 以普通用户身份运行（不加 sudo）
ENABLE_DEPRECATED_MISSING_DOMAIN_RESOLVER=true "$H" run -c "$W/tun.json" -D "$W" > "$W/core.log" 2>&1 &
pid=$!
sleep 4
ps -o user=,ruser= -p $pid
check '[ "$(ps -o user= -p $pid | tr -d " ")" = root ]' "内核以 root 身份运行（普通用户启动，未输密码）"
after=$(ifconfig -l)
newif=$(comm -13 <(tr ' ' '\n' <<<"$before" | sort) <(tr ' ' '\n' <<<"$after" | sort) | grep utun || true)
check '[ -n "$newif" ]' "创建了 TUN 网卡 $newif"
code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 20 -x http://127.0.0.1:17998 http://www.gstatic.com/generate_204)
check '[ "$code" = 204 ]' "内核联网（HTTP $code）"
check '[ "$(stat -f %Su "$W/cache.db")" = "$(id -un)" ]' "缓存文件仍归普通用户（之后切回系统代理模式还能用）"
kill $pid; sleep 2
check '! kill -0 $pid 2>/dev/null' "普通用户能结束 root 内核（App 断开连接的方式）"
tail -5 "$W/core.log"
[ $failed -eq 0 ] && echo 全部通过 || { echo "共 $failed 项失败"; exit 1; }
