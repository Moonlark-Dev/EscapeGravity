extends Node
## Central texture/font registry. Everything the game draws is a pre-rendered
## asset loaded here — no runtime shape drawing anywhere in the project.

var _cache: Dictionary = {}
var _font: FontFile
var _missing: Texture2D

func _ready() -> void:
	_font = load("res://assets/fonts/ui.ttc") as FontFile
	if _font == null:
		push_error("UI font missing: res://assets/fonts/ui.ttc")
	var img := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	img.fill(Color(1.0, 0.0, 1.0, 1.0))
	_missing = ImageTexture.create_from_image(img)

func world(name: String) -> Texture2D:
	return tex("res://assets/world/%s.png" % name)

func ui(name: String) -> Texture2D:
	return tex("res://assets/ui/%s.png" % name)

func tex(path: String) -> Texture2D:
	if _cache.has(path):
		return _cache[path]
	var t: Texture2D = null
	if ResourceLoader.exists(path):
		t = load(path) as Texture2D
	if t == null:
		push_warning("missing texture: " + path)
		t = _missing
	_cache[path] = t
	return t

func font() -> FontFile:
	return _font

func label(text: String, size: int = 18, color: Color = EG.C_TEXT, outline: int = 0) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", _font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if outline > 0:
		l.add_theme_color_override("font_outline_color", Color(0.01, 0.02, 0.05, 0.9))
		l.add_theme_constant_override("outline_size", outline)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

func sprite(path: String, additive: bool = false) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = tex(path)
	if additive:
		s.material = additive_material()
	return s

func world_sprite(name: String, additive: bool = false) -> Sprite2D:
	return sprite("res://assets/world/%s.png" % name, additive)

func ui_sprite(name: String, additive: bool = false) -> Sprite2D:
	return sprite("res://assets/ui/%s.png" % name, additive)

func additive_material() -> CanvasItemMaterial:
	var m := CanvasItemMaterial.new()
	m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	return m

func panel(name: String = "panel_9p", margin: int = 24) -> NinePatchRect:
	var p := NinePatchRect.new()
	p.texture = ui(name)
	p.patch_margin_left = margin
	p.patch_margin_right = margin
	p.patch_margin_top = margin
	p.patch_margin_bottom = margin
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p

func stylebox(name: String) -> StyleBoxTexture:
	var sb := StyleBoxTexture.new()
	sb.texture = ui(name)
	sb.texture_margin_left = 24
	sb.texture_margin_right = 24
	sb.texture_margin_top = 24
	sb.texture_margin_bottom = 24
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	return sb

func button(text: String, size: int = 20) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_override("font", _font)
	b.add_theme_font_size_override("font_size", size)
	b.add_theme_color_override("font_color", EG.C_TEXT)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_pressed_color", EG.C_CYAN)
	b.add_theme_color_override("font_disabled_color", Color(0.45, 0.52, 0.62))
	b.add_theme_stylebox_override("normal", stylebox("button_9p"))
	b.add_theme_stylebox_override("hover", stylebox("button_hover_9p"))
	b.add_theme_stylebox_override("pressed", stylebox("button_pressed_9p"))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_stylebox_override("disabled", stylebox("button_disabled_9p"))
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.mouse_entered.connect(func(): Audio.play("sfx_ui_hover", -22.0))
	b.pressed.connect(func(): Audio.play("sfx_ui_click", -10.0))
	return b

func progress_bar(fill_name: String, bg_name: String = "bar_bg_9p") -> TextureProgressBar:
	var bar := TextureProgressBar.new()
	bar.texture_under = ui(bg_name)
	bar.texture_progress = ui(fill_name)
	bar.nine_patch_stretch = true
	bar.stretch_margin_left = 8
	bar.stretch_margin_right = 8
	bar.stretch_margin_top = 8
	bar.stretch_margin_bottom = 8
	bar.fill_mode = TextureProgressBar.FILL_LEFT_TO_RIGHT
	bar.max_value = 100.0
	bar.value = 100.0
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return bar

func icon(name: String) -> TextureRect:
	var t := TextureRect.new()
	t.texture = ui(name)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return t
