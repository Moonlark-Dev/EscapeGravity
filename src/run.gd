class_name Run
extends Node2D
## One run of Escape Gravity. Owns the world, the state machine and the rules.

enum State { PLAYING, LEVELUP, SHOP, DESTROY, DEAD, REPLACE_SKILL }

var main
var hud
var seed_value := 0
var rng := RandomNumberGenerator.new()
var state := State.PLAYING
var paused := false

var world: Node2D
var fx_layer: Node2D
var camera: Camera2D
var backdrop: Backdrop
var ship: PlayerShip
var galaxy: Galaxy
var route: RunRoute

var enemies: Array = []
var missiles: Array = []
var drones: Array = []
var meteors: Array = []
var matters: Array = []
var zones: Array = []
var decoys: Array = []
var anchors: Array = []

var safe_zone: Zone = null
var shop_zone: Zone = null
var current_enemy: Enemy = null
var shop_open := false
var shop_inside := false
var shop_stock: Array = []
## 商店在线路中的相对位置：所在路线段（0 起）以及该段敌人的深度。
## 玩家没进商店、却先击败了该段敌人时，商店已经落到身后，需要随战线重定位。
var shop_route_leg := -1
var shop_bound_depth := 0

var depth := 1
var kills := 0
var run_time := 0.0
var level := 1
var xp := 0.0
var pending_levels := 0
var upgrade_cards: Array = []
var tokens := 0
var inventory: Array = []
var item_slots := EG.ITEM_SLOTS_BASE
var selected_item := 0
var skills: Array = []
var absorb_radius := EG.MATTER_ABSORB
## 核心改装（被动插件）：id -> 层数。仅本局有效。
var mods: Dictionary = {}
## 节能巡航油耗倍率（1.0 = 原价，最低 EG.ECO_CRUISE_MIN）。
var eco_cruise := 1.0
## 战地整备：消耗品生效后的免费加力窗口。
var free_boost_timer := 0.0
var _pending_skill := ""

var player_hidden := false
var fuel_dead_timer := 0.0
var safe_timer := 0.0
var next_enemy_timer := 0.0
## 修整区（安全区 / 商店）不按时间刷新：击败敌人后立即刷新。玩家正停靠
## 在其中时刷新先挂起，等离开时马上补上，避免把区域从脚下抽走。
var pending_safe_refresh := false
var pending_shop_refresh := false
var meteor_timer := 6.0
var matter_refill_timer := 2.0
var drone_timer := 12.0
var drone_warned := false

var shake := 0.0
var assist_active := false
var orbit_assist := false
var tutorial_index := 0
var tutorial_timer := 0.0
var stats := {"matter": 0, "hits": 0, "damage": 0, "unlocks": 0, "fuel_items": 0}
var last_damage_source := ""
var _screen_size := EG.SCREEN
var _last_tick := 0.0
var _alarm_cd := 0.0
var _hitstop := 0.0
var _pending_item := ""

# Headless test hooks
var auto_play := false
var auto_input := Vector2.ZERO
var auto_boost := false
var auto_pulse := false
var test_mode := false
var no_stream := false          # bot tests run in a clean, body-free arena

func _ready() -> void:
	if seed_value == 0:
		seed_value = int(Time.get_unix_time_from_system() * 1000.0) % 2147483647
	rng.seed = seed_value
	_screen_size = get_viewport().get_visible_rect().size
	if hud != null:
		hud.bind(self)
	_build_world()
	_initial_spawn()
	if hud != null:
		hud.refresh()

func _build_world() -> void:
	backdrop = Backdrop.new()
	add_child(backdrop)
	world = Node2D.new()
	world.name = "World"
	add_child(world)
	fx_layer = Node2D.new()
	fx_layer.name = "Fx"
	add_child(fx_layer)
	camera = Camera2D.new()
	camera.position = Vector2.ZERO
	camera.zoom = Vector2.ONE
	add_child(camera)
	backdrop.camera = camera
	galaxy = Galaxy.new(self, seed_value)
	galaxy.start(Vector2.ZERO)
	ship = PlayerShip.new()
	ship.run = self
	world.add_child(ship)
	skills.append({"id": "pulse", "level": 1, "cd": 0.0})
	inventory = []
	item_slots = EG.ITEM_SLOTS_BASE
	ship.fuel_cost_mult = eco_cruise

func _initial_spawn() -> void:
	if test_mode:
		# Tests need the planned nodes even without the presentation pass.
		route = galaxy.build_route(Vector2.ZERO)
		return
	# Step 2: fill matter around the start.
	scatter_matter(150, ship.position, 380.0, 2900.0, true)
	# Step 3: build the hidden route, then materialise its first nodes.
	route = galaxy.build_route(Vector2.ZERO)
	var safe_pos := _next_route_safe()
	safe_zone = make_zone("safe", _place_zone_point(safe_pos))
	var shop_pos := _next_route_shop()
	shop_zone = make_zone("shop", _place_zone_point(shop_pos))
	shop_route_leg = route.next_shop - 1
	shop_bound_depth = depth
	spawn_enemy()
	if hud != null:
		hud.toast("引力捕获完成 · 深度 1", EG.C_CYAN, 2.6)
		tutorial_timer = 2.0

# ---------------------------------------------------------------- nodes

func new_gravity_body(pos: Vector2, r: float, kind: String, variant: int) -> GravityBody:
	var b := GravityBody.new()
	b.radius = r
	b.kind = kind
	b.variant = variant
	b.position = pos
	world.add_child(b)
	if galaxy != null and not galaxy.bodies.has(b):
		galaxy.bodies.append(b)
	return b

func make_zone(kind: String, pos: Vector2) -> Zone:
	var z := Zone.new()
	z.run = self
	z.kind = kind
	z.position = pos
	world.add_child(z)
	zones.append(z)
	return z

func _add_matter(pos: Vector2, big: bool) -> void:
	var m := Matter.new()
	m.run = self
	m.big = big
	m.xp = EG.MATTER_BIG_XP if big else EG.MATTER_SMALL_XP
	m.position = pos
	world.add_child(m)
	matters.append(m)

func scatter_matter(count: int, center: Vector2, min_d: float, max_d: float, unexplored_only: bool) -> void:
	var clumps := maxi(1, count / 6)
	var per := maxi(1, count / clumps)
	var made := 0
	for _c in range(clumps):
		var p := Vector2.ZERO
		if unexplored_only:
			p = galaxy.find_unexplored_point(center, min_d, max_d, 120.0, 20)
		if p == Vector2.ZERO:
			var ang := rng.randf() * TAU
			p = center + Vector2.RIGHT.rotated(ang) * rng.randf_range(min_d, max_d)
		if galaxy.is_inside_any_body(p, 40.0):
			continue
		for i in range(per):
			var off := Vector2.RIGHT.rotated(rng.randf() * TAU) * rng.randf_range(0.0, 90.0)
			var q := p + off
			if galaxy.is_inside_any_body(q, 20.0):
				continue
			_add_matter(q, rng.randf() < EG.MATTER_BIG_CHANCE)
			made += 1
			if matters.size() >= 280:
				return

func _matter_count_near(center: Vector2, radius: float) -> int:
	var n := 0
	for mat in matters:
		if is_instance_valid(mat) and not mat.collected and mat.position.distance_to(center) <= radius:
			n += 1
	return n

func scatter_matter_at(center: Vector2, count: int, radius: float) -> void:
	for i in range(count):
		var p := center + Vector2.RIGHT.rotated(rng.randf() * TAU) * (sqrt(rng.randf()) * radius)
		if galaxy.is_inside_any_body(p, 20.0):
			continue
		_add_matter(p, rng.randf() < EG.MATTER_BIG_CHANCE)

# ---------------------------------------------------------------- loop

func _physics_process(delta: float) -> void:
	if state == State.PLAYING and not paused:
		simulate(delta)
	else:
		assist_active = false
		orbit_assist = false
	if hud != null:
		hud.refresh()

func simulate(delta: float) -> void:
	if state != State.PLAYING:
		return
	run_time += delta
	var dir := _read_dir()
	var boost := _read_boost()
	_handle_gameplay_keys()
	_update_timers(delta)

	if not no_stream:
		galaxy.ensure_around(ship.position)
	mark_exploration()
	_update_skills(delta)
	assist_active = false
	orbit_assist = false

	ship.step(delta, dir, boost)
	_assist_fuel(delta)
	_update_mods(delta)

	for m in missiles.duplicate():
		if m.dead:
			continue
		m.pull = _pull_on_missile(m)
		m.step(delta)
	for d in drones.duplicate():
		if is_instance_valid(d) and not d.dead:
			d.step(delta)
	for e in enemies:
		if not e.dead:
			e.step(delta)
	for met in meteors:
		if not met.dead:
			met.step(delta)
	for mat in matters.duplicate():
		if is_instance_valid(mat) and not mat.collected:
			mat.step(delta)
	for d in decoys:
		if not d.dead:
			d.step(delta)
	for a in anchors.duplicate():
		if is_instance_valid(a) and not a.dead:
			a.step(delta)
	for z in zones.duplicate():
		if is_instance_valid(z) and z.active:
			z.step(delta)

	_apply_decoy_orders()
	_resolve_collisions()
	_zone_checks()
	_check_fuel(delta)
	_alarm_tick(delta)
	_missile_warn_tick(delta)
	_update_spawns(delta)
	_update_camera(delta)
	_tutorial_step(delta)
	_cleanup()
	if hud != null:
		hud.flash_update(delta)


func _process(delta: float) -> void:
	# Particles, sprite bobbing and camera shake keep animating while paused
	# (the gameplay simulation itself is frozen).
	if state == State.PLAYING and not paused:
		shake = maxf(0.0, shake - delta * 2.6)
		if camera != null:
			camera.offset = Vector2(rng.randf_range(-1, 1), rng.randf_range(-1, 1)) * shake * 9.0 * Store.screenshake

func _update_timers(delta: float) -> void:
	safe_timer = maxf(0.0, safe_timer - delta)
	next_enemy_timer = maxf(0.0, next_enemy_timer - delta)
	meteor_timer -= delta
	matter_refill_timer -= delta

func mark_exploration() -> void:
	var r := screen_rect().grow(160.0)
	galaxy.mark_view(r)

func _read_dir() -> Vector2:
	if auto_play:
		return auto_input
	var v := Controls.move_vector()
	if hud != null and hud.touch_dir.length() > 0.08:
		v = hud.touch_dir
	return v

func _read_boost() -> bool:
	if auto_play:
		return auto_boost
	if hud != null and hud.touch_boost:
		return true
	return Input.is_action_pressed("boost")

func _handle_gameplay_keys() -> void:
	if auto_play:
		if auto_pulse:
			auto_pulse = false
			cast_skill(0)
		return
	if Input.is_action_just_pressed("skill_1"):
		cast_skill(0)
	if Input.is_action_just_pressed("skill_2"):
		cast_skill(1)
	if Input.is_action_just_pressed("use_item"):
		use_item_slot(selected_item)
	if Input.is_action_just_pressed("item_next"):
		select_item_slot((selected_item + 1) % maxi(1, inventory.size()))
	if Input.is_action_just_pressed("item_prev"):
		select_item_slot((selected_item - 1 + maxi(1, inventory.size())) % maxi(1, inventory.size()))

func _update_skills(delta: float) -> void:
	for s in skills:
		s["cd"] = maxf(0.0, float(s["cd"]) - delta)

func _assist_fuel(delta: float) -> void:
	if assist_active:
		ship.fuel = maxf(0.0, ship.fuel - EG.SHIP_FUEL_ASSIST * delta * ship.fuel_cost_mult)

func _pull_on_missile(m) -> Vector2:
	var pull := Vector2.ZERO
	for a in anchors:
		if not a.dead:
			pull += a.apply_to(m)
	return pull

# ---------------------------------------------------------------- camera / screen

func gravity_at(pos: Vector2) -> Vector2:
	return galaxy.gravity_at(pos, false)

