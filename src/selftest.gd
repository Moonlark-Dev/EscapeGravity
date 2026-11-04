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
	_test_momentum_and_assist()
	_test_missiles()
	_test_meteor_matter()
	_test_zones()
	_test_inventory_and_upgrades()
	_test_skills()
	_test_pulse_direction()
	_test_fuel_and_death()
	_test_spawning()
	_test_enemy_discovery()
	_test_streaming()
	_test_route()
	_test_safe_zone_clearance()
	_test_shop_binding()
	_test_body_clearance()
	_test_initial_map()
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
	# 燃料按实际 Δv 计：0→150 只烧 150/380 秒的满推力。
	var accel_fuel := EG.SHIP_FUEL_THRUST * (EG.SHIP_MAX_SPEED / EG.SHIP_ACCEL)
	_check("推进到极速只消耗加速所需燃料", absf(r.ship.fuel - (r.ship.fuel_max - accel_fuel)) < 0.2,
		"fuel=%.1f want=%.1f" % [r.ship.fuel, r.ship.fuel_max - accel_fuel])

	# 无阻力惯性：松开推进后速度保持，燃料不再下降。
	r.auto_input = Vector2.ZERO
	var coast_fuel := r.ship.fuel
	_step(r, 2.0)
	_check("松开推进 2 秒仍保持 150（太空无阻力）", absf(r.ship.vel.length() - 150.0) < 1.0,
		"speed=%.1f" % r.ship.vel.length())
	_check("滑行不消耗燃料", absf(r.ship.fuel - coast_fuel) < 0.05, "fuel=%.1f" % r.ship.fuel)

	# 引擎无法把超过极速的惯性压回，也不会在极速上空烧燃料。
	r.ship.vel = Vector2.RIGHT * 400.0
	r.ship.position = Vector2.ZERO
	r.ship.fuel = r.ship.fuel_max
	r.auto_input = Vector2.RIGHT
	var above_fuel := r.ship.fuel
	_step(r, 1.0)
	_check("超过引擎极速的惯性被保留", absf(r.ship.vel.length() - 400.0) < 2.0,
		"speed=%.1f" % r.ship.vel.length())
	_check("极速后继续按住推进不耗燃料", absf(r.ship.fuel - above_fuel) < 0.05, "fuel=%.1f" % r.ship.fuel)

	r.ship.position = Vector2.ZERO
	r.ship.vel = Vector2.ZERO
	r.ship.fuel = r.ship.fuel_max
	r.ship.boost_meter = r.ship.boost_cap
	r.ship.boost_ready = true
	r.auto_boost = true
	_step(r, 1.0)
	_check("加力极速 ≈192", absf(r.ship.vel.length() - 192.0) < 2.0, "speed=%.1f" % r.ship.vel.length())
	var boost_fuel := EG.SHIP_FUEL_BOOST * (EG.SHIP_MAX_SPEED * EG.SHIP_BOOST_SPEED_MULT / (EG.SHIP_ACCEL * EG.SHIP_BOOST_MULT))
	_check("加力燃料按实际加速计（≈4.8/s 满推力）", absf(r.ship.fuel - (r.ship.fuel_max - boost_fuel)) < 0.12,
		"fuel=%.1f want=%.1f" % [r.ship.fuel, r.ship.fuel_max - boost_fuel])
	_check("初始加力槽 6.6s（旧 2.2s 的三倍）", absf(r.ship.boost_cap - 6.6) < 0.001, "cap=%.2f" % r.ship.boost_cap)

	# 加力结束后 192 的惯性同样保留。
	r.auto_input = Vector2.ZERO
	r.auto_boost = false
	_step(r, 2.0)
	_check("加力结束后保持 192 惯性", absf(r.ship.vel.length() - 192.0) < 2.0,
		"speed=%.1f" % r.ship.vel.length())

	# single-frame thrust ratio
	r.ship.position = Vector2.ZERO
	r.ship.vel = Vector2.ZERO
	r.ship.boost_meter = r.ship.boost_cap
	r.ship.boost_ready = true
	r.ship.fuel = r.ship.fuel_max
	r.auto_input = Vector2.RIGHT
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

	# 加力槽回充只看“是否在加力”，推进中不再阻止恢复
	r.auto_boost = false
	r.auto_input = Vector2.ZERO
	r.ship.boost_meter = 0.6
	r.ship.boost_ready = true
	_step(r, 0.5)
	var before := r.ship.boost_meter
	_step(r, 0.6)
	_check("停止加力 0.7s 后加力槽恢复", r.ship.boost_meter > before + 0.3, "before=%.2f after=%.2f" % [before, r.ship.boost_meter])

	r.auto_boost = false
	r.auto_input = Vector2.RIGHT
	r.ship.fuel = r.ship.fuel_max
	r.ship.boost_meter = 0.6
	r.ship.boost_ready = true
	_step(r, 0.5)
	var before_thrust := r.ship.boost_meter
	_step(r, 0.6)
	_check("推进中（未加力）加力槽同样回充", r.ship.boost_meter > before_thrust + 0.3, "before=%.2f after=%.2f" % [before_thrust, r.ship.boost_meter])

	# 槽耗尽后即使一直按住加力，也要先松开才会在 0.22 阈值上重新点火
	r.auto_boost = true
	r.ship.position = Vector2.ZERO
	r.ship.vel = Vector2.ZERO
	r.ship.fuel = r.ship.fuel_max
	r.ship.boost_meter = 0.05
	r.ship.boost_ready = true
	_step(r, 0.2)
	_step(r, 1.0)
	_check("按住加力耗尽后不会在 0.22 阈值抖动点火", not r.ship.boost_ready and not r.ship.boosting and r.ship.boost_meter > EG.SHIP_BOOST_RESUME, "meter=%.2f ready=%s" % [r.ship.boost_meter, str(r.ship.boost_ready)])
	r.auto_boost = false
	r.simulate(dt)
	_check("松开加力后加力槽重新可用", r.ship.boost_ready)

	_check("飞船碰撞半径 40 / 护盾 20", EG.SHIP_RADIUS == 40.0 and EG.SHIP_SHIELD_MAX == 20.0)
	_kill(r)

