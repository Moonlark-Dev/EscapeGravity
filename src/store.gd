extends Node
## Persistent settings + records. Lives in user:// so it works on Windows and Android.

const PATH := "user://escape_gravity.cfg"

var master := 0.85
var music := 0.7
var sfx := 0.9
var screenshake := 1.0
var fullscreen := false
var touch_mode := false
var touch_override := -1
var hints_done := false
var best_depth := 0
var best_level := 1
var best_kills := 0
var runs := 0
var total_kills := 0
var playtime := 0.0

func _ready() -> void:
	touch_override = -1
	touch_mode = OS.has_feature("mobile") or DisplayServer.is_touchscreen_available()
	load_data()
	apply()

func load_data() -> void:
	var cf := ConfigFile.new()
	if cf.load(PATH) != OK:
		return
	master = float(cf.get_value("audio", "master", master))
	music = float(cf.get_value("audio", "music", music))
	sfx = float(cf.get_value("audio", "sfx", sfx))
	screenshake = float(cf.get_value("video", "screenshake", screenshake))
	fullscreen = bool(cf.get_value("video", "fullscreen", fullscreen))
	touch_override = int(cf.get_value("input", "touch_override", -1))
	if touch_override == 1:
		touch_mode = true
	elif touch_override == 0:
		touch_mode = false
	hints_done = bool(cf.get_value("progress", "hints_done", hints_done))
	best_depth = int(cf.get_value("records", "best_depth", best_depth))
	best_level = int(cf.get_value("records", "best_level", best_level))
	best_kills = int(cf.get_value("records", "best_kills", best_kills))
	runs = int(cf.get_value("records", "runs", runs))
	total_kills = int(cf.get_value("records", "total_kills", total_kills))
	playtime = float(cf.get_value("records", "playtime", playtime))

func save_data() -> void:
	var cf := ConfigFile.new()
	cf.set_value("audio", "master", master)
	cf.set_value("audio", "music", music)
	cf.set_value("audio", "sfx", sfx)
	cf.set_value("video", "screenshake", screenshake)
	cf.set_value("video", "fullscreen", fullscreen)
	cf.set_value("input", "touch_override", touch_override)
	cf.set_value("progress", "hints_done", hints_done)
	cf.set_value("records", "best_depth", best_depth)
	cf.set_value("records", "best_level", best_level)
	cf.set_value("records", "best_kills", best_kills)
	cf.set_value("records", "runs", runs)
	cf.set_value("records", "total_kills", total_kills)
	cf.set_value("records", "playtime", playtime)
	cf.save(PATH)

func get_opt(key: String):
	match key:
		"master":
			return master
		"music":
			return music
		"sfx":
			return sfx
		"screenshake":
			return screenshake
		"fullscreen":
			return fullscreen
		"touch":
			return touch_mode
	return null

func set_opt(key: String, value) -> void:
	match key:
		"master":
			master = float(value)
		"music":
			music = float(value)
		"sfx":
			sfx = float(value)
		"screenshake":
			screenshake = float(value)
		"fullscreen":
			fullscreen = bool(value)
		"touch":
			touch_mode = bool(value)
			touch_override = 1 if touch_mode else 0

func apply() -> void:
	Audio.set_levels(master, music, sfx)
	if not OS.has_feature("mobile"):
		var want := DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
		if DisplayServer.window_get_mode() != want:
			DisplayServer.window_set_mode(want)

func record_run(depth: int, level: int, kills: int, seconds: float) -> void:
	runs += 1
	total_kills += kills
	playtime += seconds
	best_depth = maxi(best_depth, depth)
	best_level = maxi(best_level, level)
	best_kills = maxi(best_kills, kills)
	save_data()