func gravity_ship_at(pos: Vector2) -> Vector2:
	# 安全区是驻留口袋：整个影响圈（而不只是圈内）都平衡局部天体引力，
	# 否则靠近恒星的进站路线会被恒星引力甩出去。导弹没有这套保护。
	if safe_zone != null and safe_zone.active:
		var influence: float = safe_zone.clearance_radius() + EG.ZONE_INFLUENCE_EXTRA
		if safe_zone.position.distance_to(pos) < influence:
			return Vector2.ZERO
	return galaxy.gravity_at(pos, true)

func screen_rect() -> Rect2:
	var center := camera.get_screen_center_position() if camera != null else Vector2.ZERO
	var size := _screen_size
	var vs := get_viewport().get_visible_rect().size
	if vs.x > 0 and vs.y > 0:
		var s: float = minf(vs.x / EG.SCREEN.x, vs.y / EG.SCREEN.y)
		if s > 0.01:
			size = vs / s
	return Rect2(center - size * 0.5, size)

func is_on_screen(pos: Vector2, margin: float = 40.0) -> bool:
	return screen_rect().grow(margin).has_point(pos)

func enemy_in_view(e: Enemy) -> bool:
	var r := screen_rect()
	var p := Vector2(clampf(e.position.x, r.position.x, r.end.x), clampf(e.position.y, r.position.y, r.end.y))
	return p.distance_to(e.position) < e.radius

func _update_camera(delta: float) -> void:
	var want: Vector2 = ship.position + ship.vel * 0.28
	var k: float = 1.0 - pow(0.0015, delta)
	camera.position = camera.position.lerp(want, k)
	camera.offset = camera.offset.lerp(Vector2.ZERO, 1.0 - pow(0.02, delta))

func world_to_screen(pos: Vector2) -> Vector2:
	var center := camera.get_screen_center_position()
	return pos - center + _screen_size * 0.5

# ---------------------------------------------------------------- spawning

## 五种主敌人随深度解锁轮换：炮塔 → 导弹巢 → 偏导母舰 → 引力阱舰 → 双子中继站。
const ENEMY_KINDS := ["turret", "nest", "aegis", "singularity", "twin"]

func enemy_kind_for_depth(d: int) -> String:
	return ENEMY_KINDS[posmod(d - 1, ENEMY_KINDS.size())]

## 深层不再靠疯狂堆血：+14%/层，并用精英词缀（深度 6 起每 4 层）提供难度。
func is_elite_depth(d: int) -> bool:
	if d < EG.ELITE_DEPTH_START:
		return false
	return (d - EG.ELITE_DEPTH_START) % EG.ELITE_EVERY == 0

func spawn_enemy() -> void:
	if current_enemy != null or state == State.DEAD:
		return
	var kind := enemy_kind_for_depth(depth)
	var elite := is_elite_depth(depth)
	var e := _make_attacker(kind, elite)
	e.position = _next_enemy_position(e)
	world.add_child(e)
	enemies.append(e)
	current_enemy = e
	e.fire_timer = 1.5
	if kind == "twin":
		# 双子中继站：成对刷新、共享公转中心，间距 750px。
		var partner := _make_attacker(kind, elite)
		e.twin = partner
		partner.twin = e
		e.twin_leader = true
		e.pair_angle = rng.randf() * TAU
		e.pair_center = e.position - Vector2.RIGHT.rotated(e.pair_angle) * (EG.PYLON_GAP * 0.5)
		e.position = e.pair_center + Vector2.RIGHT.rotated(e.pair_angle) * (EG.PYLON_GAP * 0.5)
		partner.pair_center = e.pair_center
		partner.pair_angle = e.pair_angle
		partner.position = galaxy.push_out_of_bodies(
			e.pair_center - Vector2.RIGHT.rotated(e.pair_angle) * (EG.PYLON_GAP * 0.5), partner.radius)
		partner.fire_timer = 2.2
		world.add_child(partner)
		enemies.append(partner)
	if hud != null and not player_hidden:
		# The attacker stays undetected until it enters the screen; the spawn
		# only hints that something is out there.
		hud.toast("深空中有未知信号在移动", EG.C_AMBER, 2.0)
	if shop_zone != null and is_on_screen(shop_zone.position):
		Audio.play("sfx_alarm", -4.0)
	shake = maxf(shake, 0.4)

func _make_attacker(kind: String, elite: bool) -> Enemy:
	var e := Enemy.new()
	e.run = self
	e.kind = kind
	e.depth = depth
	e.elite = elite
	var base_hp := EG.TURRET_HP
	match kind:
		"nest":
			e.radius = EG.NEST_RADIUS
			base_hp = EG.NEST_HP
			e.fire_out = EG.NEST_FIRE_OUT
			e.fire_in = EG.NEST_FIRE_IN
			e.burst = EG.NEST_BURST
			e.overheat_time = EG.NEST_OVERHEAT
			e.speed_out = EG.NEST_SPEED_OUT
			e.speed_in = EG.NEST_SPEED_IN
			e.max_locked = EG.NEST_MAX_LOCKED
		"aegis":
			e.radius = EG.AEGIS_RADIUS
			base_hp = EG.AEGIS_HP
			e.fire_out = EG.AEGIS_FIRE_OUT
			e.fire_in = EG.AEGIS_FIRE_IN
			e.burst = EG.AEGIS_BURST
			e.overheat_time = EG.AEGIS_OVERHEAT
			e.speed_out = EG.AEGIS_SPEED_OUT
			e.speed_in = EG.AEGIS_SPEED_IN
			e.max_locked = EG.MISSILE_MAX_LOCKED
			e.facing = rng.randf() * TAU
		"singularity":
			e.radius = EG.RIG_RADIUS
			base_hp = EG.RIG_HP
			e.fire_out = EG.RIG_FIRE_OUT
			e.fire_in = EG.RIG_FIRE_IN
			e.burst = EG.RIG_BURST
			e.overheat_time = EG.RIG_OVERHEAT
			e.speed_out = EG.RIG_SPEED_OUT
			e.speed_in = EG.RIG_SPEED_IN
			e.max_locked = EG.MISSILE_MAX_LOCKED
			e.state_timer = EG.RIG_REPEL_TIME
		"twin":
			e.radius = EG.PYLON_RADIUS
			base_hp = EG.PYLON_HP
			e.fire_out = EG.PYLON_FIRE_OUT
			e.fire_in = EG.PYLON_FIRE_IN
			e.burst = EG.PYLON_BURST
			e.overheat_time = EG.PYLON_OVERHEAT
			e.speed_out = EG.PYLON_SPEED_OUT
			e.speed_in = EG.PYLON_SPEED_IN
			e.max_locked = EG.MISSILE_MAX_LOCKED
			e.facing = rng.randf() * TAU
		_:
			e.radius = EG.TURRET_RADIUS
			base_hp = EG.TURRET_HP
			e.fire_out = EG.TURRET_FIRE_OUT
			e.fire_in = EG.TURRET_FIRE_IN
			e.burst = EG.TURRET_BURST
			e.overheat_time = EG.TURRET_OVERHEAT
			e.speed_out = EG.TURRET_SPEED_OUT
			e.speed_in = EG.TURRET_SPEED_IN
			e.max_locked = EG.MISSILE_MAX_LOCKED
	var growth: float = 1.0 + EG.DEPTH_HP_GROWTH * float(depth - 1)
	e.max_hp = base_hp * growth * (EG.ELITE_HP_MULT if elite else 1.0)
	var rate: float = maxf(0.62, 1.0 - EG.DEPTH_RATE_GROWTH * float(depth - 1))
	e.fire_out *= rate
	e.fire_in *= rate
	e.speed_out *= 1.0 + 0.02 * float(depth - 1)
	if elite:
		e.burst += 1
		e.affix = _roll_affix(kind)
		if e.affix == "volatile":
			e.max_hp *= 0.7
	e.hp = e.max_hp
	return e

func _roll_affix(kind: String) -> String:
	var pool := ["point_defense", "phase_blink", "volatile"]
	if kind == "twin":
		pool = ["point_defense", "volatile"]
	return str(pool[rng.randi_range(0, pool.size() - 1)])

## Pulls the next attacker position from the pre-generated route.  The route
## only decides where content sits; the enemy still chases the player normally.
func _next_enemy_position(e: Enemy) -> Vector2:
	if route == null:
		return _find_enemy_spawn(e)
	var before := route.encounters.size()
	var cursor: Vector2 = route.enemy_at(route.next_enemy)
	route.next_enemy += 1
	if route.encounters.size() != before:
		galaxy.apply_route_bodies()
	var clear: float = e.radius + EG.BODY_CONTENT_MARGIN
	var p := _clear_body_point(cursor, clear)
	if not _enemy_spawn_blocked(p, e):
		return p
	# The route point is normally clear; if a streamed star system landed on
	# it, ring the point instead of abandoning the planned order.
	for ring in range(1, EG.PLACE_SEARCH_RINGS + 1):
		var d: float = clear + EG.PLACE_SEARCH_STEP * float(ring)
		for i in range(24):
			var q: Vector2 = cursor + Vector2.RIGHT.rotated(TAU * float(i) / 24.0) * d
			q = _clear_body_point(q, clear)
			if not _enemy_spawn_blocked(q, e):
				return q
	return p

## Nudges a planned point out of a celestial body without changing its leg.
## `clearance` is the extra space required beyond the body surface (sprite
## radius + BODY_CONTENT_MARGIN).  The search expands in rings and rotates
## slightly each ring, so even a huge star cannot trap the point.
func _clear_body_point(p: Vector2, clearance: float) -> Vector2:
	if not galaxy.is_inside_any_body(p, clearance):
		return p
	for ring in range(1, EG.PLACE_SEARCH_RINGS + 1):
		var d: float = clearance + EG.PLACE_SEARCH_STEP * float(ring)
		var phase: float = float(ring) * 0.37
		for i in range(24):
			var q: Vector2 = p + Vector2.RIGHT.rotated(phase + TAU * float(i) / 24.0) * d
			if not galaxy.is_inside_any_body(q, clearance):
				return q
	# Last resort: run away from the nearest body along the radial line.
	var nb = galaxy.nearest_body(p)
	if nb != null:
		var away: Vector2 = p - nb.position
		if away.length() < 1.0:
			away = Vector2.RIGHT
		for k in range(1, 9):
			var q2: Vector2 = p + away.normalized() * (clearance + 1200.0 * float(k))
			if not galaxy.is_inside_any_body(q2, clearance):
				return q2
	return p

func _find_enemy_spawn(e: Enemy) -> Vector2:
	# The attacker and the safe zone should sit on the same bearing from the
	# player, so fleeing and fighting never pull in opposite directions. When a
	# safe zone exists we spawn beyond it (with enough clearance that the zone
	# does not swallow the attacker) and let Enemy.step() slide around it.
	var aligned: bool = safe_zone != null and safe_zone.active
	var base_ang: float = rng.randf() * TAU
	var min_d := EG.SPAWN_MIN
	var max_d := EG.SPAWN_MAX
	if aligned:
		base_ang = (safe_zone.position - ship.position).angle()
		var safe_d: float = ship.position.distance_to(safe_zone.position)
		min_d = maxf(EG.SPAWN_MIN, safe_d + safe_zone.clearance_radius() + e.radius + 420.0)
		max_d = min_d + 480.0
	# Pass 1: prefer unexplored space, but stay on (or near) the safe-zone ray.
	for i in range(150):
		var spread: float = 0.0 if i < 6 else minf(0.6, float(i) * 0.012)
		var ang := base_ang + rng.randf_range(-spread, spread)
		var p := ship.position + Vector2.RIGHT.rotated(ang) * rng.randf_range(min_d, max_d)
		if galaxy.is_explored(p):
			continue
		if _enemy_spawn_blocked(p, e):
			continue
		return p
	# Pass 2: the aligned ray is more important than the "unexplored" surprise;
	# allow a previously seen area if it keeps the markers aligned.
	for i in range(90):
		var spread2: float = minf(0.55, 0.05 + float(i) * 0.008)
		var ang2 := base_ang + rng.randf_range(-spread2, spread2)
		var p2 := ship.position + Vector2.RIGHT.rotated(ang2) * rng.randf_range(min_d, max_d)
		if _enemy_spawn_blocked(p2, e):
			continue
		return p2
	# Last resort: any clear point in the normal ring.
	for i in range(120):
		var p3 := ship.position + Vector2.RIGHT.rotated(rng.randf() * TAU) * rng.randf_range(EG.SPAWN_MIN, EG.SPAWN_MAX)
		if not _enemy_spawn_blocked(p3, e):
			return p3
	return ship.position + Vector2.RIGHT.rotated(base_ang) * 2100.0