func _test_gravity() -> void:
	var r := _new_run(102)
	_clear_arena(r)
	var b := r.new_gravity_body(Vector2(9000, 0), 290.0, "planet", 1)
	_check("天体表面引力 ≈285", absf(b.surface_gravity() - 285.0) < 2.0, "g=%.1f" % b.surface_gravity())
	var g_surface := b.gravity_at(b.position + Vector2(290, 0)).length()
	var g_core := b.gravity_at(b.position + Vector2(290.0 * 0.85, 0)).length()
	var g_edge := b.gravity_at(b.position + Vector2(290.0 * EG.BODY_GRAVITY_RANGE, 0)).length()
	_check("内圈 0.85r 夹紧 ≈395", absf(g_core - 395.0) < 6.0, "g=%.1f" % g_core)
	_check("表面引力即 285", absf(g_surface - 285.0) < 2.0, "g=%.1f" % g_surface)
	_check("影响半径 3r 之外引力为 0", g_edge == 0.0 and b.gravity_at(b.position + Vector2(290.0 * 3.2, 0)).length() == 0.0)

	var star := r.new_gravity_body(Vector2(0, -1500), 800.0, "star", 1)
	var ship_g := r.galaxy.gravity_at(Vector2.ZERO, true).length()
	var full_g := r.galaxy.gravity_at(Vector2.ZERO, false).length()
	_check("辅助操作装置自动平衡恒星引力（远离恒星）", ship_g < 0.001 and full_g > 0.1, "ship=%.3f full=%.2f" % [ship_g, full_g])
	_check("恒星半径 800、影响 2400", absf(star.influence - 2400.0) < 0.01)

	# Unlike the ship, missiles never get the assist: a locked missile is also
	# pulled off its interception course by a strong well.
	var mr := _new_run(113)
	_clear_arena(mr)
	mr.ship.position = Vector2(3000, 0)
	mr.new_gravity_body(Vector2(0, -1000), 800.0, "star", 1)
	var me := _make_enemy(mr, Vector2(3000, -1600))
	var gm := mr.spawn_enemy_missile(me, Vector2.ZERO, 0.0)
	gm.source = null
	var a0 := gm.angle
	for i in range(30):
		gm.step(dt)
	var bend := absf(wrapf(gm.angle - a0, -PI, PI))
	_check("锁定中的导弹同样持续受天体引力", gm.is_locked() and bend > 0.08, "bend=%.2frad" % bend)
	_kill(mr)
	_kill(r)

