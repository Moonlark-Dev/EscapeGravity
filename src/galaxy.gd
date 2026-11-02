class_name Galaxy
extends RefCounted
## Deterministic, streaming procedural galaxy: star systems, rogue planets,
## exploration bookkeeping and spawn placement helpers.

const CHUNK := 2048.0
const STAR_CELL := 7800.0
const LOAD_RADIUS := 3        # chunks (~6k px in every direction)
const UNLOAD_RADIUS := 5
const MAX_BODIES := 90

var run
var rng := RandomNumberGenerator.new()
var seed_value := 0
var bodies: Array = []          # GravityBody
var _chunks: Dictionary = {}    # Vector2i -> Array[GravityBody]
var _explored: Dictionary = {}  # Vector2i -> true
var _last_explore_cell := Vector2i(999999, 999999)

func _init(p_run, p_seed: int) -> void:
	run = p_run
	seed_value = p_seed
	rng.seed = p_seed

func start(origin: Vector2) -> void:
	# A hand-placed scenic system near spawn: one big planet + one small moon.
	_add_body(origin + Vector2(2250, -1250), 320.0, "planet", 1, true)
	_add_body(origin + Vector2(-2600, 1950), 260.0, "planet", 2, true)
	_add_body(origin + Vector2(1400, 3000), 200.0, "planet", 3, true)
	ensure_around(origin)

func ensure_around(pos: Vector2) -> void:
	var cc := cell_of(pos)
	for dy in range(-LOAD_RADIUS, LOAD_RADIUS + 1):
		for dx in range(-LOAD_RADIUS, LOAD_RADIUS + 1):
			var c := Vector2i(cc.x + dx, cc.y + dy)
			if not _chunks.has(c):
				_generate_chunk(c)
	# Unload distant chunks.
	for c in _chunks.keys():
		if abs(c.x - cc.x) > UNLOAD_RADIUS or abs(c.y - cc.y) > UNLOAD_RADIUS:
			for b in _chunks[c]:
				b.remove()
				bodies.erase(b)
			_chunks.erase(c)

func cell_of(pos: Vector2) -> Vector2i:
	return Vector2i(floori(pos.x / CHUNK), floori(pos.y / CHUNK))

func _generate_chunk(c: Vector2i) -> void:
	var chunk_bodies: Array = []
	_chunks[c] = chunk_bodies
	var crng := RandomNumberGenerator.new()
	crng.seed = hash(Vector3i(c.x, c.y, seed_value))
	var base := Vector2(c.x * CHUNK, c.y * CHUNK)

	# Star systems: one per STAR_CELL, deterministic.
	var sc := Vector2i(floori((c.x * CHUNK) / STAR_CELL), floori((c.y * CHUNK) / STAR_CELL))
	var srng := RandomNumberGenerator.new()
	srng.seed = hash(Vector3i(sc.x, sc.y, seed_value + 7717))
	var has_star := srng.randf() < 0.62
	if has_star:
		var star_pos := Vector2(sc.x * STAR_CELL + srng.randf_range(1200, STAR_CELL - 1200),
			sc.y * STAR_CELL + srng.randf_range(1200, STAR_CELL - 1200))
		if _point_in_chunk(star_pos, c):
			var star_r := srng.randf_range(EG.STAR_RADIUS_MIN, EG.STAR_RADIUS_MAX)
			if _spot_clear(star_pos, star_r + 400.0):
				var star = _add_body(star_pos, star_r, "star", 1, true)
				if star == null:
					return
				chunk_bodies.append(star)
				var n_planets := srng.randi_range(2, 4)
				for i in range(n_planets):
					var ang := srng.randf() * TAU
					var dist := star_r + srng.randf_range(950.0, 2500.0)
					var pr := srng.randf_range(EG.BODY_RADIUS_MIN, EG.BODY_RADIUS_MAX)
					var ppos := star_pos + Vector2.RIGHT.rotated(ang) * dist
					if _spot_clear(ppos, pr + 380.0) and _point_in_chunk(ppos, c):
						var pb = _add_body(ppos, pr, "planet", srng.randi_range(1, 3), false)
						if pb != null:
							chunk_bodies.append(pb)
	if not has_star:
		# Rogue planets / lone rock worlds. Always at least one attempt so no
		# chunk is completely empty when the player streams into new space.
		var tries := crng.randi_range(1, 2)
		for i in range(tries):
			var pos := base + Vector2(crng.randf_range(500, CHUNK - 500), crng.randf_range(500, CHUNK - 500))
			var rr := crng.randf_range(EG.BODY_RADIUS_MIN, EG.BODY_RADIUS_MAX)
			if _spot_clear(pos, rr + 500.0):
				var nb = _add_body(pos, rr, "planet", crng.randi_range(1, 3), false)
				if nb != null:
					chunk_bodies.append(nb)
	# a few extra planets even in star chunks, at the chunk corners
	if has_star and crng.randf() < 0.35:
		var p2 := base + Vector2(crng.randf_range(400, 900), crng.randf_range(400, 900))
		if _spot_clear(p2, 900.0):
			var nb2 = _add_body(p2, crng.randf_range(210, 340), "planet", crng.randi_range(1, 3), false)
			if nb2 != null:
				chunk_bodies.append(nb2)
	# Guarantee a landmark in chunks that ended up empty (star placement can be
	# rejected, or a star can live in a neighbouring chunk of the same cell).
	if chunk_bodies.is_empty():
		for i in range(3):
			var gp := base + Vector2(
				CHUNK * (0.32 + 0.18 * i),
				CHUNK * (0.38 + 0.12 * i)
			)
			var gr := crng.randf_range(210.0, 340.0)
			if _spot_clear(gp, gr + 380.0):
				var gb = _add_body(gp, gr, "planet", crng.randi_range(1, 3), false)
				if gb != null:
					chunk_bodies.append(gb)
				break

