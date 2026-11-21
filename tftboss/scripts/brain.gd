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
var items_have: Array = []       # fertige Items auf der Bank
var consumables: Array = []      # Verbrauchsitems (Duplicator, Remover ...)
var my_augs: Array = []
var aug_offer: Array = []        # 3 Augment-Namen, wenn gerade eine Wahl offen ist

var hp := -1                     # eigenes Leben
var lobby_hp: Array = []         # Leben aller Spieler aus der Liste rechts
var results: Array = []          # "W" / "L" pro PvP-Runde
var plan := ""                   # "win", "loss" oder "" (noch offen)
var my_score := -1.0             # Stärke meiner aktiven Traits (aus der Trait-Leiste)
var my_traits: Dictionary = {}   # Trait -> Anzahl (per Texterkennung gelesen)
var opp_scores: Array = []       # dasselbe für die Gegner, beim Scouten gelesen
var win_chance := -1.0           # geschätzte Siegchance gegen einen zufälligen Gegner
var plan_why := ""

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
	items_have.clear()
	consumables.clear()
	my_augs.clear()
	aug_offer.clear()
	target = {}
	locked = false
	hp = -1
	lobby_hp = []
	results = []
	plan = ""
	plan_why = ""
	my_score = -1.0
	my_traits = {}
	opp_scores = []
	win_chance = -1.0

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
	# Fertige Items, die ein Carry oder Tank der Comp will
	var wanted := []
	for u in c.get("carry", []) + c.get("tank", []).slice(0, 1):
		wanted.append_array(items_for(c, u))
	for it in items_have:
		if it in wanted:
			wanted.erase(it)
			total += 1.6
		elif it.ends_with("Emblem"):
			var tname: String = str(it).trim_suffix(" Emblem")
			if comp_traits(c).has(tname):
				total += 2.0
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
		out.append({"k": "aug", "idx": best, "t": "Augment nehmen: %s (%s)" % [aug_offer[best], SIDE[best]]})
		return out

	if sn == 0:
		# Stage nicht lesbar: aus dem Level schätzen, damit trotzdem gespielt wird
		if gold >= 0 and level > 0:
			stage = guess_stage()
			sn = stage_num(stage)
		else:
			out.append({"k": "info", "t": "Warte auf das Spiel. Ich lese Stage, Gold und Shop, sobald sie zu sehen sind."})
			return out
	if sn % 10 == 4 and not target.is_empty():
		var need := carousel_component()
		if need != "":
			out.append({"k": "info", "t": "Karussell: nimm %s (für %s)" % [Meta.comp_de(need), target.get("carry", ["deinen Carry"])[0]]})

	# 2. Items und Verbrauchsitems
	update_plan()
	var comps_n := 0
	for k in comps_have.values():
		comps_n += k
	if plan == "loss" and sn <= 31 and comps_n < 6 and (hp < 0 or hp >= 50):
		if comps_n >= 2:
			out.append({"k": "info", "t": "Items noch nicht bauen (Lossstreak): Komponenten halten, bei 3-2 richtig bauen."})
	else:
		for line in item_advice():
			out.append({"k": "item", "t": line})
	for line in consumable_advice():
		out.append({"k": "item", "t": line})

	# 3. Shop
	var buys := shop_advice()
	var spent := 0
	for b in buys:
		spent += b["cost"]
		out.append({"k": "buy", "slot": b["slot"], "u": b["u"], "t": "Kaufen: Platz %d %s (%s)" % [b["slot"] + 1, b["u"], b["why"]]})

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
	# Passend zum Streak-Plan: Lossstreak will Gold, Winstreak will sofort Kampfkraft
	if plan == "loss":
		if "Gold" in cats:
			s += 1.2
		if "Kampf" in cats:
			s -= 0.4
	elif plan == "win":
		if "Kampf" in cats or "Items" in cats:
			s += 1.0
		if "Gold" in cats:
			s -= 0.6
	# Wenig Leben: nur noch sofortige Stärke zählt
	if hp >= 0 and hp < 40 and "Gold" in cats:
		s -= 2.0
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
	# Fertige Items zuerst verteilen
	var given := {}
	for it in items_have:
		for u in target.get("carry", []) + target.get("tank", []).slice(0, 1):
			if it in items_for(target, u) and not given.has(it + u):
				given[it + u] = true
				var who: String = u if owned.has(u) else "deinen stärksten Carry, später an %s" % u
				lines.append("Item geben: %s auf %s" % [it, who])
				break
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
				var who: String = u if owned.has(u) else "deinen stärksten Carry, später an %s" % u
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
		elif sn <= 32 and c <= 3 and plan != "loss":
			var shared := 0
			var tr := comp_traits(target) if not target.is_empty() else {}
			for t in Meta.units[u]["t"]:
				if tr.has(t):
					shared += 1
			var ust = Meta.units[u].get("st")
			var good: bool = typeof(ust) == TYPE_DICTIONARY and float(ust.get("avg", 9.0)) <= 4.4
			if shared > 0 or good or sn <= 22:
				prio = 0.8 + shared * 0.4 + (0.3 if good else 0.0)
				why = "passt zu den Traits" if shared > 0 else ("starke Unit" if good else "Board füllen")
		if have >= 8:
			prio = 0.0
		if prio > 0.0:
			cand.append({"slot": i, "u": u, "cost": c, "prio": prio, "why": why})
	cand.sort_custom(func(a, b): return a["prio"] > b["prio"])
	var g := gold
	var keep := _keep_gold(sn)
	var fill_left := maxi(0, level + 3 - owned.size())
	for x in cand:
		if x["why"] in ["passt zu den Traits", "starke Unit", "Board füllen"]:
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
	if plan == "win" and win_streak() >= 2 and sn <= 32:
		return 0   # Winstreak halten ist mehr wert als Zinsen
	return mini(50, int(gold / 10) * 10)