func _enemy_spawn_blocked(p: Vector2, e: Enemy) -> bool:
	if galaxy.is_inside_any_body(p, e.radius + EG.BODY_CONTENT_MARGIN):
		return true
	if safe_zone != null and safe_zone.active and p.distance_to(safe_zone.position) < safe_zone.clearance_radius() + e.radius + EG.ZONE_ENEMY_CLEAR:
		return true
	if shop_zone != null and shop_zone.active and p.distance_to(shop_zone.position) < shop_zone.radius + e.radius + EG.ZONE_ENEMY_CLEAR:
		return true
	return false

func _update_spawns(delta: float) -> void:
	if test_mode:
		return
	if current_enemy == null and enemies.size() == 0 and safe_timer <= 0.0 and next_enemy_timer <= 0.0:
		spawn_enemy()

	# 自杀无人机：玩家视野里没有安全区/商店时才刷新，每 8 秒成对出现，
	# 锁定玩家的总数上限 6。区域进入视野或达到上限时只做 1 秒一次的重试，
	# 不会积攒多批。
	drone_timer -= delta
	if drone_timer <= 0.0:
		if _can_spawn_drones():
			_spawn_drone_pair()
			drone_timer = EG.DRONE_INTERVAL
		else:
			drone_timer = EG.DRONE_RETRY

	if meteor_timer <= 0.0 and not player_hidden:
		meteor_timer = EG.METEOR_INTERVAL * (EG.MOD_BELT_INTERVAL if has_mod("gravity_belt") else 1.0)
		_spawn_meteor()

	if matter_refill_timer <= 0.0:
		matter_refill_timer = 2.0
		# Keep a live field around the ship instead of only around the spawn
		# point: count nearby motes and top them up slightly ahead of travel.
		if _matter_count_near(ship.position, 3400.0) < 130 and matters.size() < 280:
			var ahead: Vector2 = ship.position + ship.vel * 4.0
			scatter_matter(30, ahead, 350.0, 3000.0, true)


func _spawn_safe_respawn() -> void:
	var p := _next_route_safe()
	var clear := EG.ZONE_RADIUS + EG.BODY_CONTENT_MARGIN
	if p == Vector2.ZERO:
		p = galaxy.find_unexplored_point(ship.position, 700.0, EG.SAFE_FUEL_DIST, clear)
	if p == Vector2.ZERO:
		p = ship.position + galaxy.nearest_unexplored_direction(ship.position) * 1200.0
	p = _place_zone_point(p)
	safe_zone = make_zone("safe", p)
	player_hidden = false
	pending_safe_refresh = false
	if hud != null:
		hud.toast("安全区信号已同步", EG.C_MINT, 2.2)
		hud.emphasize_radar()
	Audio.play("sfx_safezone", -6.0)

## The route point can land where the current fight is happening, or on a
## celestial body.  Push it away from live attackers/other zones, then out of
## any body, and repeat once: a body push must not create a new overlap.
func _place_zone_point(p: Vector2) -> Vector2:
	var clear := EG.ZONE_RADIUS + EG.BODY_CONTENT_MARGIN
	for i in range(2):
		p = _clear_zone_of_other_zones(p)
		p = _clear_zone_of_enemies(p)
		p = _clear_body_point(p, clear)
	return p

## The route point can land where the current fight is happening; slide the new
## safe zone away from any live attacker until their sprite edges have room.
func _clear_zone_of_enemies(p: Vector2) -> Vector2:
	for e in enemies:
		if e == null or e.dead:
			continue
		var need: float = EG.ZONE_RADIUS + e.radius + EG.ZONE_ENEMY_CLEAR
		var d := p.distance_to(e.position)
		if d < need:
			var away: Vector2 = Vector2.RIGHT if d < 0.01 else (p - e.position) / d
			p = e.position + away * need
	return p

## Safe zones and shops must not overlap each other either.
func _clear_zone_of_other_zones(p: Vector2) -> Vector2:
	var need: float = EG.ZONE_RADIUS * 2.0 + EG.BODY_CONTENT_MARGIN
	for z in [safe_zone, shop_zone]:
		if z == null or not is_instance_valid(z) or not z.active:
			continue
		var d := p.distance_to(z.position)
		if d < need:
			var away: Vector2 = Vector2.RIGHT if d < 0.01 else (p - z.position) / d
			p = z.position + away * need
	return p

func _spawn_shop_respawn() -> void:
	var p := _next_route_shop_for_progress()
	var clear := EG.ZONE_RADIUS + EG.BODY_CONTENT_MARGIN
	if p == Vector2.ZERO:
		p = galaxy.find_unexplored_point(ship.position, EG.SHOP_DIST_MIN, EG.SHOP_DIST_MAX, clear)
	if p == Vector2.ZERO:
		p = ship.position + galaxy.nearest_unexplored_direction(ship.position) * 3600.0
	p = _place_zone_point(p)
	shop_zone = make_zone("shop", p)
	shop_route_leg = route.next_shop - 1 if route != null else -1
	shop_bound_depth = depth
	shop_open = false
	shop_inside = false
	pending_shop_refresh = false
	if hud != null:
		hud.toast("侦测到新的交易信标", EG.C_AMBER, 2.2)

func _next_route_safe() -> Vector2:
	if route == null:
		return Vector2.ZERO
	var before := route.encounters.size()
	var p: Vector2 = route.safe_at(route.next_safe)
	route.next_safe += 1
	if route.encounters.size() != before:
		galaxy.apply_route_bodies()
	return _clear_body_point(p, EG.ZONE_RADIUS + EG.BODY_CONTENT_MARGIN)

func _next_route_shop() -> Vector2:
	if route == null:
		return Vector2.ZERO
	var before := route.encounters.size()
	var p: Vector2 = route.shop_at(route.next_shop)
	route.next_shop += 1
	if route.encounters.size() != before:
		galaxy.apply_route_bodies()
	return _clear_body_point(p, EG.ZONE_RADIUS + EG.BODY_CONTENT_MARGIN)

## 商店刷新时如果玩家已经冲到前面，路线游标不能还停在后一段。把游标
## 至少推到“当前这一战”的路线段，保证新商店出现在玩家前方而不是身后。
func _next_route_shop_for_progress() -> Vector2:
	if route == null:
		return Vector2.ZERO
	route.next_shop = maxi(route.next_shop, depth - 1)
	return _next_route_shop()

func _spawn_meteor() -> void:
	var angle := rng.randf() * TAU
	for i in range(12):
		var c := Vector2.RIGHT.rotated(angle)
		var bad := false
		if current_enemy != null:
			var ep: Vector2 = current_enemy.position
			var rel: Vector2 = ep - (ship.position + c * 400.0)
			if absf(rel.dot(Vector2(-c.y, c.x))) < current_enemy.radius + 500.0 and rel.dot(c) > 0.0:
				bad = true
		if not bad:
			break
		angle = rng.randf() * TAU
	var origin := ship.position + Vector2.RIGHT.rotated(angle) * EG.METEOR_SPAWN_DIST
	var target := ship.position + Vector2.RIGHT.rotated(angle + rng.randf_range(-0.35, 0.35)) * rng.randf_range(200.0, 520.0)
	var met := Meteor.new()
	met.run = self
	met.position = origin
	var speed := rng.randf_range(EG.METEOR_SPEED_MIN, EG.METEOR_SPEED_MAX)
	met.vel = (target - origin).normalized() * speed
	world.add_child(met)
	meteors.append(met)

# ---------------------------------------------------------------- drones

## 玩家视野内出现安全区或商店时不再刷新无人机；无人机本身也不占敌人生成位。
func _can_spawn_drones() -> bool:
	if state != State.PLAYING or player_hidden:
		return false
	if safe_zone != null and is_instance_valid(safe_zone) and safe_zone.active \
			and is_on_screen(safe_zone.position, safe_zone.clearance_radius()):
		return false
	if shop_zone != null and is_instance_valid(shop_zone) and shop_zone.active \
			and is_on_screen(shop_zone.position, shop_zone.radius):
		return false
	return drone_lock_count() < EG.DRONE_MAX_LOCKED

## 只统计仍然锁定玩家的无人机。脱锁后 locked=false，不再占用 6 个名额。
func drone_lock_count() -> int:
	var n := 0
	for d in drones:
		if is_instance_valid(d) and not d.dead and d.locked:
			n += 1
	return n

func spawn_drone(pos: Vector2, heading: float) -> Drone:
	var d := Drone.new()
	d.run = self
	d.position = pos
	d.vel = Vector2.RIGHT.rotated(heading) * d.speed
	world.add_child(d)
	drones.append(d)
	Fx.sparks(fx_layer, pos, Color(0.72, 0.44, 1.0, 0.9), 6, 130.0)
	return d

func _spawn_drone_pair() -> void:
	var free: int = EG.DRONE_MAX_LOCKED - drone_lock_count()
	if free <= 0:
		return
	var count: int = mini(EG.DRONE_PAIR, free)
	var base: float = rng.randf() * TAU
	for i in range(count):
		var spread: float = 0.0 if count <= 1 else rng.randf_range(-0.26, 0.26)
		var bearing: float = base + spread
		var p := _drone_spawn_point(bearing)
		var aim: float = (ship.position + ship.vel * 0.3 - p).angle()
		spawn_drone(p, aim)
	if not drone_warned:
		drone_warned = true
		if hud != null and not player_hidden:
			hud.toast("高速自杀无人机来袭 · 脉冲可将其解体", EG.C_AMBER, 2.6)
		Audio.play("sfx_alarm", -8.0)

## 在屏幕边缘外生成，留出 160~360px 的预警距离；优先避开天体和修整区的
## 驱离圈。找不到理想点时退回到最远的屏幕外方向。
func _drone_spawn_point(bearing: float) -> Vector2:
	var rect: Rect2 = screen_rect()
	var center := rect.get_center()
	var half := rect.size * 0.5
	for i in range(12):
		var b: float = bearing if i == 0 else bearing + rng.randf_range(-0.6, 0.6)
		var dir := Vector2.RIGHT.rotated(b)
		var edge: float = minf(absf(half.x / maxf(absf(dir.x), 0.001)),
			absf(half.y / maxf(absf(dir.y), 0.001)))
		var p: Vector2 = center + dir * (edge + rng.randf_range(
			EG.DRONE_SPAWN_EDGE_MIN, EG.DRONE_SPAWN_EDGE_MAX))
		if galaxy.is_inside_any_body(p, EG.DRONE_RADIUS + 40.0):
			continue
		var blocked := false
		for z in zones:
			if z == null or not is_instance_valid(z) or not z.active:
				continue
			if p.distance_to(z.position) < z.clearance_radius() + EG.DRONE_ZONE_WARD + EG.DRONE_RADIUS:
				blocked = true
				break
		if not blocked:
			return p
	return center + Vector2.RIGHT.rotated(bearing) * (half.length() + EG.DRONE_SPAWN_EDGE_MAX)

func remove_drone(d, explode: bool = true) -> void:
	if d == null or not is_instance_valid(d) or d.dead:
		return
	var pos: Vector2 = d.position
	d.remove()
	drones.erase(d)
	if explode:
		Fx.explosion(fx_layer, pos, 0.3, false)
		Audio.play("sfx_explosion_small", -12.0)

# ---------------------------------------------------------------- combat

# ---------------------------------------------------------------- core mods

func has_mod(id: String) -> bool:
	return int(mods.get(id, 0)) > 0

func mod_stacks(id: String) -> int:
	return int(mods.get(id, 0))

func add_mod(id: String) -> void:
	if not Defs.MODS.has(id):
		return
	mods[id] = mini(EG.MOD_MAX_STACKS, int(mods.get(id, 0)) + 1)
	if id == "curvature_wake":
		_update_absorb()
	if hud != null:
		hud.toast("改装芯片：" + str(Defs.MODS[id]["name"]), Defs.mod_school_color(id), 2.4)
	Audio.play("sfx_upgrade", -6.0)