## Inertia + gravity assist: a tangential pass around a planet must add speed
## above the engine limit, and the gained momentum must survive after leaving.
func _test_momentum_and_assist() -> void:
	var r := _new_run(119)
	_clear_arena(r)
	for b in r.galaxy.bodies.duplicate():
		b.remove()
	r.galaxy.bodies.clear()
	var body := r.new_gravity_body(Vector2.ZERO, 290.0, "planet", 1)
	r.ship.position = Vector2(0, -551.0)       # 1.9 R, just inside the 2 R well
	r.ship.vel = Vector2(150.0, 0.0)           # tangential entry
	r.ship.fuel = r.ship.fuel_max
	r.auto_input = Vector2.ZERO
	r.auto_boost = false
	var max_speed := r.ship.vel.length()
	var min_surface := 1.0e9
	for i in range(20 * 60):
		r.ship.step(dt, Vector2.ZERO, false)
		max_speed = maxf(max_speed, r.ship.vel.length())
		min_surface = minf(min_surface, r.ship.position.length() - body.radius)
	_check("环绕天体可获得超过引擎极速的速度", max_speed > 250.0, "max=%.1f" % max_speed)
	_check("环绕过程不会钻进天体表面", min_surface > EG.SHIP_RADIUS, "min_surface=%.0f" % min_surface)
	var orbit_exit := r.ship.vel.length()
	_check("离开引力圈后仍高于基础极速", orbit_exit > 180.0, "speed=%.1f" % orbit_exit)
	# Coast far from the well: no drag, no gravity, no fuel use.
	r.ship.position = Vector2(9000, 9000)
	r.ship.vel = Vector2.RIGHT * 300.0
	var fuel0 := r.ship.fuel
	for i in range(120):
		r.ship.step(dt, Vector2.ZERO, false)
	_check("深空滑行 2 秒保持 300", absf(r.ship.vel.length() - 300.0) < 1.0,
		"speed=%.1f" % r.ship.vel.length())
	_check("滑行不耗燃料", absf(r.ship.fuel - fuel0) < 0.02, "fuel=%.1f" % r.ship.fuel)
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
	e_out.discovered = true  # a known attacker that has left the screen
	e_out._fire_one()
	var mo: Missile = r.missiles[r.missiles.size() - 1]
	_check("视野外导弹仍从侧方 820px 进入", absf(mo.position.distance_to(r.ship.position) - 820.0) < 45.0,
		"d=%.0f" % mo.position.distance_to(r.ship.position))
	_kill(r)

func _test_meteor_matter() -> void:
	var r := _new_run(104)
	_clear_arena(r)
	for b in r.galaxy.bodies.duplicate():
		b.remove()
	r.galaxy.bodies.clear()
	r.no_stream = true
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

	# magnet radius 240
	var far := Matter.new()
	far.run = r
	far.position = r.ship.position + Vector2(300, 0)
	r.world.add_child(far)
	r.matters.append(far)
	var d0 := far.position.distance_to(r.ship.position)
	_step(r, 0.6)
	var d1 := far.position.distance_to(r.ship.position)
	_check("240 吸取半径：300 外不吸引", absf(d0 - d1) < 20.0, "d0=%.0f d1=%.0f" % [d0, d1])
	var near := Matter.new()
	near.run = r
	near.position = r.ship.position + Vector2(150, 0)
	r.world.add_child(near)
	r.matters.append(near)
	var n0 := near.position.distance_to(r.ship.position)
	_step(r, 0.4)
	var n1 := near.position.distance_to(r.ship.position)
	_check("240 吸取半径：150 内被吸引", n1 < n0 - 5.0, "n0=%.0f n1=%.0f" % [n0, n1])

	# A fast ship must not leave matter behind: the tractor is faster than the
	# ship and keeps pulling even when the player is already moving away.
	var hm := Matter.new()
	hm.run = r
	hm.position = r.ship.position + Vector2(-180, 0)
	r.world.add_child(hm)
	r.matters.append(hm)
	r.ship.vel = Vector2(600, 0)
	_step(r, 4.0)
	_check("高速远离时物质仍会被追上吸收", hm.collected, "collected=%s" % str(hm.collected))
	r.ship.vel = Vector2.ZERO
	_check("每 20 XP 升级", EG.XP_PER_LEVEL == 20.0)
	_kill(r)

