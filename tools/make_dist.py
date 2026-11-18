#!/usr/bin/env python3
"""Assemble dist/: per-platform release packages + SHA256SUMS.

用法：
    python3 tools/make_dist.py                        # 打包当前版本的全部平台
    python3 tools/make_dist.py --platforms windows,linux
    python3 tools/make_dist.py --version 1.1.0 --platforms windows

产物命名固定为 `EscapeGravity-<version>-<platform>.<ext>`，可直接作为 CI 工件与
GitHub Release 资产上传。
"""
from __future__ import annotations

import argparse
import hashlib
import io
import re
import shutil
import tarfile
import time
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DIST = ROOT / "dist"
GAME = "EscapeGravity"
ALL_PLATFORMS = ("windows", "linux", "android")

GODOT_LICENSE = "Godot Engine 4.7.2 — MIT License.\nSee THIRD_PARTY_NOTICES.md.\n"

RUN_README = """Escape Gravity {version}
====================

一款 2D 俯视角、物理驱动、无直接攻击的太空肉鸽。
你不能开火——唯一的伤害来源是敌人自己的追踪导弹。

运行要求
--------
Windows 10 / 11 64 位；约 140 MB 磁盘；支持 OpenGL 3.3 的显卡。
本程序为单文件 exe，内嵌全部资源，无需安装。

操作
----
W A S D / 方向键   推进（松开后保持惯性）
Shift              加力（3 倍推力，1.2 倍燃料消耗）
J / K              技能 1 / 2
Q / E              切换物品
F                  使用物品
1 / 2 / 3          升级、商店选择
Esc                暂停
R                  失败后重开

玩法要点
--------
- 太空没有阻力：松开推进不会减速，燃料只在实际加速、减速或转向时消耗。
- 推进极速 150，加力 192；贴近行星会自动绕行加速，离开引力圈后速度保留（安全上限 720）。
- 高速冲进安全区时，辅助装置会自动反推，把飞船停在 R280 圈内。
- 导弹锁定你 5 秒后脱锁；让它撞上炮塔的外壳，每发 25 伤害，两发摧毁。
- 护盾只有 20，敌方导弹 25：挨一发就结束。
- 贴着炮塔绕圈，或用脉冲把导弹沿切线甩进外壳。
- 燃料有限；安全区补满燃料并清除导弹；商店用代币换道具。
- 安全区初始只比飞船大一点，飞到中心会扩张成完整的补给圈（扩张瞬间即视为进入，不会误飞出去）。
- 敌人进入你的屏幕前不会显示位置，也不会出现在雷达上；靠近后它会主动朝你逼近。
- 但未发现的敌人仍会开火：导弹从屏幕外绕一圈再切入，射入方向更偏向敌人所在的方位，用来提示威胁来自哪里。
- 物质自动吸收，每 20 XP 升一级；升级只在安全区结算，游玩途中 HUD 会提示“待升级 ×N”。
- 撞上敌舰或天体按撞击瞬间的速度扣护盾，撞敌人 ×1.5、单次最高 5；贴着表面擦过几乎不掉血。

提示
----
- 首次运行可能出现 SmartScreen 提示（未做商业签名），选择“仍要运行”。
- 设置、最佳深度等保存在 %APPDATA%/Godot/app_userdata/Escape Gravity/。
- 字体：WenQuanYi Zen Hei（GPL-2 + 字体嵌入例外）。完整许可见 LICENSES/。
- 游戏代码以 MIT 许可证发布，完整文本见 LICENSE。

版本 {version}
"""

ANDROID_NOTE = """Escape Gravity {version}（Android arm64）
1. 允许“安装未知来源应用”；
2. 安装 EscapeGravity-{version}-android-arm64.apk；
3. 横屏游玩，进入游戏后使用左侧虚拟摇杆与右侧加力/技能按钮；
4. 需要 Android 7.0+ arm64 设备。
minSdk 24 / targetSdk 36 / versionCode 13 / 包名 com.escapegravity.game
"""