func all_mods_maxed() -> bool:
	for id in Defs.MOD_ORDER:
		if int(mods.get(id, 0)) < EG.MOD_MAX_STACKS:
			return false
	return true

func roll_mod(mod_rng: RandomNumberGenerator) -> String:
	var pool: Array = []
	for id in Defs.MOD_ORDER:
		if int(mods.get(id, 0)) < EG.MOD_MAX_STACKS:
			pool.append(id)
	if pool.is_empty():
		pool = Defs.MOD_ORDER.duplicate()
	return str(pool[mod_rng.randi_range(0, pool.size() - 1)])

func relativist_bonus(m) -> float:
	if not has_mod("relativist"):
		return 0.0
	var over: float = m.vel.length() - EG.MOD_RELATIVIST_BASE
	if over <= 0.0:
		return 0.0
	return floorf(over / EG.MOD_RELATIVIST_STEP) * EG.MOD_RELATIVIST_DMG

func meteor_knock_damage() -> float:
	return EG.MOD_METEOR_KNOCK_DAMAGE if has_mod("mass_driver") else EG.METEOR_KNOCK_DAMAGE

func recycle_reward() -> void:
	if not has_mod("recycle_reactor"):
		return
	for s in skills:
		s["cd"] = maxf(0.0, float(s["cd"]) - EG.MOD_RECYCLE_CD)
	ship.fuel = minf(ship.fuel_max, ship.fuel + EG.MOD_RECYCLE_FUEL)

func _update_absorb() -> void:
	var wake: bool = has_mod("curvature_wake") and ship.vel.length() >= EG.MOD_WAKE_SPEED
	absorb_radius = EG.MOD_WAKE_ABSORB if wake else EG.MATTER_ABSORB

func _nearest_enemy(pos: Vector2):
	var best = null
	var bd := 1e20
	for e in enemies:
		if e.dead:
			continue
		var d: float = pos.distance_squared_to(e.position)
		if d < bd:
			bd = d
			best = e
	return best

## 连锁殉爆：过热时把周围导弹全部脱锁并吸向该敌人。
func _chain_detonate(e: Enemy) -> void:
	for m in missiles:
		if m.dead or m.position.distance_to(e.position) > EG.MOD_CHAIN_RADIUS:
			continue
		m.unlock()
		m.chain = e

## 共振奇点：引力锚与诱饵信标重叠时，区内导弹提速 60% 并刷新寿命。
func _resonance_tick() -> void:
	var zones: Array = []
	for a in anchors:
		if a == null or a.dead:
			continue
		for d in decoys:
			if d == null or d.dead:
				continue
			if a.position.distance_to(d.position) <= a.radius:
				zones.append(a.position)
				break
	if zones.is_empty():
		return
	for m in missiles:
		if m.dead:
			continue
		for p in zones:
			if m.position.distance_to(p) <= EG.MOD_RESONANCE_RADIUS:
				m.speed = m.base_speed * EG.MOD_RESONANCE_SPEED
				m.life = 0.0
				if not m.is_locked() and m.vel.length() > 1.0:
					m.vel = m.vel.normalized() * m.speed
				break

## 把一簇导弹甩出去：toward_enemy 时朝最近敌人，否则沿切线（双极锚定）。
func _fling_missiles(pos: Vector2, radius: float, speed: float, toward_enemy: bool) -> void:
	var target = _nearest_enemy(pos)
	for m in missiles:
		if m.dead or m.position.distance_to(pos) > radius:
			continue
		var dir: Vector2
		if toward_enemy and target != null:
			dir = (target.position - m.position).normalized()
			m.chain = target
		else:
			dir = m.position - pos
			if dir.length() < 1.0:
				dir = Vector2.RIGHT
			dir = dir.normalized().orthogonal()
		m.speed = speed
		m.vel = dir * speed
		m.angle = dir.angle()
		m.unlock()
	Fx.warp(fx_layer, pos, Color(0.75, 0.55, 1.0, 0.75))

func _update_mods(delta: float) -> void:
	# 引力涡轮：环绕行星加速时把行星变成空中加油站。
	if has_mod("gravity_turbine") and orbit_assist:
		ship.fuel = minf(ship.fuel_max, ship.fuel + EG.MOD_TURBINE_FUEL * delta)
		ship.boost_meter = minf(ship.boost_cap,
			ship.boost_meter + ship.boost_cap * EG.MOD_TURBINE_BOOST * delta)
	free_boost_timer = maxf(0.0, free_boost_timer - delta)
	ship.boost_free = has_mod("battlefield_ready") and free_boost_timer > 0.0
	_update_absorb()
	if has_mod("resonance"):
		_resonance_tick()

## 敌方弹药梯度：深度 3 起开始混入二段加速弹，深层导弹巢会发射子母分裂弹。
func roll_enemy_ammo(kind: String, d: int) -> String:
	if d < 3:
		return "normal"
	if kind == "nest" and d >= 4 and rng.randf() < 0.35:
		return "cluster"
	if rng.randf() < minf(0.50, 0.10 * float(d - 2)):
		return "booster"
	return "normal"

func spawn_enemy_missile(enemy: Enemy, muzzle: Vector2, angle: float, ammo: String = "normal") -> Missile:
	var m := Missile.new()
	m.run = self
	m.kind = ammo
	m.position = muzzle
	m.angle = angle
	var spd := EG.MISSILE_SPEED
	match ammo:
		"booster":
			spd = EG.BOOSTER_SLOW_SPEED
		"cluster":
			spd = EG.MISSILE_SPEED
	m.speed = spd
	m.vel = Vector2.RIGHT.rotated(angle) * spd
	m.source = enemy
	world.add_child(m)
	missiles.append(m)
	Audio.play("sfx_launch", -8.0, rng.randf_range(0.94, 1.06))
	Fx.sparks(fx_layer, muzzle, Color(1.0, 0.55, 0.3, 0.8), 5, 90.0)
	return m

## 子母分裂弹的三枚微型无锁弹头。
func spawn_cluster_frag(pos: Vector2, angle: float, src) -> Missile:
	var m := Missile.new()
	m.run = self
	m.kind = "frag"
	m.position = pos
	m.angle = angle
	m.speed = EG.CLUSTER_FRAG_SPEED
	m.vel = Vector2.RIGHT.rotated(angle) * m.speed
	m.source = src
	m.locked = false
	m.seen = true
	world.add_child(m)
	missiles.append(m)
	Fx.sparks(fx_layer, pos, Color(1.0, 0.7, 0.35, 0.9), 8, 160.0)
	return m

## 水雷弹：超载殉爆与引力水雷共用。无锁、慢速，脉冲可以把它反推回敌人身上。
func spawn_mine(src, pos: Vector2, angle: float, speed: float = EG.MINE_SPEED) -> Missile:
	var m := Missile.new()
	m.run = self
	m.kind = "mine"
	m.position = pos
	m.angle = angle
	m.speed = speed
	m.dmg = EG.MINE_DMG_ENEMY
	m.vel = Vector2.RIGHT.rotated(angle) * speed
	m.source = src
	m.locked = false
	m.seen = true
	world.add_child(m)
	# _ready 会把速度按弹种设为默认 90，超载殉爆的 120 要在之后写回。
	m.speed = speed
	m.base_speed = speed
	missiles.append(m)
	Fx.sparks(fx_layer, pos, Color(0.8, 0.4, 1.0, 0.8), 5, 90.0)
	return m

func target_position(m) -> Vector2:
	if m.target == "decoy" and m.decoy != null and is_instance_valid(m.decoy):
		return m.decoy.position
	return ship.position

func locked_missile_count() -> int:
	var n := 0
	for m in missiles:
		# Sneak rounds fired from the dark have their own cap; they must not
		# starve the attacker's normal directed salvos.
		if not m.dead and m.is_locked() and not m.sneak:
			n += 1
	return n

func sneak_missile_count() -> int:
	var n := 0
	for m in missiles:
		if not m.dead and m.sneak:
			n += 1
	return n

func on_missile_unlock(m) -> void:
	stats.unlocks += 1
	Fx.sparks(fx_layer, m.position, Color(1.0, 0.6, 0.3, 0.5), 4, 60.0)
	# 近炸增幅：锁定中的导弹在 130px 内脱锁时，弹体伤害翻倍并回一点护盾。
	if has_mod("proximity_charge") and m.position.distance_to(ship.position) <= EG.MOD_PROXIMITY_RADIUS:
		m.dmg *= 2.0
		ship.heal(EG.MOD_PROXIMITY_HEAL)
		Fx.text(fx_layer, m.position + Vector2(0, -20), "近炸增幅", EG.C_MAGENTA, 16)
		Fx.sparks(fx_layer, m.position, Color(1.0, 0.45, 0.75, 0.9), 10, 140.0)
	# 惯性制导篡改：脱锁瞬间朝最近的主敌人微偏 12°（不重锁，仍吃引力）。
	if has_mod("inertia_hack"):
		var target = _nearest_enemy(m.position)
		if target != null:
			var want: float = (target.position - m.position).angle()
			var diff: float = wrapf(want - m.vel.angle(), -PI, PI)
			m.vel = m.vel.rotated(clampf(diff, -EG.MOD_INERTIA_ANGLE, EG.MOD_INERTIA_ANGLE))
			m.angle = m.vel.angle()

## 撞击伤害只看法线速度：正面撞上去才疼，贴着表面掠过几乎不掉血。
## 撞敌人 ×1.5；撞敌人和撞天体一样，单次最高 5。
func collision_damage(impact: float, enemy: bool) -> float:
	if impact <= EG.COLLISION_SPEED_MIN:
		return 0.0
	var t := clampf(inverse_lerp(EG.COLLISION_SPEED_MIN, EG.COLLISION_SPEED_MAX, impact), 0.0, 1.0)
	var dmg := lerpf(EG.COLLISION_DMG_MIN, EG.COLLISION_DMG_MAX, t)
	if enemy:
		dmg *= EG.COLLISION_ENEMY_MULT
	return minf(dmg, EG.COLLISION_DMG_MAX)

func _resolve_collisions() -> void:
	# Player vs celestial bodies / enemies: bounce + speed-based shield wear.
	for b in galaxy.bodies:
		if ship.position.distance_to(b.position) < b.radius + ship.R:
			var impact: float = ship.bounce_from(b.position, b.radius)
			var dmg := collision_damage(impact, false)
			if dmg > 0.0:
				hurt_ship(dmg, "体表")
				Fx.sparks(fx_layer, ship.position, Color(0.5, 0.85, 1.0, 0.8), 8, 120.0)
	for e in enemies:
		if e.dead:
			continue
		if ship.position.distance_to(e.position) < e.radius + ship.R:
			var impact2: float = ship.bounce_from(e.position, e.radius)
			var dmg2 := collision_damage(impact2, true)
			if dmg2 > 0.0:
				hurt_ship(dmg2, "外壳")
				Fx.sparks(fx_layer, ship.position, Color(1.0, 0.5, 0.35, 0.8), 8, 120.0)

	# 自杀无人机：撞玩家或敌人各 5 点伤害，撞击瞬间解体。
	for d in drones.duplicate():
		if d == null or not is_instance_valid(d) or d.dead:
			continue
		if d.position.distance_to(ship.position) < d.radius + ship.R:
			hurt_ship(EG.DRONE_DMG, "无人机")
			Fx.sparks(fx_layer, d.position, Color(1.0, 0.42, 0.82, 0.9), 8, 150.0)
			shake = maxf(shake, 0.3)
			remove_drone(d, true)
	for d in drones.duplicate():
		if d == null or not is_instance_valid(d) or d.dead:
			continue
		for e in enemies:
			if e.dead:
				continue
			if d.position.distance_to(e.position) < d.radius + e.radius:
				var drone_dmg: float = EG.MOD_TROJAN_DMG if d.hacked else EG.DRONE_DMG
				damage_enemy(e, drone_dmg, d.position, false)
				remove_drone(d, true)
				break

	# Meteors vs player / enemies.
	for met in meteors:
		if met.dead:
			continue
		if met.hit_cd <= 0.0 and met.position.distance_to(ship.position) < met.radius + ship.R + 2.0:
			hit_ship_by_meteor(met)
			continue
		for e in enemies:
			if e.dead:
				continue
			if met.position.distance_to(e.position) < e.radius + met.radius:
				var dmg3 := meteor_knock_damage() if met.knocked else EG.METEOR_DAMAGE
				remove_meteor(met, true)
				damage_enemy(e, dmg3, met.position, false)
				break

	# Missiles / frags / mines.
	for m in missiles.duplicate():
		if m.dead:
			continue
		var hit := false
		for e in enemies:
			if e.dead:
				continue
			if m.source == e and m.is_locked():
				continue
			if e.try_intercept(m):
				remove_missile(m, true)
				hit = true
				break
			if m.position.distance_to(e.position) < e.radius + EG.MISSILE_RADIUS:
				var dealt: float = float(m.dmg)
				if has_mod("relativist"):
					dealt += relativist_bonus(m)
				remove_missile(m, false)
				damage_enemy(e, dealt, m.position, true)
				recycle_reward()
				hit = true
				break
		if hit:
			continue
		for met in meteors:
			if met.dead:
				continue
			if m.position.distance_to(met.position) < met.radius + EG.MISSILE_RADIUS + 2.0:
				remove_missile(m, true)
				remove_meteor(met, true)
				if ship.position.distance_to(m.position) < 135.0:
					hurt_ship(2.0, "碎片")
				hit = true
				break
		if hit:
			continue
		if not player_hidden and m.position.distance_to(ship.position) < EG.MISSILE_RADIUS + ship.R + 2.0:
			remove_missile(m, true)
			if m.kind == "mine":
				hurt_ship(EG.MINE_DMG_SHIP, "水雷")
			else:
				hurt_ship(EG.MISSILE_DMG_SHIP, "导弹")
			continue
		for b in galaxy.bodies:
			if m.position.distance_to(b.position) < b.radius + EG.MISSILE_RADIUS:
				remove_missile(m, true)
				recycle_reward()
				break

