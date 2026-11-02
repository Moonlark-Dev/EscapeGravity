# QA / 验证记录

日期：2026-11-02 · 版本：1.0.1 · 引擎：Godot 4.7.2 stable
环境：Linux x86_64 · Godot headless + Xvfb/llvmpipe · JDK 17 (Temurin 17.0.21) · Android SDK build-tools 35 / platform 35

---

## 1. 逻辑自测

```bash
godot --headless --path . -- --selftest
```

完整输出：`docs/selftest_output.txt`（63 项断言 + 机器人明细）。

```
RESULT: 63 checks, 0 failed
```

**导出包内自测**（同一套脚本，从内嵌 PCK 运行）：

```bash
./build/linux/EscapeGravity.x86_64 --headless -- --selftest
# RESULT: 63 checks, 0 failed
```

覆盖面：

- 物理：极速 150、加力 3× 推力 / 192 极速、燃料上限 500 / 推进 4/s / 加力 4.8/s、加力槽 2.2s 与 0.7s 后回充、碰撞半径 40 / 12 / 护盾 20
- 引力：表面 285、内圈 395、2R 截止、恒星对飞船自动抵消
- 导弹：速度/转向率/5s 脱锁/半径、命中 25、过载 2.5s、两发摧毁 50 血炮塔
- 陨石：0.5 磨损、撞飞后对敌 5、受飞船引力
- 物质：大 3 XP、超 190 不吸、150 内被吸、20 XP/级
- 区域：安全区补满/清弹/隐藏/离开 10s 刷新；商店 3 件且不回燃料
- 物品/升级：2 格、满栏销毁、5 格上限后无栏位卡、技能满后无新技能卡
- 技能：脉冲 10 燃料 / 200 冲量 / 脱锁 / 5s CD；诱饵抵达脱锁；干扰弹偏转
- 死亡：燃料耗尽 12s 判负、导弹 25 击穿 20 护盾、复活币恢复 8
- 刷新：攻击者屏幕外 1900~2400、未探索区；安全区在 50 燃料距离内；有安全区时攻击者沿玩家—安全区连线、在外侧刷新
- 入场：视野内导弹从炮塔外壳（R+14）出膛；视野外仍为侧向 820px
- 流式：距原点 120000px 加载区块仍有 ≥3 个天体

### 机器人可玩性（同一次 selftest）

| 尝试 | 轨道半径 | 无敌 | 结果 | 命中 | 用时 |
|---|---|---|---|---|---|
| seed 200 | 700 | 否 | 失败（被击穿） | 0 | 19.7s |
| seed 300 | 700 | 是 | **击毁** | 2 | 40.3s |
| seed 201 | 790 | 否 | 失败（被击穿） | 1 | 44.6s |
| seed 301 | 790 | 是 | **击毁** | 2 | 30.6s |
| seed 202 | 880 | 否 | **击毁** | 2 | 32.1s |
| seed 302 | 880 | 是 | **击毁** | 2 | 53.7s |

- 无敌机器人：**3/3 击毁**，证明“诱导导弹撞敌人”的核心循环成立。
- 普通机器人：1/3 击毁。它只会“绕圈 + 危险时脉冲”，不会用加力脱离、干扰弹、诱饵、安全区；人类有更多手段。碰撞体放大后容错更低，建议实际试玩手感。
- 结论：机制可达成；难度高压（与文档“护盾 20 / 导弹 25 一击结束”一致）。

---

## 2. 导出包验证

### 2.1 Linux（验证打包完整性）

```bash
xvfb-run -a -s "-screen 0 1600x900x24" \
  ./build/linux/EscapeGravity.x86_64 -- --shots=/tmp/shots
```

- 退出码 0；11 张截图全部生成（**由导出包运行产生，不是编辑器**），已复制到 `docs/shots/`。
- 标题、中文字体、贴图、音频、脚本均从内嵌 PCK 加载；无缺失贴图警告。
- `build/linux/EscapeGravity.x86_64` = 96,425,736 bytes，ELF x86-64。