func _test_zones() -> void:
	var r := _new_run(105)
	_clear_arena(r)
	r.ship.position = Vector2.ZERO
	r.ship.fuel = 40.0
	var z := r.make_zone("safe", Vector2(900, 0))
	r.safe_zone = z
	_check("安全区进入前只比飞船大一点", absf(z.radius - EG.ZONE_ENTRY_RADIUS) < 0.01
		and EG.ZONE_ENTRY_RADIUS > EG.SHIP_RADIUS and EG.ZONE_ENTRY_RADIUS < EG.ZONE_RADIUS,
		"r=%.0f" % z.radius)
	_check("安全区贴图初始缩小", z.scale.x < 0.4, "scale=%.2f" % z.scale.x)
	var m := r.spawn_enemy_missile(null, Vector2(100, 0), 0.0)
	m.source = null
	r.ship.position = z.position
	r._zone_checks()
	_check("进入瞬间半径直接设为最大", absf(z.radius - 280.0) < 0.01 and EG.ZONE_RADIUS == 280.0)
	_check("扩张动画从缩小状态开始（半径已满）", z.scale.x < 0.4, "scale=%.2f" % z.scale.x)
	_check("进入安全区补满燃料", absf(r.ship.fuel - r.ship.fuel_max) < 0.01)
	_check("进入安全区清除导弹", r.missiles.size() == 0)
	_check("进入安全区隐藏威胁信息", r.player_hidden)
	r.ship.position = z.position + Vector2(400, 0)
	r._zone_checks()
	_check("离开安全区后消失并在 10s 后刷新", r.safe_zone == null and absf(r.safe_respawn_timer - 10.0) < 0.01)

	# High-speed entry: the assist must brake hard enough to stop inside R280.
	var rz := _new_run(120)
	_clear_arena(rz)
	var z2 := rz.make_zone("safe", Vector2.ZERO)
	rz.safe_zone = z2
	rz.ship.position = Vector2(-200, 0)
	rz.ship.vel = Vector2(600, 0)
	rz.ship.fuel = rz.ship.fuel_max
	rz.auto_input = Vector2.ZERO
	rz.auto_boost = false
	_step(rz, 2.0)
	_check("高速进入安全区会被辅助装置刹停",
		rz.player_hidden and rz.ship.vel.length() < 20.0 and rz.ship.position.distance_to(z2.position) < EG.ZONE_RADIUS,
		"v=%.1f d=%.0f hidden=%s" % [rz.ship.vel.length(), rz.ship.position.distance_to(z2.position), str(rz.player_hidden)])
	_kill(rz)

	var sz := r.make_zone("shop", Vector2(3000, 0))
	r.shop_zone = sz
	r.ship.position = sz.position
	r.ship.fuel = 100.0
	r._zone_checks()
	_check("商店打开 3 件商品且不回燃料", r.state == Run.State.SHOP and r.shop_stock.size() == 3 and absf(r.ship.fuel - 100.0) < 0.01)
	r.close_shop()
	_check("关闭商店回到游戏", r.state == Run.State.PLAYING)

	# A fast tangential pass is bent into a slingshot: the safe-zone well adds
	# tangential speed and the ship leaves instead of being captured.
	var rf := _new_run(125)
	_clear_arena(rf)
	for b in rf.galaxy.bodies.duplicate():
		b.remove()
	rf.galaxy.bodies.clear()
	rf.no_stream = true
	rf.ship.position = Vector2(-250, 0)
	rf.ship.vel = Vector2(0, 600)
	rf.ship.fuel = rf.ship.fuel_max
	rf.auto_input = Vector2.ZERO
	rf.auto_boost = false
	var zf := rf.make_zone("safe", Vector2.ZERO)
	rf.safe_zone = zf
	_step(rf, 4.0)
	_check("高速切线掠过安全区仍会被吸入",
		zf.entered and rf.player_hidden and rf.safe_zone == zf
		and rf.ship.position.distance_to(zf.position) < EG.ZONE_RADIUS
		and rf.ship.vel.length() < 60.0,
		"v=%.0f d=%.0f entered=%s" % [rf.ship.vel.length(), rf.ship.position.distance_to(zf.position), str(zf.entered)])
	_kill(rf)
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

func _test_pulse_direction() -> void:
	var r := _new_run(110)
	_clear_arena(r)
	r.ship.position = Vector2.ZERO
	r.ship.fuel = r.ship.fuel_max
	r.skills = [{"id": "pulse", "level": 1, "cd": 0.0}]
	var e := _make_enemy(r, Vector2(0, -2400))
	var left := r.spawn_enemy_missile(e, Vector2(120, -120), 0.0)
	var right := r.spawn_enemy_missile(e, Vector2(-120, 120), 0.0)
	left.source = null
	right.source = null

	# 向右移动：分界线水平向右；线左（屏幕上方）向左偏，线右向下偏
	r.ship.vel = Vector2(150, 0)
	r.cast_skill(0)
	_check("脉冲：移动方向左侧的导弹向左偏转", Vector2.RIGHT.cross(left.vel) < -20.0,
		"v=(%.0f, %.0f)" % [left.vel.x, left.vel.y])
	_check("脉冲：移动方向右侧的导弹向右偏转", Vector2.RIGHT.cross(right.vel) > 20.0,
		"v=(%.0f, %.0f)" % [right.vel.x, right.vel.y])

	# 向左移动但面向仍朝右：判定必须跟着移动方向翻面，而不是跟着面向
	r.ship.vel = Vector2(-150, 0)
	r.ship.facing = 0.0
	r.ship.fuel = r.ship.fuel_max
	r.skills[0]["cd"] = 0.0
	left.position = Vector2(120, -120)
	right.position = Vector2(-120, 120)
	r.cast_skill(0)
	_check("脉冲：分界线随移动方向而非面向",
		Vector2.LEFT.cross(left.vel) > 20.0 and Vector2.LEFT.cross(right.vel) < -20.0,
		"left=(%.0f, %.0f) right=(%.0f, %.0f)" % [left.vel.x, left.vel.y, right.vel.x, right.vel.y])
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
	var planned0 := r.route.enemy_at(0)
	if e != null:
		var d: float = e.position.distance_to(r.ship.position)
		ok_dist = d >= EG.SPAWN_MIN - 1.0 and d <= 2700.0
		ok_unexplored = not r.galaxy.is_explored(e.position)
	_check("首个敌人在路线首段（约 1900~2400）", ok_dist, "d=%.0f" % (e.position.distance_to(r.ship.position) if e != null else -1.0))
	_check("首个敌人使用路线第 0 个敌人点", e != null and e.position.distance_to(planned0) < 1500)
	_check("首个敌人位于未探索区域", ok_unexplored)
	var p0 := Vector2.ZERO
	if e != null:
		p0 = e.position
	if r.current_enemy != null:
		r.current_enemy.remove()
		r.enemies.clear()
		r.current_enemy = null
	r.safe_zone = null
	r.safe_respawn_timer = 0.0
	var expected_safe := r.route.safe_at(r.route.next_safe)
	r._spawn_safe_respawn()
	var ok_zone := false
	var ok_planned_safe := false
	if r.safe_zone != null:
		var d2: float = r.safe_zone.position.distance_to(r.ship.position)
		ok_zone = d2 <= EG.SAFE_FUEL_DIST + 1.0 and d2 >= 300.0
		ok_planned_safe = r.safe_zone.position.distance_to(expected_safe) < 1500.0
	_check("安全区在 50 燃料距离内刷新", ok_zone)
	_check("安全区使用路线预置点", ok_planned_safe)
	var planned1 := r.route.enemy_at(r.route.next_enemy)
	r.spawn_enemy()
	var e2 = r.current_enemy
	_check("敌人按路线顺序取生成点", e2 != null and e2.position.distance_to(planned1) < 1500.0)
	_check("第二个敌人比第一个更靠路线前方", e2 != null and (e2.position - p0).dot(r.route.forward) > 0.0)
	_kill(r)

