extends Node
## Pre-rendered audio only: generated WAV files, never synthesized at runtime.

const SFX_DIR := "res://assets/audio/%s.wav"

var _music_player: AudioStreamPlayer
var _loop_player: AudioStreamPlayer
var _loop_name := ""
var _sfx_players: Array[AudioStreamPlayer] = []
var _sfx_next := 0
var _last_played: Dictionary = {}
var _current_track := ""
var _cache: Dictionary = {}

func _ready() -> void:
	_ensure_buses()
	_music_player = AudioStreamPlayer.new()
	_music_player.bus = "Music"
	_music_player.volume_db = -3.0
	add_child(_music_player)
	_loop_player = AudioStreamPlayer.new()
	_loop_player.bus = "SFX"
	add_child(_loop_player)
	for i in range(14):
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_sfx_players.append(p)

func _ensure_buses() -> void:
	for bus_name in ["Music", "SFX"]:
		if AudioServer.get_bus_index(bus_name) == -1:
			AudioServer.add_bus()
			var idx := AudioServer.bus_count - 1
			AudioServer.set_bus_name(idx, bus_name)
			AudioServer.set_bus_send(idx, "Master")

func set_levels(master: float, music: float, sfx: float) -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(master, 0.0001)))
	var mi := AudioServer.get_bus_index("Music")
	if mi >= 0:
		AudioServer.set_bus_volume_db(mi, linear_to_db(maxf(music, 0.0001)))
	var si := AudioServer.get_bus_index("SFX")
	if si >= 0:
		AudioServer.set_bus_volume_db(si, linear_to_db(maxf(sfx, 0.0001)))

func _stream(name: String, loop: bool) -> AudioStream:
	var key := name + ("_loop" if loop else "")
	if _cache.has(key):
		return _cache[key]
	var path := SFX_DIR % name
	if not ResourceLoader.exists(path):
		push_warning("missing audio: " + path)
		return null
	var s := load(path)
	if s is AudioStreamWAV:
		var w := s as AudioStreamWAV
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD if loop else AudioStreamWAV.LOOP_DISABLED
		w.loop_begin = 0
		w.loop_end = int(w.get_length() * w.mix_rate) if loop else 0
	_cache[key] = s
	return s

func play(name: String, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	var now := Time.get_ticks_msec()
	if _last_played.has(name) and now - int(_last_played[name]) < 45:
		return
	_last_played[name] = now
	var s := _stream(name, false)
	if s == null:
		return
	var p := _sfx_players[_sfx_next]
	_sfx_next = (_sfx_next + 1) % _sfx_players.size()
	p.stream = s
	p.volume_db = volume_db
	p.pitch_scale = pitch
	p.play()

func loop_sfx(name: String, active: bool, volume_db: float = -16.0, pitch: float = 1.0) -> void:
	if active:
		if _loop_name != name:
			_loop_name = name
			var st := _stream(name, true)
			if st != null:
				_loop_player.stream = st
				_loop_player.volume_db = volume_db
				_loop_player.pitch_scale = pitch
				_loop_player.play()
		else:
			_loop_player.volume_db = volume_db
			_loop_player.pitch_scale = pitch
		if not _loop_player.playing:
			_loop_player.play()
	else:
		if _loop_name != "":
			_loop_name = ""
			_loop_player.stop()

func music(track: String) -> void:
	if track == _current_track:
		return
	_current_track = track
	if track == "":
		_music_player.stop()
		return
	var s := _stream(track, true)
	if s == null:
		return
	_music_player.stream = s
	_music_player.play()

func stop_music() -> void:
	_current_track = ""
	_music_player.stop()

func fade_music(to_db: float, seconds: float) -> void:
	var tw := create_tween()
	tw.tween_property(_music_player, "volume_db", to_db, seconds)
