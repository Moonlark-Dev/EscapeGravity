# QA / 验证记录

日期：2026-11-18 · 版本：1.2.0 · 引擎：Godot 4.7.2 stable
环境：Linux x86_64 · Godot headless + Xvfb/llvmpipe · JDK 17 (Temurin 17.0.21) · Android SDK build-tools 35 / platform 35

---

## 1. 逻辑自测

```bash
godot --headless --path . -- --selftest
```

完整输出：`docs/selftest_output.txt`（177 项断言 + 机器人明细）。

```
RESULT: 177 checks, 0 failed
```

**导出包内自测**（同一套脚本，从内嵌 PCK 运行）：

```bash
./build/linux/EscapeGravity.x86_64 --headless -- --selftest
# RESULT: 177 checks, 0 failed
```

覆盖面：

- 物理：太空无阻力（松开推进 2 秒仍保持速度）、引擎极速 150（超过后推进不把惯性压回）、加力 3× 推力 / 192 极速、燃料按实际 Δv 计（到极速后按住推进不耗油，滑行免费）、加力槽 6.6s 与 0.7s 后回充（推进中同样回充，耗尽需先松开）、碰撞半径 40 / 12 / 护盾 20
- 环绕加速：1.9R 切线进入行星引力圈，20 秒内峰值速度 >250、离开后仍 >180；深空滑行 300 速度 2 秒不衰减、不耗油
- 安全区停靠：以 600 速度进入 R78 触发圈，扩张到 R280 后辅助装置刹停，最终速度 <20 且仍在圈内；以 650 切向掠过也会被捕获井吸进圈内
- 引力：表面 285、内圈 395、3R 截止、辅助操作装置平衡恒星引力、锁定中的导弹仍受引力弯折（0.6×）
- 导弹：速度/转向率/5s 脱锁/半径、命中 25、过载 2.5s、两发摧毁 50 血炮塔
- 陨石：0.5 磨损、撞飞后对敌 5、受飞船引力
- 物质：大 3 XP、超 260 不吸、150 内被吸、高速远离仍被追上吸收、20 XP/级
- 区域：安全区进入前 R78、扩张瞬间 R280（贴图仍在缩小状态）、补满/清弹/隐藏；**离开安全区不再启动倒计时刷新**；高速切线掠过仍被吸入停靠、径向高速进入也能停靠；商店 3 件且不回燃料
- 出生区：开局同时预置路线首段安全区（与首个敌人保持 1220px 间距）与首个商店，不需要首杀解锁；首个敌人按路线生成；开局之后**只有击败敌人才刷新修整区**
- 修整区刷新（`_test_rest_zone_refresh`，1.1.0 新增 14 项断言）：敌前没有修整区 / 空场 30s 不会有倒计时刷新 / 击杀后安全区与商店**立即**刷新且互不重叠 / 离开安全区不启动倒计时、离开 20s 仍无 / 商店内击杀挂起并在离开时补刷 / 安全区内击杀挂起并在离开时补刷
- 商店绑定：每次击败敌人都会把商店立即刷新到下一段路线商店点（游标至少推进到当前深度）并绑定新深度，不再有 26s 重开与“跨过所属敌人”的单独重定位
- 发现：敌人未进屏前不可见、不进雷达/方位/血条、仇恨范围外不开火；玩家进入 2100px 后主动逼近并持续开火；未发现时导弹从屏幕外生成、以切线弧线切入、方向 72% 偏向敌人 ±57°，偷袭弹单独上限 2 且不占直射名额；进屏同一帧 `discovered` 并淡入
- 物品/升级：2 格、满栏销毁、5 格上限后无栏位卡、技能满后无新技能卡；游玩中升级只累积 `pending_levels`、不弹面板，进入安全区才开面板，停靠期间新攒的等级立即补开
- 撞击：撞敌人为同速天体的 1.5 倍、伤害随速度升高、撞敌人与撞天体单次都封顶 5、法线速度低于 40 不掉护盾
- 技能：脉冲 10 燃料 / 200 冲量 / 脱锁 / 5s CD / 按移动方向左右偏转（静止按面向）；诱饵抵达脱锁；干扰弹偏转
- 自杀无人机（`_test_drones`，1.2.0 新增 23 项断言）：成对刷新、屏幕外入场、锁定额度 6、满额停刷、速度 460 + 低转向率、视野内有安全区/商店时停刷、撞玩家 5 伤害并当场解体、近身掠过后被甩开且永久脱锁、脱锁不占锁定名额、5 秒锁定上限、撞敌人 5 伤害后解体、安全区驱离圈推开、贴本体解体、脉冲原地解体、刷新计时器接线
- 死亡：燃料耗尽 12s 判负、导弹 25 击穿 20 护盾、复活币恢复 8
- 地图：隐藏路线不回头（每段沿主方向前进）、每段经过天体引力圈、42% 尝试把天体放进两个敌人之间的空白路径且避开安全区/商店/敌人、两个敌人之间必有安全区、安全区离两侧敌人≥1150 且刷新时避开当前敌人、商店比安全区离路线更远；初始安全区/商店/敌人按路线落位；敌人按路线顺序刷新
- 生成间距：天体压住安全区/商店/敌人时环形搜索重新落点（安全区按 R280+160、敌人按外壳+160）；新天体不会生成在安全区/玩家/路线预置节点上；敌人被天体挤到会沿径向推出表面
- 入场：视野内导弹从炮塔外壳（R+14）出膛；已发现的敌人在视野外仍为侧向 820px；未发现时走屏幕外偷袭弧线
- 流式：距原点 120000px 加载区块仍有 ≥3 个天体