## Wie stark ist mein Spiel gerade (grob)? Units mit Paaren/2 Sternen, Items, Augments.
func strength() -> float:
	var sc := 0.0
	for u in owned.keys():
		var n: int = owned[u]
		var c := Meta.cost(u)
		if n >= 3:
			sc += 1.5 + c * 0.5
		elif n == 2:
			sc += 0.7
		else:
			sc += 0.15 * c
	var comps := 0
	for k in comps_have.values():
		comps += k
	sc += comps * 0.6 + items_have.size() * 1.5
	for a in my_augs:
		var cats: Array = Meta.augs.get(a, {}).get("c", [])
		if "Kampf" in cats or "Items" in cats:
			sc += 1.0
		if "Gold" in cats:
			sc -= 1.5
	return sc

func win_streak() -> int:
	var n := 0
	for i in range(results.size() - 1, -1, -1):
		if results[i] != "W":
			break
		n += 1
	return n

func loss_streak() -> int:
	var n := 0
	for i in range(results.size() - 1, -1, -1):
		if results[i] != "L":
			break
		n += 1
	return n

## Mein Platz nach Leben in der Lobby (1 = am meisten Leben), 0 wenn unbekannt
func hp_rank() -> int:
	if hp < 0 or lobby_hp.size() < 2:
		return 0
	var r := 1
	for h in lobby_hp:
		if int(h) > hp:
			r += 1
	return r

## Siegchance aus dem Vergleich der Trait-Stärke mit allen gescouteten Gegnern
func update_win_chance() -> void:
	if my_score < 0 or opp_scores.is_empty():
		win_chance = -1.0
		return
	var sum := 0.0
	for o in opp_scores:
		sum += 1.0 / (1.0 + exp(-(my_score - float(o)) / 2.5))
	win_chance = sum / opp_scores.size()

## Winstreak oder Lossstreak? Wird ab 2-1 entschieden und nach jeder Runde geprüft.
func update_plan() -> void:
	var sn := stage_num(stage)
	if sn < 21:
		return
	if sn >= 33:
		if plan != "":
			plan_why = "Ab Stage 3-3 normal weiter: Board aufbauen und Comp spielen."
		plan = ""
		return
	var st := strength()
	var wc := win_chance
	var known := owned.size() >= 2 or not comps_have.is_empty() or not items_have.is_empty() or not my_traits.is_empty()
	if not known and wc < 0.0:
		# Ohne Wissen über das Board nur nach Ergebnissen entscheiden, sonst normal spielen
		if win_streak() >= 2:
			plan = "win"
			plan_why = "Zwei Siege in Folge: Winstreak."
		elif loss_streak() >= 3:
			plan = "loss"
			plan_why = "Drei Niederlagen in Folge: Lossstreak, Gold sparen."
		else:
			plan = ""
			plan_why = "Board noch unbekannt: normal leveln und Board aufbauen."
		return
	if plan == "" and wc >= 0.0:
		if wc >= 0.55:
			plan = "win"
			plan_why = "Siegchance %d %% nach dem Scouten: Winstreak, früh leveln." % int(wc * 100)
			return
		if wc <= 0.42:
			plan = "loss"
			plan_why = "Siegchance nur %d %% nach dem Scouten: Lossstreak, Gold sparen." % int(wc * 100)
			return
	if plan == "":
		if st >= 4.0 or win_streak() >= 2:
			plan = "win"
			plan_why = "Starkes Board (Stärke %.1f): Winstreak, früh leveln." % st
		elif st < 2.5 or loss_streak() >= 2:
			plan = "loss"
			plan_why = "Schwaches Board (Stärke %.1f): Lossstreak, Gold sparen, nicht leveln." % st
		else:
			plan = "win" if win_streak() > loss_streak() else "loss"
			plan_why = "Mittelstarkes Board (Stärke %.1f), Ergebnisse entscheiden: %s." % [st, "Winstreak" if plan == "win" else "Lossstreak"]
		return
	var hp_ok := hp < 0 or hp >= 60
	if wc >= 0.0 and plan == "win" and wc < 0.35 and hp_ok and sn <= 31:
		plan = "loss"
		plan_why = "Gegner sind deutlich stärker (Siegchance %d %%): auf Lossstreak umgestellt." % int(wc * 100)
		return
	if wc >= 0.0 and plan == "loss" and wc > 0.62:
		plan = "win"
		plan_why = "Dein Board ist stärker als die Lobby (Siegchance %d %%): auf Winstreak umgestellt." % int(wc * 100)
		return
	if plan == "win" and loss_streak() >= 2 and hp_ok and sn <= 31:
		plan = "loss"
		plan_why = "Zwei Niederlagen in Folge: auf Lossstreak umgestellt."
	elif plan == "loss" and win_streak() >= 2:
		plan = "win"
		plan_why = "Zwei Siege in Folge: Board ist stark genug, auf Winstreak umgestellt."
	elif plan == "loss" and hp >= 0 and hp < 50 and sn <= 32:
		plan = "win"
		plan_why = "Leben unter 50: Lossstreak abbrechen, jetzt stabilisieren."

