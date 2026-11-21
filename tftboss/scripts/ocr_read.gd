class_name OcrRead
extends RefCounted
## Wertet erkannten Text aus: Stage, Gold, Level, Shop-Namen, Leben, Spielerliste, Traits.
## Alles fehlertolerant, weil Texterkennung mal ein Zeichen verwechselt.

static func ints(t: String) -> Array:
	var out := []
	var cur := ""
	for ch in t:
		if ch >= "0" and ch <= "9":
			cur += ch
		elif cur != "":
			out.append(int(cur))
			cur = ""
	if cur != "":
		out.append(int(cur))
	return out

static func stage(t: String) -> String:
	var rx := RegEx.create_from_string("([1-9])\\s*[-–—~]\\s*([1-7])")
	var m := rx.search(t)
	return "%s-%s" % [m.get_string(1), m.get_string(2)] if m else ""

## Gold: die längste Zahl (davor steht oft ein Münz-Symbol, das als "9" oder "@" gelesen wird)
static func gold(t: String) -> int:
	var best := -1
	var bestlen := 0
	for tok in t.replace("#", " ").split(" ", false):
		var digits := ""
		for ch in tok:
			if ch >= "0" and ch <= "9":
				digits += ch
		if digits.length() >= bestlen and digits.length() > 0 and int(digits) <= 999:
			best = int(digits)
			bestlen = digits.length()
	return best

static func level(t: String) -> int:
	var rx := RegEx.create_from_string("[LlI1|][vV][lI1|]\\.?\\s*(\\d{1,2})")
	var m := rx.search(t)
	if m and int(m.get_string(1)) >= 1 and int(m.get_string(1)) <= 11:
		return int(m.get_string(1))
	var ns := ints(t)
	# "Lvl. 5 4/20": die erste Zahl ist das Level
	for n in ns:
		if n >= 1 and n <= 11:
			return n
	return -1

static func hp(t: String) -> int:
	for n in ints(t):
		if n >= 0 and n <= 100:
			return n
	return -1

## Spielerliste: pro Zeile Name und Leben
static func lobby(t: String) -> Array:
	var out := []
	for line0 in t.split(" # ", false):
		var line: String = line0
		var y := -1
		var tl := line.rfind(" ~")
		if tl >= 0 and line.substr(tl + 2).strip_edges().is_valid_int():
			y = int(line.substr(tl + 2))
			line = line.substr(0, tl)
		var ns := ints(line)
		if ns.is_empty():
			continue
		var h: int = ns[ns.size() - 1]
		if h < 0 or h > 100:
			continue
		var name := line
		for ch in "0123456789|":
			name = name.replace(ch, "")
		out.append({"name": name.strip_edges(), "hp": h, "y": y})
	return out

static func _norm(s: String) -> String:
	var o := ""
	for ch in s.to_lower():
		if (ch >= "a" and ch <= "z") or ch == "'":
			o += ch
	return o.replace("'", "")

static func lev(a: String, b: String) -> int:
	var n := a.length()
	var m := b.length()
	if n == 0:
		return m
	if m == 0:
		return n
	var prev := PackedInt32Array()
	prev.resize(m + 1)
	for j in m + 1:
		prev[j] = j
	for i in range(1, n + 1):
		var cur := PackedInt32Array()
		cur.resize(m + 1)
		cur[0] = i
		for j in range(1, m + 1):
			var c := 0 if a[i - 1] == b[j - 1] else 1
			cur[j] = mini(mini(prev[j] + 1, cur[j - 1] + 1), prev[j - 1] + c)
		prev = cur
	return prev[m]

## Bester Name aus einer Liste, der zum Text passt (oder "")
static func match_name(t: String, names: Array) -> String:
	var words := []
	for w in t.replace("#", " ").split(" ", false):
		var nw := _norm(w)
		if nw.length() >= 2:
			words.append(nw)
	if words.is_empty():
		return ""
	var cands := []
	cands.append_array(words)
	for i in words.size() - 1:
		cands.append(words[i] + words[i + 1])
	var best := ""
	var bd := 99
	for n in names:
		var nn := _norm(n)
		if nn.length() < 2:
			continue
		for c in cands:
			var d := lev(c, nn)
			# Kurze Namen (z. B. "R&B", "Emo") nur bei genauer Übereinstimmung
			var allowed := 0 if nn.length() <= 3 else maxi(1, nn.length() / 4)
			if d <= allowed and d < bd:
				bd = d
				best = n
	return best

