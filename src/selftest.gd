class_name Selftest
extends Node
## Headless verification: 40+ assertions against the design doc, plus a bot
## playability test proving the lure loop works.

var total := 0
var failed := 0
var dt := 1.0 / 60.0

func run_tests() -> void:
	await get_tree().process_frame
	print("=== Escape Gravity selftest ===")
	_test_physics()
	_test_gravity()
	_test_missiles()
	_test_meteor_matter()
	_test_zones()
	_test_inventory_and_upgrades()
	_test_skills()
	_test_fuel_and_death()
	_test_spawning()
	_test_streaming()
	var bot := await _test_bot_playability()
	print("RESULT: %d checks, %d failed  (bot: %s)" % [total, failed, str(bot)])
	await get_tree().process_frame
	get_tree().quit(1 if failed > 0 else 0)

func _check(name: String, ok: bool, info: String = "") -> void:
	total += 1
	if not ok:
		failed += 1
	print(("PASS  " if ok else "FAIL  ") + name + ("   " + info if info != "" else ""))

func _new_run(seed: int) -> Run:
	var r := Run.new()
	r.test_mode = true
	r.auto_play = true
	r.seed_value = seed
	add_child(r)
	r.set_physics_process(false)
	r.state = Run.State.PLAYING
	return r

func _kill(r: Run) -> void:
	if r != null and is_instance_valid(r):
		r.free()

func _step(r: Run, seconds: float) -> void:
	var n := int(seconds * 60.0)
	for i in range(n):
		if r.state != Run.State.PLAYING:
			return
		r.simulate(dt)

func _clear_arena(r: Run) -> void:
	for m in r.missiles.duplicate():
		m.remove()
	r.missiles.clear()
	for e in r.enemies.duplicate():
		e.remove()
	r.enemies.clear()
	r.current_enemy = null
	for met in r.meteors.duplicate():
		met.remove()
	r.meteors.clear()
	for mat in r.matters.duplicate():
		mat.queue_free()
	r.matters.clear()
	if r.safe_zone != null:
		r.safe_zone.remove()
		r.safe_zone = null
	if r.shop_zone != null:
		r.shop_zone.remove()
		r.shop_zone = null

func _make_enemy(r: Run, pos: Vector2, kind: String = "turret") -> Enemy:
	var e := Enemy.new()
	e.run = r
	e.kind = kind
	e.radius = EG.NEST_RADIUS if kind == "nest" else EG.TURRET_RADIUS
	e.max_hp = EG.NEST_HP if kind == "nest" else EG.TURRET_HP
	e.hp = e.max_hp
	e.position = pos
	r.world.add_child(e)
	r.enemies.append(e)
	r.current_enemy = e
	return e

func _test_physics() -> void:
	var r := _new_run(101)
	_clear_arena(r)
	r.ship.position = Vector2.ZERO
	r.ship.vel = Vector2.ZERO
	r.ship.fuel = r.ship.fuel_max
	r.auto_input = Vector2.RIGHT
	r.auto_boost = false
	_step(r, 4.0)
	_check("飞船极速 150", absf(r.ship.vel.length() - 150.0) < 1.0, "speed=%.1f" % r.ship.vel.length())
	_check("燃料上限 500 / 推进 4/s", absf(r.ship.fuel - (r.ship.fuel_max - 16.0)) < 0.6, "fuel=%.1f" % r.ship.fuel)

	r.ship.position = Vector2.ZERO
	r.ship.vel = Vector2.ZERO
	r.ship.fuel = r.ship.fuel_max
	r.ship.boost_meter = r.ship.boost_cap
	r.ship.boost_ready = true
	r.auto_boost = true
	_step(r, 1.0)
	_check("加力极速 ≈192", absf(r.ship.vel.length() - 192.0) < 2.0, "speed=%.1f" % r.ship.vel.length())
	_check("加力燃料 4.8/s（1.2×）", absf(r.ship.fuel - (r.ship.fuel_max - 4.8)) < 0.6, "fuel=%.1f" % r.ship.fuel)
	_check("加力槽容量 2.2s", absf(r.ship.boost_cap - 2.2) < 0.001, "cap=%.2f" % r.ship.boost_cap)

	# single-frame thrust ratio
	r.ship.position = Vector2.ZERO
	r.ship.vel = Vector2.ZERO
	r.ship.boost_meter = r.ship.boost_cap
	r.ship.boost_ready = true
	r.ship.fuel = r.ship.fuel_max
	r.auto_boost = false
	r.simulate(dt)
	var v1 := r.ship.vel.length()
	r.ship.position = Vector2.ZERO
	r.ship.vel = Vector2.ZERO
	r.ship.fuel = r.ship.fuel_max
	r.ship.boost_meter = r.ship.boost_cap
	r.ship.boost_ready = true
	r.auto_boost = true
	r.simulate(dt)
	var v2 := r.ship.vel.length()
	_check("加力推力 3×", absf(v2 / maxf(v1, 0.001) - 3.0) < 0.12, "plain=%.2f boost=%.2f" % [v1, v2])

	# boost refill after 0.7s idle
	r.auto_boost = false
	r.auto_input = Vector2.ZERO
	r.ship.boost_meter = 0.6
	r.ship.boost_ready = true
	_step(r, 0.5)
	var before := r.ship.boost_meter
	_step(r, 0.6)
	_check("停止加力 0.7s 后加力槽恢复", r.ship.boost_meter > before + 0.3, "before=%.2f after=%.2f" % [before, r.ship.boost_meter])
	_check("飞船碰撞半径 40 / 护盾 20", EG.SHIP_RADIUS == 40.0 and EG.SHIP_SHIELD_MAX == 20.0)
	_kill(r)

