class_name Matter
extends Node2D
## XP motes. Attracted within 190 px; small = 1 XP, big = 3 XP.
##
## The tractor beam is finite rather than a magnetic snap: a fast tangential
## pass whips the mote away (toward the ship's wake) instead of capturing it.
## A slow or head-on approach still absorbs normally.  This is the same
## behaviour for every mote.

var run
var big := false
var xp := 1
var vel := Vector2.ZERO
var collected := false
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
	_glow.modulate = Color(0.45, 0.95, 1.0, 0.45)
	add_child(_glow)
	_sprite = Assets.world_sprite("matter_big" if big else "matter_small")
	_sprite.scale = Vector2.ONE * (0.62 if big else 0.7)
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
		if _fling_cd <= 0.0 and _can_fling(ship):
			_fling_from(ship)
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

## A fast pass whose heading does not point at the mote cannot hold it in the
## tractor beam: the relative motion whips it out toward the wake.  Head-on or
## slow approaches skip this branch and are absorbed by the normal pull.
func _can_fling(ship: Node2D) -> bool:
	var ship_vel: Vector2 = ship.vel
	if ship_vel.length() < EG.MATTER_FLING_SHIP_SPEED:
		return false
	var to_matter: Vector2 = position - ship.position
	if to_matter.length() < 1.0:
		return false
	return to_matter.normalized().dot(ship_vel.normalized()) < EG.MATTER_FLING_HEADING_DOT

func _fling_from(ship: Node2D) -> void:
	var ship_vel: Vector2 = ship.vel
	var away: Vector2 = position - ship.position
	if away.length() < 1.0:
		away = -ship_vel if ship_vel.length() > 1.0 else Vector2.RIGHT
	var dir: Vector2 = away.normalized() * 0.35 + ship_vel.normalized() * 0.65
	if dir.length() < 0.01:
		dir = away.normalized()
	_fling_vel = dir.normalized() * maxf(EG.MATTER_FLING_IMPULSE, ship_vel.length() * 0.85)
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
