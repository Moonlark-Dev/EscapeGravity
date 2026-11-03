class_name PlayerShip
extends Node2D
## Player ship: inertial thrust, boost gauge, fuel, shield, operation assist.
## No weapons. The only way to hurt enemies is to make missiles hit them.

var run
var vel := Vector2.ZERO
var facing := -PI * 0.5
var fuel := EG.SHIP_FUEL_MAX
var fuel_max := EG.SHIP_FUEL_MAX
var shield := EG.SHIP_SHIELD_MAX
var shield_max := EG.SHIP_SHIELD_MAX
var boost_meter := EG.SHIP_BOOST_MAX
var boost_cap := EG.SHIP_BOOST_MAX
var boost_mult := 1.0
var boost_ready := true
var thrusting := false
var boosting := false
var thrust_level := 0.0
var shield_ratio := 1.0
var invuln := 0.0
var dash_time := 0.0
var dash_dir := Vector2.RIGHT
var dash_speed := 0.0
var dead := false
var _boost_idle := 0.0
var _hull: Sprite2D
var _plume: Sprite2D
var _shield_sprite: Sprite2D
var _trail: CPUParticles2D
var _spark_timer := 0.0
var _t := 0.0

const R := EG.SHIP_RADIUS

func _ready() -> void:
	z_index = 20
	_hull = Assets.world_sprite("ship")
	add_child(_hull)
	_shield_sprite = Assets.world_sprite("ship_glow", true)
	_shield_sprite.scale = Vector2.ONE * 1.05
	_shield_sprite.modulate = Color(0.35, 0.85, 1.0, 0.0)
	add_child(_shield_sprite)
	_plume = Assets.world_sprite("engine_glow", true)
	_plume.position = Vector2(-30, 0)
	_plume.rotation = PI
	_plume.scale = Vector2(0.1, 0.7)
	_plume.modulate = Color(0.45, 0.9, 1.0, 0.9)
	add_child(_plume)
	_trail = CPUParticles2D.new()
	_trail.texture = Assets.world("spark")
	_trail.amount = 26
	_trail.lifetime = 0.45
	_trail.local_coords = false
	_trail.emission_shape = CPUParticles2D.EMISSION_SHAPE_POINT
	_trail.direction = Vector2(-1, 0)
	_trail.spread = 24.0
	_trail.initial_velocity_min = 30.0
	_trail.initial_velocity_max = 110.0
	_trail.scale_amount_min = 0.3
	_trail.scale_amount_max = 0.8
	_trail.color = Color(0.4, 0.9, 1.0, 0.8)
	_trail.emitting = false
	_trail.material = Assets.additive_material()
	_trail.position = Vector2(-14, 0)
	add_child(_trail)

