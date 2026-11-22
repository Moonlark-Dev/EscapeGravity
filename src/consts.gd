class_name EG
extends RefCounted
## Global balance constants, palette and layout for Escape Gravity.
## All values are px / seconds, taken from the design document.

# ---- Screen ----
const SCREEN := Vector2(1280.0, 720.0)
const HALF := Vector2(640.0, 360.0)

# ---- Palette ----
const C_BG := Color("05070f")
const C_PANEL := Color("0b1024")
const C_CYAN := Color("39e6ff")
const C_VIOLET := Color("8b5cf6")
const C_MAGENTA := Color("ff3d81")
const C_AMBER := Color("ffb347")
const C_MINT := Color("5cf2a8")
const C_INK := Color("060a18")
const C_TEXT := Color("e6f2ff")
const C_DIM := Color("7f93b5")

# ---- Ship ----
const SHIP_RADIUS := 40.0            # matches the 82 px visible hull height (ship.png)
const SHIP_ACCEL := 380.0
const SHIP_MAX_SPEED := 150.0        # engine-only speed limit; gravity can exceed it
const SHIP_DRAG := 0.0               # space has no drag: releasing thrust keeps momentum
const SHIP_SPEED_HARD := 720.0       # safety/play ceiling for gravity-assisted speed
const SHIP_BOOST_MULT := 3.0
const SHIP_BOOST_SPEED_MULT := 1.28
const SHIP_BOOST_MAX := 6.6          # initial gauge; 3x the old 2.2 s tank
const SHIP_BOOST_REFILL := 1.6          # per second, after the 0.7 s pause
const SHIP_BOOST_RESUME := 0.22         # hysteresis: refill before re-engage
const SHIP_BOOST_REFILL_DELAY := 0.7
const SHIP_FUEL_MAX := 270.0        # 1.4.0：500 收紧后按试玩反馈定为 270，滑行免费、补给仍有分量
const SHIP_FUEL_THRUST := 4.0        # per second of full thrust (actual delta-v)
const SHIP_FUEL_BOOST := 4.8          # 1.2x thrust cost (was 2x)
const SHIP_FUEL_ASSIST := 0.4         # orbit assist / docking brake, 10% of thrust
const SHIP_ORBIT_ACCEL := 230.0       # tangential assist while diving at a body
const SHIP_ORBIT_SPEED_MAX := 600.0   # assist fades to zero at this speed
const SHIP_SAFE_BRAKE := 1400.0       # auto-dock deceleration while entering a safe zone (stops once docked)
const SHIP_SHIELD_MAX := 20.0
const SHIP_REGEN := 0.0

# ---- Missile ----
const MISSILE_SPEED := 150.0
const MISSILE_TURN := 0.525
const MISSILE_LOCK_TIME := 5.0
const MISSILE_LIFE := 18.0
const MISSILE_RADIUS := 12.0          # missile.png is 64x28; 12 px half-width
const MISSILE_DMG_ENEMY := 25.0
const MISSILE_DMG_SHIP := 25.0
const MISSILE_MAX_LOCKED := 3
const MISSILE_GRAVITY_SCALE := 0.6      # always applied; no assist on missiles
## 锁定期把敌人外壳当实体：导弹提前转向绕飞，物理上也不允许弹体穿进外壳。
## 玩家绕圈时导弹会贴着外壳滑过去，而不是从敌人中间直接穿到另一侧。
const MISSILE_AVOID_MARGIN := 26.0      # 航向即将擦到“外壳 + 该余量”时开始绕
const MISSILE_AVOID_LOOKAHEAD := 220.0  # 提前这么远开始修正航向
## 硬约束的落点稍微压进碰撞半径 0.5px：绕不开的导弹会在碰撞结算里真的打在
## 外壳上（脱锁后的发射者同理），而不是贴着外壳滑过去白飞。
const MISSILE_AVOID_INSET := 0.5

# ---- Enemy (turret) ----
const TURRET_RADIUS := 420.0
const TURRET_HP := 50.0
const TURRET_FIRE_OUT := 5.0
const TURRET_FIRE_IN := 1.0
const TURRET_BURST := 2
const TURRET_OVERHEAT := 2.5
const TURRET_SPEED_OUT := 240.0
const TURRET_SPEED_IN := 18.0
const SPAWN_MIN := 1900.0
const SPAWN_MAX := 2400.0

