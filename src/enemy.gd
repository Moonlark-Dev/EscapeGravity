class_name Enemy
extends Node2D
## Non-small attacker. Five hulls share the visibility-driven movement and fire
## rules from the design document:
##   turret       R420  3 hard-points, the signature attacker
##   nest         R300  wider volleys
##   aegis        R360  120° frontal shield, rear is a 1.5x weak point
##   singularity  R320  repel ring / siphon window
##   twin         R210  paired station that docks-heals its partner
## Elite affixes add point-defence orbs, phase blinks and volatile mines
## instead of stacking raw HP.

var run
var kind := "turret"
var radius := EG.TURRET_RADIUS
var hp := EG.TURRET_HP
var max_hp := EG.TURRET_HP
var speed_out := EG.TURRET_SPEED_OUT
var speed_in := EG.TURRET_SPEED_IN
var fire_out := EG.TURRET_FIRE_OUT
var fire_in := EG.TURRET_FIRE_IN
var burst := EG.TURRET_BURST
var max_locked := EG.MISSILE_MAX_LOCKED
var overheat_time := EG.TURRET_OVERHEAT
var depth := 1
var elite := false
var affix := ""                      # point_defense / phase_blink / volatile
var in_view := false
var discovered := false
var hunting := false
var overheated := false
var overheat_timer := 0.0
var fire_timer := 2.0
var burst_left := 0
var burst_gap := 0.0
var dead := false
var hit_flash := 0.0
var facing := 0.0                    # +X = 0, only aegis / twin use it

# Twin pair state (leader drives the formation).
var twin: Enemy = null
var twin_leader := false
var pair_center := Vector2.ZERO
var pair_angle := 0.0
var heal_delay := 0.0
var heal_left := 0.0

# Singularity rig state.
var siphon := false
var state_timer := EG.RIG_REPEL_TIME

var _sprite: Sprite2D
var _glow: Sprite2D
var _ember: Sprite2D
var _shield: Sprite2D
var _ring_out: Sprite2D
var _ring_in: Sprite2D
var _guards: Array = []
var _guard_cd: Array = []
var _guard_angle := 0.0
var _t := 0.0
var _reveal := 0.0
var _rng := RandomNumberGenerator.new()

const SPRITE_R := {
	"turret": 400.0, "nest": 124.0, "aegis": 360.0,
	"singularity": 320.0, "twin": 210.0,
}
## 贴图文件名与 kind 不同名（kind 是玩法标识，贴图是美术资源）。
const SPRITE_NAME := {
	"turret": "turret", "nest": "nest", "aegis": "carrier",
	"singularity": "singularity_rig", "twin": "pylon",
}
const NAMES := {
	"turret": "炮塔", "nest": "导弹巢", "aegis": "偏导母舰",
	"singularity": "引力阱舰", "twin": "双子中继站",
}
const AFFIX_NAMES := {
	"point_defense": "拦截点防", "phase_blink": "相位跃迁", "volatile": "超载殉爆",
}