func hit_ship_by_meteor(met: Meteor) -> void:
	var away: Vector2 = (met.position - ship.position)
	if away.length() < 1.0:
		away = ship.vel if ship.vel.length() > 1.0 else Vector2.RIGHT.rotated(rng.randf() * TAU)
	var knock_speed := 210.0
	# 曲率尾流：高速时把陨石撞飞的速度翻倍。
	if has_mod("curvature_wake") and ship.vel.length() >= EG.MOD_WAKE_SPEED:
		knock_speed = 420.0
	met.knock(away + ship.vel * 0.7, knock_speed)
	met.position = ship.position + away.normalized() * (met.radius + ship.R + 4.0)
	met.hit_cd = 0.7
	# 引力碎星带：撞击陨石不再掉护盾、也不减速，玩家变成一根太空台球杆。
	if not has_mod("gravity_belt"):
		ship.vel *= 0.82
		hurt_ship(EG.METEOR_DAMAGE, "陨石")
	shake = maxf(shake, 0.25)

func damage_enemy(e: Enemy, amount: float, pos: Vector2, big_fx: bool) -> void:
	if e.dead:
		return
	var res: Dictionary = e.apply_hit(amount, pos)
	var dealt: float = float(res.get("damage", amount))
	stats.damage += dealt
	stats.hits += 1
	Fx.explosion(fx_layer, pos, 0.55 if big_fx else 0.42, false)
	Fx.text(fx_layer, pos, "%d" % roundi(dealt), Color(1.0, 0.78, 0.55), 24)
	if bool(res.get("crit", false)):
		Fx.text(fx_layer, pos + Vector2(0, -30), "舰尾暴击", EG.C_AMBER, 18)
		Fx.warp(fx_layer, pos, Color(1.0, 0.7, 0.35, 0.7))
	elif bool(res.get("blocked_front", false)):
		Fx.text(fx_layer, pos + Vector2(0, -26), "护盾削减", EG.C_CYAN, 15)
		Fx.sparks(fx_layer, pos, Color(0.5, 0.9, 1.0, 0.9), 10, 130.0)
	shake = maxf(shake, 0.45)
	if hud != null:
		hud.flash(Color(1.0, 0.75, 0.4, 0.22), 0.12)
	Audio.play("sfx_missile_hit", -3.0)
	if bool(res.get("overheated", false)) and e.hp > 0.0:
		# 超载殉爆：每次过热的瞬间向四周抛射水雷弹。
		if e.affix == "volatile":
			e.scatter_mines()
		if has_mod("chain_detonation"):
			_chain_detonate(e)
	if e.hp <= 0.0:
		kill_enemy(e)

func kill_enemy(e: Enemy) -> void:
	if e.dead:
		return
	var pos := e.position
	var partner: Enemy = e.twin
	e.remove()
	enemies.erase(e)
	e.twin = null
	shake = maxf(shake, 1.2)
	Fx.explosion(fx_layer, pos, 3.0, true)
	Fx.explosion(fx_layer, pos, 2.0, true)
	Fx.warp(fx_layer, pos, Color(1.0, 0.6, 0.4, 0.8))
	Audio.play("sfx_explosion_big", -2.0)
	if hud != null:
		hud.flash(Color(1.0, 0.85, 0.6, 0.3), 0.25)
	if current_enemy == e:
		current_enemy = null
	# 双子中继站：一座倒下后另一座失去联动并暴走，遭遇战要打到两座都倒下。
	if partner != null and is_instance_valid(partner) and not partner.dead:
		partner.twin = null
		partner.twin_leader = false
		partner.pair_center = partner.position
		partner.heal_delay = 0.0
		partner.heal_left = 0.0
		partner.speed_in *= 1.4
		partner.speed_out *= 1.2
		partner.fire_in = maxf(0.6, partner.fire_in * 0.8)
		partner.fire_out = maxf(1.2, partner.fire_out * 0.85)
		partner.elite = true
		if current_enemy == null:
			current_enemy = partner
		if hud != null:
			hud.toast("一座中继站被摧毁 · 另一座失去联动并开始暴走", EG.C_MAGENTA, 2.4)
	if current_enemy == null and enemies.size() > 0:
		current_enemy = enemies[0]
	if current_enemy != null:
		# 本场遭遇战还没结束：不推进深度、不刷新修整区。
		return
	scatter_matter_at(pos, 42, 460.0)
	kills += 1
	if rng.randf() < 0.25 or e.in_view or e.elite:
		tokens = mini(EG.MAX_TOKENS, tokens + 1)
		Fx.text(fx_layer, pos + Vector2(0, -60), "+1 代币", EG.C_MAGENTA, 20)
	depth += 1
	_refresh_rest_zones()
	safe_timer = EG.DEPTH_SAFE_TIME
	next_enemy_timer = EG.DEPTH_SAFE_TIME
	if hud != null:
		hud.toast("威胁解除 · 修整区已刷新 · 安全时间 %d 秒" % int(EG.DEPTH_SAFE_TIME), EG.C_MINT, 2.4)
		hud.set_safe_countdown(EG.DEPTH_SAFE_TIME)
	Audio.play("sfx_upgrade", -6.0)

## 战斗区清空后，修整区按路线顺序立即刷新：先安全区，再商店。刷新不再
## 有倒计时，只有击败敌人才会触发；玩家正停靠在某个修整区里时，不能把
## 它从脚下抽走，先把刷新挂起，离开时立刻补上。
func _refresh_rest_zones() -> void:
	var safe_in_use: bool = safe_zone != null and is_instance_valid(safe_zone) and safe_zone.entered
	if safe_zone != null and is_instance_valid(safe_zone) and not safe_in_use:
		safe_zone.remove()
		safe_zone = null
	if safe_in_use:
		pending_safe_refresh = true
	else:
		_spawn_safe_respawn()
	var shop_in_use: bool = shop_zone != null and is_instance_valid(shop_zone) and (shop_inside or state == State.SHOP)
	if shop_zone != null and is_instance_valid(shop_zone) and not shop_in_use:
		shop_zone.remove()
		shop_zone = null
	if shop_in_use:
		pending_shop_refresh = true
	else:
		_spawn_shop_respawn()

func remove_missile(m, explode: bool) -> void:
	if m.dead:
		return
	if explode:
		Fx.explosion(fx_layer, m.position, 0.35, false)
		Audio.play("sfx_explosion_small", -10.0)
	m.remove()
	missiles.erase(m)

func remove_meteor(met, fx: bool) -> void:
	if met.dead:
		return
	if fx:
		Fx.explosion(fx_layer, met.position, 0.32, false)
		Audio.play("sfx_meteor", -12.0)
	met.remove()
	meteors.erase(met)

func hurt_ship(amount: float, source: String = "") -> void:
	if state != State.PLAYING or player_hidden:
		return
	last_damage_source = source
	if ship.invuln > 0.0:
		return
	var dead := ship.take_damage(amount)
	shake = maxf(shake, 0.5)
	if hud != null:
		hud.flash(Color(1.0, 0.25, 0.35, 0.4), 0.2)
	Audio.play("sfx_hit", -4.0)
	Fx.text(fx_layer, ship.position + Vector2(0, -26), "-%d" % roundi(amount), Color(1.0, 0.4, 0.45), 20)
	if dead:
		_try_revive_or_die()

func _try_revive_or_die() -> void:
	var idx := inventory.find("revive")
	if idx >= 0:
		inventory.remove_at(idx)
		ship.shield = 8.0
		ship.invuln = 2.5
		player_hidden = false
		selected_item = clampi(selected_item, 0, maxi(0, inventory.size() - 1))
		Fx.warp(fx_layer, ship.position, Color(0.7, 0.9, 1.0, 0.9))
		Audio.play("sfx_upgrade", -2.0)
		if hud != null:
			hud.toast("复活币生效 · 护盾 8", EG.C_MINT, 2.5)
		return
	die("护盾击穿")

func die(reason: String) -> void:
	if state == State.DEAD:
		return
	state = State.DEAD
	ship.dead = true
	ship.visible = false
	Fx.explosion(fx_layer, ship.position, 2.2, true)
	Fx.explosion(fx_layer, ship.position, 1.4, true)
	shake = 1.6
	Audio.play("sfx_explosion_big", 0.0)
	Audio.fade_music(-22.0, 0.5)
	Audio.play("sfx_gameover", -2.0)
	Audio.loop_sfx("sfx_thrust", false)
	if not test_mode:
		Store.record_run(depth, level, kills, run_time)
	if hud != null:
		hud.show_gameover(get_summary(reason))

func get_summary(reason: String) -> Dictionary:
	return {
		"reason": reason,
		"depth": depth,
		"kills": kills,
		"level": level,
		"time": run_time,
		"tokens": tokens,
		"matter": stats["matter"],
		"hits": stats["hits"],
		"best_depth": Store.best_depth,
	}

# ---------------------------------------------------------------- matter / xp

func on_matter_collected(m: Matter) -> void:
	stats["matter"] += 1
	xp += float(m.xp)
	Audio.play("sfx_pickup", -18.0, rng.randf_range(0.94, 1.1))
	var pile := _matter_pickup_count()
	if pile % 4 == 0:
		Fx.pickup(fx_layer, m.position, Color(0.5, 1.0, 0.95, 0.9))
	var gained := false
	while xp >= EG.XP_PER_LEVEL:
		xp -= EG.XP_PER_LEVEL
		level += 1
		pending_levels += 1
		gained = true
	if not gained:
		return
	# 升级只在安全区内进行：游玩途中不打断节奏，先攒着。
	if player_hidden and state == State.PLAYING:
		begin_levelup()
	elif hud != null:
		hud.toast("等级提升 · 进入安全区后可升级", EG.C_VIOLET, 2.2)

func _matter_pickup_count() -> int:
	return int(stats["matter"])

# ---------------------------------------------------------------- items

func add_item(id: String) -> bool:
	if inventory.size() < item_slots:
		inventory.append(id)
		if hud != null:
			hud.toast("获得 " + Defs.ITEMS[id]["name"], Defs.item_rarity_color(id), 2.2)
		Audio.play("sfx_token", -8.0)
		return true
	_pending_item = id
	state = State.DESTROY
	if hud != null:
		hud.show_destroy(inventory, id)
	return false

