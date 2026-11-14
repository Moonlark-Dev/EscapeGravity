#!/usr/bin/env python3
"""Assemble dist/: Windows zip, Android APK, Linux tarball + SHA256SUMS."""
import hashlib
import os
import shutil
import tarfile
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DIST = ROOT / "dist"
VERSION = "1.0.9"
GAME = "EscapeGravity"

RUN_README = """Escape Gravity 1.0.9
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

版本 1.0.9 · 2026-11-14
"""

LICENSE_README = "第三方声明与字体许可，见 THIRD_PARTY_NOTICES.md 与 LICENSES/。\n"


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def add_common(z: zipfile.ZipFile, arc_root: str) -> None:
    z.writestr(f"{arc_root}/README.txt", RUN_README)
    z.writestr(f"{arc_root}/THIRD_PARTY_NOTICES.md", (ROOT / "THIRD_PARTY_NOTICES.md").read_text(encoding="utf-8"))
    z.write(ROOT / "licenses/WenQuanYi-ZenHei.txt", f"{arc_root}/LICENSES/WenQuanYi-ZenHei.txt")
    z.writestr(f"{arc_root}/LICENSES/GODOT.txt", "Godot Engine 4.7.2 — MIT License.\nSee THIRD_PARTY_NOTICES.md.\n")


def main() -> None:
    DIST.mkdir(parents=True, exist_ok=True)
    for old in DIST.glob("*"):
        if old.is_file():
            old.unlink()

    win_exe = ROOT / "build/windows/EscapeGravity.exe"
    lin_bin = ROOT / "build/linux/EscapeGravity.x86_64"
    apk = ROOT / "build/android/EscapeGravity.apk"
    for p in (win_exe, lin_bin, apk):
        if not p.exists():
            raise SystemExit(f"missing build artifact: {p}")

    win_zip = DIST / f"{GAME}-{VERSION}-windows-x86_64.zip"
    with zipfile.ZipFile(win_zip, "w", zipfile.ZIP_DEFLATED, compresslevel=6) as z:
        z.write(win_exe, f"{GAME}/EscapeGravity.exe")
        add_common(z, GAME)

    lin_tar = DIST / f"{GAME}-{VERSION}-linux-x86_64.tar.gz"
    with tarfile.open(lin_tar, "w:gz", compresslevel=6) as t:
        t.add(lin_bin, arcname=f"{GAME}/EscapeGravity.x86_64")
        for name, data in (
            ("README.txt", RUN_README),
            ("THIRD_PARTY_NOTICES.md", (ROOT / "THIRD_PARTY_NOTICES.md").read_text(encoding="utf-8")),
            ("LICENSES/WenQuanYi-ZenHei.txt", (ROOT / "licenses/WenQuanYi-ZenHei.txt").read_text(encoding="utf-8")),
            ("LICENSES/GODOT.txt", "Godot Engine 4.7.2 — MIT License.\nSee THIRD_PARTY_NOTICES.md.\n"),
        ):
            p = ROOT / name if name.startswith("LICENSES") or name.endswith(".md") else None
            tmp = DIST / ("_tmp_" + name.replace("/", "_"))
            tmp.write_text(data, encoding="utf-8")
            t.add(tmp, arcname=f"{GAME}/{name}")
            tmp.unlink()

    android_out = DIST / f"{GAME}-{VERSION}-android-arm64.apk"
    shutil.copy2(apk, android_out)

    install_note = DIST / "ANDROID-安装说明.txt"
    install_note.write_text(
        "Escape Gravity 1.0.9（Android arm64）\n"
        "1. 允许“安装未知来源应用”；\n"
        "2. 安装 EscapeGravity-1.0.9-android-arm64.apk；\n"
        "3. 横屏游玩，进入游戏后使用左侧虚拟摇杆与右侧加力/技能按钮；\n"
        "4. 需要 Android 7.0+ arm64 设备。\n"
        "minSdk 24 / targetSdk 36 / versionCode 12 / 包名 com.escapegravity.game\n",
        encoding="utf-8",
    )

    sums = []
    for p in sorted(DIST.glob("*")):
        if p.is_file():
            sums.append(f"{sha256(p)}  {p.name}")
    (DIST / "SHA256SUMS.txt").write_text("\n".join(sums) + "\n", encoding="utf-8")

    print("dist:")
    for p in sorted(DIST.glob("*")):
        print(f"  {p.name:48s} {p.stat().st_size/1048576:8.1f} MiB")
    print()
    for line in sums:
        print(line)


if __name__ == "__main__":
    main()
