# 美术 / 音频替换指南

本项目按“**素材驱动**”实现：引擎在运行时不绘制任何几何图形，所有可见内容都来自 `assets/` 下的 PNG/WAV。
因此，把几何占位图换成正式美术时，**不需要改游戏逻辑**；只要按约定替换文件、重新导入并导出即可。

---

## 1. 硬性约束（已审计）

- `src/` 中没有 `_draw()`、`draw_*()`、`ColorRect`、`Polygon2D`、`Line2D`。
- 实体是 `Sprite2D`（贴图）；UI 是 `TextureRect / NinePatchRect / TextureProgressBar / Label`；
- 背景是 3 层无缝贴图按视差平铺；粒子是 `CPUParticles2D` + 贴图；
- 条形是 `TextureProgressBar`；雷达是贴图 + 探索格贴图 + 标记贴图；摇杆是贴图；爆炸是两张贴图缩放/淡出；
- 文字由字体渲染（`assets/fonts/ui.ttc`），这是文本而非美术图形。

审计命令：

```bash
grep -rn "_draw\|draw_\(line\|circle\|arc\|polygon\|polyline\|string\|colored_polygon\)\|ColorRect\|Polygon2D\|Line2D" src/
# 唯一命中：main.gd 的 RenderingServer.frame_post_draw（截图等待，不是绘制）
```

---

## 2. 资产目录

```
assets/
├── world/   46 张世界贴图
├── ui/      58 张 UI 贴图
├── audio/   23 个 WAV（2 BGM + 21 SFX）
└── fonts/ui.ttc   文泉驿正黑（16.8 MB）
```

素材联系表：`docs/preview_world.png`、`docs/preview_ui.png`。

---

## 3. 世界贴图（`assets/world/`）

| 文件 | 原始尺寸 | 引擎内的显示方式 / 缩放 |
|---|---|---|
| `ship.png` | 128×128 | 1:1；**机头朝 +X**；可见 111×82，碰撞半径 40 |
| `ship_glow.png` | 160×160 | 叠加，护盾泡 1.0~1.05×；白色可染色 |
| `engine_glow.png` | 96×96 | 1:1，挂在机尾旋转 180°，按推力缩放；**朝 +X** |
| `missile.png` | 64×28 | 1:1，**弹头朝 +X**；碰撞半径 12（贴图半宽 14） |
| `missile_warn.png` | 96×96 | 1:1 叠加，锁定警告环（0.7×） |
| `turret.png` | 1024×1024 | `scale = 420/400`（外缘约 420px），会缓慢自转 |
| `turret_ember.png` | 768×768 | 过载时叠加红色能量纹，`scale = 420/384` |
| `nest.png` | 256×256 | `scale = R/124`（可见外缘 ≈ R）；会缓慢自转/浮动 |
| `meteor_1..3.png` | 96×96 | `scale = 0.42`（显示约 40px），碰撞半径 17；随机旋转 |
| `matter_small.png` | 32×32 | 0.7×（约 22px） |
| `matter_big.png` | 64×64 | 0.62×（约 40px） |
| `planet_1..3.png` | 768×768 | `scale = 2R/768`；碰撞/引力半径 = R（200~380） |
| `star.png` | 1536×1536 | `scale = 2R/1536`；恒星 R=620~900，玩家在 1.12R 外不受其引力 |
| `safezone.png` | 640×640 | 整张贴图按完整半径 `R/280` 缩放；`Zone` 节点出生时整体 `scale=78/280`，玩家进入中心后缓动到 `1.0`（R=280），环半径即扩张后的碰撞/效果半径 |
| `safezone_fill.png` | 640×640 | 同上，叠加，进入后变亮；扩张时复用 `safezone.png` 再叠一层做冲击波 |
| `shop_station.png` | 640×640 | `scale = R/250`（R=280） |
| `gravity_ring.png` | 512×512 | `scale = influence/250`；天体影响边界（2R） |
| `decoy.png` | 64×64 | 1:1，诱饵/信标 |
| `warp_ring.png` | 1024×1024 | 叠加，技能/击杀/区域效果放大淡出 |
| `shockwave.png` | 512×512 | 叠加，爆炸冲击波 / 摇杆外环 |
| `explosion_0..7.png` | 各 256×256 | 预渲染序列（保留用于后续扩展） |
| `explosion_2.png` / `explosion_4.png` | 256×256 | **当前实机使用**：核心火球 + 烟雾体，`Fx.explosion` 做缩放/淡出 |
| `spark.png` | 32×32 | 通用粒子（引擎/导弹/火花） |
| `smoke.png` | 128×128 | 爆炸烟雾 |
| `bg_stars_far/near.png` | 512×512 | 必须**无缝平铺**；视差 0.06 / 0.16 |
| `nebula_1..3.png` | 1024×1024 | 必须无缝平铺；视差 0.015~0.04 |
| `dust.png` | 256×256 | 无缝平铺；视差 0.34 |
| `marker_zone/shop/enemy.png` | 72×72 | 屏幕边缘方位标记（enemy 用 `arrow.png`） |
| `arrow.png` | 64×64 | **朝 +X**，旋转指向目标 |
| `title_bg.png` | 1920×1080 | 标题背景，覆盖裁切（无文字） |
| `reticle.png` | 128×128 | 预留（导弹准星） |

**替换时注意**

