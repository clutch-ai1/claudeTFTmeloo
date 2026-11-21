class_name Vision
extends RefCounted
## Liest Bildausschnitte. Lernt einmal, was wo zu sehen ist, und erkennt es danach selbst.
## Schnell: ein Platz wird nur neu verglichen, wenn sich sein Bild wirklich verändert hat.

const PATH := "user://gelernt_v2.json"
const CARD_W := 16
const CARD_H := 12
const ICON := 12
const GLYPH_W := 8
const GLYPH_H := 12
const MAX_PER_LABEL := 4

const EMPTY := "(leer)"
const IGNORE := "(ignorieren)"
const KINDS := ["shop", "aug", "item", "glyph"]

## kind -> Array von {"l": Label, "s": PackedByteArray}
var db := {}
## Platz-Schlüssel -> {"s": letzter Fingerabdruck, "r": letztes Ergebnis}
var cache := {}

func _init() -> void:
	for k in KINDS:
		db[k] = []

func load_db() -> void:
	if not FileAccess.file_exists(PATH):
		return
	var j = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if typeof(j) != TYPE_DICTIONARY:
		return
	for k in KINDS:
		db[k] = []
		for e in j.get(k, []):
			db[k].append({"l": str(e["l"]), "s": Marshalls.base64_to_raw(e["s"])})

func save_db() -> void:
	var out := {}
	for k in KINDS:
		out[k] = []
		for e in db[k]:
			out[k].append({"l": e["l"], "s": Marshalls.raw_to_base64(e["s"])})
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(out))

func count(kind: String) -> int:
	var seen := {}
	for e in db[kind]:
		if e["l"] != EMPTY and e["l"] != IGNORE:
			seen[e["l"]] = true
	return seen.size()

func forget_all() -> void:
	for k in KINDS:
		db[k] = []
	cache.clear()
	save_db()

# ---------------------------------------------------------------- Fingerabdrücke

## Helligkeit und Kontrast werden ausgeglichen, damit abgedunkelte Karten
## (zu wenig Gold) oder Hover-Effekte trotzdem passen.
static func norm_sig(img: Image, w: int, h: int) -> PackedByteArray:
	var c := img.duplicate() as Image
	c.convert(Image.FORMAT_RGB8)
	c.resize(w, h, Image.INTERPOLATE_BILINEAR)
	var d := c.get_data()
	var n := d.size()
	var sum := 0
	for v in d:
		sum += v
	var mean := float(sum) / n
	var var_ := 0.0
	for v in d:
		var_ += (v - mean) * (v - mean)
	var sd := maxf(sqrt(var_ / n), 4.0)
	var out := PackedByteArray()
	out.resize(n)
	for i in n:
		out[i] = clampi(int((d[i] - mean) / sd * 45.0 + 128.0), 0, 255)
	return out

## Streuung der Helligkeit. Ein leerer Platz ist fast einfarbig.
static func spread(img: Image) -> float:
	var c := img.duplicate() as Image
	c.convert(Image.FORMAT_L8)
	c.resize(24, 16, Image.INTERPOLATE_BILINEAR)
	var d := c.get_data()
	var sum := 0
	for v in d:
		sum += v
	var mean := float(sum) / d.size()
	var s := 0.0
	for v in d:
		s += (v - mean) * (v - mean)
	return sqrt(s / d.size())

## Mittlerer Abstand. Bricht ab, sobald es schlechter als `stop` wird.
static func dist(a: PackedByteArray, b: PackedByteArray, stop: float = 9999.0) -> float:
	var n := a.size()
	if n != b.size() or n == 0:
		return 999.0
	var lim := int(stop * n)
	var s := 0
	var i := 0
	while i < n:
		s += absi(a[i] - b[i])
		if (i & 63) == 63 and s > lim:
			return 999.0
		i += 1
	return float(s) / n

func classify(kind: String, s: PackedByteArray, limit: float) -> Dictionary:
	var best := ""
	var bd := limit
	for e in db[kind]:
		var d := dist(s, e["s"], bd)
		if d < bd:
			bd = d
			best = e["l"]
	return {"l": best, "d": bd}

func learn(kind: String, s: PackedByteArray, label: String) -> void:
	if s.is_empty():
		return
	var same: Array = db[kind].filter(func(e): return e["l"] == label)
	if same.size() >= MAX_PER_LABEL:
		db[kind].erase(same[0])
	db[kind].append({"l": label, "s": s})
	# Zwischenspeicher leeren, damit der Platz sofort neu erkannt wird
	cache.clear()
	save_db()

# ---------------------------------------------------------------- Karten, Augments, Items