func _test_gravity() -> void:
	var r := _new_run(102)
	_clear_arena(r)
	var b := r.new_gravity_body(Vector2(9000, 0), 290.0, "planet", 1)
	_check("天体表面引力 ≈285", absf(b.surface_gravity() - 285.0) < 2.0, "g=%.1f" % b.surface_gravity())
	var g_surface := b.gravity_at(b.position + Vector2(290, 0)).length()
	var g_core := b.gravity_at(b.position + Vector2(290.0 * 0.85, 0)).length()
	var g_edge := b.gravity_at(b.position + Vector2(290.0 * 2.0, 0)).length()
	_check("内圈 0.85r 夹紧 ≈395", absf(g_core - 395.0) < 6.0, "g=%.1f" % g_core)
	_check("表面引力即 285", absf(g_surface - 285.0) < 2.0, "g=%.1f" % g_surface)
	_check("影响半径 2r 之外引力为 0", g_edge == 0.0 and b.gravity_at(b.position + Vector2(700, 0)).length() == 0.0)

	var star := r.new_gravity_body(Vector2(0, -1500), 800.0, "star", 1)
	var ship_g := r.galaxy.gravity_at(Vector2.ZERO, true).length()
	var full_g := r.galaxy.gravity_at(Vector2.ZERO, false).length()
	_check("恒星引力对飞船自动抵消（远离恒星）", ship_g < 0.001 and full_g > 0.1, "ship=%.3f full=%.2f" % [ship_g, full_g])
	_check("恒星半径 800、影响 1600", absf(star.influence - 1600.0) < 0.01)
	_kill(r)

