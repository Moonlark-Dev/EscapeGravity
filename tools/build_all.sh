#!/usr/bin/env bash
# 本机构建：导入、自测、Windows/Linux/Android 导出、dist 打包。
# CI 走 .github/workflows/build.yml（Windows/Linux 发行导出 + Android debug 测试包，无需发行签名密钥）。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT="${GODOT:-$(command -v godot || echo /home/dsh/workspace/_godot/Godot_v4.7.2-stable_linux.x86_64)}"
export JAVA_HOME="${JAVA_HOME:-/home/dsh/opt/jdk17}"
export ANDROID_HOME="${ANDROID_HOME:-/home/dsh/opt/android-sdk}"
export PATH="$JAVA_HOME/bin:$PATH"

cd "$ROOT"

# Android 签名口令只存在于本地 keystore/（已被 .gitignore 排除），不写入仓库。
if [[ -f "$ROOT/keystore/env.sh" ]]; then
	# shellcheck disable=SC1091
	source "$ROOT/keystore/env.sh"
fi

mkdir -p build/windows build/linux build/android dist

echo "== import =="
"$GODOT" --headless --path "$ROOT" --import

echo "== selftest =="
"$GODOT" --headless --path "$ROOT" -- --selftest

echo "== Windows =="
"$GODOT" --headless --path "$ROOT" --export-release "Windows Desktop" build/windows/EscapeGravity.exe

echo "== Linux =="
"$GODOT" --headless --path "$ROOT" --export-release "Linux (verification)" build/linux/EscapeGravity.x86_64

if [[ -n "${GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD:-}" ]]; then
	echo "== Android =="
	"$GODOT" --headless --path "$ROOT" --export-release "Android" build/android/EscapeGravity.apk
else
	echo "== Android（跳过：未提供 GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD） =="
	export SKIP_ANDROID=1
fi

echo "== dist =="
if [[ "${SKIP_ANDROID:-0}" == "1" ]]; then
	python3 tools/make_dist.py --platforms windows,linux
else
	python3 tools/make_dist.py
fi
