# AGENTS.md — Escape Gravity

面向 AI 编码代理与人类维护者的项目指南。项目内文档、注释、提交信息、界面文案均为中文；新增内容请保持一致。

## 项目简介

《Escape Gravity》是一款 2D 俯视角、物理驱动、**没有直接攻击**的太空肉鸽。玩家只能推进、加力、释放技能，靠诱导敌人自己的追踪导弹撞上敌人来造成伤害。

- 当前版本：**1.0.6**
- 引擎：**Godot 4.7.2 stable**，GL Compatibility 渲染器
- 逻辑分辨率：**1280×720**，`canvas_items` 拉伸 + `expand` 适配宽屏/刘海屏
- 目标平台：**Windows x86_64**、**Android arm64-v8a（横屏）**
- 美术/音频：全部为预渲染 PNG / WAV；引擎运行时**不绘制任何几何图形**
- UI 语言：仅中文；字体 WenQuanYi Zen Hei（随包分发，许可见 `licenses/`）

## 发布状态

- 本仓库是**本地 Git 仓库**，当前**没有 remote、没有推送、没有打 tag / release**。
- 未经用户明确要求，不要执行 `git remote add`、`git push`、创建 GitHub/GitLab 仓库、上传发行包或发布 Web 版。
- 用户说“暂不发布”时，只做本地提交；不要顺手发 Release。
- 本版**不提供 Web 构建**，`build_all.sh` 也已移除 Web 导出。

## 技术栈与运行环境

| 项 | 值 |
|---|---|
| 引擎 | Godot 4.7.2 stable（`/home/dsh/workspace/_godot/Godot_v4.7.2-stable_linux.x86_64`） |
| 语言 | GDScript（无 C#，无第三方插件） |
| 物理 | 自写积分 + 圆碰撞，**没有使用 Godot 物理引擎** |
| 导出 | Windows / Linux / Android；Android 使用 JDK 17 + Android SDK |
| Android SDK | `/home/dsh/opt/android-sdk`（build-tools 35，platform 35/36） |
| JDK | `/home/dsh/opt/jdk17` |

路径是当前开发机的约定；换机器时用环境变量覆盖，不要把绝对路径写死进游戏代码。

## 目录结构

```
escape-gravity-release/
├── project.godot              # 项目配置、autoload、拉伸、ETC2/ASTC
├── export_presets.cfg         # Windows / Android 导出预设
├── scenes/main.tscn           # 唯一场景入口
├── src/
│   ├── main.gd                # 应用外壳：标题、开局、暂停、淡入淡出、截图/自测入口
│   ├── menu.gd                # 标题、暂停、设置、玩法说明
│   ├── ui.gd                  # HUD、雷达、威胁弧、方位标记、触屏、升级/商店/结算
│   ├── run.gd                 # 单局主控：状态机、生成、碰撞、XP、商店、燃料、深度
│   ├── ship.gd                # 惯性、加力、燃料、护盾、操作辅助
│   ├── missile.gd             # 敌方追踪导弹
│   ├── enemy.gd               # 炮塔 / 导弹巢；移动、齐射、炮口
│   ├── meteor.gd              # 陨石
│   ├── matter.gd              # 物质 / XP
│   ├── zone.gd                # 安全区 / 商店
│   ├── galaxy.gd              # 程序化星系、区块流式、探索网格、刷新点
│   ├── route.gd               # 隐藏行进路线：商店/安全区/敌人预置点
│   ├── backdrop.gd            # 相机锚定的视差星云/星点
│   ├── gravity_body.gd        # 天体引力
│   ├── decoy.gd / anchor.gd / fx.gd
│   ├── assets.gd / audio.gd / store.gd / controls.gd
│   ├── consts.gd              # 全部平衡常量
│   ├── defs.gd                # 道具、技能、升级池
│   └── selftest.gd            # 无头断言 + 机器人可玩性
├── assets/
│   ├── world/                 # 46 张世界贴图
│   ├── ui/                    # 58 张 UI 贴图
│   ├── audio/                 # 23 个 WAV
│   └── fonts/ui.ttc           # 中文字体
├── tools/                     # 素材生成、构建、打包脚本
├── docs/                      # 设计对照、美术契约、QA、截图
├── licenses/                  # 字体等第三方许可
├── build/                     # 导出产物（gitignored）
├── dist/                      # 发布包（gitignored）
└── keystore/                  # Android 签名密钥（gitignored，禁止提交）
```

