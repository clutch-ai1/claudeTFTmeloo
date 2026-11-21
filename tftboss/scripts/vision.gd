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
const KINDS := ["shop", "aug", "item", "glyph", "tier"]
## Trait-Stufen und ihr Wert für die Board-Stärke
const TIERS := {"inaktiv": 0.0, "bronze": 1.0, "silber": 2.0, "gold": 3.5, "prisma": 5.0}

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

const NOISE := "_"

func _read_number(g: Image, d: PackedByteArray) -> Dictionary:
	var w := g.get_width()
	var h := g.get_height()
	var none := {"text": "", "ok": false, "glyphs": [], "meta": []}
	if w < 3 or h < 3:
		return none
	var mx := 0
	for v in d:
		if v > mx:
			mx = v
	if mx < 110:
		return none
	var th := int(mx * 0.62)
	var colink := PackedInt32Array()
	colink.resize(w)
	for y in h:
		var row := y * w
		for x in w:
			if d[row + x] >= th:
				colink[x] += 1
	# Zusammenhängende Spalten = ein Zeichen (oder ein Fremdteil)
	var blobs := []
	var x := 0
	while x < w:
		if colink[x] > 0:
			var xs := x
			var ink := 0
			while x < w and colink[x] > 0:
				ink += colink[x]
				x += 1
			if ink >= 3:
				var y0 := h
				var y1 := -1
				for yy in h:
					var row2 := yy * w
					for xx in range(xs, x):
						if d[row2 + xx] >= th:
							y0 = mini(y0, yy)
							y1 = maxi(y1, yy)
							break
				blobs.append({"x0": xs, "x1": x - 1, "y0": y0, "y1": y1, "ink": ink, "edge": xs == 0 or x - 1 == w - 1})
		else:
			x += 1
	if blobs.is_empty():
		return none
	# Höhe der Ziffern = höchstes Teil, das nicht am Rand klebt
	var tall := 0
	for b in blobs:
		if not b["edge"] or blobs.size() == 1:
			tall = maxi(tall, b["y1"] - b["y0"] + 1)
	if tall < 4:
		return none
	var keep := []
	for b in blobs:
		var bh: int = b["y1"] - b["y0"] + 1
		var bw: int = b["x1"] - b["x0"] + 1
		# Angeschnittene Teile am Rand weg, wenn es noch andere Zeichen gibt
		if b["edge"] and blobs.size() > 1:
			continue
		var is_dash: bool = bw >= bh * 1.3 and bh <= tall * 0.4
		if bh >= tall * 0.55 or is_dash:
			keep.append(b)
	if keep.is_empty() or keep.size() > 6:
		return none
	var ly0 := h
	var ly1 := -1
	for b in keep:
		if b["y1"] - b["y0"] + 1 >= tall * 0.55:
			ly0 = mini(ly0, b["y0"])
			ly1 = maxi(ly1, b["y1"])
	var line_h := ly1 - ly0 + 1
	var glyphs := []
	var meta := []
	for b in keep:
		glyphs.append(_glyph_sig(d, w, b["x0"], b["x1"], ly0, ly1, th, line_h))
		meta.append(b["ink"])
	var text := ""
	var ok := false
	var unknown := false
	for s in glyphs:
		var c := classify("glyph", s, 52.0)
		if c["l"] == "":
			unknown = true
			text += "?"
		elif c["l"] != NOISE:
			text += c["l"]
			ok = true
	if unknown:
		ok = false
	return {"text": text, "ok": ok, "glyphs": glyphs, "meta": meta}

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

## Lernt die Zeichen. Sind es mehr Teile als Zeichen, werden die kleinsten als Störung gemerkt.
## Ergebnis: "" wenn gelernt, sonst ein Hinweis, was nicht passt.
func learn_number(glyphs: Array, text: String, meta: Array = []) -> String:
	var t := text.replace(" ", "")
	if t == "":
		return "Bitte eintippen, was dasteht."
	if t.length() > glyphs.size():
		return "Ich sehe nur %d Zeichen, du hast %d getippt. Zieh den Rahmen etwas größer, mit ein bisschen Abstand um die Zahl." % [glyphs.size(), t.length()]
	var labels := []
	labels.resize(glyphs.size())
	if t.length() == glyphs.size():
		for i in glyphs.size():
			labels[i] = t[i]
	else:
		# die kleinsten Teile sind Störungen (z. B. ein Stück vom Gold-Symbol)
		var idx := range(glyphs.size())
		var ink: Array = meta if meta.size() == glyphs.size() else idx.map(func(_i): return 0)
		var by_size := idx.duplicate()
		by_size.sort_custom(func(a, b): return ink[a] < ink[b])
		var noise := {}
		for k in glyphs.size() - t.length():
			noise[by_size[k]] = true
		var ci := 0
		for i in glyphs.size():
			if noise.has(i):
				labels[i] = NOISE
			else:
				labels[i] = t[ci]
				ci += 1
	for i in glyphs.size():
		var s: PackedByteArray = glyphs[i]
		var lab: String = labels[i]
		var same: Array = db["glyph"].filter(func(e): return e["l"] == lab)
		if same.size() >= MAX_PER_LABEL * 2:
			db["glyph"].erase(same[0])
		db["glyph"].append({"l": lab, "s": s})
	cache.clear()
	save_db()
	return ""

# ---------------------------------------------------------------- Trait-Stufen

## Farb-Merkmal eines Trait-Symbols: mittlere Farbe der bunten Pixel und Anteil bunter Pixel.
## Die Stufe (Bronze, Silber, Gold, Prismatisch) erkennt man an der Farbe, nicht an der Form.
static func tier_feat(img: Image) -> PackedByteArray:
	var c := img.duplicate() as Image
	c.convert(Image.FORMAT_RGB8)
	c.resize(16, 16, Image.INTERPOLATE_BILINEAR)
	var d := c.get_data()
	var sr := 0.0
	var sg := 0.0
	var sb := 0.0
	var n := 0
	var bright := 0
	var tr := 0.0
	var tg := 0.0
	var tb := 0.0
	for i in range(0, d.size(), 3):
		var r := d[i]
		var g := d[i + 1]
		var b := d[i + 2]
		tr += r
		tg += g
		tb += b
		var mx := maxi(r, maxi(g, b))
		var mn := mini(r, mini(g, b))
		if mx > 90:
			bright += 1
			if mx - mn > 25 or mx > 170:
				sr += r
				sg += g
				sb += b
				n += 1
	var px := d.size() / 3
	var out := PackedByteArray()
	if n == 0:
		out.append_array([int(tr / px), int(tg / px), int(tb / px)])
	else:
		out.append_array([int(sr / n), int(sg / n), int(sb / n)])
	out.append(clampi(int(255.0 * n / px), 0, 255))
	out.append(clampi(int(255.0 * bright / px), 0, 255))
	# doppelt gewichtet: Farbe zählt mehr als Helligkeit
	out.append_array(out.slice(0, 3))
	return out

func read_tier(slot_key: String, img: Image) -> Dictionary:
	if spread(img) < 6.0:
		return {"l": EMPTY, "s": PackedByteArray()}
	var f := tier_feat(img)
	var c: Dictionary = cache.get(slot_key, {})
	if not c.is_empty() and dist(f, c["s"], 3.0) < 3.0:
		return c["r"]
	var r := classify("tier", f, 22.0)
	var res := {"l": r["l"], "s": f}
	cache[slot_key] = {"s": f, "r": res}
	return res