# ---- Enemy discovery ----
const ENEMY_AGGRO_RANGE := 2100.0    # 玩家进入该距离后敌人才开始主动逼近
const ENEMY_CHASE_MULT := 1.5        # 未被看见时的逼近速度倍率
const ENEMY_REVEAL_TIME := 0.35      # 首次进入屏幕的淡入时长
const ENEMY_HIDDEN_BIAS := 0.72      # 未发现时导弹从敌人方向射入的概率
const ENEMY_HIDDEN_SPREAD := 1.0     # 偏向敌人方向时的最大角度偏移（约 ±57°）
const ENEMY_HIDDEN_EDGE_MIN := 180.0 # 出膛点在屏幕外的额外距离（下界）
const ENEMY_HIDDEN_EDGE_MAX := 320.0 # 出膛点在屏幕外的额外距离（上界）
const ENEMY_HIDDEN_MAX := 2          # 未发现时的导弹数量上限（不占 3 枚直射名额）

# ---- Nest (second non-small enemy) ----
const NEST_RADIUS := 300.0
const NEST_HP := 40.0
const NEST_FIRE_OUT := 3.6
const NEST_FIRE_IN := 1.5
const NEST_BURST := 3
const NEST_OVERHEAT := 3.0
const NEST_SPEED_OUT := 200.0
const NEST_SPEED_IN := 30.0
const NEST_MAX_LOCKED := 4

# ---- Aegis carrier (third non-small enemy) ----
## 偏导母舰：正面 120° 弧形能量盾把导弹伤害衰减 80%（25 → 5）且不触发过热；
## 舰尾是弱点，命中吃 1.5 倍暴击（37.5）并触发 4 秒长过热。转向极慢，
## 玩家必须用引力弧线 / 脉冲切向 / 诱饵把它转过去的弹道再绕回来。
const AEGIS_RADIUS := 360.0
const AEGIS_HP := 70.0
const AEGIS_FIRE_OUT := 5.0
const AEGIS_FIRE_IN := 1.2
const AEGIS_BURST := 2
const AEGIS_OVERHEAT := 2.5
const AEGIS_SPEED_OUT := 200.0
const AEGIS_SPEED_IN := 16.0
const AEGIS_TURN := 0.35             # rad/s，正面永远追不上高速绕后的弹道
const AEGIS_HALF_ARC := 1.0472       # 120° 护盾 = ±60°（弧度）
const AEGIS_FRONT_SCALE := 0.2       # 正面：25 → 5
const AEGIS_CRIT_SCALE := 1.5        # 舰尾：25 → 37.5
const AEGIS_CRIT_OVERHEAT := 4.0     # 舰尾暴击的长过热

# ---- Singularity rig (control enemy) ----
## 引力阱舰：平时斥力环把低速直射导弹推偏擦过，每 7 秒切 3.5 秒虹吸——
## 同时拉扯玩家与全场导弹。解法是趁虹吸把脱锁导弹 / 陨石送进吸引圈。
const RIG_RADIUS := 320.0
const RIG_HP := 60.0
const RIG_FIRE_OUT := 4.2
const RIG_FIRE_IN := 1.6
const RIG_BURST := 3
const RIG_OVERHEAT := 3.0
const RIG_SPEED_OUT := 150.0
const RIG_SPEED_IN := 14.0
const RIG_REPEL_TIME := 7.0          # 斥力态持续时间
const RIG_SIPHON_TIME := 3.5         # 虹吸态持续时间
const RIG_REPEL_RADIUS := 560.0
const RIG_REPEL_PUSH := 420.0        # 低速导弹被推偏的位置速度（px/s）
const RIG_REPEL_MAX_SPEED := 260.0   # 速度低于此值的导弹才会被斥力掰弯
const RIG_SIPHON_RADIUS := 820.0
const RIG_SIPHON_PULL := 620.0       # 导弹/陨石被吸向舰体的位置速度
const RIG_SIPHON_SHIP := 260.0       # 对玩家的加速度
const RIG_SIPHON_BURST := 3          # 虹吸结束时的一次齐射