## Anzahl aus Texten wie "2/3", "2 > 4 > 6", "213" (falsch gelesenes 2/3)
static func count_of(t: String) -> int:
	var rx := RegEx.create_from_string("(\\d{1,2})\\s*[/Il|]\\s*\\d")
	var m := rx.search(t)
	if m:
		return int(m.get_string(1))
	for n in ints(t):
		if n >= 1 and n <= 10:
			return n
		if n > 10 and n < 1000:
			return int(str(n)[0])
	return -1

## Trait-Leiste: Namen und Anzahl. Ergebnis: {Trait: Anzahl}
static func traits(t: String, names: Array) -> Dictionary:
	var out := {}
	var parts := t.split(" # ", false)
	var last := ""
	for p in parts:
		var n := match_name(p, names)
		var c := count_of(p)
		if n != "":
			last = n
			if c > 0:
				out[n] = c
			elif not out.has(n):
				out[n] = 0
		elif last != "" and c > 0 and out.get(last, 0) == 0:
			out[last] = c
	return out

## Stärke der aktiven Traits über die Stufen aus den Set-Daten
static func trait_power(counts: Dictionary) -> float:
	var weights := [0.0, 1.0, 2.0, 3.5, 5.0, 6.0]
	var sc := 0.0
	for t in counts.keys():
		var tiers: Array = Meta.traits.get(t, [])
		var reached := 0
		for b in tiers:
			if int(counts[t]) >= int(b):
				reached += 1
		if tiers.size() == 1 and reached == 1:
			sc += 1.0          # Einzel-Trait (Unique)
		else:
			sc += weights[mini(reached, weights.size() - 1)]
	return sc


## Wo ist der Spieler gerade? Bekommt die Texte der Menü-Bereiche (btn, btn_bin, mid, head, menu, cards).
## Ergebnis: "match", "queue", "lobby", "modes", "home" oder "" (nichts erkannt)
static func phase(T: Dictionary) -> String:
	var mid := str(T.get("mid", "")).to_upper()
	var btn := (str(T.get("btn", "")) + " " + str(T.get("btn_bin", ""))).to_upper()
	var head := str(T.get("head", "")).to_upper()
	var menu := str(T.get("menu", "")).to_upper()
	var cards := str(T.get("cards", "")).to_upper()
	if _any(mid + " " + cards, ["MATCH FOUND", "MATCH GEFUNDEN", "ACCEPT", "ANNEHMEN", "SPIEL GEFUNDEN"]):
		return "match"
	if RegEx.create_from_string("\\d{1,3}\\s*%").search(str(T.get("load", ""))) != null:
		return "loading"
	var rx := RegEx.create_from_string("\\d:\\d\\d")
	if _any(btn, ["ESTIMATED", "GESCH"]) or rx.search(btn) != null:
		return "queue"
	if _any(head, ["NORMAL", "RANKED", "DOUBLE", "TOCKER", "HYPER", "RANGLISTE", "TURBO"]) or _any(btn, ["START"]):
		return "lobby"
	if _any(menu, ["TOUR COLLECTION", "STORE", "LOADOUTS", "LEADERBOARD", "SAMMLUNG", "SHOP", "BESTENLISTE"]) or _any(btn, ["PLAY", "SPIELEN"]):
		if _any(cards, ["RANKED", "DOUBLE", "TOCKER", "RANGLISTE"]):
			return "modes"
		return "home"
	return ""

static func _any(t: String, words: Array) -> bool:
	var t2 := t.replace(" ", "")
	for w in words:
		if t.contains(w) or t2.contains(str(w).replace(" ", "")):
			return true
	return false


## Spielername aufräumen: Störzeichen am Rand weg
static func clean_name(t: String) -> String:
	var o := ""
	for ch in t.replace(" # ", " "):
		if ch.is_valid_identifier() or ch.is_valid_int() or ch == " " or (ch.unicode_at(0) > 127 and not ch in "“”‘’«»„…—–·•"):
			o += ch
	var parts := []
	for w in o.split(" ", false):
		parts.append(w)
	# einzelne Krümel am Anfang und Ende (OCR-Rauschen) entfernen
	while parts.size() > 1 and str(parts[0]).length() <= 2:
		parts.pop_front()
	while parts.size() > 1 and str(parts[parts.size() - 1]).length() <= 1:
		parts.pop_back()
	return " ".join(parts).strip_edges()

static func same_name(a: String, b: String) -> bool:
	var x := _norm(a + "")
	var y := _norm(b + "")
	if x == "" or y == "":
		return false
	return x == y or lev(x, y) <= maxi(1, y.length() / 4) or (mini(x.length(), y.length()) >= 4 and (x.contains(y) or y.contains(x)))
