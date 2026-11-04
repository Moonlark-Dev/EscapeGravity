class_name GravityBody
extends Node2D
## A planet or star. Visuals are pre-rendered sprites; gravity follows the doc:
## g = M / r^2 with an inner clamp at 0.85 R, zero outside BODY_GRAVITY_RANGE R
## (smooth 15% edge).  The 3 R well is what gives a tangential pass enough time
## to bend into an orbit and fling the ship out faster than its engine can.

var radius := 260.0
var mass := 0.0
var kind := "planet"
var variant := 1
var influence := 0.0
var spin := 0.0
var _sprite: Sprite2D
var _ring: Sprite2D
var _glow: Sprite2D
var _t := 0.0

func _ready() -> void:
	influence = radius * EG.BODY_GRAVITY_RANGE
	mass = EG.BODY_MASS * pow(radius / EG.BODY_MASS_REF, 2.0)
	z_index = -20
	if kind == "star":
		_sprite = Assets.world_sprite("star")
		_sprite.scale = Vector2.ONE * (radius * 2.0 / 1536.0)
		_glow = Assets.world_sprite("star", true)
		_glow.scale = _sprite.scale * 1.18
		_glow.modulate = Color(1.0, 0.9, 0.75, 0.35)
		add_child(_glow)
	else:
		_sprite = Assets.world_sprite("planet_%d" % variant)
		_sprite.scale = Vector2.ONE * (radius * 2.0 / 768.0)
		_glow = Assets.world_sprite("planet_%d" % variant, true)
		_glow.scale = _sprite.scale * 1.035
		_glow.modulate = Color(0.45, 0.7, 1.0, 0.16)
		add_child(_glow)
	add_child(_sprite)
	_ring = Assets.world_sprite("gravity_ring", true)
	_ring.scale = Vector2.ONE * (influence / 250.0)
	_ring.modulate = Color(0.35, 0.75, 1.0, 0.0)
	add_child(_ring)

func step(delta: float) -> void:
	_t += delta
	spin += delta * (0.012 if kind == "planet" else 0.004)
	_sprite.rotation = spin
	var cam := get_viewport().get_camera_2d()
	if cam != null:
		var d: float = cam.get_screen_center_position().distance_to(position)
		var near: bool = d < radius + 1800.0
		var target: float = 0.10 if near else 0.0
		_ring.modulate.a = lerpf(_ring.modulate.a, target, 1.0 - pow(0.02, delta))
		_ring.rotation = -_t * 0.05

func gravity_at(p: Vector2) -> Vector2:
	var d := position - p
	var dist := d.length()
	if dist >= influence or dist < 0.001:
		return Vector2.ZERO
	var clamp_r := radius * EG.BODY_CORE_CLAMP
	var d2: float = maxf(dist * dist, clamp_r * clamp_r)
	var a := mass / d2
	var edge := influence * 0.15
	var t: float = clampf((influence - dist) / edge, 0.0, 1.0)
	return d.normalized() * a * smoothstep(0.0, 1.0, t)

func surface_gravity() -> float:
	return mass / (radius * radius)

func remove() -> void:
	queue_free()