func _test_enemy_discovery() -> void:
	var r := _new_run(118)
	_clear_arena(r)
	r.ship.position = Vector2.ZERO
	r.ship.vel = Vector2.ZERO
	r.camera.position = Vector2.ZERO
	var e := _make_enemy(r, Vector2(0, -2600))
	_check("敌人生成时不可见且未被发现", not e.visible and not e.discovered)
	r.galaxy.bodies.clear()
	var far := e.position
	e.fire_timer = 0.0
	for i in range(3):
		r.simulate(dt)
	_check("远离玩家时敌人按兵不动", not e.hunting and e.position.distance_to(far) < 0.01,
		"d=%.1f" % e.position.distance_to(far))
	_check("仇恨范围外不会开火", r.missiles.is_empty())

	# Inside the aggro range but still off screen: it hunts and still fires.
	e.position = Vector2(0, -2000)
	r.camera.position = Vector2.ZERO
	r.missiles.clear()
	e.fire_timer = 0.0
	for i in range(4):
		r.simulate(dt)
	_check("玩家靠近后敌人主动逼近", e.hunting and e.position.distance_to(r.ship.position) < 1999.0,
		"d=%.1f" % e.position.distance_to(r.ship.position))
	_check("进屏前敌人仍隐藏", not e.discovered and not e.visible)
	_check("进屏前仍会开火", not r.missiles.is_empty(), "n=%d" % r.missiles.size())
	if not r.missiles.is_empty():
		var hm: Missile = r.missiles[0]
		_check("未发现时导弹从屏幕外生成", not r.is_on_screen(hm.position, 0.0), "p=%s" % str(hm.position))
		var inward: Vector2 = (r.ship.position - hm.position).normalized()
		_check("未发现时导弹以弧线而非直冲进入", Vector2.RIGHT.rotated(hm.angle).dot(inward) < 0.62,
			"dot=%.2f" % Vector2.RIGHT.rotated(hm.angle).dot(inward))
		_check("开火不会暴露敌人位置", not e.visible and not e.discovered)
	# Sneak rounds have their own cap and never consume the 3 directed slots.
	for m in r.missiles.duplicate():
		m.remove()
	r.missiles.clear()
	e._fire_one()
	e._fire_one()
	e._fire_one()
	_check("未发现导弹单独上限 2、不占直射名额",
		r.sneak_missile_count() == EG.ENEMY_HIDDEN_MAX and r.locked_missile_count() == 0,
		"sneak=%d locked=%d" % [r.sneak_missile_count(), r.locked_missile_count()])
	# Entry bearing is biased toward the enemy.
	var near_bearing := 0
	var samples := 120
	for i in range(samples):
		for m in r.missiles.duplicate():
			m.remove()
		r.missiles.clear()
		e._fire_one()
		if r.missiles.is_empty():
			continue
		var sm: Missile = r.missiles[0]
		var b: float = (sm.position - r.ship.position).angle()
		if absf(wrapf(b - (e.position - r.ship.position).angle(), -PI, PI)) <= EG.ENEMY_HIDDEN_SPREAD + 0.01:
			near_bearing += 1
	_check("未发现导弹的射入方向偏向敌人", near_bearing >= samples / 2, "%d/%d" % [near_bearing, samples])
	for m in r.missiles.duplicate():
		m.remove()
	r.missiles.clear()

	# Enter the screen: discovery, reveal fade and the HUD/radar gate opens.
	e.position = Vector2(0, -700)
	r.missiles.clear()
	r.simulate(dt)
	_check("进入屏幕即被发现", e.discovered and e.in_view)
	_check("发现后贴图淡入", e.visible and e.modulate.a > 0.0, "a=%.2f" % e.modulate.a)
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

