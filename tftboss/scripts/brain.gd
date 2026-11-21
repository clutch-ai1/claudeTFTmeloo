class_name Brain
extends RefCounted
## Entscheidet, was du tun sollst. Nutzt die Comp-Daten vom Comp-Planer.

# Spielzustand (kommt von der Bilderkennung und deinen Eingaben)
var stage := ""            # "3-2"
var level := 0
var gold := -1
var shop: Array = ["", "", "", "", ""]
var owned: Dictionary = {}       # Unit -> Anzahl Kopien
var comps_have: Dictionary = {}  # Komponente -> Anzahl
var my_augs: Array = []
var aug_offer: Array = []        # 3 Augment-Namen, wenn gerade eine Wahl offen ist

var target: Dictionary = {}      # gewählte Ziel-Comp
var locked := false

const SIDE := ["links", "Mitte", "rechts"]

static func stage_num(s: String) -> int:
	var p := s.split("-")
	if p.size() != 2 or not p[0].is_valid_int() or not p[1].is_valid_int():
		return 0
	return int(p[0]) * 10 + int(p[1])

func reset() -> void:
	stage = ""
	level = 0
	gold = -1
	shop = ["", "", "", "", ""]
	owned.clear()
	comps_have.clear()
	my_augs.clear()
	aug_offer.clear()
	target = {}
	locked = false

# ---------------------------------------------------------------- Comp-Helfer

static func late_board(c: Dictionary) -> Array:
	var opts: Dictionary = c.get("opts", {})
	for l in ["9", "8", "10", "7"]:
		var arr: Array = opts.get(l, [])
		if arr.size() > 0:
			return arr[0]["u"]
	return c.get("core", [])

static func relevant(c: Dictionary) -> Dictionary:
	var rel := {}
	for u in c.get("core", []):
		rel[u] = 2.0
	for u in late_board(c):
		rel[u] = maxf(rel.get(u, 0.0), 1.5)
	var early: Dictionary = c.get("early", {})
	for l in early.keys():
		for o in early[l]:
			for u in o["u"]:
				if not rel.has(u):
					rel[u] = 1.0
	for u in c.get("carry", []):
		rel[u] = 3.0
	return rel

static func comp_traits(c: Dictionary) -> Dictionary:
	var cnt := {}
	for u in late_board(c):
		if Meta.units.has(u):
			for t in Meta.units[u]["t"]:
				cnt[t] = cnt.get(t, 0) + 1
	var active := {}
	for t in cnt.keys():
		var tiers: Array = Meta.traits.get(t, [1])
		if tiers.size() > 0 and cnt[t] >= int(tiers[0]):
			active[t] = cnt[t]
	return active

static func items_for(c: Dictionary, u: String) -> Array:
	var it: Dictionary = c.get("items", {})
	if it.has(u):
		return it[u]["i"]
	return Meta.D.get("best", {}).get(u, [])

static func style_of(c: Dictionary) -> String:
	return str(c.get("style", "Standard"))

static func reroll_level(c: Dictionary) -> int:
	var s := style_of(c)
	if s.begins_with("lvl "):
		return int(s.substr(4))
	return 0

static func style_de(c: Dictionary) -> String:
	var s := style_of(c)
	if s.begins_with("lvl "):
		return "Reroll auf Level " + s.substr(4)
	if s.begins_with("Fast "):
		return "Schnell auf " + s.substr(5)
	return "Normal leveln"

# ---------------------------------------------------------------- Ziel-Comp

func score_comp(c: Dictionary) -> float:
	var total := (4.6 - float(c["avg"])) * 2.2
	var rel := relevant(c)
	for u in owned.keys():
		if rel.has(u):
			total += 0.6 * rel[u] * mini(int(owned[u]), 3)
	# Komponenten, die zu den Carry-Items passen
	var av := comps_have.duplicate()
	var carries: Array = c.get("carry", [])
	for i in carries.size():
		for it in items_for(c, carries[i]):
			var r: Array = Meta.recipes.get(it, [])
			for k in r:
				if av.get(k, 0) > 0:
					av[k] -= 1
					total += 0.9 if i == 0 else 0.6
	# Augments
	var tr := comp_traits(c)
	var board := late_board(c)
	for a in my_augs:
		var A: Dictionary = Meta.augs.get(a, {})
		for t in A.get("t", []):
			if tr.has(t):
				total += 2.0
		for hname in A.get("h", []):
			if hname in board:
				total += 2.0
	if not target.is_empty() and target["id"] == c["id"]:
		total += 1.5 if not locked else 3.0
	return total

