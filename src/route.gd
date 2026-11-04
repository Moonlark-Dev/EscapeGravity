class_name RunRoute
extends RefCounted
## Hidden map-generation route.  The galaxy is generated first, then a single
## forward-only polyline is laid through it; shops, safe zones and enemies are
## pre-placed relative to that polyline.  The route is never rendered and does
## not constrain the player — it is only the layout skeleton of a run.
##
## Every leg:
##   * turns less than 90 degrees from the previous leg (never doubles back),
##   * keeps moving along the initial forward axis (route order is meaningful),
##   * has a planet anchor near its middle so the route passes a gravity well,
##     and some legs put that anchor directly in the blank path between the two
##     enemies as a slingshot instead of off to the side,
##   * has one safe zone midway between the previous and the next enemy, clear
##     of both sprites,
##   * has a shop further away from the line than that safe zone.

const CHUNK := 2048.0                  # must match Galaxy.CHUNK
const PLAN_AHEAD := 12                 # encounters generated up front
const FIRST_LEG_MIN := 1900.0          # first enemy stays in the old spawn band
const FIRST_LEG_MAX := 2400.0
const LEG_MIN := 2100.0
const LEG_MAX := 2700.0
const MAX_TURN := 0.55                 # ~31.5 deg per leg
const FORWARD_DOT := 0.35              # every leg keeps advancing along `forward`
## The safe zone sits at the midpoint of a leg so it is as far as possible
## from both adjacent enemy nodes, and the lateral offset pushes it off the
## line as well.  With LEG_MIN=2100 / SAFE_OFFSET_MIN=470 the planned distance
## to either neighbour is >= 1150, i.e. >=450px between the safe zone sprite
## (R280) and a turret sprite (R420) — a safe zone no longer opens right next
## to the attacker the player is still fighting.  The first leg has no previous
## enemy, so its zone stays early and clears the first attacker instead.
const SAFE_T := 0.50                   # where the safe zone sits along a leg
const SAFE_FIRST_T := 0.35             # ... and on the first leg (start -> enemy 0)
const SAFE_OFFSET_MIN := 470.0
const SAFE_OFFSET_MAX := 600.0
const SHOP_T := 0.72
const SHOP_OFFSET_MIN := 1200.0        # clearly farther out than the safe zone
const SHOP_OFFSET_MAX := 1600.0
const BODY_T := 0.50
const BODY_OFFSET_MIN := 380.0         # inside the anchor planet's 3R influence
const BODY_OFFSET_MAX := 480.0
const BODY_RADIUS_MIN := 260.0
const BODY_RADIUS_MAX := 340.0
## Some legs put their gravity anchor directly in the blank path between the
## two enemies, so a straight run can be turned into a slingshot.  The body is
## smaller than a normal anchor and only takes the slot when it clears the safe
## zone, shop and both enemy hulls; otherwise the leg falls back to the side
## anchor above.
const PATH_BODY_CHANCE := 0.42
const PATH_BODY_T_MIN := 0.56
const PATH_BODY_T_MAX := 0.78
const PATH_BODY_OFFSET_MAX := 160.0
const PATH_BODY_RADIUS_MIN := 140.0
const PATH_BODY_RADIUS_MAX := 180.0
const BODY_PAD := 260.0
const SELF_CLEAR := 900.0              # keep new legs away from old ones

var rng := RandomNumberGenerator.new()
var seed_value := 0
var origin := Vector2.ZERO
var forward := Vector2.RIGHT           # main axis; route can never go backwards
var points: Array = []                 # origin + one point per enemy
var encounters: Array = []             # ordered [{enemy,safe,shop,body,...}]
var next_enemy := 0                    # next planned enemy node to consume
var next_safe := 0                     # next planned safe zone to consume
var next_shop := 0                     # next planned shop to consume
var _last_pos := Vector2.ZERO
var _last_dir := Vector2.RIGHT

func _init(p_seed: int, p_origin: Vector2) -> void:
	seed_value = p_seed
	origin = p_origin
	rng.seed = p_seed ^ 0x5f3759df
	forward = Vector2.RIGHT.rotated(rng.randf() * TAU)
	_last_pos = origin
	_last_dir = forward
	points = [origin]
	ensure_ahead(PLAN_AHEAD - 1)

## Makes sure encounters[0..index] exist.  Called with a rolling horizon so
## long runs keep getting the same pre-generated layout.
func ensure_ahead(index: int) -> bool:
	var grew := false
	while encounters.size() <= index:
		_append_leg()
		grew = true
	return grew