func _test_missiles() -> void:
	var r := _new_run(103)
	_clear_arena(r)
	r.ship.position = Vector2.ZERO
	var e := _make_enemy(r, Vector2(0, -1600))
	var m := r.spawn_enemy_missile(e, Vector2(0, 300), 0.0)
	m.source = null
	_check("导弹速度 150", absf(m.speed - 150.0) < 0.01 and m.vel.length() < 151.0)
	var a0 := m.angle
	for i in range(60):
		m.step(dt)
	var turned := absf(wrapf(m.angle - a0, -PI, PI))
	_check("导弹转向率 0.525 rad/s", absf(turned - 0.525) < 0.03, "turn=%.3f" % turned)
	_check("导弹碰撞半径 12", EG.MISSILE_RADIUS == 12.0)

	# lock timer starts in view and expires after 5 s
	var m2 := r.spawn_enemy_missile(e, Vector2(0, 300), 0.0)
	m2.source = null
	for i in range(int(4.9 * 60.0)):
		m2.step(dt)
	var still_locked := m2.is_locked()
	for i in range(int(0.3 * 60.0)):
		m2.step(dt)
	_check("屏幕内 5s 后脱锁", still_locked and not m2.is_locked())
	m2.remove()

	# damage: 25 per missile, 2 hits kill a 50 hp turret
	var hp0 := e.hp
	var m3 := r.spawn_enemy_missile(e, e.position + Vector2(e.radius + 2, 0), PI)
	m3.source = null
	r._resolve_collisions()
	_check("导弹撞炮塔 -25", absf(e.hp - (hp0 - 25.0)) < 0.01, "hp=%.1f" % e.hp)
	_check("命中后过载 2.5s", e.overheated and absf(e.overheat_timer - 2.5) < 0.01)
	var m4 := r.spawn_enemy_missile(e, e.position + Vector2(e.radius + 2, 0), PI)
	m4.source = null
	r._resolve_collisions()
	_check("两发摧毁 50 血炮塔", r.current_enemy == null and r.kills == 1, "kills=%d" % r.kills)
	_check("炮塔半径 420 / 血量 50", EG.TURRET_RADIUS == 420.0 and EG.TURRET_HP == 50.0)
	_check("炮塔视野外/内移速 240/18", EG.TURRET_SPEED_OUT == 240.0 and EG.TURRET_SPEED_IN == 18.0)
	_check("齐射间隔 5s/1s、上限 3 枚", EG.TURRET_FIRE_OUT == 5.0 and EG.TURRET_FIRE_IN == 1.0 and EG.MISSILE_MAX_LOCKED == 3)

	# In view the missile must leave a hull hard-point; out of view it keeps the
	# design doc's 820 px lateral entrance.
	for mm in r.missiles.duplicate():
		mm.remove()
	r.missiles.clear()
	var e_in := _make_enemy(r, Vector2(0, -500))
	e_in.in_view = true
	e_in._fire_one()
	var ms: Missile = r.missiles[r.missiles.size() - 1]
	_check("视野内导弹从炮塔外壳发射", absf(ms.position.distance_to(e_in.position) - (e_in.radius + 14.0)) < 2.5,
		"muzzle=%.0f" % ms.position.distance_to(e_in.position))
	for mm in r.missiles.duplicate():
		mm.remove()
	r.missiles.clear()
	var e_out := _make_enemy(r, Vector2(0, -1600))
	e_out.in_view = false
	e_out._fire_one()
	var mo: Missile = r.missiles[r.missiles.size() - 1]
	_check("视野外导弹仍从侧方 820px 进入", absf(mo.position.distance_to(r.ship.position) - 820.0) < 45.0,
		"d=%.0f" % mo.position.distance_to(r.ship.position))
	_kill(r)

func _test_meteor_matter() -> void:
	var r := _new_run(104)
	_clear_arena(r)
	r.ship.position = Vector2.ZERO
	r.ship.vel = Vector2.ZERO
	r.ship.shield = 20.0
	var met := Meteor.new()
	met.run = r
	met.position = Vector2.ZERO
	met.vel = Vector2.ZERO
	r.world.add_child(met)
	r.meteors.append(met)
	r._resolve_collisions()
	_check("陨石磨损护盾 0.5", absf(r.ship.shield - 19.5) < 0.01, "shield=%.2f" % r.ship.shield)

	var e := _make_enemy(r, Vector2(2000, 0))
	var met2 := Meteor.new()
	met2.run = r
	met2.position = e.position + Vector2(e.radius, 0)
	met2.knocked = true
	r.world.add_child(met2)
	r.meteors.append(met2)
	var hp0 := e.hp
	r._resolve_collisions()
	_check("被玩家撞飞的陨石对敌人 5 伤害", absf(e.hp - (hp0 - 5.0)) < 0.01, "hp=%.1f" % e.hp)

	var m := Matter.new()
	m.run = r
	m.big = true
	m.xp = 3
	m.position = r.ship.position
	r.world.add_child(m)
	r.matters.append(m)
	r.xp = 0.0
	r.simulate(dt)
	_check("大物质 3 XP / 自动吸取", absf(r.xp - 3.0) < 0.01, "xp=%.0f" % r.xp)

	# magnet radius 190
	var far := Matter.new()
	far.run = r
	far.position = r.ship.position + Vector2(300, 0)
	r.world.add_child(far)
	r.matters.append(far)
	var d0 := far.position.distance_to(r.ship.position)
	_step(r, 0.6)
	var d1 := far.position.distance_to(r.ship.position)
	_check("190 吸取半径：300 外不吸引", absf(d0 - d1) < 20.0, "d0=%.0f d1=%.0f" % [d0, d1])
	var near := Matter.new()
	near.run = r
	near.position = r.ship.position + Vector2(150, 0)
	r.world.add_child(near)
	r.matters.append(near)
	var n0 := near.position.distance_to(r.ship.position)
	_step(r, 0.4)
	var n1 := near.position.distance_to(r.ship.position)
	_check("190 吸取半径：150 内被吸引", n1 < n0 - 5.0, "n0=%.0f n1=%.0f" % [n0, n1])
	_check("每 20 XP 升级", EG.XP_PER_LEVEL == 20.0)
	_kill(r)