func _point_in_chunk(p: Vector2, c: Vector2i) -> bool:
	return int(floori(p.x / CHUNK)) == c.x and int(floori(p.y / CHUNK)) == c.y

func _spot_clear(p: Vector2, margin: float) -> bool:
	if p.length() < 1200.0:
		return false
	for b in bodies:
		if b.position.distance_to(p) < b.radius + margin:
			return false
	return true

func _add_body(p: Vector2, r: float, kind: String, variant: int, fixed: bool):
	if bodies.size() >= MAX_BODIES:
		return null
	var b = run.new_gravity_body(p, r, kind, variant)
	return b

# ---- gravity ----
func gravity_at(pos: Vector2, for_ship: bool = false) -> Vector2:
	var g := Vector2.ZERO
	for b in bodies:
		if for_ship and b.kind == "star" and pos.distance_to(b.position) > b.radius * 1.12:
			continue
		g += b.gravity_at(pos)
	return g

func nearest_body(pos: Vector2) -> Variant:
	var best = null
	var bd := 1e20
	for b in bodies:
		var d: float = b.position.distance_squared_to(pos)
		if d < bd:
			bd = d
			best = b
	return best

func is_inside_any_body(pos: Vector2, extra: float = 0.0) -> bool:
	for b in bodies:
		if pos.distance_to(b.position) < b.radius + extra:
			return true
	return false

# ---- exploration ----
func explore_cell_of(pos: Vector2) -> Vector2i:
	return Vector2i(floori(pos.x / EG.EXPLORE_CELL), floori(pos.y / EG.EXPLORE_CELL))

func mark_view(rect: Rect2) -> void:
	var a := explore_cell_of(rect.position)
	var b := explore_cell_of(rect.end)
	for y in range(a.y, b.y + 1):
		for x in range(a.x, b.x + 1):
			_explored[Vector2i(x, y)] = true
	_last_explore_cell = explore_cell_of(rect.get_center())

func is_explored(pos: Vector2) -> bool:
	return _explored.has(explore_cell_of(pos))

func explored_cell(c: Vector2i) -> bool:
	return _explored.has(c)

func explored_count_near(center: Vector2, cells: int) -> int:
	var cc := explore_cell_of(center)
	var n := 0
	for y in range(-cells, cells + 1):
		for x in range(-cells, cells + 1):
			if _explored.has(Vector2i(cc.x + x, cc.y + y)):
				n += 1
	return n

## Finds a point in an unexplored area at a given distance band from `origin`.
## Returns a zero Vector2 if nothing suitable was found.
func find_unexplored_point(origin: Vector2, min_d: float, max_d: float, clear: float = 300.0, tries: int = 90) -> Vector2:
	for i in range(tries):
		var ang := rng.randf() * TAU
		var d := rng.randf_range(min_d, max_d)
		var p := origin + Vector2.RIGHT.rotated(ang) * d
		if is_explored(p):
			continue
		if is_inside_any_body(p, clear):
			continue
		if p.distance_to(origin) < min_d:
			continue
		return p
	return Vector2.ZERO

## Direction towards the nearest unexplored sample (used as a fallback).
func nearest_unexplored_direction(origin: Vector2) -> Vector2:
	var best_dir := Vector2.RIGHT
	var best_d := 1e20
	for i in range(16):
		var ang := TAU * float(i) / 16.0
		var dir := Vector2.RIGHT.rotated(ang)
		var d := 900.0
		while d < 2600.0:
			if not is_explored(origin + dir * d):
				if d < best_d:
					best_d = d
					best_dir = dir
				break
			d += 300.0
	return best_dir

func star_systems() -> Array:
	return []