## 硬性约束（改代码前必读）

1. **禁止运行时绘制。** 代码中不得出现 `_draw()`、`draw_*()`、`ColorRect`、`Polygon2D`、`Line2D`。所有画面必须来自 `assets/` 下的预渲染 PNG：用 `Sprite2D`、`TextureRect`、`NinePatchRect`、`TextureProgressBar`、`Label` 与带贴图的粒子。唯一允许的“绘制”字样是截图等待 `RenderingServer.frame_post_draw`。
2. **素材可替换。** 新美术按同名同尺寸覆盖 `assets/` 文件即可，逻辑不应依赖颜色/形状。需要新图形时，先加到 `tools/gen_assets_*.py` 生成 PNG，再在场景里引用；不要在引擎里画。
3. **碰撞体必须贴合可见贴图。** 当前值：飞船半径 40（贴图可见 111×82）、导弹 12（64×28）、陨石 17（96×96 @0.42）、炮塔 420、导弹巢 300（贴图缩放 `R/124`）。换图改变主体占比时，同步改 `src/consts.gd` / `src/enemy.gd`。
4. **1280×720 逻辑分辨率 + expand。** 布局用锚点/容器，不要按 1280 写死 x 坐标。移动端标题按钮必须锚定屏幕中心；触屏技能键在**右侧**，不得移回左侧。
5. **不用物理引擎。** 速度积分、阻尼、硬上限、圆碰撞都在 `ship.gd` / `run.gd` 内自写；保持确定性，方便无头自测。
6. **随机必须可复现。** 世界生成、刷新、掉落统一用 `RandomNumberGenerator` 并显式播种；不要在模拟逻辑里用全局 `randf()`（视觉特效除外）。
7. **中文 UI。** 新增文案用中文；字体已随包分发，不要引入会破坏 Android 包体的字体。
8. **一击结束的难度基线。** 护盾 20、敌方导弹 25；不要为了“更容易”悄悄改伤害/护盾而不更新文档和自测。
9. **不提交构建产物和密钥。** `build/`、`dist/`、`.godot/`、`keystore/` 已被 `.gitignore` 排除；不要 `git add -f`。
10. **发布前必须清理敏感信息。** `export_presets.cfg` 目前含本地 Android 签名口令；在添加 remote / 公开仓库之前，必须清空口令、轮换密钥，并确认 `keystore/` 未被跟踪。

## 关键玩法不变量

这些行为是 1.0.6 物理/生成修复后的基线，别无意改回去：

