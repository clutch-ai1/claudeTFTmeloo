class_name Vision
extends RefCounted
## Liest Bildausschnitte. Lernt einmal, was wo zu sehen ist, und erkennt es danach selbst.

const PATH := "user://gelernt.json"
const CARD_W := 24
const CARD_H := 16
const GLYPH_W := 8
const GLYPH_H := 12
const MAX_PER_LABEL := 5

const EMPTY := "(leer)"
const IGNORE := "(ignorieren)"

## kind -> Array von {"l": Label, "s": PackedByteArray}
var db := {"shop": [], "aug": [], "glyph": []}

func load_db() -> void:
	if not FileAccess.file_exists(PATH):
		return
	var j = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if typeof(j) != TYPE_DICTIONARY:
		return
	for k in db.keys():
		db[k] = []
		for e in j.get(k, []):
			db[k].append({"l": str(e["l"]), "s": Marshalls.base64_to_raw(e["s"])})

func save_db() -> void:
	var out := {}
	for k in db.keys():
		out[k] = []
		for e in db[k]:
			out[k].append({"l": e["l"], "s": Marshalls.raw_to_base64(e["s"])})
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(out))

func count(kind: String) -> int:
	var seen := {}
	for e in db[kind]:
		seen[e["l"]] = true
	return seen.size()

func forget_all() -> void:
	db = {"shop": [], "aug": [], "glyph": []}
	save_db()

# ---------------------------------------------------------------- Karten

## Kleiner Fingerabdruck eines Bildausschnitts. Helligkeit und Kontrast werden
## ausgeglichen, damit abgedunkelte Shop-Karten (zu wenig Gold) trotzdem passen.
static func card_sig(img: Image) -> PackedByteArray:
	var c := img.duplicate() as Image
	c.convert(Image.FORMAT_RGB8)
	c.resize(CARD_W, CARD_H, Image.INTERPOLATE_BILINEAR)
	var d := c.get_data()
	var n := d.size()
	var mean := 0.0
	for v in d:
		mean += v
	mean /= n
	var var_ := 0.0
	for v in d:
		var_ += (v - mean) * (v - mean)
	var sd := maxf(sqrt(var_ / n), 4.0)
	var out := PackedByteArray()
	out.resize(n)
	for i in n:
		out[i] = clampi(int((d[i] - mean) / sd * 45.0 + 128.0), 0, 255)
	return out

## Streuung der Helligkeit. Ein leerer Shop-Platz ist fast einfarbig.
static func spread(img: Image) -> float:
	var c := img.duplicate() as Image
	c.convert(Image.FORMAT_L8)
	c.resize(32, 20, Image.INTERPOLATE_BILINEAR)
	var d := c.get_data()
	var mean := 0.0
	for v in d:
		mean += v
	mean /= d.size()
	var s := 0.0
	for v in d:
		s += (v - mean) * (v - mean)
	return sqrt(s / d.size())

static func dist(a: PackedByteArray, b: PackedByteArray) -> float:
	if a.size() != b.size() or a.size() == 0:
		return 999.0
	var s := 0
	for i in a.size():
		s += absi(a[i] - b[i])
	return float(s) / a.size()

## Bestes Label für einen Fingerabdruck. Ergebnis: {"l": Label oder "", "d": Abstand}
func classify(kind: String, s: PackedByteArray, limit: float) -> Dictionary:
	var best := ""
	var bd := 999.0
	for e in db[kind]:
		var d := dist(s, e["s"])
		if d < bd:
			bd = d
			best = e["l"]
	if bd > limit:
		return {"l": "", "d": bd}
	return {"l": best, "d": bd}

func learn(kind: String, s: PackedByteArray, label: String) -> void:
	var same: Array = db[kind].filter(func(e): return e["l"] == label)
	if same.size() >= MAX_PER_LABEL:
		db[kind].erase(same[0])
	db[kind].append({"l": label, "s": s})
	save_db()

## Liest einen Shop-Platz. Ergebnis: {"l": Unit / EMPTY / "", "s": Fingerabdruck}
func read_card(kind: String, img: Image, empty_spread: float = 0.0) -> Dictionary:
	if empty_spread > 0.0 and spread(img) < empty_spread:
		return {"l": EMPTY, "s": PackedByteArray()}
	var s := card_sig(img)
	var r := classify(kind, s, 26.0)
	return {"l": r["l"], "s": s, "d": r["d"]}

# ---------------------------------------------------------------- Zahlen

## Liest Zahlen wie Gold, Level oder "3-2". Ergebnis:
## {"text": erkannter Text oder "", "ok": alles erkannt, "glyphs": [Fingerabdrücke]}
func read_number(img: Image) -> Dictionary:
	var g := img.duplicate() as Image
	g.convert(Image.FORMAT_L8)
	var w := g.get_width()
	var h := g.get_height()
	var d := g.get_data()
	if w < 3 or h < 3:
		return {"text": "", "ok": false, "glyphs": []}
	var mx := 0
	for v in d:
		mx = maxi(mx, v)
	if mx < 110:
		return {"text": "", "ok": false, "glyphs": []}
	var th := int(mx * 0.62)
	# Zeilen mit Schrift bestimmen die Höhe der Textzeile
	var y0 := h
	var y1 := -1
	var colink := PackedInt32Array()
	colink.resize(w)
	for y in h:
		for x in w:
			if d[y * w + x] >= th:
				colink[x] += 1
				y0 = mini(y0, y)
				y1 = maxi(y1, y)
	if y1 < 0:
		return {"text": "", "ok": false, "glyphs": []}
	var line_h := y1 - y0 + 1
	if line_h < 4:
		return {"text": "", "ok": false, "glyphs": []}
	# Zeichen = zusammenhängende Spalten mit Schrift
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
	var im := Image.create(gw, gh, false, Image.FORMAT_L8)
	for yy in gh:
		for xx in gw:
			var v := d[(y0 + yy) * w + x0 + xx]
			im.set_pixel(xx, yy, Color(1, 1, 1) if v >= th else Color(0, 0, 0))
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
		learn("glyph", glyphs[i], t[i])
	return true
