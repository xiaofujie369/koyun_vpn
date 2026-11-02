#!/usr/bin/env python3
"""把域名混淆成编译参数（与 app_config.dart 的 _decode 对应）。
用法：python3 tools/encode_domains.py "https://a.com,https://b.com"
"""
import base64, sys
KEY = bytes([0x6b, 0x6f, 0x79, 0x75, 0x6e, 0x21, 0x5a, 0x37])
raw = sys.argv[1].encode()
print(base64.urlsafe_b64encode(bytes(b ^ KEY[i % len(KEY)] for i, b in enumerate(raw))).decode().rstrip("="))
