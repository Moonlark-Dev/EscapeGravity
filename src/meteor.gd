class_name Meteor
extends Node2D
## Threat, not an attack: 0.5 shield wear on impact. If the player knocks one
## away it can deal 5 damage to an enemy.

var run
var vel := Vector2.ZERO
var radius := EG.METEOR_RADIUS
var knocked := false
var spin := 0.0
var life := 0.0
var hit_cd := 0.0
var dead := false
var _sprite: Sprite2D
var _glow: Sprite2D
var _t := 0.0

func _ready() -> void:
	z_index = 8
	_glow = Assets.world_sprite("ship_glow", true)
	_glow.scale = Vector2.ONE * 0.20
	_glow.modulate = Color(0.6, 0.8, 1.0, 0.22)
	add_child(_glow)
	_sprite = Assets.world_sprite("meteor_%d" % (randi() % 3 + 1))
	_sprite.scale = Vector2.ONE * 0.42
	add_child(_sprite)
	spin = randf_range(-2.2, 2.2)

func step(delta: float) -> void:
	_t += delta
	life += delta
	hit_cd = maxf(0.0, hit_cd - delta)
	vel += run.gravity_at(position) * delta
	var to_ship: Vector2 = run.ship.position - position
	var sd: float = to_ship.length()
	if sd < 620.0 and sd > 1.0:
		vel += to_ship / sd * 30.0 * (1.0 - sd / 620.0) * delta
	position += vel * delta
	_sprite.rotation += spin * delta
	_glow.modulate.a = 0.18 + 0.06 * sin(_t * 4.0)

func knock(direction: Vector2, extra: float) -> void:
	knocked = true
	vel = direction.normalized() * (vel.length() + extra)
	spin *= 2.0

func remove() -> void:
	dead = true
	queue_free()