func step(delta: float, dir: Vector2, want_boost: bool) -> void:
	_t += delta
	invuln = maxf(0.0, invuln - delta)
	thrusting = dir.length() > 0.15 and fuel > 0.0
	dash_time = maxf(0.0, dash_time - delta)
	var was_boosting := boosting
	boosting = thrusting and want_boost and boost_ready and boost_meter > 0.02
	if boosting and not was_boosting and run != null:
		Audio.play("sfx_boost", -8.0)

	# 回充只看“是否真的在加力”：松开加力后即使仍在推进，加力槽也照常恢复。
	# 槽耗尽后要求先松开加力键，避免按住不放时在 0.22 阈值上反复抖动着火。
	if boosting:
		_boost_idle = 0.0
	else:
		_boost_idle += delta
	if not boost_ready and boost_meter >= EG.SHIP_BOOST_RESUME and not want_boost:
		boost_ready = true

	if thrusting:
		if boosting:
			boost_meter = maxf(0.0, boost_meter - delta)
			# 触底即耗尽（点火下限是 0.02，留残量会在阈值附近反复微点火）
			if boost_meter <= 0.02:
				boosting = false
				boost_ready = false
				boost_meter = 0.0
			fuel = maxf(0.0, fuel - EG.SHIP_FUEL_BOOST * delta)
		else:
			fuel = maxf(0.0, fuel - EG.SHIP_FUEL_THRUST * delta)
		var accel: float = EG.SHIP_ACCEL * (EG.SHIP_BOOST_MULT * boost_mult if boosting else 1.0)
		if dash_time <= 0.0:
			vel += dir.normalized() * accel * delta
		facing = lerp_angle(facing, dir.angle(), 1.0 - pow(0.0004, delta))
		thrust_level = lerpf(thrust_level, 1.0, 1.0 - pow(0.0006, delta))
	else:
		thrust_level = lerpf(thrust_level, 0.0, 1.0 - pow(0.0006, delta))
		if vel.length() > 6.0:
			facing = lerp_angle(facing, vel.angle(), 1.0 - pow(0.02, delta))

	if not boosting and _boost_idle > EG.SHIP_BOOST_REFILL_DELAY and boost_meter < boost_cap:
		boost_meter = minf(boost_cap, boost_meter + EG.SHIP_BOOST_REFILL * delta)

	# Operation assist (does not alter facing).
	var assist: Vector2 = run.assist_accel(self) if run != null else Vector2.ZERO
	vel += assist * delta

	# The operation assist auto-balances star gravity unless very close; missiles
	# have no such assist and are always bent by the same wells.
	vel += run.gravity_ship_at(position) * delta

	# Space drag / inertia.
	vel *= 1.0 - EG.SHIP_DRAG * delta
	var cap: float = EG.SHIP_MAX_SPEED * (EG.SHIP_BOOST_SPEED_MULT if boosting else 1.0)
	if vel.length() > cap:
		vel = vel.normalized() * cap
	if dash_time > 0.0:
		vel = dash_dir * dash_speed
		dash_time = maxf(0.0, dash_time - delta)
	position += vel * delta
	rotation = facing
	_update_visual(delta)
	if run != null:
		Audio.loop_sfx("sfx_thrust", thrusting, -16.0 if boosting else -21.0, 1.08 if boosting else 0.94)

func _update_visual(delta: float) -> void:
	shield_ratio = clampf(shield / maxf(shield_max, 1.0), 0.0, 1.0)
	var pulse: float = 1.0 + 0.03 * sin(_t * 3.0)
	var shield_alpha: float = (0.10 + 0.5 * shield_ratio) * pulse
	_shield_sprite.modulate = Color(0.35, 0.82, 1.0, shield_alpha)
	_shield_sprite.scale = Vector2.ONE * (1.0 + 0.02 * sin(_t * 2.2))
	if invuln > 0.0 and int(_t * 10.0) % 2 == 0:
		_shield_sprite.modulate.a = 0.12

	_plume.visible = thrust_level > 0.03
	if _plume.visible:
		var len_scale: float = 0.55 + 1.25 * thrust_level * (1.35 if boosting else 1.0)
		_plume.scale = Vector2(len_scale, 0.55 + 0.35 * thrust_level)
		var flick: float = 0.85 + 0.15 * sin(_t * 37.0)
		_plume.modulate = Color(0.5, 0.92, 1.0, 0.9 * flick) if boosting else Color(1.0, 0.62, 0.25, 0.72 * flick)
	_trail.emitting = thrusting
	if thrusting:
		_trail.color = Color(0.5, 0.95, 1.0, 0.75) if boosting else Color(1.0, 0.65, 0.3, 0.55)
		_trail.initial_velocity_max = 150.0 if boosting else 90.0

func dash(dir: Vector2, speed: float, time: float) -> void:
	dash_dir = dir.normalized() if dir.length() > 0.01 else Vector2.RIGHT.rotated(facing)
	dash_speed = speed
	dash_time = time
	vel = dash_dir * speed

func boost_full() -> void:
	boost_meter = boost_cap
	boost_ready = true

func refill() -> void:
	fuel = fuel_max

func heal(amount: float) -> void:
	shield = minf(shield_max, shield + amount)

func take_damage(amount: float) -> bool:
	if dead or invuln > 0.0:
		return false
	shield = maxf(0.0, shield - amount)
	invuln = 0.35
	return shield <= 0.0

func bounce_from(center: Vector2, surface_radius: float, restitution: float = 0.65) -> float:
	var d := position - center
	var dist := maxf(d.length(), 0.001)
	var n := d / dist
	var min_dist := surface_radius + R
	if dist >= min_dist:
		return 0.0
	var impact := vel.dot(-n)
	position = center + n * (min_dist + 0.5)
	vel = vel.bounce(n) * restitution
	return impact