func destroy_and_take(index: int) -> void:
	if index < 0 or index >= inventory.size():
		state = State.PLAYING
		if hud != null:
			hud.hide_destroy()
		return
	inventory.remove_at(index)
	inventory.append(_pending_item)
	if hud != null:
		hud.hide_destroy()
		hud.toast("已丢弃并放入 " + Defs.ITEMS[_pending_item]["name"], EG.C_CYAN, 2.0)
	_pending_item = ""
	if shop_inside:
		# 商店里买满包 → 丢弃替换后回到商店面板，而不是把玩家晾在空场。
		state = State.SHOP
		shop_open = true
		if hud != null:
			hud.show_shop(shop_stock, tokens)
		return
	if pending_levels > 0:
		begin_levelup()
	else:
		state = State.PLAYING

func select_item_slot(index: int) -> void:
	if inventory.size() == 0:
		return
	selected_item = clampi(index, 0, inventory.size() - 1)
	Audio.play("sfx_ui_click", -14.0, 1.1)

func use_item_slot(index: int) -> void:
	if state != State.PLAYING or index < 0 or index >= inventory.size():
		return
	var id: String = inventory[index]
	if id == "revive":
		if hud != null:
			hud.toast("复活币是被动道具：护盾归零时自动生效", EG.C_AMBER, 2.4)
		return
	match id:
		"fuel":
			ship.fuel = minf(ship.fuel_max, ship.fuel + 60.0)
			stats["fuel_items"] += 1
			Fx.text(fx_layer, ship.position + Vector2(0, -34), "+60 燃料", EG.C_MINT, 20)
		"repair":
			ship.heal(6.0)
			Fx.text(fx_layer, ship.position + Vector2(0, -34), "+6 护盾", EG.C_CYAN, 20)
		"charge":
			ship.boost_full()
			Fx.text(fx_layer, ship.position + Vector2(0, -34), "加力槽已满", EG.C_AMBER, 20)
		"flare":
			_use_flare()
		"decoy":
			_drop_decoy(ship.position + Vector2.RIGHT.rotated(ship.facing) * 150.0, ship.vel * 0.4, 7.0)
			Fx.warp(fx_layer, ship.position, Color(1.0, 0.4, 0.8, 0.7))
		"mine":
			_spawn_gravity_mine()
	inventory.remove_at(index)
	selected_item = clampi(selected_item, 0, maxi(0, inventory.size() - 1))
	Audio.play("sfx_token", -6.0)
	if has_mod("battlefield_ready"):
		free_boost_timer = EG.MOD_READY_TIME
	if hud != null:
		hud.toast("使用 " + Defs.ITEMS[id]["name"], EG.C_TEXT, 1.6)

func _use_flare() -> void:
	var behind := Vector2.RIGHT.rotated(ship.facing + PI)
	var n := 0
	for m in missiles:
		if m.dead or not m.is_locked():
			continue
		if m.position.distance_to(ship.position) > 560.0:
			continue
		var side := 1.0 if n % 2 == 0 else -1.0
		var dir := behind.rotated(side * deg_to_rad(32.0))
		m.vel = dir * 280.0
		m.angle = m.vel.angle()
		m.unlock()
		n += 1
	Fx.warp(fx_layer, ship.position, Color(1.0, 0.85, 0.4, 0.8))
	Fx.sparks(fx_layer, ship.position + behind * 30.0, Color(1.0, 0.8, 0.4, 0.9), 14, 220.0)
	Audio.play("sfx_pulse", -6.0)

func _spawn_gravity_mine() -> void:
	var a := GravityAnchor.new()
	a.run = self
	a.radius = 360.0
	a.duration = 3.5
	a.force = EG.ANCHOR_FORCE
	a.fling = true
	a.position = ship.position
	world.add_child(a)
	anchors.append(a)
	Fx.warp(fx_layer, a.position, Color(0.7, 0.45, 1.0, 0.9))
	Audio.play("sfx_gravity", -4.0)

## 引力锚 / 引力水雷消失时的收尾：双极锚定沿切线甩出，水雷朝最近敌人齐射。
func on_anchor_gone(a) -> void:
	if a == null:
		return
	if a.bipolar:
		_fling_missiles(a.position, a.radius, 340.0, false)
	if a.fling:
		_fling_missiles(a.position, a.radius + 80.0, EG.MOD_RESONANCE_FLING, true)

func _drop_decoy(pos: Vector2, vel: Vector2, life: float) -> Decoy:
	var d := Decoy.new()
	d.run = self
	d.life = life
	d.position = pos
	d.vel = vel
	world.add_child(d)
	decoys.append(d)
	for m in missiles:
		if not m.dead and m.is_locked() and m.position.distance_to(pos) < EG.DECOY_RADIUS:
			m.retarget_to(d)
	Audio.play("sfx_token", -12.0, 0.8)
	return d

func on_decoy_gone(d: Decoy, explode: bool) -> void:
	decoys.erase(d)
	for m in missiles:
		if not m.dead and m.decoy == d:
			m.decoy = null
			m.target = "ship"
			m.unlock()
	if explode:
		Fx.explosion(fx_layer, d.position, 0.45, false)
	# 共振奇点：信标结束时把攒成一团的导弹朝最近敌人齐射甩出。
	if has_mod("resonance"):
		_fling_missiles(d.position, EG.MOD_RESONANCE_RADIUS, EG.MOD_RESONANCE_FLING, true)

func _apply_decoy_orders() -> void:
	for m in missiles:
		if m.dead or m.target != "decoy" or m.decoy == null or not is_instance_valid(m.decoy):
			continue
		if m.position.distance_to(m.decoy.position) < 44.0:
			m.unlock()

# ---------------------------------------------------------------- skills

func skill_by_slot(slot: int):
	if slot < 0 or slot >= skills.size():
		return null
	return skills[slot]

func cast_skill(slot: int) -> void:
	if state != State.PLAYING or paused:
		return
	var s = skill_by_slot(slot)
	if s == null:
		return
	if float(s["cd"]) > 0.0:
		Audio.play("sfx_ui_click", -16.0, 0.7)
		return
	var data: Dictionary = Defs.SKILLS[s["id"]]
	var cost: float = float(data["fuel"]) * eco_cruise
	if ship.fuel < cost:
		if hud != null:
			hud.toast("燃料不足，无法释放" + str(data["name"]), EG.C_AMBER, 1.8)
		Audio.play("sfx_ui_click", -14.0, 0.6)
		return
	ship.fuel -= cost
	s["cd"] = float(data["cd"])
	var lv := int(s["level"])
	match s["id"]:
		"pulse":
			_cast_pulse(lv)
		"anchor":
			_cast_anchor(lv)
		"dash":
			_cast_dash(lv)
		"beacon":
			_cast_beacon(lv)

func skill_awaken(id: String) -> String:
	for s in skills:
		if s["id"] == id:
			return str(s.get("awaken", ""))
	return ""

func _cast_pulse(lv: int) -> void:
	var awake := skill_awaken("pulse")
	var radius := EG.PULSE_RADIUS * (1.0 + 0.15 * float(lv - 1))
	var impulse := EG.PULSE_IMPULSE * (1.0 + 0.15 * float(lv - 1))
	if awake == "pulse_stasis":
		radius = EG.PULSE_STASIS_RADIUS
	if awake == "pulse_fan":
		# 聚能扇面：不再向两侧平分推开，而是统一推向飞船机头正前方。
		var fwd := Vector2.RIGHT.rotated(ship.facing)
		for m in missiles.duplicate():
			if m.dead:
				continue
			if m.position.distance_to(ship.position) > radius:
				continue
			var spread: float = deg_to_rad(rng.randf_range(-EG.PULSE_SPREAD, EG.PULSE_SPREAD))
			var dir: Vector2 = fwd.rotated(spread)
			m.vel = dir * impulse
			m.angle = dir.angle()
			m.unlock()
	else:
		# 偏转分界线 = 玩家的移动方向（速度方向）；静止时退回面向。
		var travel: Vector2 = ship.vel
		if travel.length() < 20.0:
			travel = Vector2.RIGHT.rotated(ship.facing)
		var line_dir := travel.normalized()
		var left_dir := line_dir.orthogonal()
		for m in missiles.duplicate():
			if m.dead:
				continue
			var d: Vector2 = m.position - ship.position
			if d.length() > radius:
				continue
			var radial: Vector2 = d.normalized()
			var tangent: Vector2 = radial.orthogonal()
			var side: float = line_dir.cross(radial)
			if absf(side) < 0.06:
				side = line_dir.cross(m.vel)
				if absf(side) < 0.001:
					side = -1.0 if rng.randf() < 0.5 else 1.0
			var want: Vector2 = left_dir * (-signf(side))
			if tangent.dot(want) < 0.0:
				tangent = -tangent
			tangent = tangent.rotated(deg_to_rad(rng.randf_range(-EG.PULSE_SPREAD, EG.PULSE_SPREAD)))
			m.vel = tangent * impulse
			m.angle = tangent.angle()
			m.unlock()
	# 零点静滞：脉冲波及敌人本体时打断齐射并延长过热。
	if awake == "pulse_stasis":
		for e in enemies:
			if e.dead:
				continue
			if e.position.distance_to(ship.position) <= radius + e.radius:
				e.stasis(EG.PULSE_STASIS_OVERHEAT)
	# 质量投射器：脉冲也能把范围内的陨石高速轰飞。
	if has_mod("mass_driver"):
		for met in meteors:
			if met.dead:
				continue
			var dmet: Vector2 = met.position - ship.position
			if dmet.length() > radius:
				continue
			var dir2: Vector2 = dmet.normalized() if dmet.length() > 1.0 else Vector2.RIGHT
			met.knock(dir2, EG.MOD_MASS_DRIVER_KNOCK)
	# 木马协议：无人机被反向骇入，撞向主敌人；否则原地解体。
	for d in drones.duplicate():
		if d == null or not is_instance_valid(d) or d.dead:
			continue
		if d.position.distance_to(ship.position) <= radius:
			if has_mod("trojan"):
				_hack_drone(d)
			else:
				remove_drone(d, true)
	Fx.warp(fx_layer, ship.position, Color(0.5, 0.95, 1.0, 0.9))
	var wave := Assets.world_sprite("shockwave", true)
	wave.position = ship.position
	wave.z_index = 32
	wave.scale = Vector2.ONE * (radius / 256.0 * 0.25)
	wave.modulate = Color(0.5, 0.95, 1.0, 0.85)
	world.add_child(wave)
	var tw := wave.create_tween()
	tw.set_parallel(true)
	tw.tween_property(wave, "scale", Vector2.ONE * (radius / 256.0), 0.4)
	tw.tween_property(wave, "modulate:a", 0.0, 0.45)
	tw.chain().tween_callback(wave.queue_free)
	shake = maxf(shake, 0.4)
	Audio.play("sfx_pulse", -3.0)

func _hack_drone(d) -> void:
	var target = _nearest_enemy(d.position)
	if target == null:
		remove_drone(d, true)
		return
	d.hacked = true
	d.locked = false
	d.speed = EG.MOD_TROJAN_SPEED
	d.vel = (target.position - d.position).normalized() * d.speed
	Fx.warp(fx_layer, d.position, Color(1.0, 0.45, 0.8, 0.8))
	Fx.text(fx_layer, d.position, "木马协议", EG.C_MAGENTA, 16)
	Audio.play("sfx_dash", -10.0)

func _cast_anchor(lv: int) -> void:
	var a := GravityAnchor.new()
	a.run = self
	a.radius = EG.ANCHOR_RADIUS * (1.0 + 0.19 * float(lv - 1))
	a.duration = EG.ANCHOR_DURATION + float(lv - 1)
	a.force = EG.ANCHOR_FORCE
	a.bipolar = skill_awaken("anchor") == "anchor_bipolar"
	a.position = ship.position + Vector2.RIGHT.rotated(ship.facing) * 170.0
	world.add_child(a)
	anchors.append(a)
	Fx.warp(fx_layer, a.position, Color(0.65, 0.45, 1.0, 0.9))
	Audio.play("sfx_gravity", -4.0)
	shake = maxf(shake, 0.3)