### 机器人可玩性（同一次 selftest）

| 尝试 | 轨道半径 | 无敌 | 结果 | 命中 | 用时 |
|---|---|---|---|---|---|
| seed 200 | 700 | 否 | 失败（被导弹击穿） | 0 | 21.5s |
| seed 300 | 700 | 是 | **击毁** | 2 | 56.6s |
| seed 201 | 790 | 否 | 失败（被导弹击穿） | 0 | 8.5s |
| seed 301 | 790 | 是 | **击毁** | 2 | 22.9s |
| seed 202 | 880 | 否 | **击毁** | 2 | 10.9s |
| seed 302 | 880 | 是 | **击毁** | 2 | 11.4s |

- 无敌机器人：**3/3 击毁**，证明“诱导导弹撞敌人”的核心循环成立。
- 普通机器人：1/3 击毁；另外两次被导弹击穿。它只会“绕圈 + 直射导弹贴脸时脉冲”，不会用加力脱离、干扰弹、诱饵、安全区；人类有更多手段。
- 机器人测试在无天体干扰的空场地运行（`run.no_stream=true` + 清空天体），只验证诱导循环；天体引力、环绕加速与高速停靠由独立断言覆盖。
- 结论：机制可达成；未发现阶段的偷袭火力与新惯性一起提高了操作压力，但没有破坏诱导循环。

---

## 2. 导出包验证

> 本次 **1.2.0** 重跑了源码自测（177/177），重新导出 Linux 与 Windows 可执行文件（Linux 包内自测通过、重新生成截图）；
> **dist 发行包与 Android 包未重建、未上传**（下方 Android 记录为 1.0.9 实测；Windows 段同时列出 1.2.0 本地导出验证与 1.0.9 发行包记录）。

### 2.1 Linux（验证打包完整性）

```bash
xvfb-run -a -s "-screen 0 1280x720x24" \
  ./build/linux/EscapeGravity.x86_64 -- --shots=/tmp/shots
```

