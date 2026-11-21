# Escape Gravity · 1.2.0

[![Build](https://github.com/Moonlark-Dev/EscapeGravity/actions/workflows/build.yml/badge.svg)](https://github.com/Moonlark-Dev/EscapeGravity/actions/workflows/build.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

> 2D 俯视角 · 物理驱动 · 无直接攻击的太空肉鸽

- 引擎：**Godot 4.7.2**（GL Compatibility，兼顾 Android）
- 分辨率：1280×720 逻辑分辨率，`canvas_items` 拉伸 + `expand` 适配宽屏 / 刘海屏
- 美术：**全部为预渲染图片素材**（PNG），引擎运行时不绘制任何几何图形；UI 由贴图、九宫格与文字组成，粒子同样使用贴图
- 音频：预渲染 WAV（程序化合成占位音频），运行时只播放文件
- 中文字体：WenQuanYi Zen Hei（随包分发，见许可）
- 许可：**MIT**（见 [`LICENSE`](LICENSE)；字体与引擎的第三方许可见 [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md)）

## 更新日志

### 1.2.0 更新

- **新增小型敌人“自杀式无人机”**：速度 **460 px/s**、转向率仅 **0.22 rad/s**（转弯半径约 **2090px**），锁定玩家后只能画大弧冲过来。撞到玩家或其他敌人各造成 **5 点伤害**，并在撞击瞬间**解体**。大转弯半径让玩家可以用机动把它甩开：锁定最多持续 **5 秒**，近身掠过后开始远离即永久脱锁，之后不会再次追踪。
- **刷新规则**：玩家视野内没有安全区或商店时才会刷新；每 **8 秒**成对刷新 **2 架**，锁定玩家的无人机总数上限 **6 架**；视野内出现修整区时暂停刷新并每秒重试。
- **修整区克制**：安全区/商店的驱离圈会把无人机强行推离，贴到区域本体则当场解体；**脉冲技能**范围内的无人机直接原地解体。
- 无人机改用**紫/品红**机身与宽三角翼，和橙红色导弹明显区分；雷达上显示为威胁点，战斗截图与自测同步更新。
- **升级池两处修正**：安全区进站瞬间就把燃料补满，所以满油时“补充燃料（恢复 25%）”成了一张零收益废卡——现在满油直接不给（权重 0，不会进卡池），只有在安全区里又烧掉燃料后才重新出现；物品栏扩建卡的判定也改回“栏位还能不能再扩”（原先误写成 `inventory.size() < item_slots`，导致 2 格背包一装满、玩家最需要扩格时反而永远刷不出），并且背包满时权重更高（10 对 6）。

### 1.1.0 更新

- **修整区改为击败敌人后立即刷新**：安全区与商店不再有 **10 秒 / 26 秒**倒计时（`safe_respawn_timer`、`shop_respawn_timer` 与 `ZONE_RESPAWN` / `SHOP_RESPAWN` 已删除）。每清空一个战斗区，`_refresh_rest_zones` 立即把安全区与商店移到下一段路线预置点：先安全区、后商店，互不重叠。
- **离开修整区不再触发刷新**：离开安全区/商店本身不会刷新任何区域，下一次刷新只由击败敌人驱动；如果击败敌人时玩家正停靠在安全区或商店内，刷新挂起，离开的同一帧补上，避免区域从脚下被抽走。
- 开局仍由 `_initial_spawn` 预置首个安全区与商店；下一名敌人仍按击杀后 **8 秒安全时间**刷新。

### 1.0.9 更新

- **升级挪进安全区**：游玩途中打满经验槽不再弹出升级框，只累积“待升级”次数（HUD 会提示 `待升级 ×N · 进入安全区强化`）；进入安全区后一次结算，攒了几级就连着选几张。安全区内继续吸收物质攒出的新等级会立刻补开面板。这样战斗中途不会被打断，升级也变成“活着到达安全区”的奖励。
- **撞击伤害改为按速度计算**：撞上敌舰或天体时，护盾磨损由撞击瞬间**沿法线的速度**决定（**40 px/s** 起算，**380 px/s** 到顶，基础 **0.5~5**）；**撞敌人 ×1.5**，但撞敌人和撞天体**单次最高都是 5**。贴着表面擦过几乎不掉血，正面高速撞上去才疼。护盾 20 至少能扛 4 次满额撞击。

<details>
<summary>更早版本</summary>
    
### 1.0.8 更新

本版从 **1.0.5** 基线重新实现，撤回 1.0.6 / 1.0.7 的“物理甩飞”实验，重做以下四项：

- **物质靠近即吸收**：牵引半径 **260px**；进入后锁定 **5 秒**，并以 **1200 px/s**（高于飞船外部上限 720）直接追向飞船，**40px** 内拾取。高速侧掠、正在远离、从身后掠过都会追上，不再出现“靠近后被甩飞”。
- **安全区改为捕获井**：**700px** 影响圈内不再只给一个很小的向心加速度，而是把速度朝“指向圆心的目标速度”拉（目标速度上限 **520 px/s**，加速度上限 **1600 px/s²**），同时压掉切向速度；整个影响圈内抵消天体引力。高速切线掠过也会被吸进 R280，进圈后由 **1400 px/s²** 反推停靠；玩家明确朝圈外推进时仍可脱离。
- **商店记录线路相对位置**：创建时记录所在路线段与该段敌人深度。玩家没进商店、却先击败该段敌人时，旧信标移除，并在下一段路线商店点重新生成，商店始终随战线前移。
- **空白路径加速天体**：每段路线仍保证一个天体锚点；其中 **42%** 的段尝试把较小的天体（R140~180、横向 ≤160）直接放进两个敌人之间的空白路径，用于切线环绕加速；与安全区/商店/敌人/已生成天体冲突时回退到侧方锚点。

### 1.0.5 更新

- **真惯性物理**：太空不再有阻力，松开推进后飞船保持当前速度；引擎只能把速度推到 **150**（加力 192），超过引擎极速后推进只用于转向/减速，惯性不会被压回。外部速度的安全上限为 **720**。
- **燃料按实际 Δv 计**：只有真正改变速度（加速、减速、转向）时才耗油；到达极速后继续按住推进不耗燃料，滑行完全免费。
- **环绕天体加速**：引力影响半径从 **2R 提高到 3R**，给切线掠过留出足够的弯折时间；贴近行星时辅助装置会沿切线自动绕行加速，离开引力圈后速度保留，可以被甩得比引擎极速快得多。HUD 新增速度读数（超过 192 变青、超过 400 变琥珀）。
- **高速安全区停靠**：辅助装置的反推上限提高到 1400 px/s²；以 600~720 速度进入安全区时会自动刹停，停在 R280 圈内，而不是穿过去。只有明确把推进方向指向圈外时才会放手。
- **生成间距修复**：安全区/商店按完整 R280 贴图、敌人按外壳半径、天体按表面 + 160px 留白做双向避让；路线预置的安全区/商店/敌人会为后续天体预留空间，天体也不会在玩家、安全区或敌人身上流式生成；敌人若被天体挤到会沿径向推出表面。
- **路线落点更稳**：被天体挡住的安全区/商店/敌人会用 18 圈 × 24 方向的环形搜索重新落点，不再直接放弃在原来的错误位置。

### 1.0.4 更新

- **未发现的敌人也会开火**：它仍不显示贴图、不进雷达/方位/血条，但玩家进入仇恨范围后会持续射击。导弹在屏幕外生成，先以切线方向绕一段弧再切入；72% 的射入方向落在敌人方位 ±57° 内，其余全随机，既保留“位置未知”，又给出方向提示。
- **偷袭弹单独计数**：这类导弹同时最多 2 枚，且不占用正常的 3 枚直射名额，避免未发现阶段的火力把正面齐射挤掉。

### 1.0.3 更新

- **安全区改为“靠近才扩张”**：刷新后只是比飞船略大的小环（触发半径 78），玩家飞到中心才触发扩张；扩张第一帧的触发半径就设为完整的 280，动画期间不会误飞出安全区。敌人间距、引力与燃料判定都按完整半径（`clearance_radius()`）计算，扩张后不会把敌人圈进来。
- **敌人发现机制**：攻击者生成后不再立刻出现在贴图、雷达、边缘方位与顶部血条上，也不会开火。玩家进入 2100px 后它开始以 1.5× 速度主动逼近；直到外壳进入屏幕才淡入并显示位置，之后沿用原有的索敌/开火规则。（1.0.4 起改为未发现时也会发射屏幕外偷袭弹。）

### 1.0.2 修复 / 调整

- **安全区不再贴着敌人**：安全区预置点从“上一场战斗旁边”移到相邻两段敌人的中点，横向偏移加大到 470~600px；与两侧敌人的预置间距 ≥1150px，安全区贴图（R280）与炮塔外壳（R420）之间至少留 450px。首段没有上一个敌人，安全区仍落在路线前段，与首个敌人保持距离。
- **安全区刷新会避开正在交战的敌人**：刷新时若敌人进入 520px 贴图间距，安全区自动向外让位（再避开天体）；敌人刷新对安全区的间距校验同步从 400px 提高到 520px。
- **地图生成改为“星系 → 物质 → 隐藏路线”**：先铺星系与天体，再填充物质，然后生成一条只用于布局、不渲染的行进路线；商店、安全区、敌人按路线顺序预生成。路线永不回头，每段尽量经过一个天体的引力圈；两个敌人之间必有一个安全区；商店比安全区离路线更远。
- **导弹全程受天体引力**：锁定中也不再免疫引力，只有玩家的辅助操作装置会自动平衡恒星引力。
- **初始加力槽 ×3**：2.2s → 6.6s。

### 1.0.1 修复 / 调整

- 移动端：标题按钮按真实屏幕中心锚定；技能按钮从左侧移到右侧、加大到 92px，并与加力键/物品栏/代币读数重新排布，避免互相遮挡。
- 敌人进入玩家视野后，导弹从其外壳炮口（炮塔三炮口之一 / 巢的前向口）发射；视野外仍按文档从玩家侧向 820px 进入。
- 碰撞体积对齐贴图：飞船半径 13→40、导弹 7→12、陨石 11→17；导弹巢贴图比例同步改为 `R/124`。
- 无限地图：视差背景改为跟随相机锚定（此前离开初始区块后背景会消失）；增大区块加载半径并保证每个区块至少有一个天体；物质改为围绕飞船持续补给，不再只在出生点附近生成。
- 平衡：初始燃料 240→500；加力耗油从 2× 降为 1.2×（4.8/s）。
- 敌人刷新改为与安全区同向（在玩家—安全区连线的延长线上），并让敌人绕行安全区而不是顶在边缘。

</details>

## 工程结构

```
escape-gravity-release/
├── .github/
│   ├── actions/setup-godot/  # 下载并缓存 Godot 与导出模板
│   └── workflows/build.yml   # 自测 + Windows/Linux/Android 测试包 + 工件 + Release
├── project.godot             # 4.7 / GL Compatibility / 1280x720 / 自动加载
├── export_presets.cfg        # Windows / Linux / Android 导出预设（不含签名口令）
├── LICENSE                   # MIT
├── scenes/main.tscn          # 单场景入口
├── src/
│   ├── consts.gd             # 全部平衡数值与调色板
│   ├── defs.gd               # 道具、技能、升级池
│   ├── main.gd               # 应用外壳：标题 / 开一局 / 暂停 / 淡入淡出 / 截图模式
│   ├── menu.gd               # 标题、暂停、设置、玩法说明
│   ├── ui.gd                 # 局内 HUD、雷达、威胁弧、摇杆、升级/商店/销毁/结算
│   ├── run.gd                # 单局主控：状态机、生成、碰撞、升级、商店、燃料、深度
│   ├── galaxy.gd             # 程序化星系、区块流式加载、探索网格、刷新点
│   ├── route.gd              # 隐藏行进路线：商店/安全区/敌人预置点
│   ├── gravity_body.gd       # 行星/恒星与引力公式
│   ├── ship.gd               # 惯性、加力、燃料、护盾、辅助
│   ├── missile.gd            # 追踪导弹
│   ├── enemy.gd              # 炮塔 / 导弹巢
│   ├── meteor.gd / matter.gd / zone.gd / decoy.gd / anchor.gd / fx.gd
│   ├── assets.gd / audio.gd / store.gd / controls.gd
│   ├── backdrop.gd           # 视差星云/星点
│   └── selftest.gd           # 181 项无头断言 + 机器人可玩性验证
├── assets/                   # world / ui / audio / fonts
├── tools/                    # 素材生成、后期、构建、打包
├── docs/                     # ART.md / DESIGN_MAP.md / QA.md / 资产清单 / 截图
├── keystore/                 # 本地 Android 签名材料（gitignored）
└── build/ dist/              # 导出产物 / 发布包（gitignored）
```

技术要点：

- **不用物理引擎**：自己的速度积分 + 圆-圆碰撞，数值与文档一致，也便于无头模拟和机器人测试。
- **状态机**：`PLAYING / LEVELUP / SHOP / DESTROY / DEAD`，暂停由外壳控制；过场用黑色贴图淡入淡出。
- **世界流式**：2048px 区块；远处区块卸载，天体节点复用贴图。
- **所有随机**都由 `RandomNumberGenerator` 播种，便于复现。
- **截图/自测模式**：`-- --selftest` 跑断言；`-- --shots=目录` 用导出包真实渲染截图；`-- --touch` 强制触屏 UI。
- 存档在 `user://escape_gravity.cfg`：设置、最佳深度、击杀、时长；Windows 位于 `%APPDATA%/Godot/app_userdata/Escape Gravity/`，Android 位于应用私有目录。

## 验证

### 无头断言

```bash
godot --headless --path . -- --selftest
# RESULT: 181 checks, 0 failed
```

### 界面

| | |
|---|---|
| ![立绘](docs/shots/01_title.png) 标题 | ![玩法](docs/shots/02_howto.png) 玩法说明 |
| ![战斗](docs/shots/04_battle.png) 战斗 HUD | ![雷达](docs/shots/10_threat_arc.png) 威胁弧与方位 |
| ![升级](docs/shots/08_levelup.png) 升级三选一 | ![商店](docs/shots/07_shop.png) 商店 |
| ![安全区](docs/shots/06_safezone.png) 安全区 | ![结束](docs/shots/09_gameover.png) 结算 |
| ![触屏](docs/shots/12_touch.png) 触屏布局 | ![暂停](docs/shots/05_pause.png) 暂停 |

## 构建

依赖：

- Godot 4.7.2（headless 即可）+ 4.7.2 导出模板（Windows / Linux / Android）
- JDK 17、Android SDK（build-tools 35、platform 35/36，仅 Android 需要）
- 已配置 Godot Editor Settings 的 `export/android/android_sdk_path` 与 `java_sdk_path`（或设置 `ANDROID_HOME` / `JAVA_HOME`）

```bash
# 自测
godot --headless --path . -- --selftest
# Windows（单文件，内嵌 PCK）
godot --headless --path . --export-release "Windows Desktop" build/windows/EscapeGravity.exe
# Linux（用于无显示环境验证）
godot --headless --path . --export-release "Linux (verification)" build/linux/EscapeGravity.x86_64
# 打包 dist + 校验和（CI 使用 windows,linux）
python3 tools/make_dist.py --platforms windows,linux
```

Android 签名：`export_presets.cfg` 只保存密钥路径与别名，**口令从环境变量读取**：

```bash
source keystore/env.sh   # 本地签名文件，与整个 keystore/ 一起被 .gitignore 排除
JAVA_HOME=/path/to/jdk17 godot --headless --path . --export-release "Android" build/android/EscapeGravity.apk
```

一键脚本：`bash tools/build_all.sh`（存在 `keystore/env.sh` 时连 Android 一起构建，否则跳过 Android）。

**CI**：`.github/workflows/build.yml` 在 `ubuntu-24.04` 上下载并缓存 Godot 4.7.2 与导出模板，依次执行资源导入、源码自测、Windows/Linux 导出、Android 测试包（debug 签名）、导出包自测、`make_dist.py --platforms windows,linux`，然后上传四个工件：

- `escape-gravity-dist`：Windows zip、Linux tar.gz、`SHA256SUMS.txt`
- `EscapeGravity-windows-x86_64`：未压缩的 `EscapeGravity.exe`
- `EscapeGravity-linux-x86_64`：未压缩的 `EscapeGravity.x86_64`
- `EscapeGravity-android-debug`：debug 签名的 arm64 测试 APK（可直接侧载安装）

推送 `v*` tag 时，`release` job 会把 `dist/*` 附到 GitHub Release。CI 只生成 Android **debug** 测试包（临时调试密钥），不接触发行签名材料；对外分发的 release APK 仍在本地用 `keystore/` 导出后手工附到 Release。

## 许可与致谢

- **游戏代码、程序化生成的占位美术与音频**：**MIT License**，见 [`LICENSE`](LICENSE)。可自由使用、修改、再分发与商用；美术/音频为程序生成，不含第三方素材。
- **Godot Engine** © Godot Engine contributors，MIT License。
- **WenQuanYi Zen Hei** © 2007–2009 Qianqian Fang 与文泉驿项目，GPL-2 with Font embedding exception；完整许可见 `licenses/WenQuanYi-ZenHei.txt`。

完整第三方声明见 [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md)。
