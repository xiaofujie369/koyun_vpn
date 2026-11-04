#!/usr/bin/env python3
"""把 HarmonyOS Sans 裁剪成只含网站用字的网页字体（完整字体每个约 8 MB）。
网站文案有改动时重新运行：python3 convert/make_fonts.py（需要 fonttools 和 brotli）"""
import pathlib
from fontTools import subset
from fontTools.ttLib import TTFont

ROOT = pathlib.Path(__file__).resolve().parent
SRC = ROOT.parent / "app" / "assets" / "fonts"
OUT = ROOT / "public" / "fonts"

text = "".join(p.read_text(encoding="utf-8") for p in [ROOT / "public" / "index.html", ROOT / "public" / "app.js"])
chars = {c for c in text if ord(c) > 0x7e} | {chr(c) for c in range(0x20, 0x7f)}

OUT.mkdir(exist_ok=True)
for weight in ["Regular", "Medium", "Bold"]:
    font = TTFont(SRC / f"HarmonyOS_Sans_SC_{weight}.ttf")
    cmap = font.getBestCmap()
    missing = sorted(c for c in chars if ord(c) not in cmap)
    options = subset.Options(flavor="woff2", layout_features=["*"])
    s = subset.Subsetter(options)
    s.populate(unicodes=[ord(c) for c in chars])
    s.subset(font)
    font.flavor = "woff2"
    path = OUT / f"HarmonyOS_Sans_SC_{weight}.woff2"
    font.save(path)
    print(f"{path.name}: {path.stat().st_size // 1024} KB，字库缺 {len(missing)} 个字符")