- **导弹入场**：敌人在视野内时，从炮塔最近的三炮口之一 / 导弹巢前向口、`R+14` 处出膛；被发现的敌人在视野外仍按设计文档从玩家侧向 **820px** 进入。锁定期导弹不与来源敌人碰撞，避免刚出膛自爆。
- **导弹引力**：锁定中与脱锁后都持续受天体引力（`MISSILE_GRAVITY_SCALE=0.6`）；引力强于转向能力时会把导弹拉离拦截线。只有玩家的辅助装置会平衡恒星引力，别把导弹也豁免。
- **敌人刷新与发现**：按 `RunRoute` 预生成顺序取点（首段 1900~2400，之后 2100~2700）；两个敌人位置之间必有一个安全区，商店比安全区离路线更远。路线只用于布局、不渲染；不要改回随机方向刷新。敌人未进入玩家屏幕前不可见、不进雷达/方位/血条；玩家进入 `ENEMY_AGGRO_RANGE=2100` 后以 `1.5×` 速度逼近，贴图进入屏幕的同一帧才算 `discovered`。
- **未发现也会开火**：`enemy._fire_hidden` 在屏幕边缘外 180~320px 生成偷袭弹，切线初速让它绕弧切入；72% 的方向落在敌人方位 ±57° 内，其余全随机。偷袭弹 `sneak=true`，单独上限 `ENEMY_HIDDEN_MAX=2`，且**不占**正常 3 枚直射名额。别用 `locked_missile_count()` 把它们算进去，否则会挤掉正面齐射、破坏诱导循环。
- **出生区是敌对区**：`_initial_spawn` 不再生成安全区，`safe_unlocked=false`；击毁首个攻击者后 `_unlock_safe_after_first_kill` 才解锁，并把 `route.next_safe` 直接推到 1，跳过出生点旁的安全区节点。别把初始安全区加回来，也别在未解锁时让 `_update_spawns` 刷新安全区。
- **安全区与敌人保持间距**：安全区预置在相邻两段敌人的中点（`SAFE_T=0.50`，首段 `SAFE_FIRST_T=0.35`），横向偏移 470~600，圆心离两侧敌人预置点 ≥1150；刷新时 `_clear_zone_of_enemies` 会按 `ZONE_ENEMY_CLEAR=520` 推开正在交战的敌人，敌人刷新校验同一间距。别再把安全区挪回贴着上一场战斗的位置。安全区出生时只有 `ZONE_ENTRY_RADIUS=78`，但所有间距/引力/燃料判定都用 `clearance_radius()`（恒为完整 280）；玩家到中心才扩张，扩张同一帧把 `radius` 设为 280，动画只影响外观。只有安全区内 `gravity_ship_at` 返回零（station-keeping），否则 3R 引力圈会把握停的飞船拖出去。
- **安全区必须可靠吸入**：`assist_accel` 在 `clearance_radius()+420`（700px）影响圈内**持续**施加 `ZONE_GRAVITY=120` 向心牵引，不再只在无输入时生效；同时制动向外的径向速度（`SHIP_SAFE_BRAKE=1400`）和切向速度。高速切线/边缘掠过也会被拖慢并拉回 R280 内停靠，不能把玩家甩飞；玩家明确朝圈外推进（输入点积 < -0.35）时仍可脱离。进圈后仍由 1400 px/s² 反推停靠。
- **物质必须可靠吸收**：`MATTER_ABSORB=240`，牵引加速度 400~1400，牵引速度上限 `MATTER_TRACTOR_SPEED=900`（高于飞船外部上限 720），并有 `MATTER_TRACTOR_LOCK=4s` 的牵引锁定，28px 内拾取。即使玩家高速侧掠或正在远离，物质也会追上并被吸收，不能出现“靠近后被甩飞”的行为。
- **商店绑定敌人深度**：创建商店时记录 `shop_bound_depth=depth`。如果玩家没有使用商店、并且击毁了所属敌人和下一个敌人（`depth > shop_bound_depth + 1`），`_maybe_refresh_shop` 会移除旧信标并在下一个路线商店点重新生成；使用商店离开后仍按 `SHOP_RESPAWN=26` 计时。别让被跳过的商店永远留在身后。
- **空白路径可能藏加速天体**：`RunRoute._make_route_body` 有 42% 概率尝试把该段的天体锚点放进两个敌人之间的空白路径（`PATH_BODY_T=0.56~0.78`、横向 ≤160、半径 140~180），只有避开安全区/商店/两侧敌人/已生成路线天体时才接受，否则回退到原侧方锚点（`BODY_T=0.50`、偏移 380~480）。每段仍保证有一个天体锚点。
- **无限地图**：`Backdrop._process` 必须用相机中心 `c` 锚定图层；删掉 `c` 项会导致离开初始区块后背景消失。`Galaxy.LOAD_RADIUS=3`、`MAX_BODIES=90`，空区块保底一颗天体；`Galaxy._generate_chunk` 会为落在该区块的路线段补一颗行星；物质每 2 秒按飞船周边 3400px 数量补充，5200px 外回收。
- **触屏右侧控制列**：底部加力 150px → 其上技能 92×2 → 再上物品栏 → 物品提示；代币读数在雷达下方。方位标记重叠时沿屏幕边缘错开。
- **真惯性**：太空无阻力（`SHIP_DRAG=0`），松开推进保持速度；`SHIP_MAX_SPEED=150` 只是引擎可加速到的上限，超过后推进只用于转向/减速，不能把惯性压回；外部速度安全上限 `SHIP_SPEED_HARD=720`。别把全局硬上限加回 150。
- **燃料按实际 Δv**：`ship.step` 只按本帧真正改变的速度量扣油；到极速后按住推进不耗油，滑行免费。加力槽同理，只有实际加速才消耗。
- **环绕加速**：`BODY_GRAVITY_RANGE=3`（原 2）；`assist_accel` 在贴体 320px 内沿切线加速，速度 600 处淡出；离开引力圈后速度保留。安全区停靠反推上限 `SHIP_SAFE_BRAKE=1400`，以 600~720 进站要能在 R280 内停住；只有明确朝圈外推进时才放手。
- **天体与内容双向避让**：新天体落点用 `Galaxy.body_fits()` 检查已加载天体、当前飞船、安全区/商店/敌人和**全部路线预置节点**；安全区/商店/敌人刷新用 `_clear_body_point()` 的 18 圈 × 24 方向环形搜索，安全区按完整 R280、敌人按外壳、天体按表面 + `BODY_CONTENT_MARGIN=160` 留白。别再把 `_clear_body_point` 的 clearance 传成 90/120。
- **平衡**：初始燃料 **500**；推进 4/s、加力 **4.8/s（1.2×）**（均按实际 Δv），3× 推力，引擎极速 150 / 加力 192，初始槽 **6.6s**；护盾 20。
- **状态机**：`PLAYING / LEVELUP / SHOP / DESTROY / DEAD`；暂停由 `main.gd` 控制，`run.paused` 冻结模拟。
- **存档**：`user://escape_gravity.cfg` 只保存设置与历史记录；没有中途存档 / 云存档 / meta 解锁。