func pick_target() -> void:
	if Meta.comps.is_empty():
		return
	var best: Dictionary = {}
	var bs := -1e9
	for c in Meta.comps:
		var s := score_comp(c)
		if s > bs:
			bs = s
			best = c
	target = best
	var sn := stage_num(stage)
	locked = sn >= 31

func ranked_comps() -> Array:
	var arr := []
	for c in Meta.comps:
		arr.append({"c": c, "s": score_comp(c)})
	arr.sort_custom(func(a, b): return a["s"] > b["s"])
	return arr

# ---------------------------------------------------------------- Anweisungen

## Liefert eine Liste von {"t": Text, "k": Art} in der Reihenfolge, in der du es tun sollst.
func advise() -> Array:
	var out := []
	pick_target()
	var sn := stage_num(stage)

	# 1. Augment-Wahl hat Vorrang
	if aug_offer.size() == 3 and aug_offer.all(func(a): return a != ""):
		var best := -1
		var bs := -1e9
		for i in 3:
			var s := aug_score(aug_offer[i])
			if s > bs:
				bs = s
				best = i
		out.append({"k": "aug", "t": "Augment nehmen: %s (%s)" % [aug_offer[best], SIDE[best]]})
		return out

	if sn == 0:
		out.append({"k": "info", "t": "Warte auf das Spiel. Ich lese Stage, Gold und Shop, sobald sie zu sehen sind."})
		return out

	# 2. Items
	for line in item_advice():
		out.append({"k": "item", "t": line})

	# 3. Shop
	var buys := shop_advice()
	var spent := 0
	for b in buys:
		spent += b["cost"]
		out.append({"k": "buy", "t": "Kaufen: Platz %d %s (%s)" % [b["slot"] + 1, b["u"], b["why"]]})

	# 4. Level und Rollen
	for x in econ_advice(gold - spent if gold >= 0 else -1):
		out.append(x)

	if out.is_empty():
		out.append({"k": "info", "t": "Nichts kaufen. Runde abwarten."})
	return out

func aug_score(name: String) -> float:
	var A: Dictionary = Meta.augs.get(name, {})
	if A.is_empty():
		return -5.0
	var s := 0.0
	var st = A.get("st")
	if typeof(st) == TYPE_DICTIONARY and st.has("avg"):
		s += (4.5 - float(st["avg"])) * 3.0
	s += {"Prismatic": 0.6, "Gold": 0.3}.get(A.get("r", ""), 0.0)
	var cats: Array = A.get("c", [])
	if "Items" in cats or "Item" in cats:
		s += 1.0
	if "Gold" in cats:
		s += 0.8
	if "Kampf" in cats:
		s += 0.5
	if "Reroll" in cats and not target.is_empty():
		s += 1.5 if reroll_level(target) > 0 else -0.5
	if not target.is_empty():
		var tr := comp_traits(target)
		var board := late_board(target)
		for t in A.get("t", []):
			s += 3.0 if tr.has(t) else -1.5
		for h in A.get("h", []):
			s += 2.5 if h in board else -1.0
	return s

func item_advice() -> Array:
	var lines := []
	if target.is_empty():
		return lines
	var av := comps_have.duplicate()
	var order: Array = []
	for u in target.get("carry", []):
		order.append(u)
	for u in target.get("tank", []).slice(0, 1):
		order.append(u)
	for u in order:
		for it in items_for(target, u):
			var r: Array = Meta.recipes.get(it, [])
			if r.size() != 2:
				continue
			var ok := false
			if r[0] == r[1]:
				ok = av.get(r[0], 0) >= 2
			else:
				ok = av.get(r[0], 0) >= 1 and av.get(r[1], 0) >= 1
			if ok:
				av[r[0]] -= 1
				av[r[1]] -= 1
				var who: String = u if owned.has(u) else "die Unit, die %s gerade hält (später weitergeben)" % u
				lines.append("Item bauen: %s (%s + %s) auf %s" % [it, Meta.comp_de(r[0]), Meta.comp_de(r[1]), who])
	return lines