func _ready() -> void:
	z_index = -2
	_rng.seed = hash(position) + 51
	var key: String = kind if SPRITE_R.has(kind) else "turret"
	_sprite = Assets.world_sprite(SPRITE_NAME.get(key, key))
	_sprite.scale = Vector2.ONE * (radius / float(SPRITE_R[key]))
	_glow = Assets.world_sprite("ship_glow", true)
	_ember = Assets.world_sprite("ship_glow", true)
	match kind:
		"turret":
			_glow.scale = Vector2.ONE * 4.2
			_glow.modulate = Color(0.35, 0.8, 1.0, 0.10)
			# 复用同一个 _ember 节点，避免创建后丢弃造成资源泄漏。
			_ember.texture = Assets.world("turret_ember")
			_ember.scale = Vector2.ONE * (radius / 384.0)
			_ember.modulate = Color(1.0, 0.3, 0.25, 0.0)
		"nest":
			_glow.scale = Vector2.ONE * 2.4
			_glow.modulate = Color(1.0, 0.3, 0.7, 0.13)
			_ember.scale = Vector2.ONE * 0.9
			_ember.modulate = Color(1.0, 0.3, 0.5, 0.0)
		"aegis":
			_glow.scale = Vector2.ONE * 3.0
			_glow.modulate = Color(0.45, 0.75, 1.0, 0.10)
			_ember.scale = Vector2.ONE * 1.4
			_ember.modulate = Color(0.5, 0.85, 1.0, 0.0)
		"singularity":
			_glow.scale = Vector2.ONE * 2.8
			_glow.modulate = Color(0.62, 0.42, 1.0, 0.14)
			_ember.scale = Vector2.ONE * 1.2
			_ember.modulate = Color(0.8, 0.4, 1.0, 0.0)
		"twin":
			_glow.scale = Vector2.ONE * 1.8
			_glow.modulate = Color(1.0, 0.72, 0.35, 0.12)
			_ember.scale = Vector2.ONE * 0.8
			_ember.modulate = Color(1.0, 0.6, 0.25, 0.0)
	add_child(_glow)
	add_child(_sprite)
	add_child(_ember)
	if kind == "aegis":
		# 正面弧形能量盾：始终贴着母舰朝向，命中角度由 Run 计算。
		_shield = Assets.world_sprite("shield_arc", true)
		_shield.scale = Vector2.ONE * ((radius + 24.0) / 330.0)
		_shield.modulate = Color(0.55, 0.9, 1.0, 0.55)
		add_child(_shield)
	if kind == "singularity":
		_ring_out = Assets.world_sprite("ring_repel", true)
		_ring_out.scale = Vector2.ONE * (EG.RIG_REPEL_RADIUS / 210.0)
		_ring_out.modulate = Color(0.45, 0.95, 1.0, 0.0)
		add_child(_ring_out)
		_ring_in = Assets.world_sprite("ring_siphon", true)
		_ring_in.scale = Vector2.ONE * (EG.RIG_SIPHON_RADIUS / 210.0)
		_ring_in.modulate = Color(0.72, 0.45, 1.0, 0.0)
		add_child(_ring_in)
	if affix == "point_defense":
		for i in range(2):
			var orb := Assets.world_sprite("guard_orb", true)
			orb.scale = Vector2.ONE * (EG.POINT_DEFENSE_RADIUS / 28.0)
			orb.modulate = Color(0.55, 0.95, 1.0, 0.9)
			add_child(orb)
			_guards.append(orb)
			_guard_cd.append(0.0)
	if elite:
		_sprite.modulate = Color(1.0, 0.82, 0.62)
	# Undiscovered attackers are fully invisible: no hull, glow or ember may
	# leak their position before the player's screen shows them.
	visible = false

## Skips the discovery fade (screenshots / tests / debug hooks).
func reveal(instant: bool = true) -> void:
	discovered = true
	hunting = true
	_reveal = 1.0 if instant else _reveal
	visible = true
	modulate = Color(1.0, 1.0, 1.0, 1.0)

## 让朝向目标的正面（含护盾贴图）立刻对齐，供截图/调试跳过模拟时使用。
func face_towards(pos: Vector2) -> void:
	facing = (pos - position).angle()
	if _sprite != null:
		_sprite.rotation = facing
	if _shield != null:
		_shield.rotation = facing

func display_name() -> String:
	var base: String = NAMES.get(kind, "炮塔")
	if affix != "":
		base += " · " + str(AFFIX_NAMES.get(affix, "精英"))
	elif elite:
		base += " · 精英"
	return base

