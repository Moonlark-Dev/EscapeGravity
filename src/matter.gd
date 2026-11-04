class_name Matter
extends Node2D
## XP motes. Attracted within 190 px; small = 1 XP, big = 3 XP.
##
## The tractor is deliberately stronger and faster than the ship so a mote is
## always drawn in, even after a gravity-assisted pass.  It is never
## intentionally flung away.

var run
var big := false
var xp := 1
var vel := Vector2.ZERO
var collected := false
var _tractor_lock := 0.0
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
	var ship: Node2D = run.ship
	var d: Vector2 = ship.position - position
	var dist: float = d.length()
	_tractor_lock = maxf(0.0, _tractor_lock - delta)
	if dist < run.absorb_radius:
		_tractor_lock = EG.MATTER_TRACTOR_LOCK
	if dist < run.absorb_radius or _tractor_lock > 0.0:
		var pull: float = lerpf(EG.MATTER_TRACTOR_PULL_NEAR, EG.MATTER_TRACTOR_PULL_FAR,
			clampf(dist / run.absorb_radius, 0.0, 1.0))
		vel += d.normalized() * pull * delta
		vel = vel.limit_length(EG.MATTER_TRACTOR_SPEED)
		position += vel * delta
		if dist < EG.MATTER_COLLECT_RADIUS:
			collect()
			return
	position.y += sin(_t * 2.4 + _phase) * 3.0 * delta
	_sprite.rotation += delta * 0.8
	var a: float = 0.55 + 0.25 * sin(_t * 5.0 + _phase)
	_glow.modulate.a = a
	_sprite.modulate.a = 0.8 + 0.2 * sin(_t * 6.0 + _phase)

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