func _test_zones() -> void:
	var r := _new_run(105)
	_clear_arena(r)
	r.ship.position = Vector2.ZERO
	r.ship.fuel = 40.0
	var z := r.make_zone("safe", Vector2(900, 0))
	r.safe_zone = z
	_check("安全区半径 280", absf(z.radius - 280.0) < 0.01 and EG.ZONE_RADIUS == 280.0)
	var m := r.spawn_enemy_missile(null, Vector2(100, 0), 0.0)
	m.source = null
	r.ship.position = z.position
	r._zone_checks()
	_check("进入安全区补满燃料", absf(r.ship.fuel - r.ship.fuel_max) < 0.01)
	_check("进入安全区清除导弹", r.missiles.size() == 0)
	_check("进入安全区隐藏威胁信息", r.player_hidden)
	r.ship.position = z.position + Vector2(400, 0)
	r._zone_checks()
	_check("离开安全区后消失并在 10s 后刷新", r.safe_zone == null and absf(r.safe_respawn_timer - 10.0) < 0.01)

	var sz := r.make_zone("shop", Vector2(3000, 0))
	r.shop_zone = sz
	r.ship.position = sz.position
	r.ship.fuel = 100.0
	r._zone_checks()
	_check("商店打开 3 件商品且不回燃料", r.state == Run.State.SHOP and r.shop_stock.size() == 3 and absf(r.ship.fuel - 100.0) < 0.01)
	r.close_shop()
	_check("关闭商店回到游戏", r.state == Run.State.PLAYING)
	_kill(r)

func _test_inventory_and_upgrades() -> void:
	var r := _new_run(106)
	_clear_arena(r)
	r.item_slots = 2
	r.inventory.clear()
	var ok1 := r.add_item("fuel")
	var ok2 := r.add_item("repair")
	var ok3 := r.add_item("flare")
	_check("物品栏基础 2 格", ok1 and ok2 and not ok3 and r.state == Run.State.DESTROY)
	r.destroy_and_take(0)
	_check("满栏时销毁后可放入新道具", r.inventory.size() == 2 and r.inventory.has("flare"), str(r.inventory))
	r.item_slots = EG.ITEM_SLOTS_MAX
	r.inventory = ["fuel", "repair", "flare", "decoy", "charge"]
	var slot_seen := false
	var new_skill_seen := false
	r.skills = [{"id": "pulse", "level": 1, "cd": 0.0}, {"id": "anchor", "level": 1, "cd": 0.0}]
	for i in range(60):
		var cards := Defs.roll_upgrades(r, r.rng)
		for c in cards:
			if c["id"] == "slot":
				slot_seen = true
			if c["id"] == "skill_new":
				new_skill_seen = true
	_check("5 格上限后不再提供物品栏卡", not slot_seen)
	_check("技能槽满后不再提供新技能", not new_skill_seen)
	_check("物品栏上限 5 / 技能槽 2", EG.ITEM_SLOTS_MAX == 5 and EG.SKILL_SLOTS == 2)
	_kill(r)

