class_name Drone
extends Node2D
## 小型高速自杀无人机。速度很高、转向率很低，锁定玩家后只能画一个大弧；
## 撞到玩家或敌人各造成 5 点伤害，并在撞击瞬间解体。
##
## 大转弯半径意味着玩家只要保持机动就能甩开它：锁定最多持续 5 秒，或者
## 在近身掠过后开始远离时立即脱锁；脱锁是永久的，之后只作为直线残骸飞行。
## 安全区/商店的驱离圈会把它推开，贴到区域本体则解体；脉冲技能会直接让
## 它原地解体。

var run
var radius := EG.DRONE_RADIUS
var speed := EG.DRONE_SPEED
var vel := Vector2.ZERO
var locked := true
var lost := false
## 木马协议：被脉冲反向骇入后，以 560 px/s 直撞主敌人并造成 15 伤害。
var hacked := false
var dead := false
var _lock_elapsed := 0.0
var _drift_t := 0.0
var _near := false
var _last_dist := 1e20
var _t := 0.0
var _sprite: Sprite2D
var _glow: Sprite2D
var _trail: CPUParticles2D

func _ready() -> void:
	z_index = 14
	_glow = Assets.world_sprite("ship_glow", true)
	_glow.scale = Vector2.ONE * 0.34
	_glow.modulate = Color(0.62, 0.42, 1.0, 0.5)
	add_child(_glow)
	_sprite = Assets.world_sprite("drone")
	add_child(_sprite)
	_trail = CPUParticles2D.new()
	_trail.texture = Assets.world("spark")
	_trail.amount = 14
	_trail.lifetime = 0.3
	_trail.local_coords = false
	_trail.emission_shape = CPUParticles2D.EMISSION_SHAPE_POINT
	_trail.direction = Vector2.LEFT
	_trail.spread = 12.0
	_trail.initial_velocity_min = 10.0
	_trail.initial_velocity_max = 42.0
	_trail.scale_amount_min = 0.14
	_trail.scale_amount_max = 0.34
	_trail.color = Color(0.78, 0.45, 1.0, 0.65)
	_trail.emitting = true
	_trail.material = Assets.additive_material()
	add_child(_trail)

func step(delta: float) -> void:
	if dead:
		return
	_t += delta

	# 安全区/商店的驱离场：靠近时把机头硬掰向外，贴到本体则当场解体。
	var warded := _zone_ward(delta)
	if dead:
		return

	if hacked:
		# 骇入后不再追踪玩家，也不再吃区域驱离：直线撞向锁定的敌人。
		position += vel * delta
		_visual()
		return
	if lost:
		_drift_t += delta
		if _drift_t >= EG.DRONE_DRIFT_LIFE:
			if run != null:
				run.remove_drone(self, false)
			return
		position += vel * delta
		_push_out()
		_visual()
		return

	var dist_now: float = position.distance_to(run.ship.position)
	_lock_elapsed += delta
	if _lock_elapsed >= EG.DRONE_LOCK_TIME:
		_lose_lock()
	elif _near and dist_now > _last_dist + 0.5:
		# 已经近身掠过、现在开始远离：转弯半径太大，追不回来了。
		_lose_lock()
	if not _near and dist_now < EG.DRONE_LOSE_DIST:
		_near = true
	_last_dist = dist_now

	if not lost and not warded:
		# 预判一点点玩家的速度，但仍然受极低转向率限制：高速掠过时会
		# 冲过头，再画一个很大的弧转回来。
		var target: Vector2 = run.ship.position + run.ship.vel * 0.22
		var cur := vel.angle()
		var desired := (target - position).angle()
		var diff := wrapf(desired - cur, -PI, PI)
		var max_step := EG.DRONE_TURN * delta
		vel = Vector2.RIGHT.rotated(cur + clampf(diff, -max_step, max_step)) * speed

	position += vel * delta
	_push_out()
	_visual()

func _push_out() -> void:
	if run != null and run.galaxy != null:
		position = run.galaxy.push_out_of_bodies(position, radius)

## 永久脱锁：不再追踪玩家，只沿当前方向直线飞离，几秒后自行解体。
func _lose_lock() -> void:
	if lost:
		return
	locked = false
	lost = true
	_drift_t = 0.0
	if _trail != null:
		_trail.emitting = false

## Returns true while the drone is being repelled by a zone. If it actually
## touches the zone footprint it asks the run to disintegrate it and goes dead.
func _zone_ward(delta: float) -> bool:
	if run == null:
		return false
	var warded := false
	for z in run.zones:
		if z == null or not is_instance_valid(z) or not z.active:
			continue
		var clear: float = z.clearance_radius()
		var d: float = position.distance_to(z.position)
		if d < clear + radius + 2.0:
			run.remove_drone(self, true)
			return true
		var ward: float = clear + EG.DRONE_ZONE_WARD
		if d >= ward:
			continue
		var away: Vector2 = position - z.position
		if away.length() < 1.0:
			away = Vector2.RIGHT
		away = away.normalized()
		# 驱离是强行把机头掰向圈外，强于它自己的转向能力：否则 460 px/s
		# 的高速机在 0.4 秒内就会冲进区域本体。
		var cur := vel.angle()
		var diff := wrapf(away.angle() - cur, -PI, PI)
		var max_step := 12.0 * delta
		vel = Vector2.RIGHT.rotated(cur + clampf(diff, -max_step, max_step)) * speed
		warded = true
	return warded

func _visual() -> void:
	rotation = vel.angle()
	if _glow != null:
		if hacked:
			_glow.modulate.a = 0.75
		else:
			_glow.modulate.a = 0.12 if lost else 0.42 + 0.12 * sin(_t * 10.0)
	if _sprite != null:
		if hacked:
			_sprite.modulate = Color(1.0, 0.62, 0.85, 1.0)
		elif lost:
			_sprite.modulate = Color(0.62, 0.54, 0.78, 1.0)
		else:
			_sprite.modulate = Color(1, 1, 1, 1)

func remove() -> void:
	dead = true
	queue_free()
