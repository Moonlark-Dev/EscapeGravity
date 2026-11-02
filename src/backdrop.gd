class_name Backdrop
extends Node2D
## Pre-rendered seamless star/nebula layers with manual parallax tiling.
## No runtime drawing: just sprites moved and wrapped.
##
## The tile grid is anchored to the camera (not to the world origin), so the
## background keeps covering the screen at any world coordinate. Parallax is
## applied as a wrapped offset inside that grid.

var camera: Camera2D
var _layers: Array = []

class Layer:
	var node: Node2D
	var tile: float
	var speed: float
	var offset: Vector2

func _ready() -> void:
	z_index = -100
	_add_layer(Assets.world("nebula_1"), 1024.0, 0.015, Color(0.55, 0.85, 1.0, 0.22), Vector2(0, 0))
	_add_layer(Assets.world("nebula_2"), 1024.0, 0.025, Color(0.75, 0.55, 1.0, 0.18), Vector2(311, 133))
	_add_layer(Assets.world("nebula_3"), 1024.0, 0.04, Color(1.0, 0.45, 0.7, 0.12), Vector2(733, 522))
	_add_layer(Assets.world("bg_stars_far"), 512.0, 0.06, Color(0.8, 0.9, 1.0, 0.45), Vector2(0, 0))
	_add_layer(Assets.world("bg_stars_near"), 512.0, 0.16, Color(1, 1, 1, 0.72), Vector2(97, 251))
	_add_layer(Assets.world("dust"), 256.0, 0.34, Color(0.6, 0.8, 1.0, 0.22), Vector2(0, 0))

func _visible_logical_size() -> Vector2:
	var v := get_viewport().get_visible_rect().size
	if v.x <= 0.0 or v.y <= 0.0:
		return EG.SCREEN
	var s: float = minf(v.x / EG.SCREEN.x, v.y / EG.SCREEN.y)
	if s <= 0.01:
		return EG.SCREEN
	return v / s

func _add_layer(tex: Texture2D, tile: float, speed: float, tint: Color, offset: Vector2) -> void:
	var n := Node2D.new()
	add_child(n)
	# Cover the widest aspect ratio the project can be displayed at, not just
	# the 1280x720 design canvas (mobile "expand" can expose a 20:9 view).
	var view := _visible_logical_size()
	var cols := int(ceil((view.x + tile * 2.0) / tile)) + 1
	var rows := int(ceil((view.y + tile * 2.0) / tile)) + 1
	for y in range(rows):
		for x in range(cols):
			var s := Sprite2D.new()
			s.texture = tex
			s.centered = false
			s.position = Vector2(x - 1, y - 1) * tile
			s.modulate = tint
			n.add_child(s)
	var l := Layer.new()
	l.node = n
	l.tile = tile
	l.speed = speed
	l.offset = offset
	_layers.append(l)

func _process(_delta: float) -> void:
	if camera == null:
		camera = get_viewport().get_camera_2d()
	if camera == null:
		return
	var c := camera.get_screen_center_position()
	for l in _layers:
		# Camera-space anchor + wrapped parallax offset. Without the `c` term the
		# grid stayed near the world origin and vanished a few chunks out.
		var par := Vector2(
			fposmod(-c.x * l.speed + l.offset.x, l.tile),
			fposmod(-c.y * l.speed + l.offset.y, l.tile)
		)
		l.node.position = c + par - Vector2(l.tile, l.tile)
