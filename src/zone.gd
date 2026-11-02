class_name Zone
extends Node2D
## Safe zone / shop. Both are circular areas; safe zones refill fuel and hide
## threat info, shops trade items for tokens.

var run
var kind := "safe"
var radius := EG.ZONE_RADIUS
var active := true
var entered := false
var used := false
var _ring: Sprite2D
var _fill: Sprite2D
var _station: Sprite2D
var _t := 0.0
var _visual_scale := 1.0

func _ready() -> void:
	z_index = -5
	_t = randf() * 5.0
	if kind == "safe":
		_fill = Assets.world_sprite("safezone_fill", true)
		_fill.scale = Vector2.ONE * (radius / 280.0 * 1.06)
		_fill.modulate = Color(0.35, 1.0, 0.78, 0.10)
		add_child(_fill)
		_ring = Assets.world_sprite("safezone")
		_ring.scale = Vector2.ONE * (radius / 280.0)
		add_child(_ring)
		_visual_scale = radius / 280.0
	else:
		_fill = Assets.world_sprite("safezone_fill", true)
		_fill.scale = Vector2.ONE * (radius / 280.0 * 1.1)
		_fill.modulate = Color(1.0, 0.72, 0.35, 0.07)
		add_child(_fill)
		_station = Assets.world_sprite("shop_station")
		_station.scale = Vector2.ONE * (radius / 250.0)
		add_child(_station)
		_visual_scale = radius / 250.0
		_ring = null

func step(delta: float) -> void:
	_t += delta
	if _ring != null:
		_ring.rotation += delta * 0.06
		_ring.modulate.a = 0.85 + 0.15 * sin(_t * 1.4)
		_fill.modulate.a = (0.20 if entered else 0.09) + 0.02 * sin(_t * 2.0)
	if _station != null:
		_station.rotation += delta * 0.09
		_station.position = Vector2(0, sin(_t * 1.1) * 4.0)
	if _fill != null:
		_fill.rotation -= delta * 0.03

func set_entered(on: bool) -> void:
	entered = on
	var target := 1.06 if on else 1.0
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(self, "scale", Vector2.ONE * target, 0.35).set_trans(Tween.TRANS_CUBIC)
	if _ring != null:
		tw.tween_property(_ring, "modulate:a", 1.0 if on else 0.85, 0.3)

func inside(pos: Vector2) -> bool:
	return position.distance_to(pos) < radius

func remove() -> void:
	active = false
	if run != null:
		run.zones.erase(self)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(self, "scale", Vector2.ZERO, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw.tween_property(self, "modulate:a", 0.0, 0.45)
	tw.chain().tween_callback(queue_free)
