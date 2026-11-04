class_name Zone
extends Node2D
## Safe zone / shop. Both are circular areas; safe zones refill fuel and hide
## threat info, shops trade items for tokens.
##
## A safe zone spawns as a small marker barely larger than the ship. Reaching
## its centre triggers the expansion: the trigger radius jumps straight to the
## full ZONE_RADIUS (so the player can never drift back out mid-animation)
## while the ring itself animates open with a short shockwave.
##
## Some safe zones are gravity anomalies (`unstable`): the ring is tinted
## magenta, pushes an idle ship away instead of pulling it in, and ejects
## anyone who crosses the ring.  They never refuel or hide threats.

var run
var kind := "safe"
var radius := EG.ZONE_ENTRY_RADIUS
var active := true
var entered := false
var used := false
var unstable := false
var _ring: Sprite2D
var _fill: Sprite2D
var _station: Sprite2D
var _pulse: Sprite2D
var _t := 0.0
var _full_radius := EG.ZONE_RADIUS

func _ready() -> void:
	z_index = -5
	_t = randf() * 5.0
	if kind == "safe":
		_full_radius = EG.ZONE_RADIUS
		_fill = Assets.world_sprite("safezone_fill", true)
		_fill.scale = Vector2.ONE * (_full_radius / 280.0 * 1.06)
		if unstable:
			_fill.modulate = Color(1.0, 0.30, 0.48, 0.10)
		else:
			_fill.modulate = Color(0.35, 1.0, 0.78, 0.10)
		add_child(_fill)
		_ring = Assets.world_sprite("safezone")
		_ring.scale = Vector2.ONE * (_full_radius / 280.0)
		if unstable:
			_ring.modulate = Color(1.0, 0.45, 0.68, 1.0)
		add_child(_ring)
		_pulse = Assets.world_sprite("safezone", true)
		_pulse.scale = _ring.scale
		if unstable:
			_pulse.modulate = Color(1.0, 0.35, 0.55, 0.0)
		else:
			_pulse.modulate = Color(1.0, 1.0, 1.0, 0.0)
		_pulse.visible = false
		add_child(_pulse)
		# A stable marker starts as a small ring around the ship-sized entry
		# point; every sprite is authored at full size and scaled down as a
		# whole.  An anomaly is already fully open: its warning ring must be
		# readable from a distance, and the whole R280 area is the trap.
		if unstable:
			radius = _full_radius
			scale = Vector2.ONE
		else:
			scale = Vector2.ONE * (radius / _full_radius)
	else:
		_full_radius = EG.ZONE_RADIUS
		radius = _full_radius
		_fill = Assets.world_sprite("safezone_fill", true)
		_fill.scale = Vector2.ONE * (_full_radius / 280.0 * 1.1)
		_fill.modulate = Color(1.0, 0.72, 0.35, 0.07)
		add_child(_fill)
		_station = Assets.world_sprite("shop_station")
		_station.scale = Vector2.ONE * (radius / 250.0)
		add_child(_station)
		_ring = null

func step(delta: float) -> void:
	_t += delta
	if _ring != null:
		_ring.rotation += delta * 0.06
		_ring.modulate.a = 0.85 + 0.15 * sin(_t * 1.4)
		_fill.modulate.a = (0.20 if entered else 0.09) + 0.02 * sin(_t * 2.0)
	if unstable and _pulse != null:
		# A visible warning pulse: the player can read the anomaly before the
		# repulsion kicks in, so the fling is a risk, not a gotcha.
		_pulse.visible = true
		_pulse.rotation += delta * 0.35
		_pulse.scale = _ring.scale * (0.94 + 0.06 * sin(_t * 2.6))
		_pulse.modulate = Color(1.0, 0.35, 0.55, 0.20 + 0.14 * sin(_t * 3.4))
	if _station != null:
		_station.rotation += delta * 0.09
		_station.position = Vector2(0, sin(_t * 1.1) * 4.0)
	if _fill != null:
		_fill.rotation -= delta * 0.03

func set_entered(on: bool) -> void:
	entered = on
	if on:
		# Physics switches to the full size on the same frame the player
		# reaches the centre; only the visuals travel.
		radius = _full_radius
		var tw := create_tween()
		tw.set_parallel(true)
		tw.tween_property(self, "scale", Vector2.ONE, EG.ZONE_EXPAND_TIME) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		if _ring != null:
			tw.tween_property(_ring, "modulate:a", 1.0, 0.3)
		if _pulse != null:
			_pulse.visible = true
			_pulse.modulate = Color(1.0, 1.0, 1.0, 0.9)
			var base: Vector2 = _ring.scale if _ring != null else Vector2.ONE
			_pulse.scale = base * 0.82
			tw.tween_property(_pulse, "scale", base * 1.6, 0.72) \
				.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			tw.tween_property(_pulse, "modulate:a", 0.0, 0.72)
			tw.chain().tween_callback(func(): _pulse.visible = false)
	else:
		var tw2 := create_tween()
		tw2.tween_property(self, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_CUBIC)
		if _ring != null:
			tw2.parallel().tween_property(_ring, "modulate:a", 0.85, 0.3)

func inside(pos: Vector2) -> bool:
	return position.distance_to(pos) < radius

## Radius used for spacing / gravity / fuel safety. A safe zone reserves the
## full expanded footprint from the moment it spawns, even while it still looks
## like a small ring, so attackers never end up inside the future ring.
func clearance_radius() -> float:
	return maxf(radius, _full_radius)

func remove() -> void:
	active = false
	if run != null:
		run.zones.erase(self)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(self, "scale", Vector2.ZERO, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw.tween_property(self, "modulate:a", 0.0, 0.45)
	tw.chain().tween_callback(queue_free)
