class_name Missile
extends Node2D
## Enemy ammo. Five flavours share the same node:
##   normal   150 px/s, 0.525 rad/s, 5 s lock, then flies straight
##   booster  1.8 s of slow high-turn calibration, then a 340 px/s lance
##   cluster  splits into 3 unguided frags when its lock timer expires
##   frag     one of those frags: fast, unguided, 12 damage
##   mine     slow unguided mine; pulse can bat it back into its owner
## Missiles have no operation assist: celestial gravity always applies.

var run
var kind := "normal"
var vel := Vector2.ZERO
var angle := 0.0
var speed := EG.MISSILE_SPEED
var base_speed := EG.MISSILE_SPEED
var dmg := EG.MISSILE_DMG_ENEMY
var locked := true
var lock_timer := 0.0
var seen := false
var life := 0.0
var target := "ship"
var decoy = null
var source: Node2D = null
## 连锁殉爆 / 共振奇点会把脱锁弹吸向某个敌人：不是重新锁定，只是额外转向。
var chain: Node2D = null
## True for a missile launched by an undiscovered attacker.
var sneak := false
var dead := false
var pull := Vector2.ZERO
var _age := 0.0
var _ignited := false
var _sprite: Sprite2D
var _base_mod := Color(1.0, 1.0, 1.0, 1.0)
var _glow: Sprite2D
var _trail: CPUParticles2D
var _t := 0.0
var _warn: Sprite2D

func _ready() -> void:
	z_index = 15
	_glow = Assets.world_sprite("ship_glow", true)
	_glow.modulate = Color(1.0, 0.35, 0.25, 0.55)
	add_child(_glow)
	match kind:
		"booster":
			speed = EG.BOOSTER_SLOW_SPEED
			_sprite = Assets.world_sprite("missile_booster")
			_glow.scale = Vector2.ONE * 0.40
			_glow.modulate = Color(1.0, 0.45, 0.2, 0.6)
		"mine":
			speed = EG.MINE_SPEED
			dmg = EG.MINE_DMG_ENEMY
			_sprite = Assets.world_sprite("mine")
			_glow.scale = Vector2.ONE * 0.34
			_glow.modulate = Color(0.8, 0.35, 1.0, 0.5)
		"frag":
			speed = EG.CLUSTER_FRAG_SPEED
			dmg = EG.CLUSTER_FRAG_DMG
			_sprite = Assets.world_sprite("missile")
			_sprite.scale = Vector2.ONE * 0.62
			_sprite.modulate = Color(1.0, 0.7, 0.45)
			_glow.scale = Vector2.ONE * 0.22
			_glow.modulate = Color(1.0, 0.65, 0.3, 0.5)
		"cluster":
			_sprite = Assets.world_sprite("missile")
			_sprite.modulate = Color(1.0, 0.82, 0.55)
			_glow.scale = Vector2.ONE * 0.34
			_glow.modulate = Color(1.0, 0.6, 0.25, 0.6)
		_:
			_sprite = Assets.world_sprite("missile")
			_glow.scale = Vector2.ONE * 0.28
	if kind == "mine":
		_glow.scale = Vector2.ONE * 0.7
	add_child(_sprite)
	_base_mod = _sprite.modulate
	base_speed = speed
	_warn = Assets.world_sprite("missile_warn", true)
	_warn.scale = Vector2.ONE * 0.7
	_warn.modulate = Color(1.0, 0.3, 0.25, 0.0)
	add_child(_warn)
	_trail = CPUParticles2D.new()
	_trail.texture = Assets.world("spark")
	_trail.amount = 10 if kind == "mine" else 18
	_trail.lifetime = 0.34
	_trail.local_coords = false
	_trail.emission_shape = CPUParticles2D.EMISSION_SHAPE_POINT
	_trail.direction = Vector2.LEFT
	_trail.spread = 12.0 if kind == "mine" else 10.0
	_trail.initial_velocity_min = 8.0
	_trail.initial_velocity_max = 34.0
	_trail.scale_amount_min = 0.14
	_trail.scale_amount_max = 0.32
	_trail.color = trail_color()
	_trail.emitting = true
	_trail.material = Assets.additive_material()
	add_child(_trail)