func step(delta: float) -> void:
	_t += delta
	if dead:
		return
	hit_flash = maxf(0.0, hit_flash - delta)
	in_view = run.enemy_in_view(self)
	var player_pos: Vector2 = run.ship.position
	var dir: Vector2 = (player_pos - position).normalized()
	var dist_to_player: float = position.distance_to(player_pos)

	# Discovery: the first frame any part of the hull enters the screen. Until
	# then the enemy is a hidden contact that does not appear on radar either.
	if not discovered and in_view:
		discovered = true
		if run.hud != null:
			run.hud.toast("发现攻击者：%s" % NAMES.get(kind, "炮塔"), EG.C_MAGENTA, 2.2)
	_reveal = move_toward(_reveal, 1.0 if discovered else 0.0, delta / maxf(0.01, EG.ENEMY_REVEAL_TIME))
	visible = _reveal > 0.001
	modulate = Color(1.0, 1.0, 1.0, _reveal)

	if not hunting and dist_to_player <= EG.ENEMY_AGGRO_RANGE:
		hunting = true

	# Oriented hulls turn toward the player at their own (slow) rate.
	if kind == "aegis":
		facing = rotate_toward(facing, (player_pos - position).angle(), EG.AEGIS_TURN * delta)
		_sprite.rotation = facing
	elif kind == "twin":
		facing = rotate_toward(facing, (player_pos - position).angle(), 0.9 * delta)
		_sprite.rotation = facing

	var avoid := _avoidance(player_pos)
	if avoid.length() > 0.01:
		dir = (dir + avoid).normalized()

	if kind == "twin" and twin != null and is_instance_valid(twin) and not twin.dead:
		if twin_leader:
			_move_pair(delta, dir, dist_to_player)
	else:
		_move_single(delta, dir, dist_to_player)
		if run != null and run.galaxy != null:
			position = run.galaxy.push_out_of_bodies(position, radius)

	if kind == "singularity":
		_rig_fields(delta)

	_update_affix(delta)
	_update_twin_heal(delta)

	if overheated:
		overheat_timer -= delta
		if overheat_timer <= 0.0:
			overheated = false
			_on_overheat_end()
	else:
		# 引力阱舰在虹吸充能态只蓄力，不进行常规齐射。
		if kind == "singularity" and siphon:
			fire_timer = maxf(fire_timer, 0.4)
		else:
			_fire_logic(delta)
	_visual(delta)

func _avoidance(player_pos: Vector2) -> Vector2:
	var avoid := Vector2.ZERO
	for b in run.galaxy.bodies:
		var gap: float = position.distance_to(b.position) - b.radius - radius
		if gap < 700.0:
			var away: Vector2 = (position - b.position).normalized()
			avoid += away * (1.0 - clampf(gap / 700.0, 0.0, 1.0)) * 2.2
	# Skirt a safe zone instead of stalling against it.
	if run.safe_zone != null and run.safe_zone.active:
		var zpos: Vector2 = run.safe_zone.position
		var zd: float = position.distance_to(zpos)
		var clear: float = run.safe_zone.clearance_radius() + radius + 240.0
		if zd < clear:
			var away2: Vector2 = (position - zpos)
			if away2.length() < 1.0:
				away2 = Vector2.RIGHT.rotated(_rng.randf() * TAU)
			away2 = away2.normalized()
			var toward: Vector2 = (player_pos - position).normalized()
			var tangent: Vector2 = away2.orthogonal()
			if tangent.dot(toward) < 0.0:
				tangent = -tangent
			var push: float = 1.0 - clampf(zd / clear, 0.0, 1.0)
			avoid += (tangent * 1.9 + away2 * 1.2) * push * 2.2
	return avoid

func _move_single(delta: float, dir: Vector2, dist_to_player: float) -> void:
	var spd: float = speed_in if in_view else speed_out
	if not discovered:
		# Hidden hunters close in faster and ignore the normal standoff.
		spd = speed_out * EG.ENEMY_CHASE_MULT
	if hunting:
		if not discovered and not in_view:
			position += dir * spd * delta
		elif dist_to_player > radius + 520.0:
			position += dir * spd * delta
		elif dist_to_player < radius + 260.0:
			position -= dir * spd * 0.55 * delta

## 双子中继站：两站以 pair_center 为中心、间距 750px 同步公转，整体像单个
## 敌人一样逼近/后退。跟班的位置由 leader 直接写入，自己不再单独移动。
func _move_pair(delta: float, dir: Vector2, dist_to_player: float) -> void:
	var spd: float = speed_in if in_view else speed_out
	if not discovered:
		spd = speed_out * EG.ENEMY_CHASE_MULT
	pair_angle += EG.PYLON_ORBIT * delta
	if hunting or not discovered:
		if (not discovered and not in_view) or dist_to_player > radius + 520.0:
			pair_center += dir * spd * delta
		elif dist_to_player < radius + 260.0:
			pair_center -= dir * spd * 0.55 * delta
	var half: Vector2 = Vector2.RIGHT.rotated(pair_angle) * (EG.PYLON_GAP * 0.5)
	position = run.galaxy.push_out_of_bodies(pair_center + half, radius)
	if twin != null and is_instance_valid(twin) and not twin.dead:
		twin.position = run.galaxy.push_out_of_bodies(pair_center - half, twin.radius)
		pair_center = (position + twin.position) * 0.5