def project_version() -> str:
    """从 project.godot 读取唯一权威版本号。"""
    text = (ROOT / "project.godot").read_text(encoding="utf-8")
    match = re.search(r'^config/version="([^"]+)"', text, re.MULTILINE)
    if not match:
        raise SystemExit("project.godot 中找不到 config/version")
    return match.group(1)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with open(path, "rb") as file:
        for chunk in iter(lambda: file.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def common_files(version: str) -> list[tuple[str, bytes]]:
    """每个平台包都附带的自述、许可与第三方声明。"""
    return [
        ("README.txt", RUN_README.format(version=version).encode("utf-8")),
        ("LICENSE", (ROOT / "LICENSE").read_bytes()),
        ("THIRD_PARTY_NOTICES.md", (ROOT / "THIRD_PARTY_NOTICES.md").read_bytes()),
        ("LICENSES/WenQuanYi-ZenHei.txt", (ROOT / "licenses/WenQuanYi-ZenHei.txt").read_bytes()),
        ("LICENSES/GODOT.txt", GODOT_LICENSE.encode("utf-8")),
    ]


def add_zip_bytes(archive: zipfile.ZipFile, arcname: str, data: bytes) -> None:
    info = zipfile.ZipInfo(arcname, date_time=(2026, 1, 1, 0, 0, 0))
    info.compress_type = zipfile.ZIP_DEFLATED
    info.external_attr = 0o644 << 16
    archive.writestr(info, data)


def add_tar_bytes(archive: tarfile.TarFile, arcname: str, data: bytes, mode: int = 0o644) -> None:
    info = tarfile.TarInfo(arcname)
    info.size = len(data)
    info.mode = mode
    info.mtime = int(time.time())
    archive.addfile(info, io.BytesIO(data))


def package_windows(version: str) -> Path:
    exe = ROOT / "build/windows/EscapeGravity.exe"
    if not exe.exists():
        raise SystemExit(f"缺少 Windows 构建产物：{exe}")
    out = DIST / f"{GAME}-{version}-windows-x86_64.zip"
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED, compresslevel=6) as archive:
        archive.write(exe, f"{GAME}/EscapeGravity.exe")
        for name, data in common_files(version):
            add_zip_bytes(archive, f"{GAME}/{name}", data)
    return out


def package_linux(version: str) -> Path:
    binary = ROOT / "build/linux/EscapeGravity.x86_64"
    if not binary.exists():
        raise SystemExit(f"缺少 Linux 构建产物：{binary}")
    out = DIST / f"{GAME}-{version}-linux-x86_64.tar.gz"
    with tarfile.open(out, "w:gz", compresslevel=6) as archive:
        info = archive.gettarinfo(str(binary), f"{GAME}/EscapeGravity.x86_64")
        info.mode = 0o755
        with open(binary, "rb") as file:
            archive.addfile(info, file)
        for name, data in common_files(version):
            add_tar_bytes(archive, f"{GAME}/{name}", data)
    return out


def package_android(version: str) -> Path:
    apk = ROOT / "build/android/EscapeGravity.apk"
    if not apk.exists():
        raise SystemExit(f"缺少 Android 构建产物：{apk}")
    out = DIST / f"{GAME}-{version}-android-arm64.apk"
    shutil.copy2(apk, out)
    note = DIST / "ANDROID-安装说明.txt"
    note.write_text(ANDROID_NOTE.format(version=version), encoding="utf-8")
    return out


def main() -> None:
    parser = argparse.ArgumentParser(description="打包 Escape Gravity 发布包")
    parser.add_argument(
        "--platforms",
        default=",".join(ALL_PLATFORMS),
        help=f"逗号分隔的平台，可选 {', '.join(ALL_PLATFORMS)}（默认全部）",
    )
    parser.add_argument("--version", default=None, help="版本号（默认读取 project.godot）")
    args = parser.parse_args()

    platforms = [item.strip() for item in args.platforms.split(",") if item.strip()]
    unknown = sorted(set(platforms) - set(ALL_PLATFORMS))
    if unknown:
        raise SystemExit(f"未知平台：{', '.join(unknown)}")
    version = args.version or project_version()

    DIST.mkdir(parents=True, exist_ok=True)
    for old in DIST.glob("*"):
        if old.is_file():
            old.unlink()

    for platform in platforms:
        if platform == "windows":
            package_windows(version)
        elif platform == "linux":
            package_linux(version)
        elif platform == "android":
            package_android(version)

    packaged = sorted(path for path in DIST.glob("*") if path.is_file())
    sums = [f"{sha256(path)}  {path.name}" for path in packaged]
    (DIST / "SHA256SUMS.txt").write_text("\n".join(sums) + "\n", encoding="utf-8")

    print(f"Escape Gravity {version} —— dist/：")
    for path in sorted(DIST.glob("*")):
        if path.is_file():
            print(f"  {path.name:52s} {path.stat().st_size / 1048576:8.1f} MiB")
    print()
    print("\n".join(sums))


if __name__ == "__main__":
    main()
