class_name Matter
extends Node2D
## XP motes. Attracted within 190 px; small = 1 XP, big = 3 XP.
##
## A volatile mote is gravitationally unstable: when the ship gets inside the
## tractor radius it is flung away instead of being absorbed.  The kick has a
## short cooldown, so a determined player can still chase it down.

var run
var big := false
var xp := 1
var vel := Vector2.ZERO
var collected := false
var volatile := false
var fling_t := 0.0
var _fling_cd := 0.0
var _fling_vel := Vector2.ZERO
var _sprite: Sprite2D
var _glow: Sprite2D
var _t := 0.0
var _phase := 0.0
var _base_y := 0.0

func _ready() -> void:
	z_index = 9
	_phase = randf() * TAU
	_glow = Assets.world_sprite("ship_glow", true)
	_glow.scale = Vector2.ONE * (0.24 if big else 0.13)
	if volatile:
		_glow.modulate = Color(1.0, 0.32, 0.72, 0.5)
	else:
		_glow.modulate = Color(0.45, 0.95, 1.0, 0.45)
	add_child(_glow)
	_sprite = Assets.world_sprite("matter_big" if big else "matter_small")
	_sprite.scale = Vector2.ONE * (0.62 if big else 0.7)
	if volatile:
		_sprite.modulate = Color(1.0, 0.6, 0.9, 1.0)
	add_child(_sprite)
	_base_y = position.y
	_t = randf() * 10.0

func step(delta: float) -> void:
	_t += delta
	if collected:
		return
	_fling_cd = maxf(0.0, _fling_cd - delta)
	if fling_t > 0.0:
		fling_t = maxf(0.0, fling_t - delta)
		position += _fling_vel * delta
		_fling_vel = _fling_vel.move_toward(Vector2.ZERO, EG.MATTER_FLING_DECEL * delta)
		_sprite.rotation += delta * 3.2
		_glow.modulate.a = 0.45 + 0.35 * sin(_t * 12.0)
		_sprite.modulate.a = 0.9
		if fling_t <= 0.0:
			_fling_vel = Vector2.ZERO
		return
	var ship: Node2D = run.ship
	var d: Vector2 = ship.position - position
	var dist: float = d.length()
	if dist < run.absorb_radius:
		if volatile and _fling_cd <= 0.0:
			_fling_away(ship)
			return
		var pull: float = lerpf(900.0, 220.0, clampf(dist / run.absorb_radius, 0.0, 1.0))
		vel += d.normalized() * pull * delta
		vel = vel.limit_length(520.0)
		position += vel * delta
		if dist < 24.0:
			collect()
			return
	position.y += sin(_t * 2.4 + _phase) * 3.0 * delta
	_sprite.rotation += delta * 0.8
	var a: float = 0.55 + 0.25 * sin(_t * 5.0 + _phase)
	_glow.modulate.a = a
	_sprite.modulate.a = 0.8 + 0.2 * sin(_t * 6.0 + _phase)

## Launch the mote away from the ship.  The small random turn keeps repeated
## reactions from looking like a perfect radial bounce.
func _fling_away(ship: Node2D) -> void:
	var away: Vector2 = position - ship.position
	if away.length() < 1.0:
		away = Vector2.RIGHT.rotated(randf() * TAU)
	var dir := away.normalized().rotated(randf_range(-0.55, 0.55))
	_fling_vel = dir * EG.MATTER_FLING_SPEED
	fling_t = EG.MATTER_FLING_TIME
	_fling_cd = EG.MATTER_FLING_COOLDOWN
	if run != null:
		run.on_matter_flung(self)

func collect() -> void:
	if collected:
		return
	collected = true
	if run != null:
		run.matters.erase(self)
		run.on_matter_collected(self)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(self, "scale", Vector2.ONE * 2.2, 0.18)
	tw.tween_property(self, "modulate:a", 0.0, 0.18)
	tw.chain().tween_callback(queue_free)
