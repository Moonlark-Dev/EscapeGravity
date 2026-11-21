class_name Defs
extends RefCounted
## Static content tables: items, skills, core mods, skill awakenings and the
## upgrade pool.

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
	"mine": {
		"name": "引力水雷", "rarity": "epic", "icon": "icon_item_mine",
		"desc": "原地布下一枚引力水雷：持续 3.5 秒把附近导弹吸成一团，消失时把它们甩向最近的敌人。",
	},
}

const ITEM_ORDER := ["fuel", "repair", "flare", "decoy", "charge", "revive", "mine"]

## 商店专属服务：不占背包格，购买即结算。
const SERVICES := {
	"service_repair": {
		"name": "现场满额维修", "icon": "icon_service", "rarity": "rare",
		"desc": "立刻把护盾补满，不占背包格。",
	},
	"service_full_boost": {
		"name": "应急加力灌注", "icon": "icon_boost", "rarity": "common",
		"desc": "立刻回满加力槽，不占背包格。",
	},
}

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

## 超载觉醒：技能 Lv3 之后才会进入升级池，二选一（或若干）分支。
const AWAKENINGS := {
	"pulse_fan": {
		"skill": "pulse", "name": "聚能扇面", "rarity": "legend",
		"desc": "脉冲不再向两侧平分推开，而是把范围内所有导弹统一推向飞船机头正前方。",
	},
	"pulse_stasis": {
		"skill": "pulse", "name": "零点静滞", "rarity": "epic",
		"desc": "脉冲半径扩至 480；波及敌人本体时打断其当前齐射并延长 1.5 秒过热。",
	},
	"dash_afterimage": {
		"skill": "dash", "name": "残影诱饵", "rarity": "epic",
		"desc": "相位滑行的起点自动留下一枚持续 3 秒的微型诱饵信标。",
	},
	"anchor_bipolar": {
		"skill": "anchor", "name": "双极锚定", "rarity": "legend",
		"desc": "引力锚消失瞬间产生一次微型脉冲，把吸拢成团的导弹沿切线高速甩出。",
	},
	"beacon_mirror": {
		"skill": "beacon", "name": "镜像双生", "rarity": "epic",
		"desc": "诱饵信标一次投放两枚（机身前后各一），诱饵数量翻倍。",
	},
}

const AWAKEN_ORDER := ["pulse_fan", "pulse_stasis", "dash_afterimage", "anchor_bipolar", "beacon_mirror"]

## 四大流派的核心改装（永久被动，单局可叠层）。
const MOD_SCHOOLS := {
	"gravity": {"name": "引力弹弓流", "icon": "icon_mod_gravity", "color": Color("39e6ff")},
	"deceive": {"name": "欺骗劫持流", "icon": "icon_mod_deceive", "color": Color("ff3d81")},
	"billiard": {"name": "星体台球流", "icon": "icon_mod_billiard", "color": Color("ffb347")},
	"trap": {"name": "陷阱阵列流", "icon": "icon_mod_trap", "color": Color("8b5cf6")},
}

const MODS := {
	"gravity_turbine": {
		"name": "引力涡轮", "school": "gravity", "rarity": "rare",
		"desc": "贴近行星环绕加速时，每秒恢复 3 点燃料与 25% 加力槽。",
	},
	"relativist": {
		"name": "相对论弹头", "school": "gravity", "rarity": "epic",
		"desc": "敌方导弹速度超过 200 后，每再快 50 px/s，对敌伤害 +8。",
	},
	"curvature_wake": {
		"name": "曲率尾流", "school": "gravity", "rarity": "rare",
		"desc": "飞船速度高于 350 时，物质吸收半径翻倍至 520，撞飞陨石的速度翻倍。",
	},
	"proximity_charge": {
		"name": "近炸增幅", "school": "deceive", "rarity": "epic",
		"desc": "锁定中的导弹在 130px 内脱锁时，弹体伤害翻倍并恢复 1.5 护盾。",
	},
	"inertia_hack": {
		"name": "惯性制导篡改", "school": "deceive", "rarity": "rare",
		"desc": "所有脱锁的导弹瞬间向最近的主敌人方向自动微偏 12°。",
	},
	"chain_detonation": {
		"name": "连锁殉爆", "school": "deceive", "rarity": "epic",
		"desc": "导弹命中敌人触发过热时，450px 内的其他导弹立刻脱锁并被吸向该敌人。",
	},
	"mass_driver": {
		"name": "质量投射器", "school": "billiard", "rarity": "epic",
		"desc": "脉冲也能把范围内的陨石高速轰飞；被撞飞/轰飞的陨石对敌伤害从 5 提升到 18。",
	},
	"trojan": {
		"name": "木马协议", "school": "billiard", "rarity": "epic",
		"desc": "脉冲不再让自杀无人机解体，而是把它们反向骇入、以 560 px/s 撞向主敌人造成 15 伤害。",
	},
	"gravity_belt": {
		"name": "引力碎星带", "school": "billiard", "rarity": "rare",
		"desc": "场上陨石刷新频率翻倍；玩家撞陨石不再掉护盾、也不再减速。",
	},
	"resonance": {
		"name": "共振奇点", "school": "trap", "rarity": "legend",
		"desc": "引力锚与诱饵信标重叠时形成聚变区：区内导弹速度 +60%、寿命刷新；信标结束时把它们甩向最近敌人。",
	},
	"recycle_reactor": {
		"name": "回收反应堆", "school": "trap", "rarity": "rare",
		"desc": "敌方导弹撞上敌人或天体爆炸时，所有技能冷却 -0.8 秒并返还 3 点燃料。",
	},
	"battlefield_ready": {
		"name": "战地整备", "school": "trap", "rarity": "epic",
		"desc": "使用任何消耗品后 3 秒内，加力不消耗加力槽与燃料。",
	},
}