## Liest einen Platz. Ergebnis: {"l": Label / EMPTY / "", "s": Fingerabdruck, "new": ob neu verglichen}
func read_slot(slot_key: String, kind: String, img: Image, empty_spread: float) -> Dictionary:
	if empty_spread > 0.0 and spread(img) < empty_spread:
		return {"l": EMPTY, "s": PackedByteArray(), "new": false}
	var w := CARD_W
	var h := CARD_H
	if kind == "item":
		w = ICON
		h = ICON
	var s := norm_sig(img, w, h)
	var c: Dictionary = cache.get(slot_key, {})
	if not c.is_empty() and dist(s, c["s"], 6.0) < 6.0:
		return c["r"]
	var r := classify(kind, s, 16.0 if kind == "item" else 20.0)
	var res := {"l": r["l"], "s": s, "new": true}
	cache[slot_key] = {"s": s, "r": res}
	return res

# ---------------------------------------------------------------- Zahlen

## Liest Zahlen wie Gold, Level oder "3-2". Ergebnis:
## {"text": erkannter Text, "ok": alles erkannt, "glyphs": [Fingerabdrücke]}
func read_number(slot_key: String, img: Image) -> Dictionary:
	var g := img.duplicate() as Image
	g.convert(Image.FORMAT_L8)
	var d := g.get_data()
	var hsh := hash(d)
	var c: Dictionary = cache.get(slot_key, {})
	if not c.is_empty() and c["h"] == hsh:
		return c["r"]
	var r := _read_number(g, d)
	cache[slot_key] = {"h": hsh, "r": r}
	return r

func _read_number(g: Image, d: PackedByteArray) -> Dictionary:
	var w := g.get_width()
	var h := g.get_height()
	var none := {"text": "", "ok": false, "glyphs": []}
	if w < 3 or h < 3:
		return none
	var mx := 0
	for v in d:
		if v > mx:
			mx = v
	if mx < 110:
		return none
	var th := int(mx * 0.62)
	var y0 := h
	var y1 := -1
	var colink := PackedInt32Array()
	colink.resize(w)
	for y in h:
		var row := y * w
		for x in w:
			if d[row + x] >= th:
				colink[x] += 1
				if y < y0:
					y0 = y
				if y > y1:
					y1 = y
	if y1 < 0 or y1 - y0 + 1 < 4:
		return none
	var line_h := y1 - y0 + 1
	var runs := []
	var x := 0
	while x < w:
		if colink[x] > 0:
			var xs := x
			var ink := 0
			while x < w and colink[x] > 0:
				ink += colink[x]
				x += 1
			if ink >= 3:
				runs.append([xs, x - 1])
		else:
			x += 1
	if runs.size() > 6:
		return none
	var glyphs := []
	for r in runs:
		glyphs.append(_glyph_sig(d, w, r[0], r[1], y0, y1, th, line_h))
	var text := ""
	var ok := glyphs.size() > 0
	for s in glyphs:
		var c := classify("glyph", s, 52.0)
		if c["l"] == "":
			ok = false
			text += "?"
		else:
			text += c["l"]
	return {"text": text, "ok": ok, "glyphs": glyphs}

static func _glyph_sig(d: PackedByteArray, w: int, x0: int, x1: int, y0: int, y1: int, th: int, line_h: int) -> PackedByteArray:
	var gw := x1 - x0 + 1
	var gh := y1 - y0 + 1
	var raw := PackedByteArray()
	raw.resize(gw * gh)
	for yy in gh:
		var src := (y0 + yy) * w + x0
		for xx in gw:
			raw[yy * gw + xx] = 255 if d[src + xx] >= th else 0
	var im := Image.create_from_data(gw, gh, false, Image.FORMAT_L8, raw)
	im.resize(GLYPH_W, GLYPH_H, Image.INTERPOLATE_BILINEAR)
	var out := im.get_data()
	# Seitenverhältnis mit hineinrechnen, sonst sehen "1" und "-" gleich aus
	var aspect := clampi(int(float(gw) / float(line_h) * 120.0), 0, 255)
	for i in 12:
		out.append(aspect)
	return out

func learn_number(glyphs: Array, text: String) -> bool:
	var t := text.replace(" ", "")
	if t.length() != glyphs.size():
		return false
	for i in glyphs.size():
		var s: PackedByteArray = glyphs[i]
		var same: Array = db["glyph"].filter(func(e): return e["l"] == t[i])
		if same.size() >= MAX_PER_LABEL:
			db["glyph"].erase(same[0])
		db["glyph"].append({"l": t[i], "s": s})
	cache.clear()
	save_db()
	return true