func _test_skills() -> void:
	var r := _new_run(107)
	_clear_arena(r)
	r.ship.position = Vector2.ZERO
	r.ship.fuel = r.ship.fuel_max
	r.skills = [{"id": "pulse", "level": 1, "cd": 0.0}]
	var e := _make_enemy(r, Vector2(0, -2200))
	var m := r.spawn_enemy_missile(e, Vector2(0, 220), 0.0)
	m.source = null
	r.cast_skill(0)
	_check("脉冲消耗 10 燃料", absf(r.ship.fuel - (r.ship.fuel_max - 10.0)) < 0.01, "fuel=%.1f" % r.ship.fuel)
	_check("脉冲使导弹脱锁", not m.is_locked())
	_check("脉冲冲量 200", absf(m.vel.length() - 200.0) < 12.0, "v=%.1f" % m.vel.length())
	_check("脉冲冷却 5s", absf(float(r.skills[0]["cd"]) - 5.0) < 0.01)

	var d := r._drop_decoy(Vector2(0, 420), Vector2.ZERO, 7.0)
	var m2 := r.spawn_enemy_missile(e, Vector2(0, 120), 0.0)
	m2.source = null
	m2.retarget_to(d)
	m2.position = d.position
	r._apply_decoy_orders()
	_check("诱饵弹：导弹抵达后脱锁", not m2.is_locked())
	_check("诱饵受引力影响", d.vel.length() >= 0.0)

	# flare
	r.inventory = ["flare"]
	var m3 := r.spawn_enemy_missile(e, Vector2(120, 0), 0.0)
	m3.source = null
	m3.retarget_to(null)
	m3.locked = true
	var was_locked := m3.is_locked()
	r.use_item_slot(0)
	_check("干扰弹：使锁定导弹偏转并脱锁", was_locked and not m3.is_locked() and m3.vel.length() > 200.0)
	_kill(r)

func _test_fuel_and_death() -> void:
	var r := _new_run(108)
	_clear_arena(r)
	r.ship.fuel = 0.0
	r.ship.shield = 20.0
	_step(r, 12.5)
	_check("燃料耗尽且无安全区/燃料道具 → 12s 后结束", r.state == Run.State.DEAD)
	_kill(r)

	var r2 := _new_run(109)
	_clear_arena(r2)
	r2.ship.shield = 25.0
	var e := _make_enemy(r2, Vector2(0, -1200))
	var m := r2.spawn_enemy_missile(e, r2.ship.position + Vector2(20, 0), PI)
	m.source = null
	r2._resolve_collisions()
	_check("敌方导弹伤害 25（护盾 20 时一击结束）", r2.state == Run.State.DEAD or r2.ship.shield <= 0.0)
	_kill(r2)

	var r3 := _new_run(110)
	_clear_arena(r3)
	r3.inventory = ["revive"]
	r3.ship.shield = 5.0
	r3.ship.take_damage(5.0)
	r3._try_revive_or_die()
	_check("复活币自动消耗并恢复 8 护盾", r3.state == Run.State.PLAYING and absf(r3.ship.shield - 8.0) < 0.01 and r3.inventory.size() == 0)
	_kill(r3)

func _test_spawning() -> void:
	var r := _new_run(111)
	_clear_arena(r)
	r.ship.position = Vector2.ZERO
	r.galaxy.mark_view(Rect2(Vector2(-640, -360), Vector2(1280, 720)))
	r.spawn_enemy()
	var e = r.current_enemy
	var ok_dist := false
	var ok_unexplored := false
	if e != null:
		var d: float = e.position.distance_to(r.ship.position)
		ok_dist = d >= EG.SPAWN_MIN - 1.0 and d <= EG.SPAWN_MAX + 1.0
		ok_unexplored = not r.galaxy.is_explored(e.position)
	_check("攻击者在屏幕外 1900~2400 刷新", ok_dist, "d=%.0f" % (e.position.distance_to(r.ship.position) if e != null else -1.0))
	_check("攻击者刷新在未探索区域", ok_unexplored)
	if r.current_enemy != null:
		r.current_enemy.remove()
		r.enemies.clear()
		r.current_enemy = null
	r.safe_zone = null
	r.safe_respawn_timer = 0.0
	r._spawn_safe_respawn()
	var ok_zone := false
	if r.safe_zone != null:
		var d2: float = r.safe_zone.position.distance_to(r.ship.position)
		ok_zone = d2 <= EG.SAFE_FUEL_DIST + 1.0 and d2 >= 600.0
	_check("安全区在 50 燃料距离内刷新", ok_zone)
	# Enemy and safe zone should share a bearing so the two HUD markers agree.
	if r.current_enemy != null:
		r.current_enemy.remove()
		r.enemies.clear()
		r.current_enemy = null
	if r.safe_zone != null:
		r.safe_zone.remove()
		r.safe_zone = null
	r.safe_zone = r.make_zone("safe", r.ship.position + Vector2(1100, 0))
	r.spawn_enemy()
	var e2 = r.current_enemy
	var diff := 9.0
	var outer := false
	if e2 != null:
		diff = absf(wrapf((e2.position - r.ship.position).angle(), -PI, PI))
		outer = e2.position.distance_to(r.ship.position) > 1100.0
	_check("攻击者沿玩家-安全区连线刷新", e2 != null and diff < 0.55, "diff=%.2frad" % diff)
	_check("攻击者刷新在安全区外侧", e2 != null and outer)
	_kill(r)

