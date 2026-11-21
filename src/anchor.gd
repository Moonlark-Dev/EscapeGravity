class_name GravityAnchor
extends Node2D
## Skill: a temporary gravity source that pulls missiles. The ship is unaffected.

var run
var radius := EG.ANCHOR_RADIUS
var force := EG.ANCHOR_FORCE
var duration := EG.ANCHOR_DURATION
## 引力水雷：消失时把吸成一团的导弹朝最近敌人齐射甩出。
var fling := false
## 双极锚定觉醒：消失瞬间沿切线高速甩射。
var bipolar := false
var life := 0.0
var dead := false
var _ring: Sprite2D
var _core: Sprite2D
var _t := 0.0

func _ready() -> void:
	z_index = 11
	_core = Assets.world_sprite("warp_ring", true)
	_core.scale = Vector2.ONE * 0.12
	_core.modulate = Color(0.62, 0.45, 1.0, 0.85)
	add_child(_core)
	_ring = Assets.world_sprite("gravity_ring", true)
	_ring.scale = Vector2.ONE * (radius / 250.0)
	_ring.modulate = Color(0.6, 0.4, 1.0, 0.5)
	add_child(_ring)

func step(delta: float) -> void:
	_t += delta
	life += delta
	if life >= duration:
		_finish()
		return
	var k: float = sin(clampf(life / duration, 0.0, 1.0) * PI)
	_core.rotation -= delta * 2.0
	_ring.rotation += delta * 0.4
	_ring.modulate.a = 0.25 + 0.4 * k
	_core.scale = Vector2.ONE * (0.10 + 0.05 * k)
	_ring.scale = Vector2.ONE * (radius / 250.0) * (0.96 + 0.04 * sin(_t * 3.0))

func apply_to(missile: Node2D) -> Vector2:
	var d: Vector2 = position - missile.position
	var dist: float = d.length()
	if dist > radius or dist < 1.0:
		return Vector2.ZERO
	var k: float = 1.0 - dist / radius
	return d.normalized() * force * (0.25 + 0.75 * k)

func _finish() -> void:
	if dead:
		return
	if run != null:
		run.on_anchor_gone(self)
	remove()

func remove() -> void:
	if dead:
		return
	dead = true
	if run != null:
		run.anchors.erase(self)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(self, "modulate:a", 0.0, 0.3)
	tw.chain().tween_callback(queue_free)