func _test_route() -> void:
	var r := _new_run(114)
	var route: RunRoute = r.galaxy.route
	_check("地图生成阶段预置隐藏路线", route != null and route.encounters.size() >= RunRoute.PLAN_AHEAD,
		"n=%d" % (route.encounters.size() if route != null else -1))
	route.ensure_ahead(23)
	_check("路线按滚动窗口继续预生成", route.encounters.size() >= 24, "n=%d" % route.encounters.size())
	var min_fwd := 1.0
	var no_reverse := true
	for i in range(1, route.points.size()):
		var seg: Vector2 = route.points[i] - route.points[i - 1]
		min_fwd = minf(min_fwd, seg.normalized().dot(route.forward))
		if i >= 2:
			var prev: Vector2 = route.points[i - 1] - route.points[i - 2]
			if seg.normalized().dot(prev.normalized()) < 0.0:
				no_reverse = false
	_check("路线不会往回走", min_fwd > 0.0 and no_reverse, "min_fwd=%.3f" % min_fwd)

	var safe_between := true
	var shop_farther := true
	var body_near := true
	var safe_clear := 1.0e9
	var path_bodies := 0
	var path_ok := true
	var prev_enemy: Vector2 = route.origin
	var first_enc := true
	for enc in route.encounters:
		var seg: Vector2 = enc["enemy"] - prev_enemy
		var dir := seg.normalized()
		var safe_rel: Vector2 = enc["safe"] - prev_enemy
		var t: float = safe_rel.dot(dir) / maxf(seg.length(), 1.0)
		var safe_lat: float = absf(safe_rel.cross(dir))
		if t <= 0.05 or t >= 0.95 or safe_lat > 650.0:
			safe_between = false
		safe_clear = minf(safe_clear, enc["safe"].distance_to(enc["enemy"]))
		if not first_enc:
			safe_clear = minf(safe_clear, enc["safe"].distance_to(prev_enemy))
		var shop_lat: float = absf((enc["shop"] - prev_enemy).cross(dir))
		if shop_lat <= safe_lat + 300.0:
			shop_farther = false
		var body_lat: float = absf((enc["body"]["pos"] - prev_enemy).cross(dir))
		if body_lat >= float(enc["body"]["radius"]) * 2.0:
			body_near = false
		var body: Dictionary = enc["body"]
		if bool(body.get("path", false)):
			path_bodies += 1
			var body_rel: Vector2 = body["pos"] - prev_enemy
			var bt: float = body_rel.dot(dir) / maxf(seg.length(), 1.0)
			var blat: float = absf(body_rel.cross(dir))
			var br: float = float(body["radius"])
			if bt < 0.50 or bt > 0.85 or blat > RunRoute.PATH_BODY_OFFSET_MAX + 1.0:
				path_ok = false
			if br < RunRoute.PATH_BODY_RADIUS_MIN - 0.1 or br > RunRoute.PATH_BODY_RADIUS_MAX + 0.1:
				path_ok = false
			var zone_need: float = EG.ZONE_RADIUS + br + EG.BODY_CONTENT_MARGIN
			if body["pos"].distance_to(enc["safe"]) < zone_need or body["pos"].distance_to(enc["shop"]) < zone_need:
				path_ok = false
			var enemy_need: float = EG.TURRET_RADIUS + br + EG.BODY_CONTENT_MARGIN
			if body["pos"].distance_to(prev_enemy) < enemy_need or body["pos"].distance_to(enc["enemy"]) < enemy_need:
				path_ok = false
		first_enc = false
		prev_enemy = enc["enemy"]
	_check("两个敌人位置之间必有安全区", safe_between)
	# 安全区圆心到相邻敌人预置点 >= 1150 时，安全区贴图（R280）与炮塔外壳（R420）
	# 之间才留有 450px 以上的空隙，不会出现“安全区就开在敌人旁边”。
	_check("安全区离两侧敌人都足够远", safe_clear >= 1140.0, "min=%.0f" % safe_clear)
	_check("商店比安全区离路线更远", shop_farther)
	_check("每段路线经过某个天体的引力圈", body_near)
	_check("两个敌人之间的空白路径会生成加速天体", path_bodies >= 1, "n=%d" % path_bodies)
	_check("加速天体位于空白路径且避开安全区/商店/敌人", path_ok)

	var anchor: Dictionary = route.encounters[6]["body"]
	r.galaxy.ensure_around(anchor["pos"])
	var nb = r.galaxy.nearest_body(anchor["pos"])
	_check("路线段所在区块保证有天体", nb != null and nb.position.distance_to(anchor["pos"]) < 900.0)

	var r2 := _new_run(115)
	_clear_arena(r2)
	r2.spawn_enemy()
	var p0: Vector2 = r2.route.enemy_at(0)
	_check("敌人位置按路线顺序消耗", r2.route.next_enemy == 1 and r2.current_enemy != null and r2.current_enemy.position.distance_to(p0) < 1500.0)
	_kill(r2)
	_kill(r)

