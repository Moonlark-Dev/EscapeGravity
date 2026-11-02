class_name Enemy
extends Node2D
## Non-small attacker. "turret" is the doc's signature enemy (R=420, HP 50);
## "nest" is a second non-small variant with wider volleys. Both share the
## visibility-driven movement and fire rules from the design document.

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
var in_view := false
var overheated := false
var overheat_timer := 0.0
var fire_timer := 2.0
var burst_left := 0
var burst_gap := 0.0
var dead := false
var hit_flash := 0.0
var _sprite: Sprite2D
var _glow: Sprite2D
var _ember: Sprite2D
var _t := 0.0
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	z_index = -2
	_rng.seed = hash(position) + 51
	if kind == "turret":
		_sprite = Assets.world_sprite("turret")
		_sprite.scale = Vector2.ONE * (radius / 400.0)
		_glow = Assets.world_sprite("ship_glow", true)
		_glow.scale = Vector2.ONE * 4.2
		_glow.modulate = Color(0.35, 0.8, 1.0, 0.10)
		_ember = Assets.world_sprite("turret_ember", true)
		_ember.scale = Vector2.ONE * (radius / 384.0)
		_ember.modulate = Color(1.0, 0.3, 0.25, 0.0)
	else:
		_sprite = Assets.world_sprite("nest")
		_sprite.scale = Vector2.ONE * (radius / 124.0)
		_glow = Assets.world_sprite("ship_glow", true)
		_glow.scale = Vector2.ONE * 2.4
		_glow.modulate = Color(1.0, 0.3, 0.7, 0.13)
		_ember = Assets.world_sprite("ship_glow", true)
		_ember.scale = Vector2.ONE * 0.9
		_ember.modulate = Color(1.0, 0.3, 0.5, 0.0)
	add_child(_glow)
	add_child(_sprite)
	add_child(_ember)
	if elite:
		_sprite.modulate = Color(1.0, 0.82, 0.62)

func step(delta: float) -> void:
	_t += delta
	if dead:
		return
	hit_flash = maxf(0.0, hit_flash - delta)
	in_view = run.enemy_in_view(self)
	var player_pos: Vector2 = run.ship.position
	var dir: Vector2 = (player_pos - position).normalized()

	# Slide around celestial bodies instead of clipping through them.
	var avoid := Vector2.ZERO
	for b in run.galaxy.bodies:
		var gap: float = position.distance_to(b.position) - b.radius - radius
		if gap < 700.0:
			var away: Vector2 = (position - b.position).normalized()
			avoid += away * (1.0 - clampf(gap / 700.0, 0.0, 1.0)) * 2.2
	# Skirt a safe zone instead of stalling against it. When the zone sits
	# between us and the player, push along the tangent that leads around it;
	# otherwise just back away.
	if run.safe_zone != null and run.safe_zone.active:
		var zpos: Vector2 = run.safe_zone.position
		var zd: float = position.distance_to(zpos)
		var clear: float = run.safe_zone.radius + radius + 240.0
		if zd < clear:
			var away: Vector2 = (position - zpos)
			if away.length() < 1.0:
				away = Vector2.RIGHT.rotated(_rng.randf() * TAU)
			away = away.normalized()
			var toward: Vector2 = (player_pos - position).normalized()
			var tangent: Vector2 = away.orthogonal()
			if tangent.dot(toward) < 0.0:
				tangent = -tangent
			var push: float = 1.0 - clampf(zd / clear, 0.0, 1.0)
			avoid += (tangent * 1.9 + away * 1.2) * push * 2.2
	if avoid.length() > 0.01:
		dir = (dir + avoid).normalized()

	var spd: float = speed_in if in_view else speed_out
	var dist_to_player: float = position.distance_to(player_pos)
	if dist_to_player > radius + 520.0:
		position += dir * spd * delta
	elif dist_to_player < radius + 260.0:
		position -= dir * spd * 0.55 * delta

	if overheated:
		overheat_timer -= delta
		if overheat_timer <= 0.0:
			overheated = false
	else:
		fire_timer -= delta
		if burst_left > 0:
			burst_gap -= delta
			if burst_gap <= 0.0:
				_fire_one()
				burst_left -= 1
				burst_gap = 0.2
		elif fire_timer <= 0.0:
			var locked: int = run.locked_missile_count()
			if locked < max_locked and not run.player_hidden:
				burst_left = 1 if _rng.randf() < 0.45 else burst
				burst_gap = 0.0
				fire_timer = fire_in if in_view else fire_out
			else:
				fire_timer = 0.25
	_visual(delta)

func _fire_one() -> void:
	if run.locked_missile_count() >= max_locked:
		burst_left = 0
		return
	var player: Vector2 = run.ship.position
	var spawn: Vector2
	var muzzle_angle: float
	if in_view:
		# In view the missile must come out of the hull, not pop into existence
		# off screen. Turrets have three hard-points; pick the one nearest the
		# player. Nests launch from their forward aperture.
		var to_player: Vector2 = (player - position).normalized()
		var aim_angle: float = to_player.angle()
		muzzle_angle = aim_angle
		if kind == "turret":
			var step: float = TAU / 3.0
			var local: float = wrapf(aim_angle - _sprite.rotation, -PI, PI)
			muzzle_angle = _sprite.rotation + roundf(local / step) * step
		spawn = position + Vector2.RIGHT.rotated(muzzle_angle) * (radius + 14.0)
		if run.galaxy.is_inside_any_body(spawn, 26.0):
			# A planet is hugging that hard-point; use the open side instead.
			muzzle_angle = aim_angle
			spawn = position + Vector2.RIGHT.rotated(aim_angle) * (radius + 14.0)
	else:
		# Outside the view the design doc keeps the 820 px lateral entrance: it
		# preserves the standoff and makes the missile's origin readable.
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
	run.spawn_enemy_missile(self, spawn, aim)
	# Muzzle flash on the hull for readability.
	Fx.sparks(run.fx_layer, spawn, Color(1.0, 0.55, 0.3, 0.9), 7, 130.0)

func _visual(delta: float) -> void:
	if kind == "turret":
		_sprite.rotation += delta * 0.025
	else:
		_sprite.rotation += delta * 0.18
		_sprite.position = Vector2(0, sin(_t * 1.7) * 6.0)
	var heated: float = (0.55 + 0.2 * sin(_t * 9.0)) if overheated else 0.0
	_ember.modulate.a = lerpf(_ember.modulate.a, heated, 1.0 - pow(0.001, delta))
	_glow.modulate.a = 0.10 + 0.05 * sin(_t * 2.0)
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

func take_hit(amount: float) -> void:
	if dead:
		return
	hp -= amount
	hit_flash = 0.12
	overheated = true
	overheat_timer = overheat_time
	burst_left = 0
	fire_timer = 0.6

func remove() -> void:
	dead = true
	queue_free()