const MOD_ORDER := [
	"gravity_turbine", "relativist", "curvature_wake",
	"proximity_charge", "inertia_hack", "chain_detonation",
	"mass_driver", "trojan", "gravity_belt",
	"resonance", "recycle_reactor", "battlefield_ready",
]

const UPGRADES := {
	"repair_25": {"title": "应急修复", "desc": "恢复 25% 护盾。", "rarity": "common", "icon": "icon_shield"},
	"repair_full": {"title": "护盾重构", "desc": "把护盾完全充满。", "rarity": "rare", "icon": "icon_shield"},
	"eco_cruise": {"title": "节能巡航", "desc": "引擎推进与技能油耗降低 12%（最多叠到 5 折）。", "rarity": "common", "icon": "icon_fuel"},
	"fuel_max_10": {"title": "燃料罐扩容", "desc": "燃料上限 +40（同时补满）。", "rarity": "common", "icon": "icon_fuel"},
	"fuel_max_20": {"title": "副油箱", "desc": "燃料上限 +80（同时补满）。", "rarity": "rare", "icon": "icon_fuel"},
	"slot": {"title": "物品栏扩建", "desc": "物品栏 +1 格（最多 5 格）。", "rarity": "rare", "icon": "icon_inventory"},
	"token_1": {"title": "代币", "desc": "获得 1 枚代币。", "rarity": "common", "icon": "icon_token"},
	"token_2": {"title": "代币包", "desc": "获得 2 枚代币。", "rarity": "rare", "icon": "icon_token"},
	"token_3": {"title": "代币箱", "desc": "获得 3 枚代币。", "rarity": "epic", "icon": "icon_token"},
	"boost_cap": {"title": "加力槽扩容", "desc": "加力槽上限 +10%。", "rarity": "common", "icon": "icon_boost"},
	"boost_power": {"title": "加力喷口", "desc": "加力推力 +7%。", "rarity": "common", "icon": "icon_boost"},
	"item": {"title": "获得道具", "desc": "随机获得一件道具（物品栏满时需要丢弃一件）。", "rarity": "rare", "icon": "icon_inventory"},
	"skill_new": {"title": "新技能", "desc": "解锁一个技能；技能槽已满时可替换一个已有技能。", "rarity": "rare", "icon": "icon_skill"},
	"skill_up": {"title": "技能强化", "desc": "强化一个已拥有的技能。", "rarity": "common", "icon": "icon_skill"},
	"mod_card": {"title": "核心改装", "desc": "获得一张永久被动改装芯片。", "rarity": "epic", "icon": "icon_mod_gravity"},
	"skill_awaken": {"title": "超载觉醒", "desc": "让一个 Lv3 技能觉醒新的形态。", "rarity": "legend", "icon": "icon_awaken"},
}

static func rarity_color(rarity: String) -> Color:
	var r = RARITY.get(rarity, RARITY["common"])
	return r["color"]

static func item_rarity_color(id: String) -> Color:
	var it = ITEMS.get(id, {})
	return rarity_color(it.get("rarity", "common"))

## 某个技能可选的超载觉醒分支（按 AWAKEN_ORDER 顺序）。
static func awaken_branches(skill_id: String) -> Array:
	var out: Array = []
	for aid in AWAKEN_ORDER:
		if str(AWAKENINGS[aid]["skill"]) == skill_id:
			out.append(aid)
	return out

static func mod_school_color(mod_id: String) -> Color:
	var m: Dictionary = MODS.get(mod_id, {})
	return MOD_SCHOOLS.get(m.get("school", "gravity"), MOD_SCHOOLS["gravity"])["color"]

