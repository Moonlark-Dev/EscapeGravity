class_name Missile
extends Node2D
## Homing missile: 150 px/s, 0.525 rad/s turn, 5 s lock after entering view,
## then flies straight (still bent by gravity). Cannot be destroyed by the player.

var run
var vel := Vector2.ZERO
var angle := 0.0
var speed := EG.MISSILE_SPEED
var locked := true
var lock_timer := 0.0
var seen := false
var life := 0.0
var target := "ship"
var decoy = null
var source: Node2D = null
## True for a missile launched by an undiscovered attacker. Sneak rounds get
## their own cap and do not consume the normal 3-lock budget.
var sneak := false
var dead := false
var pull := Vector2.ZERO
var _age := 0.0
var _sprite: Sprite2D
var _glow: Sprite2D
var _trail: CPUParticles2D
var _t := 0.0
var _warn: Sprite2D

func _ready() -> void:
	z_index = 15
	_glow = Assets.world_sprite("ship_glow", true)
	_glow.scale = Vector2.ONE * 0.28
	_glow.modulate = Color(1.0, 0.35, 0.25, 0.55)
	add_child(_glow)
	_sprite = Assets.world_sprite("missile")
	add_child(_sprite)
	_warn = Assets.world_sprite("missile_warn", true)
	_warn.scale = Vector2.ONE * 0.7
	_warn.modulate = Color(1.0, 0.3, 0.25, 0.0)
	add_child(_warn)
	_trail = CPUParticles2D.new()
	_trail.texture = Assets.world("spark")
	_trail.amount = 18
	_trail.lifetime = 0.34
	_trail.local_coords = false
	_trail.emission_shape = CPUParticles2D.EMISSION_SHAPE_POINT
	_trail.direction = Vector2.LEFT
	_trail.spread = 10.0
	_trail.initial_velocity_min = 8.0
	_trail.initial_velocity_max = 34.0
	_trail.scale_amount_min = 0.16
	_trail.scale_amount_max = 0.36
	_trail.color = Color(1.0, 0.55, 0.3, 0.55)
	_trail.emitting = true
	_trail.material = Assets.additive_material()
	add_child(_trail)

func step(delta: float) -> void:
	_t += delta
	_age += delta
	life += delta
	if life > EG.MISSILE_LIFE:
		dead = true
		return

	var enemy = run.current_enemy if run != null else null
	if not seen and run != null and run.is_on_screen(position):
		seen = true
	if locked and seen:
		lock_timer += delta
		if lock_timer >= EG.MISSILE_LOCK_TIME:
			unlock()

	# Missiles have no operation assist: celestial gravity always applies, even
	# while locked.  Guidance only wins where its turn rate can out-turn the
	# gravity well (near the surface the missile is dragged off course).
	var g: Vector2 = run.gravity_at(position) * EG.MISSILE_GRAVITY_SCALE if run != null else Vector2.ZERO
	if locked:
		var cur := vel.angle()
		var tpos: Vector2 = run.target_position(self)
		var desired := (tpos - position).angle()
		var diff := wrapf(desired - cur, -PI, PI)
		# Do not fly into the enemy right after launch (design doc: avoid self-hits).
		if enemy != null and position.distance_to(enemy.position) < enemy.radius + 34.0:
			var to_enemy: Vector2 = (enemy.position - position).normalized()
			var fwd := Vector2.RIGHT.rotated(cur)
			if fwd.dot(to_enemy) > 0.1:
				diff += 1.2 * signf(fwd.cross(to_enemy))
		var max_step := EG.MISSILE_TURN * delta
		var steer := clampf(diff, -max_step, max_step)
		if pull.length() > 1.0:
			var pa := wrapf(pull.angle() - (cur + steer), -PI, PI)
			steer += clampf(pa, -1.15 * delta, 1.15 * delta)
		vel = Vector2.RIGHT.rotated(cur + steer) * speed + g * delta
		if vel.length() > 0.1:
			angle = vel.angle()
			vel = vel.normalized() * speed
	else:
		vel += (g + pull) * delta
		if vel.length() > 1.0:
			angle = vel.angle()

	position += vel * delta
	rotation = angle
	_trail.emitting = locked
	_glow.modulate.a = 0.45 + 0.15 * sin(_t * 12.0) if locked else 0.15
	if _warn != null:
		_warn.modulate.a = (0.30 + 0.18 * sin(_t * 9.0)) if locked and seen else 0.0
		_warn.rotation = -angle + _t * 0.6
	_sprite.modulate = Color(1, 1, 1, 1) if locked else Color(0.75, 0.62, 0.58, 1)

func unlock() -> void:
	if not locked:
		return
	locked = false
	lock_timer = 0.0
	if run != null:
		run.on_missile_unlock(self)

func retarget_to(decoy_node) -> void:
	decoy = decoy_node
	target = "decoy"
	lock_timer = 0.0
	locked = true
	seen = true

func is_locked() -> bool:
	return locked

func remove() -> void:
	dead = true
	queue_free()