# ---- Twin pylons (paired encounter) ----
## 双子中继站：成对刷新、保持约 750px 间距同步公转。一发导弹打中 A 时，
## 若 B 不在过热态，3 秒后 A 开始缓慢回血——所以要么借 A 的导弹去炸 B
## （锁定期只豁免发射者），要么两发连引同时打进双双过热。
const PYLON_RADIUS := 210.0
const PYLON_HP := 42.0
const PYLON_FIRE_OUT := 3.4
const PYLON_FIRE_IN := 1.6
const PYLON_BURST := 2
const PYLON_OVERHEAT := 2.6
const PYLON_SPEED_OUT := 210.0
const PYLON_SPEED_IN := 26.0
const PYLON_GAP := 1500.0            # 两站间距（1.4.0：750 → 1500，两节点生成距离 ×2）
const PYLON_ORBIT := 0.42            # 公转角速度（rad/s）
const PYLON_HEAL_DELAY := 3.0        # 受击后多久开始回血
const PYLON_HEAL_TIME := 3.0         # 回血持续时间
const PYLON_HEAL_RATE := 0.10        # 每秒恢复的最大生命比例

# ---- New enemy ammo ----
## 二段加速弹：前 1.8 秒 110 px/s 高转向校准，点火后 340 px/s、角速度暴跌。
const BOOSTER_SLOW_SPEED := 110.0
const BOOSTER_SLOW_TURN := 0.90
const BOOSTER_IGNITE_TIME := 1.8
const BOOSTER_FAST_SPEED := 340.0
const BOOSTER_FAST_TURN := 0.12
## 子母分裂弹：锁定倒计时结束时分裂成 3 枚扇形微型无锁弹头。
const CLUSTER_FRAGS := 3
const CLUSTER_FRAG_SPEED := 185.0
const CLUSTER_FRAG_DMG := 12.0
const CLUSTER_FRAG_SPREAD := 22.0    # 度，每枚之间的夹角
const CLUSTER_FRAG_LIFE := 7.0
## 超载殉爆/水雷弹：无锁慢速，能被脉冲反推回去炸自己。
const MINE_SPEED := 90.0
const MINE_DMG_ENEMY := 14.0
const MINE_DMG_SHIP := 12.0
const MINE_LIFE := 24.0
const VOLATILE_MINES := 6
const VOLATILE_MINE_SPEED := 120.0

# ---- Elite affixes / depth scaling ----
## 深层不再靠疯狂堆血：+22%/层 降到 +14%/层，改用精英词缀提供难度。
const DEPTH_HP_GROWTH := 0.14
const DEPTH_RATE_GROWTH := 0.035
const ELITE_HP_MULT := 1.45
const ELITE_DEPTH_START := 6         # 深度 6 起开始出现精英词缀
const ELITE_EVERY := 4               # 之后每 4 层一个
const POINT_DEFENSE_RADIUS := 30.0
const POINT_DEFENSE_ORBIT := 1.7     # 护卫球环绕角速度
const POINT_DEFENSE_MIN_SPEED := 280.0  # 高于此速度的导弹会凿穿拦截
const POINT_DEFENSE_CD := 1.2        # 单颗护卫球的拦截间隔
const PHASE_BLINK_DIST := 900.0      # 相位跃迁：过热结束时跳到玩家侧翼
const PHASE_BLINK_ANGLE := 1.1       # 侧翼张角（弧度）

# ---- Core mods (roguelike passive builds) ----
const MOD_MAX_STACKS := 3
# A 引力弹弓流
const MOD_TURBINE_FUEL := 3.0        # 环绕行星每秒回燃料
const MOD_TURBINE_BOOST := 0.25      # 环绕行星每秒回加力槽比例
const MOD_RELATIVIST_BASE := 200.0   # 导弹速度阈值
const MOD_RELATIVIST_STEP := 50.0    # 每超 50 px/s
const MOD_RELATIVIST_DMG := 8.0      # 对敌伤害 +8
const MOD_WAKE_SPEED := 350.0        # 曲率尾流触发速度
const MOD_WAKE_ABSORB := 520.0       # 物质吸收半径翻倍
# B 欺骗劫持流
const MOD_PROXIMITY_RADIUS := 130.0  # 近炸增幅的擦弹距离
const MOD_PROXIMITY_HEAL := 1.5
const MOD_INERTIA_ANGLE := 0.2094    # 12° 辅助微偏转
const MOD_CHAIN_RADIUS := 450.0      # 连锁殉爆半径
# C 星体台球流
const MOD_MASS_DRIVER_KNOCK := 320.0 # 脉冲对陨石的轰飞速度
const MOD_METEOR_KNOCK_DAMAGE := 18.0
const MOD_TROJAN_SPEED := 560.0
const MOD_TROJAN_DMG := 15.0
const MOD_BELT_INTERVAL := 0.5       # 陨石刷新间隔倍率
# D 陷阱阵列流
const MOD_RESONANCE_SPEED := 1.6     # 共振奇点内的导弹速度倍率
const MOD_RESONANCE_RADIUS := 420.0
const MOD_RESONANCE_FLING := 380.0   # 信标结束时甩向最近敌人的速度
const MOD_RECYCLE_CD := 0.8
const MOD_RECYCLE_FUEL := 3.0
const MOD_READY_TIME := 3.0          # 战地整备：免费加力时长