func econ_advice(g: int) -> Array:
	var out := []
	if target.is_empty() or g < 0:
		return out
	update_plan()
	var sn := stage_num(stage)
	var style := style_of(target)
	var rr := reroll_level(target)
	# Level-Plan: früh nach Streak, danach nach der Comp
	var want := 0
	if sn <= 32 and plan == "win":
		want = 4 if sn >= 21 else 0
		if sn >= 25:
			want = 5
		if sn >= 32:
			want = 6
	elif sn <= 31 and plan == "loss":
		want = 0          # Lossstreak: nicht leveln
	elif sn == 32 and plan == "loss":
		want = 6 if rr == 0 or rr >= 6 else rr
	else:
		var lvplan: Array = target.get("lv", [])
		if lvplan.is_empty():
			lvplan = _standard_levels(style)
		for e in lvplan:
			if sn >= stage_num(str(e["s"])):
				want = maxi(want, int(e["l"]))
		if rr > 0 and sn >= 31 and want > rr and _missing_three_stars().size() > 0:
			want = rr
	if level > 0 and want > level and g >= 4:
		out.append({"k": "level", "t": "Level hoch auf %d (F)" % want})
		return out
	var missing := _missing_core()
	var roll := ""
	var until := 50
	# Notfall: wenig Leben, Board stabilisieren
	if hp >= 0 and sn >= 33 and hp <= 20 and g > 4:
		roll = "Nur noch %d Leben: alles rollen (D)" % hp
		until = 0
	elif hp >= 0 and sn >= 33 and hp <= 40 and g > 20 and missing.size() > 0:
		roll = "%d Leben: rollen bis 20 Gold zum Stabilisieren (D)" % hp
		until = 20
	elif plan == "loss" and sn == 32 and hp >= 0 and hp < 60 and g > 30:
		roll = "Lossstreak vorbei: rollen bis 30 Gold zum Stabilisieren (D)"
		until = 30
	elif rr > 0 and level >= rr and sn >= 31:
		var m3 := _missing_three_stars()
		if m3.size() > 0 and g > 50:
			roll = "Rollen bis 50 Gold (D), suche %s" % ", ".join(m3.slice(0, 3))
			until = 50
	elif style.begins_with("Fast 8") and level >= 8 and sn >= 42 and missing.size() > 0:
		roll = "Roll-down auf 8: rollen bis ca. 15 Gold (D), suche %s" % ", ".join(missing.slice(0, 3))
		until = 15
	elif style.begins_with("Fast 9") and level >= 9 and missing.size() > 0:
		roll = "Roll-down auf 9: rollen bis ca. 10 Gold (D), suche %s" % ", ".join(missing.slice(0, 3))
		until = 10
	elif style == "Standard" and level >= 7 and sn >= 41 and missing.size() > 0 and g > 30:
		roll = "Rollen bis 30 Gold (D), suche %s" % ", ".join(missing.slice(0, 3))
		until = 30
	elif g > 60 and sn >= 41:
		roll = "Zu viel Gold: rollen bis 50 (D)"
		until = 50
	if roll != "" and g > until:
		out.append({"k": "roll", "t": roll, "until": until})
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

