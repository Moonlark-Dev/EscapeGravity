class_name Defs
extends RefCounted
## Static content tables: items, skills and the upgrade pool.

const RARITY := {
	"common": {"name": "普通", "color": Color("9fb4d0"), "weight": 40},
	"rare": {"name": "稀有", "color": Color("39e6ff"), "weight": 30},
	"epic": {"name": "史诗", "color": Color("c084fc"), "weight": 20},
	"legend": {"name": "传说", "color": Color("ffb347"), "weight": 6},
}

const ITEMS := {
	"fuel": {
		"name": "备用能源", "rarity": "rare", "icon": "icon_item_fuel",
		"desc": "立即恢复 60 点燃料。",
	},
	"repair": {
		"name": "护盾补片", "rarity": "common", "icon": "icon_item_repair",
		"desc": "立即修复 6 点护盾（不超过上限）。",
	},
	"flare": {
		"name": "干扰弹", "rarity": "rare", "icon": "icon_item_flare",
		"desc": "在飞船身后释放，把附近锁定你的导弹向两个斜前方甩开。",
	},
	"decoy": {
		"name": "诱饵弹", "rarity": "epic", "icon": "icon_item_decoy",
		"desc": "在飞船前方投出诱饵信标，锁定你的导弹会转火；导弹抵达信标后脱锁。信标受引力影响。",
	},
	"charge": {
		"name": "紧急充能装置", "rarity": "legend", "icon": "icon_item_charge",
		"desc": "立即回满加力槽。",
	},
	"revive": {
		"name": "复活币", "rarity": "legend", "icon": "icon_item_revive",
		"desc": "护盾归零时自动消耗，以 8 点护盾复活一次。",
	},
}

const ITEM_ORDER := ["fuel", "repair", "flare", "decoy", "charge", "revive"]

const SKILLS := {
	"pulse": {
		"name": "脉冲", "icon": "skill_pulse", "color": Color("39e6ff"),
		"cd": 5.0, "fuel": 10.0,
		"desc": "以飞船为圆心释放脉冲：范围内导弹脱锁，并获得 200 的切线冲量（±15°）。",
		"levels": [
			"半径 300，冲量 200",
			"半径 345，冲量 230",
			"半径 390，冲量 260",
		],
	},
	"anchor": {
		"name": "引力锚", "icon": "skill_gravity", "color": Color("8b5cf6"),
		"cd": 9.0, "fuel": 15.0,
		"desc": "在飞船前方投放一个持续 4 秒的引力源，把导弹拉向它。",
		"levels": [
			"半径 420，持续 4 秒",
			"半径 500，持续 5 秒",
			"半径 580，持续 6 秒",
		],
	},
	"dash": {
		"name": "相位滑行", "icon": "skill_dash", "color": Color("5cf2a8"),
		"cd": 7.0, "fuel": 12.0,
		"desc": "向移动方向（无输入时朝面向）瞬间加速，留下相位残影。",
		"levels": [
			"冲刺速度 430，持续 0.22 秒",
			"冲刺速度 500，持续 0.26 秒",
			"冲刺速度 570，持续 0.30 秒",
		],
	},
	"beacon": {
		"name": "诱饵信标", "icon": "skill_decoy", "color": Color("ff3d81"),
		"cd": 11.0, "fuel": 16.0,
		"desc": "向前投放一个诱饵信标，锁定你的导弹会转火到信标。",
		"levels": [
			"信标持续 6 秒",
			"信标持续 8 秒",
			"信标持续 10 秒",
		],
	},
}

const SKILL_ORDER := ["pulse", "anchor", "dash", "beacon"]

const UPGRADES := {
	"repair_25": {"title": "应急修复", "desc": "恢复 25% 护盾。", "rarity": "common", "icon": "icon_shield"},
	"repair_full": {"title": "护盾重构", "desc": "把护盾完全充满。", "rarity": "rare", "icon": "icon_shield"},
	"fuel_25": {"title": "补充燃料", "desc": "恢复 25% 燃料。", "rarity": "common", "icon": "icon_fuel"},
	"fuel_max_10": {"title": "燃料罐扩容", "desc": "燃料上限 +10（同时补满）。", "rarity": "common", "icon": "icon_fuel"},
	"fuel_max_20": {"title": "副油箱", "desc": "燃料上限 +20（同时补满）。", "rarity": "rare", "icon": "icon_fuel"},
	"slot": {"title": "物品栏扩建", "desc": "物品栏 +1 格（最多 5 格）。", "rarity": "rare", "icon": "icon_inventory"},
	"token_1": {"title": "代币", "desc": "获得 1 枚代币。", "rarity": "common", "icon": "icon_token"},
	"token_2": {"title": "代币包", "desc": "获得 2 枚代币。", "rarity": "rare", "icon": "icon_token"},
	"token_3": {"title": "代币箱", "desc": "获得 3 枚代币。", "rarity": "epic", "icon": "icon_token"},
	"boost_cap": {"title": "加力槽扩容", "desc": "加力槽上限 +10%。", "rarity": "common", "icon": "icon_boost"},
	"boost_power": {"title": "加力喷口", "desc": "加力推力 +7%。", "rarity": "common", "icon": "icon_boost"},
	"item": {"title": "获得道具", "desc": "随机获得一件道具（物品栏满时需要丢弃一件）。", "rarity": "rare", "icon": "icon_inventory"},
	"skill_new": {"title": "新技能", "desc": "解锁一个技能，填入空技能槽。", "rarity": "rare", "icon": "icon_skill"},
	"skill_up": {"title": "技能强化", "desc": "强化一个已拥有的技能。", "rarity": "common", "icon": "icon_skill"},
}