func _append_leg() -> void:
	var first := encounters.is_empty()
	var leg := rng.randf_range(FIRST_LEG_MIN, FIRST_LEG_MAX) if first else rng.randf_range(LEG_MIN, LEG_MAX)
	var dir := _choose_dir()
	var enemy := _last_pos + dir * leg
	# A lazy self-intersection guard: if the endpoint lands too close to an
	# older leg, swing once toward the main axis.
	for i in range(1, points.size()):
		if _dist_to_segment(enemy, points[i - 1], points[i]) < SELF_CLEAR:
			dir = (_last_dir + forward).normalized()
			enemy = _last_pos + dir * leg
			break
	var side := 1.0 if rng.randf() < 0.5 else -1.0
	var perp: Vector2 = dir.orthogonal() * side
	var safe_t := SAFE_FIRST_T if first else SAFE_T
	var safe := _last_pos + dir * (leg * safe_t) + perp * rng.randf_range(SAFE_OFFSET_MIN, SAFE_OFFSET_MAX)
	var shop := _last_pos + dir * (leg * SHOP_T) + perp * rng.randf_range(SHOP_OFFSET_MIN, SHOP_OFFSET_MAX)
	var body := _make_route_body(_last_pos, dir, leg, perp, safe, shop, enemy)
	encounters.append({
		"enemy": enemy,
		"safe": safe,
		"shop": shop,
		"body": body,
	})
	points.append(enemy)
	_last_pos = enemy
	_last_dir = dir

## The single gravity anchor for a leg.  Most legs keep the doc's side anchor
## (opposite the safe zone, 380~480 px off the line); some try to place a
## smaller body right in the blank path between the enemies.  The path body is
## only accepted when it clears both enemies, the safe zone, the shop and every
## previously planned route body, so it never crowds another planned node.
func _make_route_body(prev: Vector2, dir: Vector2, leg: float, perp: Vector2,
		safe: Vector2, shop: Vector2, enemy: Vector2) -> Dictionary:
	if rng.randf() < PATH_BODY_CHANCE:
		for _i in range(16):
			var t := rng.randf_range(PATH_BODY_T_MIN, PATH_BODY_T_MAX)
			var r := rng.randf_range(PATH_BODY_RADIUS_MIN, PATH_BODY_RADIUS_MAX)
			var p := prev + dir * (leg * t) + perp * rng.randf_range(-PATH_BODY_OFFSET_MAX, PATH_BODY_OFFSET_MAX)
			if _route_body_clear(p, r, safe, shop, prev, enemy):
				return _body_dict(p, r, true)
	var bp := prev + dir * (leg * BODY_T) - perp * rng.randf_range(BODY_OFFSET_MIN, BODY_OFFSET_MAX)
	var br := rng.randf_range(BODY_RADIUS_MIN, BODY_RADIUS_MAX)
	return _body_dict(bp, br, false)

func _body_dict(p: Vector2, r: float, path: bool) -> Dictionary:
	return {
		"pos": p,
		"radius": r,
		"variant": rng.randi_range(1, 3),
		"chunk": Vector2i(floori(p.x / CHUNK), floori(p.y / CHUNK)),
		"path": path,
	}

func _route_body_clear(p: Vector2, r: float, safe: Vector2, shop: Vector2,
		prev: Vector2, enemy: Vector2) -> bool:
	var zone_need: float = EG.ZONE_RADIUS + r + EG.BODY_CONTENT_MARGIN
	if p.distance_to(safe) < zone_need or p.distance_to(shop) < zone_need:
		return false
	var enemy_need: float = EG.TURRET_RADIUS + r + EG.BODY_CONTENT_MARGIN
	if p.distance_to(prev) < enemy_need or p.distance_to(enemy) < enemy_need:
		return false
	for enc in encounters:
		if p.distance_to(enc["safe"]) < zone_need:
			return false
		if p.distance_to(enc["shop"]) < zone_need:
			return false
		if p.distance_to(enc["enemy"]) < enemy_need:
			return false
		var ab: Dictionary = enc["body"]
		if p.distance_to(ab["pos"]) < float(ab["radius"]) + r + BODY_PAD:
			return false
	return true

func _choose_dir() -> Vector2:
	var dir := _last_dir.rotated(rng.randf_range(-MAX_TURN, MAX_TURN))
	# Hard no-backtracking: every leg must keep advancing along the main axis.
	var limit := acos(FORWARD_DOT)
	if dir.dot(forward) < FORWARD_DOT:
		dir = forward.rotated(clampf(forward.angle_to(dir), -limit, limit))
	# And it must not reverse the previous leg either.
	if dir.dot(_last_dir) < 0.15:
		dir = (_last_dir + forward).normalized()
	return dir.normalized()

func _dist_to_segment(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var l2 := ab.length_squared()
	if l2 < 0.001:
		return p.distance_to(a)
	var t := clampf((p - a).dot(ab) / l2, 0.0, 1.0)
	return p.distance_to(a + ab * t)

# ---- accessors (all keep the rolling horizon) ----

func enemy_at(index: int) -> Vector2:
	ensure_ahead(index)
	return encounters[index]["enemy"]

func safe_at(index: int) -> Vector2:
	ensure_ahead(index)
	return encounters[index]["safe"]

func shop_at(index: int) -> Vector2:
	ensure_ahead(index)
	return encounters[index]["shop"]

func body_anchors() -> Array:
	var out: Array = []
	for e in encounters:
		out.append(e["body"])
	return out

func body_anchors_in_chunk(c: Vector2i) -> Array:
	var out: Array = []
	for e in encounters:
		var b: Dictionary = e["body"]
		if b["chunk"] == c:
			out.append(b)
	return out