func _test_safe_zone_clearance() -> void:
	var r := _new_run(117)
	_clear_arena(r)
	r.spawn_enemy()
	var e: Enemy = r.current_enemy
	var want: float = EG.ZONE_RADIUS + e.radius + EG.ZONE_ENEMY_CLEAR
	var nudged: Vector2 = r._clear_zone_of_enemies(e.position + Vector2(80, 0))
	var kept: Vector2 = r._clear_zone_of_enemies(e.position + Vector2(want, 0))
	_check("安全区避开当前敌人（贴图留间隙）", nudged.distance_to(e.position) >= want - 1.0,
		"d=%.0f want=%.0f" % [nudged.distance_to(e.position), want])
	_check("已经够远的安全区点不被挪动", kept.distance_to(e.position + Vector2(want, 0)) < 1.0)
	_kill(r)

func _test_shop_binding() -> void:
	var r := _new_run(126)
	_clear_arena(r)
	r.depth = 1
	var old_pos := Vector2(3000, 0)
	r.shop_zone = r.make_zone("shop", old_pos)
	r.shop_bound_depth = 1
	var e1 := _make_enemy(r, Vector2(0, -1000))
	r.kill_enemy(e1)
	_check("商店所属敌人被击败后不立即刷新",
		r.depth == 2 and r.shop_zone != null and r.shop_zone.position.distance_to(old_pos) < 1.0)
	var e2 := _make_enemy(r, Vector2(0, -1200))
	r.kill_enemy(e2)
	_check("击败下一个敌人后商店自动重新生成",
		r.depth == 3 and r.shop_zone != null and r.shop_zone.position.distance_to(old_pos) > 100.0,
		"depth=%d d=%.0f" % [r.depth, r.shop_zone.position.distance_to(old_pos) if r.shop_zone != null else -1.0])
	_check("重新生成的商店绑定到新深度", r.shop_bound_depth == 3 and r.route.next_shop >= 1)
	_kill(r)

## The reported bug: a safe zone or an enemy could be born inside / hugging a
## celestial body.  Test both directions: content avoids loaded bodies, and
## bodies avoid live/planned content.
func _test_body_clearance() -> void:
	var r := _new_run(121)
	_clear_arena(r)
	r.ship.position = Vector2.ZERO
	var ep: Vector2 = r.route.enemy_at(0)
	r.new_gravity_body(ep, 800.0, "star", 1)
	r.spawn_enemy()
	var e: Enemy = r.current_enemy
	var need_e: float = 800.0 + e.radius + EG.BODY_CONTENT_MARGIN
	_check("敌人不会生成在天体内部或贴脸", e != null and e.position.distance_to(ep) >= need_e - 1.0,
		"d=%.0f need=%.0f" % [e.position.distance_to(ep) if e != null else -1.0, need_e])
	_check("敌人生成点完全在天体表面之外",
		e != null and not r.galaxy.is_inside_any_body(e.position, e.radius + EG.BODY_CONTENT_MARGIN - 0.5))
	_kill(r)

	var r2 := _new_run(122)
	_clear_arena(r2)
	r2.ship.position = Vector2.ZERO
	var sp: Vector2 = r2.route.safe_at(0)
	r2.new_gravity_body(sp, 300.0, "planet", 1)
	r2._spawn_safe_respawn()
	var z: Zone = r2.safe_zone
	var need_z: float = 300.0 + EG.ZONE_RADIUS + EG.BODY_CONTENT_MARGIN
	_check("安全区不会生成在天体内部或贴脸", z != null and z.position.distance_to(sp) >= need_z - 1.0,
		"d=%.0f need=%.0f" % [z.position.distance_to(sp) if z != null else -1.0, need_z])
	_check("安全区完整落在天体表面之外",
		z != null and not r2.galaxy.is_inside_any_body(z.position, EG.ZONE_RADIUS + EG.BODY_CONTENT_MARGIN - 0.5))
	_kill(r2)

	var r3 := _new_run(123)
	_clear_arena(r3)
	r3.ship.position = Vector2.ZERO
	var shp: Vector2 = r3.route.shop_at(0)
	r3.new_gravity_body(shp, 300.0, "planet", 1)
	r3._spawn_shop_respawn()
	var s: Zone = r3.shop_zone
	_check("商店不会生成在天体内部或贴脸", s != null and s.position.distance_to(shp) >= need_z - 1.0,
		"d=%.0f need=%.0f" % [s.position.distance_to(shp) if s != null else -1.0, need_z])
	_kill(r3)

	var r4 := _new_run(124)
	_clear_arena(r4)
	var zpos := Vector2(4000, 0)
	r4.safe_zone = r4.make_zone("safe", zpos)
	_check("新天体不会生成在安全区上", not r4.galaxy.body_fits(zpos, 300.0, 400.0, true))
	_check("天体最终落地校验拒绝内容区", r4.galaxy._add_body(zpos, 300.0, "planet", 1, false) == null)
	_check("安全区之外仍能落天体", r4.galaxy.body_fits(Vector2(100000, 100000), 300.0, 400.0, true))
	_check("路线预置安全点预留了天体空间", not r4.galaxy.body_fits(r4.route.safe_at(1), 300.0, 400.0, true))
	_check("玩家所在位置不会突然生成天体", not r4.galaxy.body_fits(r4.ship.position + Vector2(500, 0), 300.0, 400.0, true))
	_kill(r4)

