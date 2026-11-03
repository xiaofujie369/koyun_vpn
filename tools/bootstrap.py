#!/usr/bin/env python3
"""Koyun 启动引导配置工具（配合 Cloudflare Pages 仓库 koyunoss 使用）

App 每次启动先读取引导文件 boot.json，拿到"当前可用的接口域名 / 官网"。
域名被封时，只要改配置、重新生成 boot.json 推送到 koyunoss 仓库，客户无需更新 App。

boot.json 内容经过 AES-256-GCM 加密 + Ed25519 签名：
  * 加密：文件里看不到明文域名
  * 签名：只有持有私钥的人能生成，App 只认签名正确的文件（防止被伪造、劫持到钓鱼网站）

用法：
  python3 tools/bootstrap.py keygen              第一次使用：生成密钥（只做一次！）
  python3 tools/bootstrap.py edit                改域名（交互式），生成 boot.json 并推送到 koyunoss
  python3 tools/bootstrap.py build               按 boot_config.json 生成 boot.json（不推送）
  python3 tools/bootstrap.py show [boot.json]    解密并检查 boot.json（验证签名）
  python3 tools/bootstrap.py defines             打印编译参数（KOYUN_BOOT_PUB / KOYUN_BOOT_KEY）
  python3 tools/bootstrap.py urls "url1,url2"    把引导地址列表编码成编译参数 KOYUN_BOOT

密钥和明文配置保存在 /root/koyunvpn/koyunvpn资料/（不会上传 GitHub）。
"""
import base64
import json
import os
import subprocess
import sys
import tempfile
import time

from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
from cryptography.hazmat.primitives.ciphers.aead import AESGCM
from cryptography.hazmat.primitives import serialization

NOTES = "/root/koyunvpn/koyunvpn资料"
KEYS = os.path.join(NOTES, "boot_keys.json")
PLAIN = os.path.join(NOTES, "boot_config.json")
OSS_REPO = "https://github.com/xiaofujie369/koyunoss.git"
OSS_DIR = os.path.join(NOTES, "koyunoss")  # koyunoss 仓库的本地副本
XOR = bytes([0x6B, 0x6F, 0x79, 0x75, 0x6E, 0x21, 0x5A, 0x37])  # 与 app_config.dart 的 _decode 一致


def b64(b: bytes) -> str:
    return base64.b64encode(b).decode()


def unb64(s: str) -> bytes:
    return base64.b64decode(s)


def xor_encode(text: str) -> str:
    raw = text.encode()
    return base64.urlsafe_b64encode(bytes(c ^ XOR[i % len(XOR)] for i, c in enumerate(raw))).decode().rstrip("=")


def load_keys():
    if not os.path.exists(KEYS):
        sys.exit(f"❌ 找不到密钥文件 {KEYS}，请先运行：python3 tools/bootstrap.py keygen")
    with open(KEYS) as f:
        k = json.load(f)
    priv = Ed25519PrivateKey.from_private_bytes(unb64(k["sign_private"]))
    return priv, unb64(k["sign_public"]), unb64(k["aes_key"])


def cmd_keygen():
    if os.path.exists(KEYS):
        sys.exit(f"❌ 密钥已存在：{KEYS}\n   重新生成会让所有已发布的 App 读不了新配置！如确需更换，请先手动备份并删除该文件。")
    priv = Ed25519PrivateKey.generate()
    pub = priv.public_key().public_bytes(serialization.Encoding.Raw, serialization.PublicFormat.Raw)
    raw_priv = priv.private_bytes(serialization.Encoding.Raw, serialization.PrivateFormat.Raw,
                                  serialization.NoEncryption())
    data = {
        "说明": "Koyun 引导配置密钥。sign_private 是私钥，绝对不能泄露、不能丢；丢了只能发新版 App 换密钥。",
        "created": time.strftime("%Y-%m-%d %H:%M:%S"),
        "sign_private": b64(raw_priv),
        "sign_public": b64(pub),
        "aes_key": b64(AESGCM.generate_key(bit_length=256)),
    }
    os.makedirs(NOTES, exist_ok=True)
    fd = os.open(KEYS, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, "w") as f:
        json.dump(data, f, ensure_ascii=False, indent=1)
    print(f"✅ 已生成密钥：{KEYS}")
    cmd_defines()


def cmd_defines():
    _, pub, aes = load_keys()
    print("编译参数（加到 GitHub Secrets 和编译机 /opt/kvbuild/keys/app.env）：")
    print(f"KOYUN_BOOT_PUB={xor_encode(b64(pub))}")
    print(f"KOYUN_BOOT_KEY={xor_encode(b64(aes))}")


def build_file(cfg: dict) -> dict:
    priv, _, aes = load_keys()
    cfg = dict(cfg)
    cfg["ts"] = int(time.time())  # 时间戳：App 不接受比本机缓存更旧的配置（防回滚）
    plain = json.dumps(cfg, ensure_ascii=False, separators=(",", ":")).encode()
    nonce = os.urandom(12)
    data = AESGCM(aes).encrypt(nonce, plain, None)
    sig = priv.sign(nonce + data)
    return {"v": 1, "n": b64(nonce), "d": b64(data), "s": b64(sig)}


