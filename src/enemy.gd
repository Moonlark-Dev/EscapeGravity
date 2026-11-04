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
var discovered := false
var hunting := false
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
var _reveal := 0.0
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
			run.hud.toast("发现攻击者：%s" % ("导弹巢" if kind == "nest" else "炮塔"), EG.C_MAGENTA, 2.2)
	_reveal = move_toward(_reveal, 1.0 if discovered else 0.0, delta / maxf(0.01, EG.ENEMY_REVEAL_TIME))
	visible = _reveal > 0.001
	modulate = Color(1.0, 1.0, 1.0, _reveal)

	# Once the player gets close the attacker starts hunting, closing the gap
	# before it is ever visible. Before that it simply holds position.
	if not hunting and dist_to_player <= EG.ENEMY_AGGRO_RANGE:
		hunting = true

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
		var clear: float = run.safe_zone.clearance_radius() + radius + 240.0
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
	if not discovered:
		# Hidden hunters close in faster and ignore the normal standoff: they
		# must actually reach the screen edge before the standoff band could
		# park them just outside a vertical screen boundary.
		spd = speed_out * EG.ENEMY_CHASE_MULT
	if hunting:
		if not discovered and not in_view:
			position += dir * spd * delta
		elif dist_to_player > radius + 520.0:
			position += dir * spd * delta
		elif dist_to_player < radius + 260.0:
			position -= dir * spd * 0.55 * delta
	# Never let a hull finish a frame inside a celestial body, even if a giant
	# well streamed in next to it or the avoidance push was not enough.
	if run != null and run.galaxy != null:
		position = run.galaxy.push_out_of_bodies(position, radius)

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
			var sneak: int = run.sneak_missile_count()
			# An undiscovered attacker still shoots; the missile comes in from
			# off screen so the shot itself never reveals the hull. It only
			# starts firing once the player is inside its aggro range. Sneak
			# rounds have their own cap so they never starve the normal salvos.
			var can_fire: bool = locked < max_locked and not run.player_hidden and (discovered or hunting)
			if not discovered and sneak >= EG.ENEMY_HIDDEN_MAX:
				can_fire = false
			if can_fire:
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
	if not in_view and not discovered:
		if run.sneak_missile_count() >= EG.ENEMY_HIDDEN_MAX:
			burst_left = 0
			return
		_fire_hidden(player)
		return
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

## Missile launch while the attacker is still undiscovered. The round appears
## outside the screen and is launched mostly tangentially, so it curves around
## the edge before turning in. The entry bearing is biased toward the enemy so
## the player gets a direction hint without ever seeing the hull.
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
	# Keep the spawn out of planets and out of the (invisible) attacker's hull.
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
	# Mostly tangent + a small inward component: the homing turn produces an
	# off-screen arc instead of a straight line into the player.
	var heading: Vector2 = dir.orthogonal() * side - dir * _rng.randf_range(0.18, 0.5)
	var m = run.spawn_enemy_missile(self, spawn, heading.angle())
	m.sneak = true

func _offscreen_point(center: Vector2, half: Vector2, bearing: float) -> Vector2:
	var dir := Vector2.RIGHT.rotated(bearing)
	var edge: float = minf(absf(half.x / maxf(absf(dir.x), 0.001)),
		absf(half.y / maxf(absf(dir.y), 0.001)))
	return center + dir * (edge + _rng.randf_range(EG.ENEMY_HIDDEN_EDGE_MIN, EG.ENEMY_HIDDEN_EDGE_MAX))

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