# ---- Upgrade rework ----
const ECO_CRUISE_MULT := 0.88        # 节能巡航：推进/技能油耗 -12%
const ECO_CRUISE_MIN := 0.50         # 最多叠到 5 折
const FUEL_MAX_CARD_A := 40.0        # 燃料上限卡 +40
const FUEL_MAX_CARD_B := 80.0        # 燃料上限卡 +80
const SLOT_WEIGHT_FULL := 11.0       # 背包满时的物品栏扩建权重
const SLOT_WEIGHT_OPEN := 6.0

# ---- Skill awakenings (Lv4 branches) ----
const PULSE_STASIS_RADIUS := 480.0
const PULSE_STASIS_OVERHEAT := 1.5
const DASH_AFTERIMAGE_LIFE := 3.0
const BEACON_MIRROR_LIFE := 0.75     # 镜像双生：两枚信标各 75% 时长

# ---- Shop shelves ----
## 货架 1 补给位 1~2 代币 / 货架 2 战术道具 3~4 / 货架 3 黑市改装 5~7。
const SHOP_SHELF_MIN := [1, 3, 5]
const SHOP_SHELF_MAX := [2, 4, 7]

# ---- Celestial bodies ----
const BODY_RADIUS_MIN := 200.0
const BODY_RADIUS_MAX := 380.0
const BODY_MASS_REF := 290.0
const BODY_MASS := 24000000.0
const BODY_GRAVITY_RANGE := 3.0
const BODY_CORE_CLAMP := 0.85
const STAR_RADIUS_MIN := 620.0
const STAR_RADIUS_MAX := 900.0
## Minimum visual gap between a body's surface and any spawned content.  A safe
## zone keeps its full expanded sprite (R280) clear of the body, and an enemy
## keeps its hull clear too, so nothing can be born inside or hugging a planet.
const BODY_CONTENT_MARGIN := 160.0
const PLACE_SEARCH_STEP := 320.0     # radial step when relocating blocked content
const PLACE_SEARCH_RINGS := 18       # 18 x 24 candidate ring around a planned point

# ---- Suicide drone ----
## 小型高速自杀无人机：速度远高于飞船引擎极速，转向率却很低，转弯半径约
## 460 / 0.22 ≈ 2090 px。撞到玩家/敌人各造成 5 点伤害并当场解体；锁定最多
## 持续 5s，近身掠过后开始远离即视为被玩家甩开，永久脱锁。
const DRONE_SPEED := 460.0
const DRONE_TURN := 0.22             # rad/s, very wide arc
const DRONE_RADIUS := 18.0
const DRONE_DMG := 5.0
const DRONE_MAX_LOCKED := 6
const DRONE_PAIR := 2
const DRONE_INTERVAL := 8.0
const DRONE_RETRY := 1.0             # re-check while a zone is in view / at cap
const DRONE_LOCK_TIME := 5.0         # 锁定上限；超时即被甩开，不再重锁
const DRONE_LOSE_DIST := 240.0       # 近身掠过并开始远离的判定距离
const DRONE_DRIFT_LIFE := 8.0        # 脱锁后直线残骸的存活时间
const DRONE_ZONE_WARD := 320.0       # 安全区/商店的驱离圈（在完整半径之外）
const DRONE_SPAWN_EDGE_MIN := 160.0
const DRONE_SPAWN_EDGE_MAX := 360.0

# ---- Meteor ----
const METEOR_INTERVAL := 10.0
const METEOR_DAMAGE := 0.5
const METEOR_KNOCK_DAMAGE := 5.0
const METEOR_RADIUS := 17.0           # meteor_*.png at 0.42 scale is ~34 px across
const METEOR_SPEED_MIN := 110.0
const METEOR_SPEED_MAX := 210.0
const METEOR_SPAWN_DIST := 900.0