func _cast_dash(lv: int) -> void:
	var dir := _read_dir()
	if dir.length() < 0.1:
		dir = Vector2.RIGHT.rotated(ship.facing)
	var speed := EG.DASH_SPEED * (1.0 + 0.16 * float(lv - 1))
	var time := EG.DASH_TIME * (1.0 + 0.18 * float(lv - 1))
	var origin: Vector2 = ship.position
	ship.dash(dir, speed, time)
	Fx.sparks(fx_layer, ship.position, Color(0.5, 1.0, 0.85, 0.9), 12, 220.0)
	Fx.warp(fx_layer, ship.position, Color(0.45, 1.0, 0.8, 0.7))
	# 残影诱饵：冲刺起点留下一枚持续 3 秒的微型诱饵信标。
	if skill_awaken("dash") == "dash_afterimage":
		var d := _drop_decoy(origin, Vector2.ZERO, EG.DASH_AFTERIMAGE_LIFE)
		d.scale = Vector2.ONE * 0.7
	Audio.play("sfx_dash", -4.0)
	shake = maxf(shake, 0.25)

func _cast_beacon(lv: int) -> void:
	var life := 6.0 + 2.0 * float(lv - 1)
	if skill_awaken("beacon") == "beacon_mirror":
		# 镜像双生：机身前后各投一枚。
		var half := life * EG.BEACON_MIRROR_LIFE
		var front := _drop_decoy(ship.position + Vector2.RIGHT.rotated(ship.facing) * 140.0, ship.vel * 0.2, half)
		front.modulate = Color(1.0, 0.8, 0.95)
		var back := _drop_decoy(ship.position - Vector2.RIGHT.rotated(ship.facing) * 140.0, ship.vel * 0.2, half)
		back.modulate = Color(0.95, 0.75, 1.0)
		Fx.warp(fx_layer, back.position, Color(1.0, 0.4, 0.8, 0.7))
	else:
		var d := _drop_decoy(ship.position + Vector2.RIGHT.rotated(ship.facing) * 140.0, ship.vel * 0.2, life)
		d.modulate = Color(1.0, 0.8, 0.95)
		Fx.warp(fx_layer, d.position, Color(1.0, 0.4, 0.8, 0.7))
	Audio.play("sfx_gravity", -6.0, 1.2)

func unowned_skills() -> Array:
	var out: Array = []
	for id in Defs.SKILL_ORDER:
		var has := false
		for s in skills:
			if s["id"] == id:
				has = true
				break
		if not has:
			out.append(id)
	return out

func upgradable_skills() -> Array:
	var out: Array = []
	for s in skills:
		if int(s["level"]) < 3:
			out.append(s["id"])
	return out

# ---------------------------------------------------------------- upgrades

func begin_levelup() -> void:
	if state == State.DEAD:
		return
	state = State.LEVELUP
	upgrade_cards = Defs.roll_upgrades(self, rng)
	if hud != null:
		hud.show_levelup(upgrade_cards)
	Audio.play("sfx_upgrade", -4.0)

func choose_upgrade(index: int) -> void:
	if state != State.LEVELUP or index < 0 or index >= upgrade_cards.size():
		return
	var card: Dictionary = upgrade_cards[index]
	# 技能槽满时也能选新技能：先进入“双槽对比替换”流程，替换后继承一半等级。
	if card["id"] == "skill_new" and bool(card.get("replace", false)):
		_pending_skill = str(card["skill_id"])
		upgrade_cards = []
		pending_levels = maxi(0, pending_levels - 1)
		state = State.REPLACE_SKILL
		if hud != null:
			hud.hide_levelup()
			hud.show_skill_replace(skills, _pending_skill)
		return
	_apply_upgrade(card)
	upgrade_cards = []
	pending_levels = maxi(0, pending_levels - 1)
	if state == State.DESTROY:
		# 升级卡给的道具撑满物品栏：add_item 已经把面板换成“丢弃一件”，
		# 这里再关一次会把销毁面板清空，玩家就只剩键盘可选了。
		return
	if hud != null:
		hud.hide_levelup()
	_resume_play()

## 技能替换：选中的槽位被新技能占用，并按原等级的一半继承。
func choose_skill_replace(index: int) -> void:
	if state != State.REPLACE_SKILL:
		return
	if index < 0 or index >= skills.size() or _pending_skill == "":
		cancel_skill_replace()
		return
	var old_lv := int(skills[index]["level"])
	var new_lv := maxi(1, int(floor(float(old_lv) * 0.5)))
	var old_name: String = str(Defs.SKILLS[skills[index]["id"]]["name"])
	var new_name: String = str(Defs.SKILLS[_pending_skill]["name"])
	skills[index] = {"id": _pending_skill, "level": new_lv, "cd": 0.0}
	_pending_skill = ""
	if hud != null:
		hud.hide_skill_replace()
		hud.toast("以 %s 替换 %s · 继承 Lv%d" % [new_name, old_name, new_lv], EG.C_CYAN, 2.4)
	state = State.PLAYING
	_resume_play()
	Audio.play("sfx_upgrade", -8.0)

## 取消替换不该白丢一次升级：把这次等级还回去并重新开一轮（等于重摇）。
func cancel_skill_replace() -> void:
	if state != State.REPLACE_SKILL:
		return
	_pending_skill = ""
	pending_levels += 1
	if hud != null:
		hud.hide_skill_replace()
	state = State.PLAYING
	_resume_play()

func _resume_play() -> void:
	if state == State.DEAD or state == State.DESTROY:
		return
	if pending_levels > 0:
		begin_levelup()
	elif player_hidden and safe_zone != null and safe_zone.entered:
		state = State.PLAYING
		if hud != null:
			hud.clear_overlay()
	else:
		state = State.PLAYING

func _apply_upgrade(card: Dictionary) -> void:
	match card["id"]:
		"repair_25":
			ship.heal(ship.shield_max * 0.25)
		"repair_full":
			ship.shield = ship.shield_max
		"eco_cruise":
			# 节能巡航取代“恢复 25% 燃料”：进站必满油，燃料卡是废卡；
			# 油耗折扣才是真正和 500 基础池挂钩的续航强化。
			eco_cruise = maxf(EG.ECO_CRUISE_MIN, eco_cruise * EG.ECO_CRUISE_MULT)
			ship.fuel_cost_mult = eco_cruise
		"fuel_max_10":
			ship.fuel_max += EG.FUEL_MAX_CARD_A
			ship.fuel = ship.fuel_max
		"fuel_max_20":
			ship.fuel_max += EG.FUEL_MAX_CARD_B
			ship.fuel = ship.fuel_max
		"slot":
			item_slots = mini(EG.ITEM_SLOTS_MAX, item_slots + 1)
		"token_1":
			tokens = mini(EG.MAX_TOKENS, tokens + 1)
		"token_2":
			tokens = mini(EG.MAX_TOKENS, tokens + 2)
		"token_3":
			tokens = mini(EG.MAX_TOKENS, tokens + 3)
		"boost_cap":
			ship.boost_cap *= 1.1
			ship.boost_meter = ship.boost_cap
			ship.boost_ready = true
		"boost_power":
			ship.boost_mult *= 1.07
		"item":
			add_item(card.get("item_id", "fuel"))
		"mod_card":
			add_mod(str(card.get("mod_id", "gravity_turbine")))
		"skill_awaken":
			_apply_awaken(str(card.get("skill_id", "pulse")), str(card.get("awaken", "")))
		"skill_new":
			skills.append({"id": card["skill_id"], "level": 1, "cd": 0.0})
		"skill_up":
			for s in skills:
				if s["id"] == card["skill_id"]:
					s["level"] = mini(3, int(s["level"]) + 1)
					break
	Audio.play("sfx_upgrade", -8.0)

func _apply_awaken(skill_id: String, awaken: String) -> void:
	if awaken == "" or not Defs.AWAKENINGS.has(awaken):
		return
	for s in skills:
		if s["id"] == skill_id:
			s["awaken"] = awaken
			s["level"] = 4
			break
	if hud != null:
		hud.toast("超载觉醒：" + str(Defs.AWAKENINGS[awaken]["name"]), EG.C_AMBER, 2.6)

func awakenable_skills() -> Array:
	var out: Array = []
	for s in skills:
		if int(s["level"]) < 3 or str(s.get("awaken", "")) != "":
			continue
		for aid in Defs.AWAKEN_ORDER:
			if str(Defs.AWAKENINGS[aid]["skill"]) == str(s["id"]):
				out.append({"skill": str(s["id"]), "awaken": aid})
	return out

# ---------------------------------------------------------------- zones

func _zone_checks() -> void:
	if safe_zone != null and safe_zone.active:
		if not safe_zone.entered and safe_zone.inside(ship.position):
			_enter_safe()
		elif safe_zone.entered and not safe_zone.inside(ship.position):
			_leave_safe()
	if shop_zone != null and shop_zone.active:
		if not shop_open and not shop_inside and shop_zone.inside(ship.position):
			_open_shop()
		if shop_inside and not shop_zone.inside(ship.position):
			_leave_shop()

func _enter_safe() -> void:
	safe_zone.entered = true
	safe_zone.set_entered(true)
	player_hidden = true
	ship.fuel = ship.fuel_max
	for m in missiles.duplicate():
		if not m.dead:
			Fx.sparks(fx_layer, m.position, Color(0.5, 1.0, 0.9, 0.7), 4, 70.0)
			m.remove()
	missiles.clear()
	for met in meteors.duplicate():
		remove_meteor(met, false)
	meteors.clear()
	Audio.play("sfx_safezone", -3.0)
	if hud != null:
		hud.toast("进入安全区 · 燃料已补满", EG.C_MINT, 2.6)
		hud.set_info_hidden(true)
		hud.set_safe_mode(true)
	# 安全区是唯一的升级点：把游玩中攒下的次数在这里一次开出来。
	if pending_levels > 0 and state == State.PLAYING:
		begin_levelup()

func _leave_safe() -> void:
	player_hidden = false
	var z := safe_zone
	safe_zone = null
	z.remove()
	Audio.play("sfx_ui_click", -10.0)
	if hud != null:
		hud.toast("离开安全区 · 击败敌人后刷新下一个", EG.C_AMBER, 2.2)
		hud.set_info_hidden(false)
		hud.set_safe_mode(false)
	# 安全区里击败过敌人：刷新被挂起，离开的同一帧补上新的安全区。
	if pending_safe_refresh:
		_spawn_safe_respawn()

func _open_shop() -> void:
	shop_open = true
	shop_inside = true
	state = State.SHOP
	shop_stock = _roll_shop()
	if hud != null:
		hud.show_shop(shop_stock, tokens)
	Audio.play("sfx_safezone", -6.0)

func _leave_shop() -> void:
	shop_inside = false
	if shop_open:
		shop_open = false
		if state == State.SHOP:
			state = State.PLAYING
		if hud != null:
			hud.hide_shop()
	var z := shop_zone
	shop_zone = null
	if z != null:
		z.remove()
	# 在商店范围内击败过敌人：刷新被挂起，离开的同一帧补上新的信标。
	if pending_shop_refresh:
		_spawn_shop_respawn()

func close_shop() -> void:
	if state != State.SHOP:
		return
	shop_open = false
	state = State.PLAYING
	shop_inside = true
	if hud != null:
		hud.hide_shop()
	Audio.play("sfx_ui_click", -6.0)

## 商店固定三货架：1 补给位（1~2）/ 2 战术道具位（3~4）/ 3 黑市改装位（5~7）。
func _roll_shop() -> Array:
	var stock: Array = []
	var sup := ["repair", "fuel", "service_repair"]
	stock.append(_item_offer(str(sup[rng.randi_range(0, sup.size() - 1)]), "补给位",
		rng.randi_range(EG.SHOP_SHELF_MIN[0], EG.SHOP_SHELF_MAX[0])))
	var tac := ["flare", "decoy", "charge", "mine", "service_full_boost"]
	stock.append(_item_offer(str(tac[rng.randi_range(0, tac.size() - 1)]), "战术道具位",
		rng.randi_range(EG.SHOP_SHELF_MIN[1], EG.SHOP_SHELF_MAX[1])))
	var price3 := rng.randi_range(EG.SHOP_SHELF_MIN[2], EG.SHOP_SHELF_MAX[2])
	if awakenable_skills().size() > 0 and rng.randf() < 0.45:
		var pick: Array = awakenable_skills()
		var entry: Dictionary = pick[rng.randi_range(0, pick.size() - 1)]
		var aw: Dictionary = Defs.AWAKENINGS[entry["awaken"]]
		stock.append({
			"kind": "awaken", "id": entry["awaken"], "skill_id": entry["skill"],
			"title": "觉醒：" + str(aw["name"]), "desc": str(aw["desc"]),
			"rarity": str(aw["rarity"]), "icon": "icon_awaken",
			"shelf": "黑市改装位", "price": price3, "sold": false,
		})
	else:
		var mid := roll_mod(rng)
		var mod: Dictionary = Defs.MODS[mid]
		stock.append({
			"kind": "mod", "id": mid, "title": "改装：" + str(mod["name"]),
			"desc": str(mod["desc"]), "rarity": str(mod["rarity"]),
			"icon": str(Defs.MOD_SCHOOLS[mod["school"]]["icon"]),
			"shelf": "黑市改装位", "price": price3, "sold": false,
		})
	return stock