1. 机头/弹头/箭头统一朝 **+X**；船只旋转由引擎设置，不要烘焙朝向偏好。
2. 透明背景、中心对齐；四周留辉光内边距（见 `ASSET_MANIFEST.md`）。
3. 行星/恒星的可视球体与碰撞半径要有固定比例；如新美术的球体占比不同，只需改：
   - 行星：`src/gravity_body.gd` 中 `radius * 2.0 / 768.0`
   - 恒星：`radius * 2.0 / 1536.0`
   - 炮塔：`src/enemy.gd` 中 `radius / 400.0`；巢：`radius / 124.0`
4. 天体、安全区、商店的**碰撞半径与效果半径由代码数值决定**（R=200~380 / 280 / 280），贴图只负责视觉匹配。
   飞船/导弹/陨石/巢的碰撞半径已按可见像素对齐（40 / 12 / 17 / R）；换图若改变主体占比，请同步改 `src/consts.gd` 与 `src/enemy.gd` 的缩放。
5. 天空/星云必须无缝；否则平铺时会看到接缝。

---

## 4. UI 贴图（`assets/ui/`）

- 九宫格：`panel_9p`、`panel_alt_9p`、`card_9p`、`button_9p`、`button_hover_9p`、`button_pressed_9p`、`button_disabled_9p`（`patch_margin = 24px`）；`bar_bg_9p` 为 8px。
  替换时保持四角装饰在 24px 内、中间区域可任意拉伸。
- 条形：`bar_fill_shield/exp/fuel/boost/hp.png` 用 `TextureProgressBar` 左→右填充。
- 雷达：`radar_plate`（底盘）、`radar_sweep`（旋转扫描）、`radar_player/zone/shop/enemy/threat`（标记）。
- 威胁弧：`threat_arc.png` 是 **90° 弧带**，圆心在画布中心，半径 198~255（512 画布）；引擎按威胁方向旋转 `angle + 90°`，按距离缩放 0.55~0.9。
- 触屏：`joystick_base/knob`、`btn_boost`/`btn_boost_down`、`btn_skill`、`btn_item`。
- 图标：`icon_skill_*`、`icon_item_*`、`icon_*`（HUD 小图标与升级卡）。
- 其它：`title_logo.png`（标题艺术字）、`title_bg.png`、`vignette.png`、`white.png`、`black.png`、`divider.png`、`prompt_key.png`、`cd_dark.png`、`icon_192.png`、`icon_adaptive_fg_432.png`、`icon_adaptive_bg_432.png`（Android 启动图标）。

**额外补充文件**（不在初版 manifest 内，由本实现补充）：

```
icon_item_repair.png, icon_item_revive.png, icon_inventory.png, icon_skill.png,
black.png, white.png, icon_192.png, icon_adaptive_fg_432.png, icon_adaptive_bg_432.png
```

替换图标时保持视觉重量一致、透明背景；九宫格尺寸可不同，但边框像素需与 `Assets.stylebox()` 中 24px 对应。

---

## 5. 音频（`assets/audio/`）

- 2 首 BGM：`bgm_menu.wav`、`bgm_run.wav`。运行时设置 `AudioStreamWAV.LOOP_FORWARD`，循环点 0 → 长度；替换时请保证首尾可无缝循环。
- 21 个 SFX：`sfx_*.wav`（见 `ASSET_MANIFEST.md`）。`sfx_thrust` 是循环推进声（`Audio.loop_sfx`）。
- 命名即引用：代码只按文件名加载；替换同名文件即可。
- 音量：BGM 默认 -3 dB，推进 -16/-21 dB，音效 0~-18 dB；峰值建议 ≤ -1 dBFS。

生成脚本：`tools/gen_audio.py`（numpy 合成，44.1kHz 16-bit；可重跑覆盖）。

---

## 6. 重新生成 / 重新导入

```bash
# 程序化生成世界 / UI / 音频（会覆盖同名文件）
python3 tools/gen_assets_world.py
python3 tools/gen_assets_ui.py
python3 tools/gen_audio.py
python3 tools/post_assets.py      # 星云提亮、行星裁剪、爆炸序列重绘

# Godot 导入（生成 .import 与 .godot/imported）
godot --headless --path . --import
```

> 生成脚本按 4× 超采样绘制后缩小；**大尺寸贴图（>768px）已改成 2× 或 1×**，避免 OOM。
> 如果重跑时内容被截断/导入报 `read beyond end of data`，说明有进程正在同时写文件；等生成结束再 `--import`。

---

## 7. 字体

`assets/fonts/ui.ttc` = 系统 `wqy-zenhei.ttc`（16.8 MB，未修改）。替换字体时：

1. 保持文件名 `ui.ttc`（或改 `Assets` 里的路径）；
2. 确认包含中文常用字与英文数字；
3. 保留 `licenses/WenQuanYi-ZenHei.txt` 或换成新字体的许可。

UI 字号在 `src/ui.gd` / `src/menu.gd` 通过 `add_theme_font_size_override` 设置；不依赖字体自身 metrics。

---

## 8. 想换成正式美术时的清单

1. 按上表的文件尺寸与朝向，导出 PNG（透明背景、中心对齐、+X 朝向）。
2. 放入同名路径，`--import`，打开游戏看 `docs/ART.md` 中的缩放公式是否需要微调。
3. 九宫格保持 24px 边框；条形填充保持横向渐变。
4. 天空/星云必须无缝。
5. 图标保持统一线宽与光晕；不要烘焙文字（标题 Logo 除外）。
6. 音效替换同名 WAV；BGM 保持可循环。
7. 重新导出：`bash tools/build_all.sh`。
