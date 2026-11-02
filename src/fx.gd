class_name Fx
extends RefCounted
## One-shot effects built from pre-rendered sprites and particle textures.
## No shape drawing: every effect is a texture animated by nodes/tweens.

static func explosion(parent: Node, pos: Vector2, amount: float, big: bool = false) -> void:
	if parent == null:
		return
	# Bright flash + a slower smoke body; two plain sprites are more reliable
	# (and cheaper) than a frame animation for a 0.45 s effect.
	var core := Assets.world_sprite("explosion_2", true)
	core.position = pos
	core.z_index = 32
	core.scale = Vector2.ONE * (amount * 0.32)
	core.modulate = Color(1.5, 1.3, 1.1, 1.0)
	parent.add_child(core)
	var tw := core.create_tween()
	tw.set_parallel(true)
	tw.tween_property(core, "scale", Vector2.ONE * (amount * 1.25), 0.42).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(core, "modulate:a", 0.0, 0.5)
	tw.chain().tween_callback(core.queue_free)

	var body := Assets.world_sprite("explosion_4")
	body.position = pos
	body.z_index = 31
	body.scale = Vector2.ONE * (amount * 0.55)
	body.modulate = Color(1.0, 0.85, 0.7, 0.85)
	parent.add_child(body)
	var twb := body.create_tween()
	twb.set_parallel(true)
	twb.tween_property(body, "scale", Vector2.ONE * (amount * 1.55), 0.6)
	twb.tween_property(body, "modulate:a", 0.0, 0.6)
	twb.chain().tween_callback(body.queue_free)

	var wave := Assets.world_sprite("shockwave", true)
	wave.position = pos
	wave.z_index = 29
	wave.scale = Vector2.ONE * (0.22 * amount)
	wave.modulate = Color(1.0, 0.86, 0.62, 0.85 if not big else 0.7)
	parent.add_child(wave)
	var tw2 := wave.create_tween()
	tw2.set_parallel(true)
	tw2.tween_property(wave, "scale", Vector2.ONE * (1.05 * amount), 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw2.tween_property(wave, "modulate:a", 0.0, 0.55)
	tw2.chain().tween_callback(wave.queue_free)
	sparks(parent, pos, Color(1.0, 0.65, 0.3, 1.0), 22 if big else 10, amount * 2.2)
	if big:
		smoke(parent, pos, 0.8, 6)

static func sparks(parent: Node, pos: Vector2, color: Color, count: int, speed: float = 160.0) -> void:
	if parent == null:
		return
	var p := CPUParticles2D.new()
	p.texture = Assets.world("spark")
	p.position = pos
	p.z_index = 31
	p.amount = maxi(4, count)
	p.lifetime = 0.5
	p.one_shot = true
	p.explosiveness = 1.0
	p.local_coords = false
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_POINT
	p.direction = Vector2.RIGHT
	p.spread = 180.0
	p.initial_velocity_min = speed * 0.35
	p.initial_velocity_max = speed
	p.damping_min = 90.0
	p.damping_max = 160.0
	p.scale_amount_min = 0.25
	p.scale_amount_max = 0.8
	p.color = color
	p.material = Assets.additive_material()
	parent.add_child(p)
	p.emitting = true
	p.finished.connect(p.queue_free)

static func smoke(parent: Node, pos: Vector2, scale: float, count: int = 5) -> void:
	if parent == null:
		return
	var p := CPUParticles2D.new()
	p.texture = Assets.world("smoke")
	p.position = pos
	p.z_index = 28
	p.amount = count
	p.lifetime = 1.3
	p.one_shot = true
	p.explosiveness = 0.8
	p.local_coords = false
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 24.0 * scale
	p.direction = Vector2.UP
	p.spread = 180.0
	p.initial_velocity_min = 20.0
	p.initial_velocity_max = 70.0
	p.damping_min = 10.0
	p.damping_max = 30.0
	p.scale_amount_min = 0.5 * scale
	p.scale_amount_max = 1.3 * scale
	p.color = Color(0.55, 0.62, 0.75, 0.35)
	parent.add_child(p)
	p.emitting = true
	p.finished.connect(p.queue_free)

static func pickup(parent: Node, pos: Vector2, color: Color) -> void:
	if parent == null:
		return
	var p := CPUParticles2D.new()
	p.texture = Assets.world("spark")
	p.position = pos
	p.z_index = 25
	p.amount = 6
	p.lifetime = 0.28
	p.one_shot = true
	p.explosiveness = 1.0
	p.local_coords = false
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_POINT
	p.direction = Vector2.UP
	p.spread = 180.0
	p.initial_velocity_min = 20.0
	p.initial_velocity_max = 70.0
	p.scale_amount_min = 0.2
	p.scale_amount_max = 0.5
	p.color = color
	p.material = Assets.additive_material()
	parent.add_child(p)
	p.emitting = true
	p.finished.connect(p.queue_free)

static func text(parent: Node, pos: Vector2, msg: String, color: Color, size: int = 22) -> void:
	if parent == null:
		return
	var l := Assets.label(msg, size, color, 4)
	l.position = pos - Vector2(40, 12)
	l.z_index = 40
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.size = Vector2(120, 30)
	parent.add_child(l)
	var tw := l.create_tween()
	tw.set_parallel(true)
	tw.tween_property(l, "position:y", l.position.y - 46.0, 0.8).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "modulate:a", 0.0, 0.8).set_delay(0.25)
	tw.chain().tween_callback(l.queue_free)

static func warp(parent: Node, pos: Vector2, color: Color = Color(0.5, 0.9, 1.0, 1.0)) -> void:
	if parent == null:
		return
	var w := Assets.world_sprite("warp_ring", true)
	w.position = pos
	w.z_index = 35
	w.scale = Vector2.ONE * 0.05
	w.modulate = color
	parent.add_child(w)
	var tw := w.create_tween()
	tw.set_parallel(true)
	tw.tween_property(w, "scale", Vector2.ONE * 0.9, 1.0).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(w, "modulate:a", 0.0, 1.0)
	tw.chain().tween_callback(w.queue_free)