func _fire_logic(delta: float) -> void:
	fire_timer -= delta
	if burst_left > 0:
		burst_gap -= delta
		if burst_gap <= 0.0:
			_fire_one()
			burst_left -= 1
			burst_gap = 0.2
	elif fire_timer <= 0.0:
		var locked: int = run.locked_missile_count()
		var sneak: int = run.sneak_missile_count()
		# An undiscovered attacker still shoots; the missile comes in from off
		# screen so the shot itself never reveals the hull.
		var can_fire: bool = locked < max_locked and not run.player_hidden and (discovered or hunting)
		if not discovered and sneak >= EG.ENEMY_HIDDEN_MAX:
			can_fire = false
		if can_fire:
			burst_left = 1 if _rng.randf() < 0.45 else burst
			burst_gap = 0.0
			fire_timer = fire_in if in_view else fire_out
		else:
			fire_timer = 0.25

func _fire_one() -> void:
	if run.locked_missile_count() >= max_locked:
		burst_left = 0
		return
	var player: Vector2 = run.ship.position
	if not in_view and not discovered:
		if run.sneak_missile_count() >= EG.ENEMY_HIDDEN_MAX:
			burst_left = 0
			return
		_fire_hidden(player)
		return
	var spawn: Vector2
	var muzzle_angle: float
	if in_view:
		# In view the missile must come out of the hull. Turrets have three
		# hard-points; nests launch from the forward aperture; the aegis and
		# the twin pylons fire from their bow.
		var to_player: Vector2 = (player - position).normalized()
		var aim_angle: float = to_player.angle()
		muzzle_angle = aim_angle
		if kind == "turret":
			var step: float = TAU / 3.0
			var local: float = wrapf(aim_angle - _sprite.rotation, -PI, PI)
			muzzle_angle = _sprite.rotation + roundf(local / step) * step
		elif kind == "aegis" or kind == "twin":
			muzzle_angle = facing
		spawn = position + Vector2.RIGHT.rotated(muzzle_angle) * (radius + 14.0)
		if run.galaxy.is_inside_any_body(spawn, 26.0):
			muzzle_angle = aim_angle
			spawn = position + Vector2.RIGHT.rotated(aim_angle) * (radius + 14.0)
	else:
		# Outside the view the design doc keeps the 820 px lateral entrance.
		var to_p: Vector2 = (player - position).normalized()
		var perp: Vector2 = to_p.orthogonal()
		var side: float = 1.0 if _rng.randf() < 0.5 else -1.0
		spawn = player + perp * side * 820.0
		var bad: bool = spawn.distance_to(position) < radius + 90.0 or run.galaxy.is_inside_any_body(spawn, 40.0)
		if bad:
			side = -side
			spawn = player + perp * side * 820.0
			bad = spawn.distance_to(position) < radius + 90.0 or run.galaxy.is_inside_any_body(spawn, 40.0)
		if bad:
			muzzle_angle = (player - position).angle() + _rng.randf_range(-0.3, 0.3)
			spawn = position + Vector2.RIGHT.rotated(muzzle_angle) * (radius + 42.0)
	var aim: float = (player + run.ship.vel * 0.35 - spawn).angle()
	var ammo: String = run.roll_enemy_ammo(kind, depth)
	run.spawn_enemy_missile(self, spawn, aim, ammo)
	Fx.sparks(run.fx_layer, spawn, Color(1.0, 0.55, 0.3, 0.9), 7, 130.0)