## 常用命令

```bash
# 无头自测（源工程）
/home/dsh/workspace/_godot/Godot_v4.7.2-stable_linux.x86_64 \
  --headless --path . -- --selftest

# 一键构建：import + 自测 + Windows/Linux/Android 导出 + dist 打包
bash tools/build_all.sh

# 只导出 Windows
/home/dsh/workspace/_godot/Godot_v4.7.2-stable_linux.x86_64 \
  --headless --path . --export-release "Windows Desktop" build/windows/EscapeGravity.exe

# 只导出 Android（需要 JDK 17 / SDK / keystore）
JAVA_HOME=/home/dsh/opt/jdk17 ANDROID_HOME=/home/dsh/opt/android-sdk \
  /home/dsh/workspace/_godot/Godot_v4.7.2-stable_linux.x86_64 \
  --headless --path . --export-release "Android" build/android/EscapeGravity.apk

# 桌面截图（Xvfb）
xvfb-run -a -s "-screen 0 1280x720x24" ./build/linux/EscapeGravity.x86_64 -- --shots=/tmp/shots

# 移动端 20:9 截图（触屏 UI）
xvfb-run -a -s "-screen 0 2400x1080x24" ./build/linux/EscapeGravity.x86_64 \
  --resolution 2400x1080 -- --touch --shots=/tmp/shots_mobile

# 打包 dist + SHA256SUMS
python3 tools/make_dist.py
```

注意：

- `--shots` / `--touch` 是 `OS.get_cmdline_user_args()`，必须放在 `--` 之后。
- Android 导出会读取 `keystore/escapegravity.keystore`；该目录不在 Git 中，换机器需另行恢复。
- 不要在仓库里启动 Web 服务器；用户已明确不需要 Web 试玩。

## 验证与完成标准

改动运行逻辑后，至少完成：