## Roll three upgrade cards. `run` is duck-typed (needs ship, inventory, item
## slots, skills, mods and the helper lists).
static func roll_upgrades(run, rng: RandomNumberGenerator) -> Array:
	var weights := {}
	weights["repair_25"] = 12.0 if run.ship.shield < run.ship.shield_max * 0.98 else 2.0
	weights["repair_full"] = 5.0 if run.ship.shield < run.ship.shield_max * 0.9 else 0.8
	# 节能巡航取代了“恢复 25% 燃料”：进站必满油，燃料卡是废卡；油耗折扣
	# 才是真正和 500 基础池挂钩的续航强化，叠到 5 折为止。
	weights["eco_cruise"] = 11.0 if run.ship.fuel_cost_mult > EG.ECO_CRUISE_MIN + 0.001 else 0.0
	weights["fuel_max_10"] = 9.0
	weights["fuel_max_20"] = 5.0
	# 扩建卡看的是“栏位还能不能再扩”（与背包是否装满无关）；背包越满越值得出现。
	var slot_weight := 0.0
	if run.item_slots < EG.ITEM_SLOTS_MAX:
		slot_weight = EG.SLOT_WEIGHT_FULL if run.inventory.size() >= run.item_slots else EG.SLOT_WEIGHT_OPEN
	weights["slot"] = slot_weight
	weights["token_1"] = 9.0
	weights["token_2"] = 5.0
	weights["token_3"] = 2.0
	weights["boost_cap"] = 8.0
	weights["boost_power"] = 8.0
	weights["item"] = 10.0
	# 技能槽满时仍能刷出新技能卡，选中后走替换流程（继承原槽一半等级）。
	weights["skill_new"] = 10.0 if run.unowned_skills().size() > 0 else 0.0
	weights["skill_up"] = 12.0 if run.upgradable_skills().size() > 0 else 0.0
	weights["mod_card"] = 9.0 if not run.all_mods_maxed() else 0.0
	weights["skill_awaken"] = 10.0 if run.awakenable_skills().size() > 0 else 0.0

	var picked: Array = []
	var picked_ids: Array = []
	var keys: Array = weights.keys()
	for i in range(3):
		var total := 0.0
		for k in keys:
			# 权重为 0 的卡是“当前没有任何收益”（油耗见底、栏位已满等），不进卡池。
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
		# Resolve concrete payload for item / skill / mod / awakening cards.
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
			card["replace"] = run.skills.size() >= EG.SKILL_SLOTS
			card["title"] = "解锁技能：" + SKILLS[sid]["name"]
			card["desc"] = SKILLS[sid]["desc"]
			if card["replace"]:
				card["desc"] = SKILLS[sid]["desc"] + "（技能槽已满：选择后替换一个技能，继承其一半等级）"
		elif chosen == "skill_up":
			var sid2: String = run.upgradable_skills()[rng.randi_range(0, run.upgradable_skills().size() - 1)]
			card["skill_id"] = sid2
			card["title"] = "强化技能：" + SKILLS[sid2]["name"]
			card["desc"] = "技能等级 +1。"
		elif chosen == "mod_card":
			var mid: String = run.roll_mod(rng)
			var mod: Dictionary = MODS[mid]
			var school: Dictionary = MOD_SCHOOLS[mod["school"]]
			card["mod_id"] = mid
			card["title"] = "改装：" + mod["name"]
			card["desc"] = "【%s】%s" % [school["name"], mod["desc"]]
			card["rarity"] = mod["rarity"]
			card["icon"] = school["icon"]
		elif chosen == "skill_awaken":
			var pick: Array = run.awakenable_skills()
			var entry: Dictionary = pick[rng.randi_range(0, pick.size() - 1)]
			var sid3: String = entry["skill"]
			var branches: Array = awaken_branches(sid3)
			card["skill_id"] = sid3
			card["awaken"] = entry["awaken"]
			card["icon"] = "icon_awaken"
			if branches.size() > 1:
				# 有两条分支的技能（脉冲）先给一张通用卡，选中后再弹“二选一”。
				var names := PackedStringArray()
				for bid in branches:
					names.append("「%s」" % str(AWAKENINGS[bid]["name"]))
				card["branches"] = branches
				card["title"] = "超载觉醒：" + SKILLS[sid3]["name"]
				card["desc"] = "二选一：" + String(" / ").join(names) + "（选中后再挑分支）"
				card["rarity"] = "legend"
			else:
				card["title"] = "觉醒：" + str(AWAKENINGS[entry["awaken"]]["name"])
				card["desc"] = AWAKENINGS[entry["awaken"]]["desc"]
				card["rarity"] = AWAKENINGS[entry["awaken"]]["rarity"]
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