# ---- Impact (ramming a hull or a celestial body) ----
## 撞击伤害只由撞击瞬间沿法线的速度决定：40 px/s 起算，380 px/s 到顶。
## 撞敌人再乘 1.5，但不管撞敌人还是撞天体，单次最高都是 5
## （护盾 20 至少能扛 4 下；正常引擎速度正面撞炮塔外壳约 3 点）。
const COLLISION_SPEED_MIN := 40.0
const COLLISION_SPEED_MAX := 380.0
const COLLISION_DMG_MIN := 0.5
const COLLISION_DMG_MAX := 5.0
const COLLISION_ENEMY_MULT := 1.5

# ---- Matter / XP ----
## 进入这个半径就锁定并开始牵引；牵引速度高于飞船外部硬上限
## SHIP_SPEED_HARD=720，所以玩家高速掠过时物质仍能追上，不会被甩飞。
const MATTER_ABSORB := 260.0
const MATTER_TRACTOR_SPEED := 1200.0
const MATTER_TRACTOR_LOCK := 5.0
const MATTER_COLLECT_RADIUS := 40.0
const XP_PER_LEVEL := 100.0          # 1.4.0：升级所需经验 ×5（20 → 100）
const MATTER_BIG_CHANCE := 0.33
const MATTER_BIG_XP := 3
const MATTER_SMALL_XP := 1

# ---- Zones ----
const ZONE_RADIUS := 280.0           # 安全区扩张后的完整半径
const ZONE_ENTRY_RADIUS := 78.0      # 进入前只比飞船大一点，玩家到中心才触发扩张
const ZONE_EXPAND_TIME := 0.62       # 进入时的扩张动画时长
## 安全区是捕获井而不是弹弓：影响圈内用“目标速度”把飞船往圆心带，
## 目标速度随距离收缩，并用足够大的增益/加速度上限压掉切向速度。
const ZONE_CAPTURE_SPEED := 520.0
const ZONE_CAPTURE_ACCEL := 1600.0
const ZONE_CAPTURE_GAIN := 3.2
const ZONE_INFLUENCE_EXTRA := 420.0  # 影响圈 = clearance_radius() + 该值
const ZONE_ENEMY_CLEAR := 520.0     # 安全区贴图边缘与敌人外壳的最小间距
const SAFE_FUEL_DIST := 1875.0      # placement band: ~12.5 s of full-thrust delta-v (50 fuel)
const SHOP_DIST_MIN := 2800.0
const SHOP_DIST_MAX := 4200.0

# ---- Skills ----
const PULSE_CD := 5.0
const PULSE_FUEL := 10.0
const PULSE_RADIUS := 300.0
const PULSE_IMPULSE := 200.0
const PULSE_SPREAD := 15.0
const ANCHOR_CD := 9.0
const ANCHOR_FUEL := 15.0
const ANCHOR_RADIUS := 420.0
const ANCHOR_FORCE := 620.0
const ANCHOR_DURATION := 4.0
const DASH_CD := 7.0
const DASH_FUEL := 12.0
const DASH_SPEED := 430.0
const DASH_TIME := 0.22
const DECOY_CD := 11.0
const DECOY_FUEL := 16.0
const DECOY_RADIUS := 340.0

# ---- Inventory / UI ----
const ITEM_SLOTS_BASE := 2
const ITEM_SLOTS_MAX := 5
const SKILL_SLOTS := 2
const HUD_BEARING_INSET := 20.0
const DEPTH_SAFE_TIME := 8.0
const MAX_TOKENS := 99

# ---- Radar ----
const RADAR_RANGE := 2400.0
const RADAR_RADIUS := 82.0
const EXPLORE_CELL := 400.0

# ---- Helpers ----
static func xp_to_next(_level: int) -> float:
	return XP_PER_LEVEL

static func shield_color(ratio: float) -> Color:
	if ratio > 0.6:
		return C_CYAN
	if ratio > 0.3:
		return C_AMBER
	return C_MAGENTA

static func lerp_color_by_ratio(from: Color, to: Color, t: float) -> Color:
	return from.lerp(to, clampf(t, 0.0, 1.0))