1. `RESULT: 136 checks, 0 failed`；导出包内再跑一次 `./build/linux/EscapeGravity.x86_64 --headless -- --selftest`。
2. 用导出包重新生成截图；桌面 11 张 + 移动端 20:9 一张，检查标题居中、触屏按钮不重叠。
3. 无运行时绘制审计（应只有 `RenderingServer.frame_post_draw` 一条命中）：
   ```bash
   grep -rn "_draw\|draw_\(line\|circle\|arc\|polygon\|polyline\|string\|colored_polygon\)\|ColorRect\|Polygon2D\|Line2D" src/
   ```
4. APK：`apksigner verify` 通过 v2 + v3；`aapt2 dump badging` 的包名/版本/SDK/arm64/landscape 正确；无危险权限。
5. Windows：`file build/windows/EscapeGravity.exe` 为 PE32+ x86-64，尾部含 `GDPC` 内嵌 PCK。
6. 同步文档：`README.md` 的版本/数值/交付物表、`docs/DESIGN_MAP.md`、`docs/QA.md`、`docs/ART.md`（如改缩放）、`docs/selftest_output.txt`。

## 常见任务

- **改平衡数值**：只改 `src/consts.gd`（少数在 `run.gd` / `enemy.gd`），同时更新自测里的硬编码期望、README 的“关键数值”、`docs/DESIGN_MAP.md` 和 `docs/QA.md`。
- **换美术**：按 `docs/ART.md` 的同名文件覆盖；若主体占比变化，改碰撞半径或 `enemy.gd` 的缩放分母；重新导入并生成截图。
- **加技能/道具**：`src/defs.gd` 加定义 → `run.gd` 的 `cast_skill` / `use_item` / 升级池 → `ui.gd` 的图标与文案 → 自测。
- **改移动端布局**：`ui.gd._build_touch` 与 `menu.gd._button_centered`；必须用 `--touch --resolution 2400x1080` 重新截图。
- **改敌人 AI**：`enemy.gd.step`（移动/安全区绕行/开火）与 `run.gd._next_enemy_position`（路线刷新）；`_find_enemy_spawn` 只作路线缺失时的回退。不要破坏“视野内炮口、视野外 820”的入场规则。
- **改地图流式**：`galaxy.gd.ensure_around` / `_generate_chunk`、`route.gd`、`backdrop.gd`、`run.gd._update_spawns` 的物质补充；改完在远点（如 120000px）验证仍有一天体与背景，并跑路线自测。
- **改文档/截图**：截图由导出包生成，不要用编辑器截图冒充；`docs/.gdignore` 防止 Godot 导入 docs 内的 PNG。

## Git 约定

- 当前在 `main` 分支；本地仓库，无 remote。
- 提交信息用中文或英文均可，建议 `type(scope): subject`，例如：
  - `fix(mobile): 技能键移到右侧并放大`
  - `fix(world): 背景改为相机锚定`
  - `docs: 更新 1.0.6 验证记录`
- 一个提交只做一类改动；不要把一个功能、格式化、文档混在一起。
- 提交前检查：
  ```bash
  git status --short --ignored
  ```
  确认没有 `build/`、`dist/`、`keystore/`、`.godot/`、`__pycache__/` 被跟踪。
- **不要**在没有用户明确要求时 `git tag`、`git push`、创建 Release 或上传 APK/zip。
- 如果用户要求发布：先处理 `export_presets.cfg` 的签名口令与 `keystore/`（轮换/移出仓库），再讨论 remote 与 release。

## 已知限制

- Android 没有真机实测；只做了导出、签名、aapt2 静态检查和同 PCK 的 Linux 运行验证。
- Windows exe 未做商业代码签名，首次运行可能出现 SmartScreen。
- 触屏/手柄未做 UI 焦点导航；菜单需要点击/触摸。
- 仅中文 UI；没有多语言。
- 技能替换、激光、中途存档、meta 解锁未实现（见 `README.md` §6）。
- 音效为程序化合成占位，未做人耳母带试听。
- 低端 Android 帧率未做基准；掉帧时优先减少物质数量与星云层数。