func trail_color() -> Color:
	match kind:
		"booster":
			return Color(1.0, 0.75, 0.35, 0.65) if _ignited else Color(1.0, 0.55, 0.3, 0.45)
		"mine":
			return Color(0.8, 0.4, 1.0, 0.55)
		"frag":
			return Color(1.0, 0.7, 0.35, 0.55)
		"cluster":
			return Color(1.0, 0.6, 0.25, 0.55)
		_:
			return Color(1.0, 0.55, 0.3, 0.55)

func life_limit() -> float:
	match kind:
		"mine":
			return EG.MINE_LIFE
		"frag":
			return EG.CLUSTER_FRAG_LIFE
		_:
			return EG.MISSILE_LIFE

func turn_rate() -> float:
	match kind:
		"booster":
			return EG.BOOSTER_FAST_TURN if _ignited else EG.BOOSTER_SLOW_TURN
		"frag", "mine":
			return 0.0
		_:
			return EG.MISSILE_TURN

func step(delta: float) -> void:
	_t += delta
	_age += delta
	life += delta
	if life > life_limit():
		dead = true
		return

	_update_booster()

	if not seen and run != null and run.is_on_screen(position):
		seen = true
	if locked and seen:
		lock_timer += delta
		if lock_timer >= EG.MISSILE_LOCK_TIME:
			if kind == "cluster":
				_split()
				return
			unlock()

	# Missiles have no operation assist: celestial gravity always applies, even
	# while locked. Guidance only wins where its turn rate can out-turn it.
	var g: Vector2 = run.gravity_at(position) * EG.MISSILE_GRAVITY_SCALE if run != null else Vector2.ZERO
	if locked:
		var cur := vel.angle()
		var tpos: Vector2 = run.target_position(self)
		var desired := (tpos - position).angle()
		var diff := wrapf(desired - cur, -PI, PI)
		# 锁定期把敌人外壳当障碍：绕飞优先于直线追踪，否则玩家绕圈时
		# 导弹会从敌人正中间穿过去（以前只有出生点的短暂偏转，且方向算反）。
		var avoid := _avoidance_steer(cur)
		if avoid != 0.0:
			diff = avoid
		var max_step := turn_rate() * delta
		var steer := clampf(diff, -max_step, max_step)
		if pull.length() > 1.0:
			var pa := wrapf(pull.angle() - (cur + steer), -PI, PI)
			steer += clampf(pa, -1.15 * delta, 1.15 * delta)
		vel = Vector2.RIGHT.rotated(cur + steer) * speed + g * delta
		if vel.length() > 0.1:
			angle = vel.angle()
			vel = vel.normalized() * speed
	else:
		vel += (g + pull) * delta
		if chain != null and is_instance_valid(chain) and not chain.dead:
			# 被吸向敌人：不是重新锁定，只是给一个额外的转向偏置。
			var want := (chain.position - position).angle()
			var diff2 := wrapf(want - vel.angle(), -PI, PI)
			var step2 := clampf(diff2, -1.7 * delta, 1.7 * delta)
			vel = vel.rotated(step2)
		if vel.length() > 1.0:
			angle = vel.angle()

	position += vel * delta
	if locked:
		_resolve_hull_penetration()
	rotation = angle
	_trail.emitting = locked or kind == "mine"
	_glow.modulate.a = (0.45 + 0.15 * sin(_t * 12.0)) if locked else 0.15
	if _warn != null:
		_warn.visible = kind != "mine" and kind != "frag"
		_warn.modulate.a = (0.30 + 0.18 * sin(_t * 9.0)) if locked and seen else 0.0
		_warn.rotation = -angle + _t * 0.6
	_sprite.modulate = _base_mod if locked else _base_mod.darkened(0.18)