func _test_initial_map() -> void:
	var r := _new_run(116)
	r.test_mode = false
	r._initial_spawn()
	var route: RunRoute = r.galaxy.route
	_check("出生点没有安全区", r.safe_zone == null and not r.safe_unlocked and route.next_safe == 0)
	_check("出生点直接生成敌人", r.current_enemy != null)
	_check("初始商店落在路线预置点", r.shop_zone != null and r.shop_zone.position.distance_to(route.shop_at(0)) < 1500.0)
	_check("初始商店绑定到当前敌人深度", r.shop_bound_depth == 1)
	var init_d: float = -1.0
	if r.current_enemy != null:
		init_d = r.current_enemy.position.distance_to(route.enemy_at(0))
	_check("首个敌人落在路线预置点", init_d >= 0.0 and init_d < 2200.0, "d=%.0f" % init_d)
	_check("地图生成时填充了物质", r.matters.size() > 50, "matter=%d" % r.matters.size())
	# First kill unlocks the safe zone, skipping the spawn-side safe node.
	var first_safe: Vector2 = route.safe_at(0)
	var e: Enemy = r.current_enemy
	r.kill_enemy(e)
	_check("击毁首个敌人后解锁安全区", r.safe_unlocked and absf(r.safe_respawn_timer - EG.ZONE_RESPAWN) < 0.01)
	_check("解锁时跳过出生点旁的安全区节点", route.next_safe == 1 and route.safe_at(1) != first_safe)
	r._spawn_safe_respawn()
	_check("解锁后的安全区出现在前方路线节点", r.safe_zone != null and
		r.safe_zone.position.distance_to(route.safe_at(1)) < 1500.0)
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
	r.no_stream = true
	_clear_arena(r)
	for b in r.galaxy.bodies.duplicate():
		b.remove()
	r.galaxy.bodies.clear()
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
		var to_target := target - r.ship.position
		var want_speed: float = clampf(to_target.length() * 2.2, 0.0, EG.SHIP_MAX_SPEED)
		var want_vel: Vector2 = to_target.normalized() * want_speed
		var input := (want_vel - r.ship.vel)
		if input.length() < 0.01:
			input = to_target
		input = input.normalized()
		if r.ship.position.distance_to(e.position) < e.radius + 90.0:
			input = (r.ship.position - e.position).normalized()
		var danger := false
		var in_pulse_range := false
		for m in r.missiles:
			if not m.dead and m.position.distance_to(r.ship.position) < 360.0:
				danger = true
			# 贴脸才脉冲：过早释放会把导弹推离“绕圈诱导”的弧线。
			# 未发现阶段的偷袭弹不参与脉冲，避免把直射诱导弹一起推走。
			if not m.dead and not m.sneak and m.position.distance_to(r.ship.position) < 120.0:
				in_pulse_range = true
		# Keep the bot out of celestial bodies now that gravity pulls much
		# harder than in the 2 R well.
		var body_dodge := Vector2.ZERO
		for b in r.galaxy.bodies:
			var gap: float = r.ship.position.distance_to(b.position) - b.radius
			if gap < 320.0:
				body_dodge += (r.ship.position - b.position).normalized() * (1.0 - maxf(gap, 0.0) / 320.0)
		if body_dodge.length() > 0.01:
			input = (input * 0.4 + body_dodge.normalized() * 1.6).normalized()
		r.auto_input = input
		r.auto_boost = danger and r.ship.boost_meter > 0.4
		if r.skills.size() > 0 and float(r.skills[0]["cd"]) <= 0.0 and in_pulse_range:
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
