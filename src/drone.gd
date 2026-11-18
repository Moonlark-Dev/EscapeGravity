class_name Drone
extends Node2D
## 小型高速自杀无人机。速度很高、转向率很低，锁定玩家后只能画一个大弧；
## 撞到玩家或敌人各造成 5 点伤害。撞到玩家时大概率被甩飞并永久脱锁，
## 之后不再追踪。安全区/商店的驱离圈会把它推开，贴到区域本体则解体；
## 脉冲技能会直接让它原地解体。

var run
var radius := EG.DRONE_RADIUS
var speed := EG.DRONE_SPEED
var vel := Vector2.ZERO
var locked := true
var flung := false
var hit_cd := 0.0
var life := 0.0
var dead := false
var deflect_chance := EG.DRONE_DEFLECT_CHANCE
var _flung_t := 0.0
var _t := 0.0
var _sprite: Sprite2D
var _glow: Sprite2D
var _trail: CPUParticles2D

func _ready() -> void:
	z_index = 14
	_glow = Assets.world_sprite("ship_glow", true)
	_glow.scale = Vector2.ONE * 0.34
	_glow.modulate = Color(1.0, 0.42, 0.18, 0.5)
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
	_trail.color = Color(1.0, 0.5, 0.2, 0.6)
	_trail.emitting = true
	_trail.material = Assets.additive_material()
	add_child(_trail)

func step(delta: float) -> void:
	if dead:
		return
	_t += delta
	life += delta
	hit_cd = maxf(0.0, hit_cd - delta)

	if flung:
		_flung_t += delta
		if _flung_t >= EG.DRONE_FLUNG_LIFE:
			if run != null:
				run.remove_drone(self, false)
			return
		position += vel * delta
		_visual()
		return

	# 安全区/商店的驱离场：靠近时把机头硬掰向外，贴到本体则当场解体。
	if _zone_ward(delta):
		if dead:
			return
	else:
		if locked and run != null:
			# 预判一点点玩家的速度，但仍然受极低转向率限制：高速掠过时会
			# 冲过头，再画一个很大的弧转回来。
			var target: Vector2 = run.ship.position + run.ship.vel * 0.22
			var cur := vel.angle()
			var desired := (target - position).angle()
			var diff := wrapf(desired - cur, -PI, PI)
			var max_step := EG.DRONE_TURN * delta
			vel = Vector2.RIGHT.rotated(cur + clampf(diff, -max_step, max_step)) * speed

	position += vel * delta
	if run != null and run.galaxy != null:
		position = run.galaxy.push_out_of_bodies(position, radius)
	_visual()

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

## 被玩家撞飞：沿远离玩家的方向弹开，永久脱锁；之后只作为高速残骸飞行。
func fling_from(ship) -> void:
	var away: Vector2 = position - ship.position
	if away.length() < 1.0:
		away = -vel.normalized() if vel.length() > 1.0 else Vector2.RIGHT
	away = away.normalized()
	var carry := Vector2.ZERO
	if ship.vel.length() > 20.0:
		carry = ship.vel.normalized() * 0.55
	var dir: Vector2 = away + carry
	if dir.length() < 0.1:
		dir = away
	dir = dir.normalized()
	locked = false
	flung = true
	_flung_t = 0.0
	speed = EG.DRONE_FLUNG_SPEED
	vel = dir * speed
	hit_cd = 0.6
	if _trail != null:
		_trail.emitting = false

func _visual() -> void:
	rotation = vel.angle()
	if _glow != null:
		_glow.modulate.a = 0.12 if flung else 0.42 + 0.12 * sin(_t * 10.0)
	if _sprite != null:
		_sprite.modulate = Color(0.72, 0.6, 0.55, 1.0) if flung else Color(1, 1, 1, 1)

func remove() -> void:
	dead = true
	queue_free()
