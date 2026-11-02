#!/usr/bin/env bash
# Rebuild everything: import, self-test, Windows/Linux/Android exports, dist packages.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT="${GODOT:-/home/dsh/workspace/_godot/Godot_v4.7.2-stable_linux.x86_64}"
export JAVA_HOME="${JAVA_HOME:-/home/dsh/opt/jdk17}"
export ANDROID_HOME="${ANDROID_HOME:-/home/dsh/opt/android-sdk}"
export PATH="$JAVA_HOME/bin:$PATH"

cd "$ROOT"
mkdir -p build/windows build/linux build/android dist

echo "== import =="
"$GODOT" --headless --path "$ROOT" --import

echo "== selftest =="
"$GODOT" --headless --path "$ROOT" -- --selftest

echo "== Windows =="
"$GODOT" --headless --path "$ROOT" --export-release "Windows Desktop" build/windows/EscapeGravity.exe

echo "== Linux =="
"$GODOT" --headless --path "$ROOT" --export-release "Linux (verification)" build/linux/EscapeGravity.x86_64

echo "== Android =="
"$GODOT" --headless --path "$ROOT" --export-release "Android" build/android/EscapeGravity.apk

echo "== dist =="
python3 tools/make_dist.py