## Missile launch while the attacker is still undiscovered.
func _fire_hidden(player: Vector2) -> void:
	var rect: Rect2 = run.screen_rect()
	var center := rect.get_center()
	var half := rect.size * 0.5
	var enemy_bearing := (position - player).angle()
	var bearing: float
	if _rng.randf() < EG.ENEMY_HIDDEN_BIAS:
		bearing = enemy_bearing + _rng.randf_range(-EG.ENEMY_HIDDEN_SPREAD, EG.ENEMY_HIDDEN_SPREAD)
	else:
		bearing = _rng.randf() * TAU
	var spawn := _offscreen_point(center, half, bearing)
	for i in range(10):
		var clear: bool = not run.galaxy.is_inside_any_body(spawn, 46.0) and spawn.distance_to(position) > radius + 120.0
		if clear:
			break
		bearing += (0.5 if i % 2 == 0 else -0.5) * float(i + 1)
		spawn = _offscreen_point(center, half, bearing)
	var dir := (spawn - center)
	if dir.length() < 1.0:
		dir = Vector2.RIGHT.rotated(bearing)
	dir = dir.normalized()
	var side: float = 1.0 if _rng.randf() < 0.5 else -1.0
	var heading: Vector2 = dir.orthogonal() * side - dir * _rng.randf_range(0.18, 0.5)
	var ammo: String = run.roll_enemy_ammo(kind, depth)
	var m = run.spawn_enemy_missile(self, spawn, heading.angle(), ammo)
	m.sneak = true

func _offscreen_point(center: Vector2, half: Vector2, bearing: float) -> Vector2:
	var dir := Vector2.RIGHT.rotated(bearing)
	var edge: float = minf(absf(half.x / maxf(absf(dir.x), 0.001)),
		absf(half.y / maxf(absf(dir.y), 0.001)))
	return center + dir * (edge + _rng.randf_range(EG.ENEMY_HIDDEN_EDGE_MIN, EG.ENEMY_HIDDEN_EDGE_MAX))

# ---------------------------------------------------------------- mechanics

## 引力阱舰的斥力环 / 虹吸场。斥力把低速直射弹推偏擦过；虹吸同时拉扯玩家、
## 导弹与陨石，把脱锁弹/陨石吸到脸上，这就是它的解题窗口。
func _rig_fields(delta: float) -> void:
	state_timer -= delta
	if state_timer <= 0.0:
		siphon = not siphon
		state_timer = EG.RIG_SIPHON_TIME if siphon else EG.RIG_REPEL_TIME
		if not siphon:
			# 虹吸结束 → 蓄好的齐射一次打出来。
			burst_left = EG.RIG_SIPHON_BURST
			burst_gap = 0.0
		else:
			if run.hud != null and discovered:
				run.hud.toast("引力阱舰进入虹吸态 · 把脱锁弹送进吸引圈", EG.C_VIOLET, 2.0)
	if siphon:
		for m in run.missiles:
			if m.dead:
				continue
			var d: Vector2 = position - m.position
			var dist: float = d.length()
			if dist > EG.RIG_SIPHON_RADIUS or dist < 1.0:
				continue
			var k: float = 1.0 - dist / EG.RIG_SIPHON_RADIUS
			m.position += d / dist * EG.RIG_SIPHON_PULL * (0.35 + 0.65 * k) * delta
		for met in run.meteors:
			if met.dead:
				continue
			var dm: Vector2 = position - met.position
			var md: float = dm.length()
			if md > EG.RIG_SIPHON_RADIUS or md < 1.0:
				continue
			met.position += dm / md * EG.RIG_SIPHON_PULL * 0.7 * delta
		var ds: Vector2 = position - run.ship.position
		if ds.length() < EG.RIG_SIPHON_RADIUS and ds.length() > 1.0:
			run.ship.vel += ds.normalized() * EG.RIG_SIPHON_SHIP * delta
	else:
		for m in run.missiles:
			if m.dead:
				continue
			var d2: Vector2 = m.position - position
			var dist2: float = d2.length()
			if dist2 > EG.RIG_REPEL_RADIUS or dist2 < 1.0:
				continue
			if m.vel.length() >= EG.RIG_REPEL_MAX_SPEED:
				continue
			var inward: float = -m.vel.dot(d2 / dist2)
			if inward <= 0.0:
				continue
			m.position += d2 / dist2 * EG.RIG_REPEL_PUSH * delta

