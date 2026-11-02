#!/bin/bash
# 把测试版设为 GitHub 正式发布（App 的"检查更新"才能检测到）
# 用法：bash tools/publish.sh 1.0.5
set -e
V="$1"
REPO=xiaofujie369/koyun_vpn
if [ -z "$V" ]; then echo "请写上版本号，例如：bash tools/publish.sh 1.0.5"; exit 1; fi
TAG="v$V-test"
if ! gh release view "$TAG" -R $REPO >/dev/null 2>&1; then
  echo "❌ 还没有 $TAG：可能还在编译或上传，请稍后再试"; exit 1
fi
N=$(gh release view "$TAG" -R $REPO --json assets -q '[.assets[].name | select(endswith("-setup.exe"))] | length')
if [ "$N" = "0" ]; then echo "❌ $TAG 里还没有安装包，请稍后再试"; exit 1; fi
gh release edit "$TAG" -R $REPO --draft=false --prerelease=false --latest >/dev/null
L=$(gh api repos/$REPO/releases/latest -q .tag_name)
if [ "$L" = "$TAG" ]; then
  echo "✅ 已正式发布 $TAG，App 里点「检查更新」就能看到"
else
  echo "⚠️ 已发布，但最新版本显示为 $L，请把结果告诉 Claude"
fi