func consumable_advice() -> Array:
	var lines := []
	if target.is_empty() or consumables.is_empty():
		return lines
	var carry: Array = target.get("carry", [])
	var main_carry: String = carry[0] if carry.size() > 0 else ""
	var board := late_board(target)
	# Beste Unit zum Kopieren: die mit den meisten Kopien, Carrys zuerst
	var dup_best := func(max_cost: int) -> String:
		var best := ""
		var bs := -1.0
		for u in owned.keys():
			if not u in board or Meta.cost(u) > max_cost:
				continue
			var n: int = owned[u]
			if n >= 9:
				continue
			var sc := float(n) + (3.0 if u in carry else 0.0) + (1.0 if n in [2, 5, 8] else 0.0)
			if sc > bs:
				bs = sc
				best = u
		return best
	for c in consumables:
		match c:
			"Champion Duplicator":
				var u: String = dup_best.call(7)
				lines.append("Duplicator auf %s benutzen" % u if u != "" else "Duplicator aufheben, bis du eine Unit der Comp hast")
			"Lesser Champion Duplicator", "Neeko's Help":
				var u2: String = dup_best.call(3)
				lines.append("%s auf %s benutzen" % [Meta.comp_de(c), u2] if u2 != "" else "%s aufheben (nur für 1 bis 3 Kosten)" % Meta.comp_de(c))
			"Masterwork Upgrade", "Lucky Item Chest", "Radiant Lucky Item Chest", "Dr. Mundo's Record Contract":
				if main_carry != "":
					lines.append("%s auf %s benutzen%s" % [Meta.comp_de(c), main_carry, "" if owned.has(main_carry) else " (sobald du ihn hast)"])
			"Magnetic Remover":
				lines.append("Item-Entferner aufheben: damit Items von einer Unit holen, die nicht ins Endboard gehört")
			"Reforger", "Salvager":
				lines.append("%s auf Items benutzen, die %s nicht braucht" % [Meta.comp_de(c), target["name"]])
			"Training Dummy":
				lines.append("Trainingspuppe vorne hinstellen, damit sie Schaden schluckt")
	return lines

## Bis zu welchem Gold der Autopilot rollt
func _roll_floor(style: String, rr: int) -> int:
	if rr > 0:
		return 50
	if style.begins_with("Fast 8"):
		return 15
	if style.begins_with("Fast 9"):
		return 10
	if style == "Standard":
		return 30
	return 50

## Standard-Levelplan, falls die Comp keine eigenen Daten hat
static func _standard_levels(style: String) -> Array:
	if style.begins_with("lvl "):
		var rr := int(style.substr(4))
		return [{"l": 4, "s": "2-1"}, {"l": 5, "s": "2-5"}, {"l": rr, "s": "3-2"}, {"l": rr + 1, "s": "4-5"}, {"l": 8, "s": "5-1"}]
	if style.begins_with("Fast 9"):
		return [{"l": 4, "s": "2-1"}, {"l": 5, "s": "2-5"}, {"l": 6, "s": "3-2"}, {"l": 7, "s": "3-5"}, {"l": 8, "s": "4-1"}, {"l": 9, "s": "5-1"}]
	if style.begins_with("Fast 8"):
		return [{"l": 4, "s": "2-1"}, {"l": 5, "s": "2-5"}, {"l": 6, "s": "3-2"}, {"l": 7, "s": "3-5"}, {"l": 8, "s": "4-2"}, {"l": 9, "s": "5-2"}]
	return [{"l": 4, "s": "2-1"}, {"l": 5, "s": "2-5"}, {"l": 6, "s": "3-2"}, {"l": 7, "s": "4-1"}, {"l": 8, "s": "4-5"}, {"l": 9, "s": "5-5"}]

## Welche Komponente fehlt dem Carry am meisten (fürs Karussell)?
func carousel_component() -> String:
	var need := {}
	var carry: Array = target.get("carry", [])
	for i in carry.size():
		for it in items_for(target, carry[i]):
			if it in items_have:
				continue
			for k in Meta.recipes.get(it, []):
				need[k] = need.get(k, 0.0) + (1.0 if i == 0 else 0.6)
	for k in comps_have.keys():
		if need.has(k):
			need[k] -= comps_have[k] * 0.9
	var best := ""
	var bs := 0.0
	for k in need.keys():
		if need[k] > bs:
			bs = need[k]
			best = k
	return best

## Stage grob aus dem Level schätzen (wenn die Anzeige oben nicht lesbar ist)
func guess_stage() -> String:
	return {1: "1-3", 2: "1-3", 3: "1-4", 4: "2-1", 5: "2-5", 6: "3-2", 7: "4-1", 8: "4-5", 9: "5-2", 10: "6-1"}.get(level, "3-1")
