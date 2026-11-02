class_name Decoy
extends Node2D
## A lure. Missiles that lock onto it become unlocked when they reach it.
## Affected by gravity, and can be dropped on an enemy's hull.

var run
var vel := Vector2.ZERO
var life := 7.0
var dead := false
var _sprite: Sprite2D
var _glow: Sprite2D
var _ring: Sprite2D
var _t := 0.0

func _ready() -> void:
	z_index = 12
	_glow = Assets.world_sprite("ship_glow", true)
	_glow.scale = Vector2.ONE * 0.55
	_glow.modulate = Color(1.0, 0.45, 0.85, 0.45)
	add_child(_glow)
	_sprite = Assets.world_sprite("decoy")
	add_child(_sprite)
	_ring = Assets.world_sprite("gravity_ring", true)
	_ring.scale = Vector2.ONE * 0.5
	_ring.modulate = Color(1.0, 0.4, 0.8, 0.35)
	add_child(_ring)

func step(delta: float) -> void:
	_t += delta
	life -= delta
	if life <= 0.0:
		remove()
		return
	vel += run.gravity_at(position) * delta
	position += vel * delta
	rotation += delta * 2.4
	_glow.modulate.a = 0.35 + 0.15 * sin(_t * 8.0)
	_ring.rotation -= delta * 0.8
	_ring.scale = Vector2.ONE * (0.45 + 0.05 * sin(_t * 3.0))

func remove(explode: bool = true) -> void:
	if dead:
		return
	dead = true
	if run != null:
		run.on_decoy_gone(self, explode)
	queue_free()