### 2.2 Windows

```bash
file build/windows/EscapeGravity.exe
# PE32+ executable for MS Windows 5.02 (GUI), x86-64
python3 -c "d=open(...).read(); print(b'GDPC' in d[-4096:])"   # True
```

- 单文件、内嵌 PCK，无外部依赖；132,109,784 bytes。
- 未做商业代码签名（没有证书），首次运行会有 SmartScreen 提示。

### 2.3 Android

```bash
aapt2 dump badging build/android/EscapeGravity.apk
apksigner verify --verbose --print-certs build/android/EscapeGravity.apk
```

```
package: name='com.escapegravity.game' versionCode='2' versionName='1.0.1'
minSdkVersion:'24'
targetSdkVersion:'36'
native-code: 'arm64-v8a'
uses-feature: android.hardware.screen.landscape
application-icon: res/mipmap-anydpi-v26/icon.xml
Verifies
Verified using v2 scheme (APK Signature Scheme v2): true
Verified using v3 scheme (APK Signature Scheme v3): true
Signer #1 certificate DN: CN=Escape Gravity, OU=Games, O=Escape Gravity, L=Shanghai, ST=Shanghai, C=CN
Signer #1 certificate SHA-256: ddd8a610132d862301c8987f18f545a6eefdf58f0617547d7fad3cec0113f5ff
```

- APK：49,637,092 bytes；含全部 `assets/`（贴图、字体、WAV、脚本 `.gdc`、场景）。
- 权限：无危险权限（只有 Godot/模板默认项）。
- 未在真机运行（本机无 Android 设备）；静态检查 + 签名验证通过，Linux 导出包已验证同一 PCK 的运行时行为。

---

## 3. 资产完整性

`docs/asset_check.txt`：

```
world: expected=40 present=46 missing=[]
ui:    expected=50 present=58 missing=[]
audio: expected=23 present=23 missing=[]
```

（`present` 包含实现中补充的 UI 图标与 `black/white` 等辅助贴图，见 `docs/ART.md`。）

---

## 4. 无运行时绘制审计

```bash
grep -rn "_draw\|draw_\(line\|circle\|arc\|polygon\|polyline\|string\|colored_polygon\)\|ColorRect\|Polygon2D\|Line2D" src/
```

唯一命中：

```
src/main.gd:202:	await RenderingServer.frame_post_draw
```

这是截图等待渲染帧，不是绘制。所有画面元素来自预渲染 PNG。

---

## 5. 界面检查

- 16:9（1280×720）：标题、玩法、设置、战斗、暂停、安全区、商店、升级、结算、威胁弧、爆炸 —— 12 张截图见 `docs/shots/`。
- 20:9（2400×1080 / 逻辑 1600×720，触屏）：标题按钮按屏幕中心锚定；右侧控制列自下而上为加力 150、技能 92×2、物品栏，代币读数在雷达下方，互不重叠。
- 中文字体在导出包中正常渲染（WenQuanYi Zen Hei，16.8 MB TTC）。
- 九宫格面板/按钮在 300~1040px 宽度下拉伸无变形。
- 触屏 UI 在安全区会随雷达/威胁信息一起隐藏（仅保留暂停键），离开后恢复。

---

## 6. 未验证 / 限制

- Android 真机（触屏、帧率、音频输出、刘海/手势条适配）。
- 实体手柄（代码按 InputMap 标准映射实现，未接真机）。
- 人耳试听（BGM/SFX 为 numpy 合成；已做电平/循环/首尾检查，见 `docs/audio_report.md`）。
- 长时间运行的内存/性能曲线（交易、深度 20+、200+ 物质、多个导弹）。
- Windows 实机（无 Wine/Windows 环境）；PE 头、PCK 标记、导出流程已验证。
- 代码签名（Windows SmartScreen；Android 使用项目自签名密钥）。
