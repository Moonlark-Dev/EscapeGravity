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
const SHIP_FUEL_MAX := 500.0
const SHIP_FUEL_THRUST := 4.0        # per second of full thrust (actual delta-v)
const SHIP_FUEL_BOOST := 4.8          # 1.2x thrust cost (was 2x)
const SHIP_FUEL_ASSIST := 0.4         # orbit assist / docking brake, 10% of thrust
const SHIP_ORBIT_ACCEL := 230.0       # tangential assist while diving at a body
const SHIP_ORBIT_SPEED_MAX := 600.0   # assist fades to zero at this speed
const SHIP_SAFE_BRAKE := 1400.0       # auto-dock deceleration inside a safe zone
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

# ---- Meteor ----
const METEOR_INTERVAL := 10.0
const METEOR_DAMAGE := 0.5
const METEOR_KNOCK_DAMAGE := 5.0
const METEOR_RADIUS := 17.0           # meteor_*.png at 0.42 scale is ~34 px across
const METEOR_SPEED_MIN := 110.0
const METEOR_SPEED_MAX := 210.0
const METEOR_SPAWN_DIST := 900.0

# ---- Matter / XP ----
const MATTER_ABSORB := 240.0
const XP_PER_LEVEL := 20.0
const MATTER_BIG_CHANCE := 0.33
const MATTER_BIG_XP := 3
const MATTER_SMALL_XP := 1
## The tractor must outrun a gravity-assisted ship.  The speed cap is above
## SHIP_SPEED_HARD and the pull is strong at every range, so a mote is never
## left behind (or "flung away") when the player passes at high speed.
const MATTER_TRACTOR_SPEED := 900.0
const MATTER_TRACTOR_PULL_NEAR := 1400.0
const MATTER_TRACTOR_PULL_FAR := 400.0
const MATTER_COLLECT_RADIUS := 28.0
const MATTER_TRACTOR_LOCK := 4.0

# ---- Zones ----
const ZONE_RADIUS := 280.0           # 安全区扩张后的完整半径
const ZONE_ENTRY_RADIUS := 78.0      # 进入前只比飞船大一点，玩家到中心才触发扩张
const ZONE_EXPAND_TIME := 0.62       # 进入时的扩张动画时长
const ZONE_GRAVITY := 120.0
const ZONE_RESPAWN := 10.0
const ZONE_ENEMY_CLEAR := 520.0     # 安全区贴图边缘与敌人外壳的最小间距
## The zone is a capture well: the inward pull is always on while the player
## is in the approach band, and outward radial motion is braked so a fast
## tangential pass is bent back into the ring instead of being slung out.
const SAFE_FUEL_DIST := 1875.0      # placement band: ~12.5 s of full-thrust delta-v (50 fuel)
const SHOP_DIST_MIN := 2800.0
const SHOP_DIST_MAX := 4200.0
const SHOP_RESPAWN := 26.0

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