static func rarity_color(rarity: String) -> Color:
	var r = RARITY.get(rarity, RARITY["common"])
	return r["color"]

static func item_rarity_color(id: String) -> Color:
	var it = ITEMS.get(id, {})
	return rarity_color(it.get("rarity", "common"))

## Roll three upgrade cards. `run` is duck-typed (needs inventory_size/max,
## skills array, shield/fuel values).
static func roll_upgrades(run, rng: RandomNumberGenerator) -> Array:
	var weights := {}
	weights["repair_25"] = 12.0 if run.ship.shield < run.ship.shield_max * 0.98 else 2.0
	weights["repair_full"] = 5.0 if run.ship.shield < run.ship.shield_max * 0.9 else 0.8
	# 安全区进站瞬间就把燃料补满（见 Run._enter_safe），满油时这张卡收益为 0，
	# 不能再塞进面板；只有在圈内又烧掉燃料后才重新有资格出现。
	weights["fuel_25"] = 12.0 if run.ship.fuel < run.ship.fuel_max * 0.98 else 0.0
	weights["fuel_max_10"] = 9.0
	weights["fuel_max_20"] = 5.0
	# 扩建卡看的是“栏位还能不能再扩”（与背包是否装满无关）；背包越满越值得出现。
	var slot_weight := 0.0
	if run.item_slots < EG.ITEM_SLOTS_MAX:
		slot_weight = 10.0 if run.inventory.size() >= run.item_slots else 6.0
	weights["slot"] = slot_weight
	weights["token_1"] = 10.0
	weights["token_2"] = 5.0
	weights["token_3"] = 2.0
	weights["boost_cap"] = 9.0
	weights["boost_power"] = 9.0
	weights["item"] = 11.0
	weights["skill_new"] = 10.0 if run.skills.size() < EG.SKILL_SLOTS and run.unowned_skills().size() > 0 else 0.0
	weights["skill_up"] = 12.0 if run.upgradable_skills().size() > 0 else 0.0

	var picked: Array = []
	var picked_ids: Array = []
	var keys: Array = weights.keys()
	for i in range(3):
		var total := 0.0
		for k in keys:
			# 权重为 0 的卡是“当前没有任何收益”（满油、栏位已满等），一律不进卡池。
			if picked_ids.has(k) or float(weights[k]) <= 0.0:
				continue
			total += float(weights[k])
		if total <= 0.0:
			break
		var r := rng.randf() * total
		var chosen = ""
		for k in keys:
			if picked_ids.has(k) or float(weights[k]) <= 0.0:
				continue
			r -= float(weights[k])
			if r <= 0.0:
				chosen = k
				break
		if chosen == "":
			break
		picked_ids.append(chosen)
		var card: Dictionary = UPGRADES[chosen].duplicate(true)
		card["id"] = chosen
		# Resolve concrete payload for item / skill cards.
		if chosen == "item":
			var item_id: String = _roll_item(rng)
			card["item_id"] = item_id
			card["title"] = ITEMS[item_id]["name"]
			card["desc"] = "获得 " + ITEMS[item_id]["name"] + "：" + ITEMS[item_id]["desc"]
			card["rarity"] = ITEMS[item_id]["rarity"]
			card["icon"] = ITEMS[item_id]["icon"]
		elif chosen == "skill_new":
			var pool: Array = run.unowned_skills()
			var sid: String = pool[rng.randi_range(0, pool.size() - 1)]
			card["skill_id"] = sid
			card["title"] = "解锁技能：" + SKILLS[sid]["name"]
			card["desc"] = SKILLS[sid]["desc"]
		elif chosen == "skill_up":
			var sid2: String = run.upgradable_skills()[rng.randi_range(0, run.upgradable_skills().size() - 1)]
			card["skill_id"] = sid2
			card["title"] = "强化技能：" + SKILLS[sid2]["name"]
			card["desc"] = "技能等级 +1。"
		picked.append(card)
	return picked

static func _roll_item(rng: RandomNumberGenerator) -> String:
	var total := 0.0
	for id in ITEM_ORDER:
		total += float(RARITY[ITEMS[id]["rarity"]]["weight"])
	var r := rng.randf() * total
	for id in ITEM_ORDER:
		r -= float(RARITY[ITEMS[id]["rarity"]]["weight"])
		if r <= 0.0:
			return id
	return "fuel"