func _item_offer(id: String, shelf: String, price: int) -> Dictionary:
	if Defs.SERVICES.has(id):
		var sv: Dictionary = Defs.SERVICES[id]
		return {
			"kind": "service", "id": id, "title": str(sv["name"]), "desc": str(sv["desc"]),
			"rarity": str(sv["rarity"]), "icon": str(sv["icon"]),
			"shelf": shelf, "price": price, "sold": false,
		}
	var it: Dictionary = Defs.ITEMS[id]
	return {
		"kind": "item", "id": id, "title": str(it["name"]), "desc": str(it["desc"]),
		"rarity": str(it["rarity"]), "icon": str(it["icon"]),
		"shelf": shelf, "price": price, "sold": false,
	}

func buy_offer(index: int) -> void:
	if state != State.SHOP or index < 0 or index >= shop_stock.size():
		return
	var offer: Dictionary = shop_stock[index]
	if bool(offer["sold"]):
		return
	if tokens < int(offer["price"]):
		if hud != null:
			hud.toast("代币不足", EG.C_MAGENTA, 1.6)
		Audio.play("sfx_ui_click", -12.0, 0.6)
		return
	tokens -= int(offer["price"])
	offer["sold"] = true
	match str(offer["kind"]):
		"mod":
			add_mod(str(offer["id"]))
			if hud != null:
				hud.toast("购入改装：" + str(Defs.MODS[offer["id"]]["name"]),
					Defs.mod_school_color(str(offer["id"])), 2.2)
		"awaken":
			_apply_awaken(str(offer.get("skill_id", "pulse")), str(offer["id"]))
		"service":
			_apply_service(str(offer["id"]))
			if hud != null:
				hud.toast("购入服务：" + str(Defs.SERVICES[offer["id"]]["name"]), EG.C_MINT, 2.2)
		_:
			var id := str(offer["id"])
			if inventory.size() < item_slots:
				inventory.append(id)
				if hud != null:
					hud.toast("购入 " + Defs.ITEMS[id]["name"], Defs.item_rarity_color(id), 2.0)
			else:
				# 背包已满：直接复用现成的“丢弃替换”流程，不再干脆拒买。
				_pending_item = id
				state = State.DESTROY
				if hud != null:
					hud.hide_shop()
					hud.show_destroy(inventory, id)
				Audio.play("sfx_token", -4.0)
				return
	Audio.play("sfx_token", -4.0)
	if hud != null:
		hud.refresh_shop(shop_stock, tokens)

func _apply_service(id: String) -> void:
	match id:
		"service_repair":
			ship.shield = ship.shield_max
			Fx.text(fx_layer, ship.position + Vector2(0, -34), "护盾已满", EG.C_CYAN, 20)
		"service_full_boost":
			ship.boost_full()
			Fx.text(fx_layer, ship.position + Vector2(0, -34), "加力槽已满", EG.C_AMBER, 20)

# ---------------------------------------------------------------- fuel

func has_item(id: String) -> bool:
	return inventory.has(id)

func _check_fuel(delta: float) -> void:
	if ship.fuel > 0.5:
		fuel_dead_timer = 0.0
		return
	var safe_on_screen := safe_zone != null and is_on_screen(safe_zone.position, safe_zone.clearance_radius())
	var has_fuel_item := has_item("fuel")
	if safe_on_screen or has_fuel_item:
		fuel_dead_timer = 0.0
		return
	fuel_dead_timer += delta
	if fuel_dead_timer > 12.0:
		die("燃料耗尽")

# ---------------------------------------------------------------- assist

func assist_accel(s: PlayerShip, delta: float = 0.0) -> Vector2:
	var acc := Vector2.ZERO
	var input := _read_dir()
	if player_hidden or (safe_zone != null and safe_zone.inside(s.position)):
		# 高速进站：安全区扩张到 R280 后，辅助装置用足够强的反推把飞船
		# 停在圈内，而不是让它在 0.4 秒里穿过去。默认一直刹车；只有玩家
		# 明确把推进方向指向圈外时才放手，避免把玩家困在安全区里。
		var z: Zone = safe_zone
		if z != null and s.vel.length() > 12.0:
			var leaving := false
			if input.length() > 0.1:
				var to_center: Vector2 = (z.position - s.position)
				if to_center.length() > 1.0:
					leaving = input.normalized().dot(to_center.normalized()) < -0.35
			if not leaving:
				acc += -s.vel.normalized() * minf(EG.SHIP_SAFE_BRAKE, s.vel.length() * 6.0)
				assist_active = true
		return acc
	if safe_zone != null and safe_zone.active:
		var z: Zone = safe_zone
		var to_center: Vector2 = z.position - s.position
		var dist: float = to_center.length()
		if dist > 1.0 and dist < z.clearance_radius() + EG.ZONE_INFLUENCE_EXTRA:
			var leaving := false
			if input.length() > 0.1:
				leaving = input.normalized().dot(to_center.normalized()) < -0.35
			if not leaving:
				# 捕获井：把速度朝“指向圆心的目标速度”拉，而不是只加一个
				# 很小的向心加速度。目标速度随距离收缩，增益和加速度上限
				# 足够压掉切向速度，高速掠过也会被带回圈内。
				var desired_speed: float = minf(EG.ZONE_CAPTURE_SPEED, dist * 2.0)
				var desired: Vector2 = to_center / dist * desired_speed
				var steer: Vector2 = (desired - s.vel) * EG.ZONE_CAPTURE_GAIN
				acc += steer.limit_length(EG.ZONE_CAPTURE_ACCEL)
				assist_active = true
	for b in galaxy.bodies:
		var surface: float = s.position.distance_to(b.position) - b.radius
		if surface > 320.0 or surface < 0.0:
			continue
		var radial: Vector2 = (s.position - b.position).normalized()
		var inward: float = -s.vel.dot(radial)
		if inward < 45.0:
			continue
		if input.length() > 0.1 and input.normalized().dot(radial) > 0.25:
			continue
		var speed: float = s.vel.length()
		var fade: float = clampf(1.0 - speed / EG.SHIP_ORBIT_SPEED_MAX, 0.0, 1.0)
		if fade <= 0.0:
			continue
		var tangent: Vector2 = radial.orthogonal()
		var vt: Vector2 = s.vel - radial * s.vel.dot(radial)
		if vt.dot(tangent) < 0.0:
			tangent = -tangent
		acc += tangent * EG.SHIP_ORBIT_ACCEL * fade
		assist_active = true
		orbit_assist = true
	return acc

# ---------------------------------------------------------------- cleanup

func _exit_tree() -> void:
	Audio.loop_sfx("sfx_thrust", false)

func _cleanup() -> void:
	var limit := 4200.0
	for met in meteors.duplicate():
		if not met.dead and met.position.distance_to(ship.position) > limit + 1800.0:
			remove_meteor(met, false)
	for m in missiles.duplicate():
		if m.chain != null and not is_instance_valid(m.chain):
			m.chain = null
		if not m.dead and m.position.distance_to(ship.position) > 6000.0:
			remove_missile(m, false)
	for d in drones.duplicate():
		if d == null or not is_instance_valid(d):
			drones.erase(d)
			continue
		if d.dead:
			drones.erase(d)
		elif d.position.distance_to(ship.position) > 6000.0:
			remove_drone(d, false)
	for mat in matters.duplicate():
		if not is_instance_valid(mat):
			matters.erase(mat)
			continue
		if not mat.collected and mat.position.distance_to(ship.position) > 5200.0:
			mat.queue_free()
			matters.erase(mat)
	for d in decoys.duplicate():
		if d.dead:
			decoys.erase(d)
	for a in anchors.duplicate():
		if a.dead:
			anchors.erase(a)

var _warn_cd := 0.0
func _missile_warn_tick(delta: float) -> void:
	_warn_cd -= delta
	if _warn_cd > 0.0:
		return
	for m in missiles:
		if not m.dead and m.is_locked() and m.position.distance_to(ship.position) < 520.0:
			_warn_cd = 0.9
			Audio.play("sfx_lock", -14.0, 1.0)
			return

func _alarm_tick(delta: float) -> void:
	_alarm_cd -= delta
	if _alarm_cd > 0.0:
		return
	if ship.fuel < 55.0 or ship.shield < 6.0:
		_alarm_cd = 4.0
		Audio.play("sfx_alarm", -10.0)
	else:
		_alarm_cd = 0.5

func _tutorial_step(delta: float) -> void:
	if test_mode:
		return
	if Store.hints_done or tutorial_index > 6:
		return
	tutorial_timer += delta
	var texts := [
		[2.0, "WASD / 左摇杆 推进 · Shift 加力 · J 脉冲", EG.C_CYAN],
		[10.0, "导弹锁你 5 秒后脱锁：把它的弹道引向炮塔", EG.C_AMBER],
		[18.0, "护盾只有 20，敌方导弹一击必杀", EG.C_MAGENTA],
		[26.0, "松开推进不会减速；燃料只在实际加速、减速或转向时消耗", EG.C_MINT],
		[34.0, "贴近行星时辅助装置会自动绕行加速，离开引力圈后速度保留", EG.C_CYAN],
		[42.0, "炮塔外壳会伤害你，但它也是导弹唯一能撞的东西", EG.C_VIOLET],
		[50.0, "辅助操作装置会平衡恒星引力；导弹没有这套装置，始终被引力弯折", EG.C_CYAN],
		[58.0, "偏导母舰正面有 120° 能量盾：绕到舰尾打 1.5 倍暴击", EG.C_AMBER],
		[66.0, "引力阱舰虹吸时把脱锁弹或陨石送进吸引圈，它会把东西吸到脸上", EG.C_VIOLET],
		[74.0, "商店黑市货架必出核心改装或技能觉醒，绕远路才有的东西", EG.C_MINT],
	]
	if Store.touch_mode:
		texts = [
			[2.0, "拖动左摇杆推进 · 右侧加力键冲刺 · 脉冲技能", EG.C_CYAN],
			[10.0, "导弹锁你 5 秒后脱锁：把它的弹道引向炮塔", EG.C_AMBER],
			[18.0, "护盾只有 20，敌方导弹一击必杀", EG.C_MAGENTA],
			[26.0, "松开推进不会减速；燃料只在实际加速、减速或转向时消耗", EG.C_MINT],
			[34.0, "贴近行星时辅助装置会自动绕行加速，离开引力圈后速度保留", EG.C_CYAN],
			[42.0, "炮塔外壳会伤害你，但它也是导弹唯一能撞的东西", EG.C_VIOLET],
			[50.0, "辅助操作装置会平衡恒星引力；导弹没有这套装置，始终被引力弯折", EG.C_CYAN],
			[58.0, "偏导母舰正面有 120° 能量盾：绕到舰尾打 1.5 倍暴击", EG.C_AMBER],
			[66.0, "引力阱舰虹吸时把脱锁弹或陨石送进吸引圈，它会把东西吸到脸上", EG.C_VIOLET],
			[74.0, "商店黑市货架必出核心改装或技能觉醒，绕远路才有的东西", EG.C_MINT],
		]
	if tutorial_index < texts.size() and tutorial_timer >= float(texts[tutorial_index][0]):
		if hud != null:
			hud.toast(str(texts[tutorial_index][1]), texts[tutorial_index][2], 3.0)
		tutorial_index += 1
	if tutorial_index >= texts.size():
		Store.hints_done = true
		Store.save_data()