func shop_advice() -> Array:
	var res := []
	if gold < 0:
		return res
	var sn := stage_num(stage)
	var rel := relevant(target) if not target.is_empty() else {}
	var rr := reroll_level(target) if not target.is_empty() else 0
	var cand := []
	for i in shop.size():
		var u: String = shop[i]
		if u == "" or u == Vision.EMPTY or u == Vision.IGNORE or not Meta.units.has(u):
			continue
		var c := Meta.cost(u)
		var have: int = owned.get(u, 0)
		var prio := 0.0
		var why := ""
		if rel.has(u):
			prio = rel[u] * 2.0
			why = "Carry" if u in target.get("carry", []) else "für " + target["name"]
			if rr > 0 and c <= 3:
				prio += 2.0
				why += ", für 3 Sterne"
		elif have >= 1 and sn < 41 and c <= 3:
			prio = 1.5 + have
			why = "Paar, wird 2 Sterne" if have == 2 else "Paar"
		elif sn <= 23 and c <= 2:
			prio = 0.8
			why = "Board stärker machen"
		if have >= 8:
			prio = 0.0
		if prio > 0.0:
			cand.append({"slot": i, "u": u, "cost": c, "prio": prio, "why": why})
	cand.sort_custom(func(a, b): return a["prio"] > b["prio"])
	var g := gold
	var keep := _keep_gold(sn)
	var fill_left := maxi(0, level + 1 - owned.size())
	for x in cand:
		if x["why"] == "Board stärker machen":
			if fill_left <= 0:
				continue
			fill_left -= 1
		var important: bool = x["prio"] >= 4.0
		if g - x["cost"] >= keep or (important and g >= x["cost"]):
			res.append(x)
			g -= x["cost"]
	return res

## Gold, das liegen bleiben soll (Zinsen)
func _keep_gold(sn: int) -> int:
	if sn < 21:
		return 0
	if sn <= 22:
		return 0
	var rr := reroll_level(target) if not target.is_empty() else 0
	if rr > 0 and level >= rr and sn >= 31:
		return 50
	return mini(50, int(gold / 10) * 10)

func econ_advice(g: int) -> Array:
	var out := []
	if target.is_empty() or g < 0:
		return out
	var sn := stage_num(stage)
	var style := style_of(target)
	var rr := reroll_level(target)
	# Level-Plan der Comp: ab welcher Stage welches Level
	var want := 0
	for e in target.get("lv", []):
		if sn >= stage_num(str(e["s"])):
			want = maxi(want, int(e["l"]))
	if rr > 0 and sn >= 31 and want > rr and _missing_three_stars().size() > 0:
		want = rr
	if level > 0 and want > level and g >= 4:
		out.append({"k": "level", "t": "Level hoch auf %d (F drücken, bis Level %d)" % [want, want]})
		return out
	var missing := _missing_core()
	var roll := ""
	if rr > 0 and level >= rr and sn >= 31:
		var m3 := _missing_three_stars()
		if m3.size() > 0 and g > 50:
			roll = "Rollen bis 50 Gold (D), suche %s" % ", ".join(m3.slice(0, 3))
	elif style.begins_with("Fast 8") and level >= 8 and sn >= 42 and missing.size() > 0:
		roll = "Roll-down: rollen bis ca. 15 Gold (D), suche %s" % ", ".join(missing.slice(0, 3))
	elif style.begins_with("Fast 9") and level >= 9 and missing.size() > 0:
		roll = "Roll-down auf 9: rollen bis ca. 10 Gold (D), suche %s" % ", ".join(missing.slice(0, 3))
	elif style == "Standard" and level >= 7 and sn >= 41 and missing.size() > 0 and g > 30:
		roll = "Rollen bis 30 Gold (D), suche %s" % ", ".join(missing.slice(0, 3))
	elif g > 60 and sn >= 41:
		roll = "Zu viel Gold: rollen bis 50 (D)"
	if roll != "":
		out.append({"k": "roll", "t": roll})
	elif sn >= 21:
		var nxt := (int(g / 10) + 1) * 10
		if g < 50:
			out.append({"k": "info", "t": "Nicht rollen. Gold sparen (nächste Zinsstufe bei %d)" % nxt})
		else:
			out.append({"k": "info", "t": "Nicht rollen. 50 Gold halten"})
	return out

func _missing_core() -> Array:
	var m := []
	for u in late_board(target):
		if not owned.has(u):
			m.append(u)
	m.sort_custom(func(a, b): return Meta.cost(a) > Meta.cost(b))
	return m

func _missing_three_stars() -> Array:
	var m := []
	var rr := reroll_level(target)
	for u in late_board(target):
		if Meta.cost(u) <= mini(3, maxi(1, rr - 4)) and owned.get(u, 0) < 9:
			m.append(u)
	for u in target.get("carry", []):
		if Meta.cost(u) <= 3 and owned.get(u, 0) < 9 and not u in m:
			m.push_front(u)
	return m