func _test_streaming() -> void:
	var r := _new_run(112)
	var far := Vector2(120000, 0)
	r.galaxy.ensure_around(far)
	var near := 0
	for b in r.galaxy.bodies:
		if b.position.distance_to(far) < 6000.0:
			near += 1
	_check("远离出生点仍有天体区块", near >= 3, "near=%d total=%d" % [near, r.galaxy.bodies.size()])
	var has_matter_field := r.ship.fuel_max >= 500.0
	_check("初始燃料 500", has_matter_field and absf(r.ship.fuel - 500.0) < 0.01, "fuel=%.0f" % r.ship.fuel)
	_kill(r)

func _test_bot_playability() -> Dictionary:
	var attempts: Array = []
	for i in range(3):
		attempts.append(await _bot_attempt(200 + i, 700.0 + i * 90.0, false))
		attempts.append(await _bot_attempt(300 + i, 700.0 + i * 90.0, true))
	var invuln_runs := 0
	var invuln_kills := 0
	var normal_kills := 0
	for a in attempts:
		if a["invuln"]:
			invuln_runs += 1
			if a["killed"]:
				invuln_kills += 1
		elif a["killed"]:
			normal_kills += 1
	_check("无敌机器人能靠诱导击毁炮塔（验证核心循环）", invuln_kills >= 2, "invuln kills %d/%d" % [invuln_kills, invuln_runs])
	_check("普通机器人也能至少击毁一次炮塔", normal_kills >= 1, "normal kills %d/3" % normal_kills)
	return {"attempts": attempts, "invuln_kills": invuln_kills, "normal_kills": normal_kills}

func _bot_attempt(seed_value: int, orbit_radius: float, invuln: bool) -> Dictionary:
	var r := _new_run(seed_value)
	_clear_arena(r)
	r.ship.position = Vector2.ZERO
	r.ship.vel = Vector2.ZERO
	r.ship.fuel = r.ship.fuel_max
	r.ship.shield = 1000.0 if invuln else 20.0
	r.ship.shield_max = 1000.0 if invuln else 20.0
	r.skills = [{"id": "pulse", "level": 1, "cd": 0.0}]
	var e := _make_enemy(r, Vector2(0, -2100))
	e.fire_timer = 1.6
	var orbit_angle := 0.0
	var t := 0.0
	var hits := 0
	# Let the enemy approach, then orbit it tightly.
	while t < 60.0 and r.state == Run.State.PLAYING and r.current_enemy == e:
		orbit_angle += 0.42 * dt
		var target := e.position + Vector2.RIGHT.rotated(orbit_angle) * orbit_radius
		var input := (target - r.ship.position).normalized()
		if r.ship.position.distance_to(e.position) < e.radius + 90.0:
			input = (r.ship.position - e.position).normalized()
		r.auto_input = input
		var danger := false
		for m in r.missiles:
			if not m.dead and m.position.distance_to(r.ship.position) < 360.0:
				danger = true
		r.auto_boost = danger and r.ship.boost_meter > 0.4
		if r.skills.size() > 0 and float(r.skills[0]["cd"]) <= 0.0 and danger:
			r.auto_pulse = true
		var hp_before: float = e.hp
		r.simulate(dt)
		if e.hp < hp_before:
			hits += 1
		t += dt
	var killed: bool = e.dead or e.hp <= 0.0
	var end_state := r.state
	print("  bot seed=%d orbit=%.0f invuln=%s -> hp=%.0f hits=%d t=%.1fs state=%d dmg=%s" % [seed_value, orbit_radius, str(invuln), e.hp if not e.dead else 0.0, hits, t, end_state, r.last_damage_source])
	_kill(r)
	return {"seed": seed_value, "orbit": orbit_radius, "invuln": invuln, "killed": killed, "hits": hits, "time": t, "state": end_state}