- 1.2.0 源码重新导出后在 Xvfb + llvmpipe 下真实运行，退出码 0；11 张截图全部重新生成（**由导出包运行产生，不是编辑器**），已复制到 `docs/shots/`。战斗截图额外摆出两架紫/品红自杀无人机，便于核对新敌人与橙红导弹的颜色区分及雷达点。
- 标题、中文字体、贴图、音频、脚本均从内嵌 PCK 加载；无缺失贴图警告。
- `build/linux/EscapeGravity.x86_64` = 96,370,352 bytes，ELF x86-64（1.2.0 导出）。
- 触屏 20:9 截图另用 `--resolution 2400x1080 -- --touch --shots=...` 生成，取 `04_battle` 作为 `docs/shots/12_touch.png`。

### 2.2 Windows（1.2.0 本地导出验证；1.0.9 发行包记录）

> 1.2.0 已在本地重新导出 Windows 可执行文件并验证 PE 头与 `GDPC` 标记；`dist/` 发行包未重建、未上传，推送后由 GitHub Actions 构建 1.2.0 的 Windows 工件。下方 1.0.9 发行包记录保留作对照。

```bash
file build/windows/EscapeGravity.exe
# PE32+ executable for MS Windows 5.02 (GUI), x86-64
python3 -c "d=open(...).read(); print(b'GDPC' in d[-4096:])"   # True
```

- 1.2.0 本地导出：132,054,400 bytes，PE32+ x86-64，尾部 `GDPC` 校验通过；单文件、内嵌 PCK，无外部依赖。
- 1.0.9 发行包：132,039,856 bytes。
- 未做商业代码签名（没有证书），首次运行会有 SmartScreen 提示。

### 2.3 Android（1.0.9 发行包记录，1.2.0 未重建）

> 以下为 1.0.9 实包记录；1.2.0 的 Android 发行包本次未重建、未上传。1.2.0 预期 versionCode **14**（versionName `1.2.0`），当前直链与下列输出仍是 1.0.9 包（versionCode 12）。
> CI 从本次起会额外导出 `EscapeGravity-debug.apk`（临时调试密钥签名，versionCode 14）并上传为 `EscapeGravity-android-debug` 工件；它只是测试包，不是下方用项目密钥签名的发行 APK。

```bash
aapt2 dump badging build/android/EscapeGravity.apk
apksigner verify --verbose --print-certs build/android/EscapeGravity.apk
```

```
package: name='com.escapegravity.game' versionCode='12' versionName='1.0.9'
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

- APK：49,566,968 bytes；含全部 `assets/`（贴图、字体、WAV、脚本 `.gdc`、场景）。
- 权限：无危险权限（只有 Godot/模板默认项）。
- 未在真机运行（本机无 Android 设备）；静态检查 + 签名验证通过，Linux 导出包已验证同一 PCK 的运行时行为。

### 2.4 OpenList 分发

> 以下为 1.0.9 的上传记录；**1.2.0 未上传到 OpenList**（发行包尚未重建）。

- 已上传到 NAS 的 `/vol1/1000/MyFiles/Public/`：
  - `dist/EscapeGravity-1.0.9-windows-x86_64.zip`：60,168,030 bytes，SHA-256 `b32f54b4…f3cd5f73`
  - `dist/EscapeGravity-1.0.9-android-arm64.apk`：49,566,968 bytes，SHA-256 `0cbaeea9…db305cc3`
- 远端 `sha256sum` 与本地逐字节一致；直链 HEAD 均返回 `200` 且 `content-length` 与本地一致（zip `application/zip`，apk `application/vnd.android.package-archive`）：
  - Windows：<https://files.thisisxd.top/d/EscapeGravity-1.0.9-windows-x86_64.zip>
  - Android：<https://files.thisisxd.top/d/EscapeGravity-1.0.9-android-arm64.apk>

---

## 3. 资产完整性

`docs/asset_check.txt`：

```
world: expected=40 present=47 missing=[]
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
src/main.gd:209:	await RenderingServer.frame_post_draw
```

这是截图等待渲染帧，不是绘制。所有画面元素来自预渲染 PNG。

---

## 5. 界面检查

> 以下截图均由 **1.2.0 Linux 导出包**重新生成（导出包真实运行，不是编辑器截图）。

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