func _update_affix(delta: float) -> void:
	if affix != "point_defense":
		return
	_guard_angle += EG.POINT_DEFENSE_ORBIT * delta * (0.45 if overheated else 1.0)
	for i in range(_guards.size()):
		_guard_cd[i] = maxf(0.0, float(_guard_cd[i]) - delta)
		var orb: Sprite2D = _guards[i]
		orb.position = guard_position(i)
		orb.rotation += delta * 3.0
		orb.modulate.a = 0.30 if float(_guard_cd[i]) > 0.0 else 0.9

func guard_position(i: int) -> Vector2:
	var a: float = _guard_angle + PI * float(i)
	return Vector2.RIGHT.rotated(a) * (radius + 44.0)

## 拦截点防：低速零星导弹会被护卫球吃掉；速度 ≥280 的导弹（加速弹、
## 引力加速后的弹）直接凿穿，齐射也能让两颗球同时进入冷却。
func try_intercept(m) -> bool:
	if affix != "point_defense" or dead:
		return false
	if m.vel.length() >= EG.POINT_DEFENSE_MIN_SPEED:
		return false
	for i in range(_guards.size()):
		if float(_guard_cd[i]) > 0.0:
			continue
		if m.position.distance_to(position + guard_position(i)) < EG.POINT_DEFENSE_RADIUS + EG.MISSILE_RADIUS:
			_guard_cd[i] = EG.POINT_DEFENSE_CD
			Fx.sparks(run.fx_layer, m.position, Color(0.55, 0.95, 1.0, 0.9), 8, 150.0)
			Audio.play("sfx_explosion_small", -14.0)
			return true
	return false

func _update_twin_heal(delta: float) -> void:
	if kind != "twin" or twin == null or not is_instance_valid(twin) or twin.dead:
		heal_delay = 0.0
		heal_left = 0.0
		return
	if heal_delay > 0.0:
		heal_delay = maxf(0.0, heal_delay - delta)
		# 联动条件只看另一座：若它正在过热，这次回血不启动。
		if heal_delay <= 0.0 and not twin.overheated:
			heal_left = EG.PYLON_HEAL_TIME
	if heal_left > 0.0:
		heal_left = maxf(0.0, heal_left - delta)
		hp = minf(max_hp, hp + max_hp * EG.PYLON_HEAL_RATE * delta)

func _on_overheat_end() -> void:
	if affix != "phase_blink" or run == null or run.ship == null:
		return
	var from := position
	var to_ship: Vector2 = (run.ship.position - position).normalized()
	if to_ship.length() < 0.1:
		to_ship = Vector2.RIGHT
	var side: float = 1.0 if _rng.randf() < 0.5 else -1.0
	position = run.ship.position + to_ship.rotated(side * EG.PHASE_BLINK_ANGLE) * EG.PHASE_BLINK_DIST
	position = run.galaxy.push_out_of_bodies(position, radius + 20.0)
	Fx.warp(run.fx_layer, from, Color(0.75, 0.55, 1.0, 0.8))
	Fx.warp(run.fx_layer, position, Color(0.75, 0.55, 1.0, 0.6))
	fire_timer = maxf(fire_timer, 1.0)

## 超载殉爆：每次过热都向四周抛射 6 枚无锁慢速水雷弹。
func scatter_mines() -> void:
	if affix != "volatile" or run == null:
		return
	for i in range(EG.VOLATILE_MINES):
		var ang: float = TAU * float(i) / float(EG.VOLATILE_MINES) + _rng.randf_range(-0.12, 0.12)
		# 出膛点必须在外壳之外，否则水雷会立刻炸到抛射者自己。
		run.spawn_mine(self, position + Vector2.RIGHT.rotated(ang) * (radius + 36.0), ang, EG.VOLATILE_MINE_SPEED)
	Fx.warp(run.fx_layer, position, Color(1.0, 0.55, 0.25, 0.7))

## 零点静滞：脉冲打断当前齐射并延长过热。
func stasis(seconds: float) -> void:
	if dead:
		return
	overheated = true
	overheat_timer = maxf(overheat_timer, 0.0) + seconds
	burst_left = 0
	fire_timer = maxf(fire_timer, 1.2)