def read_file(doc: dict) -> dict:
    _, pub, aes = load_keys()
    from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PublicKey
    nonce, data, sig = unb64(doc["n"]), unb64(doc["d"]), unb64(doc["s"])
    Ed25519PublicKey.from_public_bytes(pub).verify(sig, nonce + data)  # 签名不对会抛异常
    return json.loads(AESGCM(aes).decrypt(nonce, data, None))


def check_cfg(cfg: dict):
    api = cfg.get("api") or []
    if not api or not all(isinstance(u, str) and u.startswith("https://") for u in api):
        sys.exit("❌ api 必须是以 https:// 开头的地址列表")
    web = cfg.get("web", "")
    if web and not web.startswith("https://"):
        sys.exit("❌ web 必须以 https:// 开头")


def load_plain() -> dict:
    if not os.path.exists(PLAIN):
        sys.exit(f"❌ 找不到明文配置 {PLAIN}，请运行：python3 tools/bootstrap.py edit")
    with open(PLAIN, encoding="utf-8") as f:
        return json.load(f)


def save_plain(cfg: dict):
    fd = os.open(PLAIN, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        json.dump(cfg, f, ensure_ascii=False, indent=1)


def cmd_build(out=None) -> str:
    cfg = load_plain()
    check_cfg(cfg)
    doc = build_file(cfg)
    out = out or os.path.join(tempfile.gettempdir(), "boot.json")
    with open(out, "w") as f:
        json.dump(doc, f, separators=(",", ":"))
    back = read_file(doc)
    print(f"✅ 已生成 {out}（{os.path.getsize(out)} 字节），自检通过：接口 {len(back['api'])} 个")
    return out


def ask_list(prompt, old):
    print(f"{prompt}\n  当前：{', '.join(old) if old else '（无）'}")
    v = input("  输入新的（多个用英文逗号分隔，直接回车 = 不改）：").strip()
    if not v:
        return old
    return [x.strip().rstrip("/") for x in v.split(",") if x.strip()]


def cmd_edit():
    cfg = load_plain() if os.path.exists(PLAIN) else {"api": [], "web": ""}
    cfg["api"] = ask_list("① 接口域名（App 登录 / 订阅用，按顺序尝试，被封的放后面或删掉）", cfg.get("api", []))
    w = ask_list("② 官网 / 网页注册地址（只填一个）", [cfg["web"]] if cfg.get("web") else [])
    cfg["web"] = w[0] if w else ""
    check_cfg(cfg)
    print("\n将要发布的配置：")
    print(json.dumps(cfg, ensure_ascii=False, indent=1))
    if input("确认发布？输入 y 回车：").strip().lower() != "y":
        sys.exit("已取消，没有任何改动")
    save_plain(cfg)
    publish()


def publish():
    if not os.path.isdir(os.path.join(OSS_DIR, ".git")):
        subprocess.run(["git", "clone", "-q", OSS_REPO, OSS_DIR], check=True)
    subprocess.run(["git", "-C", OSS_DIR, "pull", "-q", "--rebase"], check=False)
    cmd_build(os.path.join(OSS_DIR, "boot.json"))
    g = ["git", "-C", OSS_DIR, "-c", "user.name=xiaofujie369", "-c", "user.email=cc@koyun.edu.kg"]
    subprocess.run(g + ["add", "boot.json"], check=True)
    if subprocess.run(g + ["diff", "--cached", "--quiet"]).returncode == 0:
        print("配置没有变化，无需推送")
        return
    subprocess.run(g + ["commit", "-q", "-m", "update"], check=True)
    subprocess.run(["git", "-C", OSS_DIR, "push", "-q"], check=True)
    print("✅ 已推送到 koyunoss，Cloudflare Pages 约 1 分钟后生效；App 下次启动自动读取")


def cmd_show(path=None):
    path = path or os.path.join(OSS_DIR, "boot.json")
    with open(path) as f:
        doc = json.load(f)
    try:
        cfg = read_file(doc)
    except Exception as e:  # noqa
        sys.exit(f"❌ 签名或解密失败：{e!r}")
    print("✅ 签名正确，内容：")
    t = cfg.get("ts", 0)
    print(f"  生成时间：{time.strftime('%Y-%m-%d %H:%M:%S', time.localtime(t))}")
    print(json.dumps(cfg, ensure_ascii=False, indent=1))


if __name__ == "__main__":
    a = sys.argv[1:]
    if not a or a[0] in ("-h", "--help", "help"):
        print(__doc__)
    elif a[0] == "keygen":
        cmd_keygen()
    elif a[0] == "defines":
        cmd_defines()
    elif a[0] == "build":
        cmd_build(a[1] if len(a) > 1 else None)
    elif a[0] == "edit":
        cmd_edit()
    elif a[0] == "show":
        cmd_show(a[1] if len(a) > 1 else None)
    elif a[0] == "urls" and len(a) > 1:
        urls = [u.strip() for u in a[1].split(",") if u.strip()]
        if not all(u.startswith("https://") for u in urls):
            sys.exit("❌ 引导地址必须以 https:// 开头")
        print(f"KOYUN_BOOT={xor_encode(','.join(urls))}")
    else:
        print(__doc__)