## 锁定中的导弹把每艘敌舰的外壳当成实体障碍：如果当前航向在绕飞提前量内
## 会擦进外壳，就改朝“绕外壳的切线”转向，返回相对当前航向的转向量；
## 没有威胁时返回 0，交回正常的追踪逻辑。
func _avoidance_steer(cur: float) -> float:
	if run == null or run.enemies.is_empty():
		return 0.0
	var fwd := Vector2.RIGHT.rotated(cur)
	var best := 0.0
	var best_urgency := 0.0
	for e in run.enemies:
		if e == null or not is_instance_valid(e) or e.dead:
			continue
		var rel: Vector2 = position - e.position
		var dist := rel.length()
		var hull: float = e.radius + EG.MISSILE_RADIUS
		if dist > hull + EG.MISSILE_AVOID_LOOKAHEAD:
			continue
		var to_e := -rel
		# 贴着外壳或已经进入外壳时强制修正；离得还远则只在航向真的
		# 会擦进外壳时才绕飞，不从敌人旁边经过时也乱绕。
		if dist > hull:
			if fwd.dot(to_e) <= 0.0:
				continue
			var perp := absf(fwd.cross(to_e))
			if perp > hull + EG.MISSILE_AVOID_MARGIN:
				continue
		var tangent := rel.orthogonal()
		if tangent.dot(fwd) < 0.0:
			tangent = -tangent
		var off := wrapf(tangent.angle() - cur, -PI, PI)
		var urgency := 1.0 - clampf((dist - hull) / maxf(EG.MISSILE_AVOID_LOOKAHEAD, 1.0), 0.0, 1.0)
		if urgency > best_urgency:
			best_urgency = urgency
			best = off
	return best

## 硬约束：锁定期弹体不能进入敌舰外壳。真的贴上就把位置推回表面，并把
## 撞向舰体的速度分量改成沿切线的滑行速度——表现为贴着外壳绕飞。
func _resolve_hull_penetration() -> void:
	if run == null:
		return
	for e in run.enemies:
		if e == null or not is_instance_valid(e) or e.dead:
			continue
		var rel: Vector2 = position - e.position
		var dist := rel.length()
		var min_d: float = e.radius + EG.MISSILE_RADIUS - EG.MISSILE_AVOID_INSET
		if dist >= min_d:
			continue
		var n: Vector2 = rel / dist if dist > 0.001 else Vector2.RIGHT.rotated(vel.angle() + PI)
		position = e.position + n * min_d
		var inward: float = -vel.dot(n)
		if inward > 0.0:
			vel += n * inward
		if vel.length() < 1.0:
			var slide: Vector2 = n.orthogonal()
			if slide.dot(vel) < 0.0:
				slide = -slide
			vel = slide
		vel = vel.normalized() * speed
		angle = vel.angle()

## 二段加速弹：前 1.8 秒低速高转向校准，之后点火飙到 340 px/s 但角速度暴跌。
func _update_booster() -> void:
	if kind != "booster":
		return
	var fast: bool = _age >= EG.BOOSTER_IGNITE_TIME
	if fast == _ignited:
		return
	_ignited = fast
	if fast:
		speed = EG.BOOSTER_FAST_SPEED
		_glow.modulate = Color(1.0, 0.65, 0.25, 0.85)
		_glow.scale = Vector2.ONE * 0.55
		_trail.color = trail_color()
		if run != null:
			Fx.warp(run.fx_layer, position, Color(1.0, 0.6, 0.25, 0.7))
			Fx.sparks(run.fx_layer, position, Color(1.0, 0.75, 0.35, 0.9), 10, 180.0)
			Audio.play("sfx_boost", -14.0)

## 子母分裂弹：锁定倒计时结束时不脱锁平飞，而是分裂成 3 枚扇形微型无锁弹头。
func _split() -> void:
	var base := vel.angle()
	var src = source
	remove()
	if run == null:
		return
	for i in range(EG.CLUSTER_FRAGS):
		var off: float = deg_to_rad(EG.CLUSTER_FRAG_SPREAD) * (float(i) - float(EG.CLUSTER_FRAGS - 1) * 0.5)
		run.spawn_cluster_frag(position, base + off, src)

func unlock() -> void:
	if not locked:
		return
	locked = false
	lock_timer = 0.0
	if run != null:
		run.on_missile_unlock(self)

func retarget_to(decoy_node) -> void:
	decoy = decoy_node
	target = "decoy"
	lock_timer = 0.0
	locked = true
	seen = true

func is_locked() -> bool:
	return locked

func remove() -> void:
	dead = true
	queue_free()