func stun(seconds: float) -> void:
	burst_left = 0
	fire_timer = maxf(fire_timer, seconds)

# ---------------------------------------------------------------- damage

## 结算一次命中。偏导母舰的正面 120° 会把伤害衰减到 20% 且不触发过热，
## 舰尾则吃 1.5 倍暴击并进入 4 秒长过热。返回实际结算结果供 HUD/特效使用。
func apply_hit(amount: float, hit_pos: Vector2) -> Dictionary:
	var dealt := amount
	var crit := false
	var heat := overheat_time
	if kind == "aegis":
		var ang: float = (hit_pos - position).angle()
		var diff: float = absf(wrapf(ang - facing, -PI, PI))
		if diff <= EG.AEGIS_HALF_ARC:
			dealt = amount * EG.AEGIS_FRONT_SCALE
			heat = 0.0
		elif diff >= PI - EG.AEGIS_HALF_ARC:
			dealt = amount * EG.AEGIS_CRIT_SCALE
			heat = EG.AEGIS_CRIT_OVERHEAT
			crit = true
	hp -= dealt
	hit_flash = 0.12
	if heat > 0.0:
		overheated = true
		overheat_timer = heat
		burst_left = 0
		fire_timer = 0.6
	if kind == "twin" and twin != null and is_instance_valid(twin) and not twin.dead:
		heal_delay = EG.PYLON_HEAL_DELAY
		heal_left = 0.0
	return {"damage": dealt, "crit": crit, "overheated": heat > 0.0, "blocked_front": kind == "aegis" and heat == 0.0}

func _visual(delta: float) -> void:
	match kind:
		"turret":
			_sprite.rotation += delta * 0.025
		"nest":
			_sprite.rotation += delta * 0.18
			_sprite.position = Vector2(0, sin(_t * 1.7) * 6.0)
		"singularity":
			_sprite.rotation += delta * 0.12
		"twin":
			_sprite.position = Vector2(0, sin(_t * 1.4) * 4.0)
	var heated: float = (0.55 + 0.2 * sin(_t * 9.0)) if overheated else 0.0
	_ember.modulate.a = lerpf(_ember.modulate.a, heated, 1.0 - pow(0.001, delta))
	_glow.modulate.a = 0.10 + 0.05 * sin(_t * 2.0)
	if _shield != null:
		_shield.rotation = facing
		var front_alpha: float = 0.50 + 0.10 * sin(_t * 3.0)
		_shield.modulate.a = 0.20 if overheated else front_alpha
	if _ring_out != null and _ring_in != null:
		_ring_out.rotation += delta * 0.6
		_ring_in.rotation -= delta * 1.1
		var target_out: float = 0.0 if siphon else (0.34 + 0.12 * sin(_t * 5.0))
		var target_in: float = (0.38 + 0.16 * sin(_t * 6.0)) if siphon else 0.0
		_ring_out.modulate.a = lerpf(_ring_out.modulate.a, target_out, 1.0 - pow(0.002, delta))
		_ring_in.modulate.a = lerpf(_ring_in.modulate.a, target_in, 1.0 - pow(0.002, delta))
		var breath: float = 1.0 + 0.03 * sin(_t * (5.0 if siphon else 2.0))
		_ring_out.scale = Vector2.ONE * (EG.RIG_REPEL_RADIUS / 210.0) * breath
		_ring_in.scale = Vector2.ONE * (EG.RIG_SIPHON_RADIUS / 210.0) * (2.0 - breath)
	var base := Color(1.0, 1.0, 1.0)
	if kind == "turret":
		base = Color(0.70, 0.79, 0.92)
	if hit_flash > 0.0:
		_sprite.modulate = Color(2.0, 2.0, 2.0, 1.0)
	elif elite:
		_sprite.modulate = base.lerp(Color(1.0, 0.62, 0.4), 0.5)
	elif overheated:
		_sprite.modulate = base.lerp(Color(0.55, 0.8, 1.0), 0.7)
	else:
		_sprite.modulate = base

func remove() -> void:
	dead = true
	queue_free()
