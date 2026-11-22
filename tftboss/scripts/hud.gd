class_name Hud
extends RefCounted
## Liest die TFT-Oberfläche direkt aus den Pixeln: Ziffern (Gold, Level, Streak, Leben),
## Spielerliste, Kugeln auf dem Board, Units (Lebensbalken) und Item-Plätze.
## Alle Positionen sind Anteile vom Bildschirm (16:9), gemessen an echten 1920x1080-Bildern.

const GW := 10
const GH := 14
const BUILTIN := "res://data/digits.json"
const USER := "user://ziffern.json"

# Feste Bereiche (x, y, w, h als Anteil)
const R_GOLD := [0.5276, 0.8148, 0.0323, 0.0324]
const R_LEVEL := [0.2000, 0.8148, 0.0210, 0.0296]
const R_STREAK := [0.5911, 0.8102, 0.0208, 0.0296]
const R_ITEMS := [0.0028, 0.2389, 0.0283, 0.5011]
const ITEM_SLOTS := 10

var templates: Array = []    # {"l": "5", "s": PackedByteArray}
var user_templates: Array = []

func _init() -> void:
	for p in [BUILTIN, USER]:
		if FileAccess.file_exists(p):
			var j = JSON.parse_string(FileAccess.get_file_as_string(p))
			if typeof(j) == TYPE_ARRAY:
				for e in j:
					var t := {"l": str(e["l"]), "s": Marshalls.base64_to_raw(str(e["s"]))}
					templates.append(t)
					if p == USER:
						user_templates.append(t)

static func rect(img: Image, r: Array) -> Rect2i:
	var W := img.get_width()
	var H := img.get_height()
	return Rect2i(int(r[0] * W), int(r[1] * H), maxi(1, int(r[2] * W)), maxi(1, int(r[3] * H)))

# ================================================================= Ziffern

## Zerlegt einen Ausschnitt in Zeichen (helle Schrift auf dunklem Grund). Ergebnis: Array von Signaturen
static func segment(img: Image) -> Array:
	var g := img.duplicate() as Image
	g.convert(Image.FORMAT_L8)
	var w := g.get_width()
	var h := g.get_height()
	var d := g.get_data()
	var mx := 0
	for v in d:
		mx = maxi(mx, v)
	if mx < 120:
		return []
	var th := maxi(135, int(mx * 0.62))
	var cols := PackedInt32Array()
	cols.resize(w)
	for y in h:
		for x in w:
			if d[y * w + x] >= th:
				cols[x] += 1
	var blobs := []
	var x := 0
	while x < w:
		if cols[x] > 0:
			var xs := x
			while x < w and cols[x] > 0:
				x += 1
			var y0 := h
			var y1 := -1
			for yy in h:
				for xx in range(xs, x):
					if d[yy * w + xx] >= th:
						y0 = mini(y0, yy)
						y1 = maxi(y1, yy)
						break
			blobs.append({"x0": xs, "x1": x - 1, "y0": y0, "y1": y1})
		else:
			x += 1
	var tall := 0
	for b in blobs:
		if b["x0"] > 0 and b["x1"] < w - 1:
			tall = maxi(tall, b["y1"] - b["y0"] + 1)
	if tall < 6:
		return []
	var out := []
	for b in blobs:
		var bh: int = b["y1"] - b["y0"] + 1
		var bw: int = b["x1"] - b["x0"] + 1
		if b["x0"] == 0 or b["x1"] == w - 1:
			continue
		if bh < tall * 0.7:
			continue          # Münze, Pfeil, Punkt, Bindestrich: keine Ziffer
		if bw > tall * 1.2:
			continue          # zusammengeklebt / Symbol
		out.append(_sig(d, w, b["x0"], b["x1"], b["y0"], b["y1"], th, tall))
	return out

static func _sig(d: PackedByteArray, w: int, x0: int, x1: int, y0: int, y1: int, th: int, tall: int) -> PackedByteArray:
	var gw := x1 - x0 + 1
	var gh := y1 - y0 + 1
	var raw := PackedByteArray()
	raw.resize(gw * gh)
	for yy in gh:
		for xx in gw:
			raw[yy * gw + xx] = 255 if d[(y0 + yy) * w + x0 + xx] >= th else 0
	var im := Image.create_from_data(gw, gh, false, Image.FORMAT_L8, raw)
	im.resize(GW, GH, Image.INTERPOLATE_BILINEAR)
	var s := im.get_data()
	var aspect := clampi(int(float(gw) / float(tall) * 200.0), 0, 255)
	for i in 14:
		s.append(aspect)
	return s

func _classify(s: PackedByteArray) -> Dictionary:
	var best := ""
	var bd := 1e9
	for t in templates:
		var ts: PackedByteArray = t["s"]
		if ts.size() != s.size():
			continue
		var sum := 0
		for i in s.size():
			sum += absi(s[i] - ts[i])
		var dd := float(sum) / s.size()
		if dd < bd:
			bd = dd
			best = t["l"]
	return {"l": best, "d": bd}

## Liest eine ganze Zahl. -1, wenn nichts oder ein Zeichen unsicher ist.
func read_int(img: Image, limit: float = 55.0) -> int:
	var sigs := segment(img)
	if sigs.is_empty() or sigs.size() > 3:
		return -1
	var t := ""
	for s in sigs:
		var c := _classify(s)
		if c["l"] == "" or c["d"] > limit:
			return -1
		t += c["l"]
	return int(t)

## Merkt sich die Ziffern einer sicher bekannten Zahl (z. B. von der Windows-Texterkennung)
func learn(img: Image, value: int) -> bool:
	var sigs := segment(img)
	var t := str(value)
	if sigs.size() != t.length():
		return false
	var changed := false
	for i in sigs.size():
		var c := _classify(sigs[i])
		if c["l"] == t[i] and c["d"] < 18.0:
			continue
		var e := {"l": t[i], "s": sigs[i]}
		templates.append(e)
		user_templates.append(e)
		changed = true
	if user_templates.size() > 200:
		var old = user_templates.pop_front()
		templates.erase(old)
	if changed:
		var arr := []
		for u in user_templates:
			arr.append({"l": u["l"], "s": Marshalls.raw_to_base64(u["s"])})
		var f := FileAccess.open(USER, FileAccess.WRITE)
		if f:
			f.store_string(JSON.stringify(arr))
	return changed

func gold(img: Image) -> int:
	var v := read_int(img.get_region(rect(img, R_GOLD)))
	return v if v <= 300 else -1

func level(img: Image) -> int:
	var v := read_int(img.get_region(rect(img, R_LEVEL)))
	return v if v >= 1 and v <= 11 else -1

func streak_num(img: Image) -> int:
	var v := read_int(img.get_region(rect(img, R_STREAK)))
	return v if v <= 30 else -1

# ================================================================= Spielerliste rechts

## Porträts rechts finden. Ergebnis: Array {"y": Mitte, "own": bool, "hp": int}
func lobby(img: Image) -> Array:
	var W := img.get_width()
	var H := img.get_height()
	var sx := float(W) / 1920.0
	var sy := float(H) / 1080.0
	var x0 := int(1840 * sx)
	var x1 := mini(W - 1, int(1915 * sx))
	var runs := []
	var cur := {}
	for y in range(int(140 * sy), int(830 * sy)):
		var red := 0
		var blue := 0
		var gold := 0
		for x in range(x0, x1):
			var c := img.get_pixel(x, y)
			if c.r > 0.59 and c.g < 0.35 and c.b < 0.35:
				red += 1
			elif c.b > 0.59 and c.r < 0.35:
				blue += 1
			elif c.r > 0.67 and c.g > 0.51 and c.b < 0.35:
				gold += 1
		var on := red + blue + gold >= 4
		if on:
			if cur.is_empty():
				cur = {"a": y, "b": y, "g": 0, "o": 0}
			cur["b"] = y
			cur["g"] += gold
			cur["o"] += red + blue
		elif not cur.is_empty():
			runs.append(cur)
			cur = {}
	if not cur.is_empty():
		runs.append(cur)
	# Teile zusammenfassen, die zum selben Porträt gehören
	var groups := []
	for r in runs:
		if not groups.is_empty() and r["a"] - groups[-1]["b"] < 14 * sy:
			groups[-1]["b"] = r["b"]
			groups[-1]["g"] += r["g"]
			groups[-1]["o"] += r["o"]
		else:
			groups.append(r.duplicate())
	var out := []
	for g in groups:
		var hgt: int = g["b"] - g["a"]
		if hgt < 30 * sy:
			continue
		var own: bool = g["g"] > 300 * sx * sy and g["g"] > g["o"]
		var cy: int = (g["a"] + g["b"]) / 2 if own or hgt >= 45 * sy else g["b"] - int(26 * sy)
		var e := {"y": cy, "own": own, "hp": -1}
		if own:
			e["hp"] = read_int(img.get_region(Rect2i(int(1788 * sx), cy - int(17 * sy), int(40 * sx), int(34 * sy))))
		else:
			e["hp"] = read_int(img.get_region(Rect2i(int(1824 * sx), cy - int(11 * sy), int(30 * sx), int(22 * sy))))
		out.append(e)
	return out

## Mein Leben: große weiße Zahl im dunklen Pfeil-Kasten links neben meinem Porträt (x≈1793-1828).
## Sucht die ganze Liste ab, weil mein Platz je nach Rang wandert. -1 = nicht gefunden
func own_hp(img: Image) -> int:
	var W := img.get_width()
	var H := img.get_height()
	var sx := float(W) / 1920.0
	var sy := float(H) / 1080.0
	var a := -1
	for y in range(int(150 * sy), int(845 * sy)):
		var br := 0
		var dk := 0
		for x in range(int(1793 * sx), int(1828 * sx)):
			var c := img.get_pixel(x, y)
			if c.r > 0.78 and c.g > 0.78 and c.b > 0.78:
				br += 1
			elif c.r < 0.27 and c.g < 0.27 and c.b < 0.27:
				dk += 1
		if br >= 2 and dk >= int(8 * sx):
			if a < 0:
				a = y
		elif a >= 0:
			var h := y - a
			if h >= int(13 * sy) and h <= int(24 * sy):
				var v := read_int(img.get_region(Rect2i(int(1788 * sx), a - int(6 * sy), int(42 * sx), h + int(12 * sy))))
				if v >= 0 and v <= 150:
					return v
			a = -1
	return -1

# ================================================================= Board

## Blaue Beute-Kugeln auf dem Board (gut sichtbar, satt blau/türkis). Ergebnis: Bildschirm-Punkte
static func orbs(img: Image) -> Array:
	var W := img.get_width()
	var H := img.get_height()
	var X0 := int(0.229 * W)
	var Y0 := int(0.111 * H)
	var X1 := int(0.771 * W)
	var Y1 := int(0.685 * H)
	var C := maxi(4, int(8.0 * W / 1920.0))
	var gw := (X1 - X0) / C
	var gh := (Y1 - Y0) / C
	var hit := PackedByteArray()
	hit.resize(gw * gh)
	for gy in gh:
		for gx in gw:
			var cnt := 0
			var cy := 0
			for yy in range(0, C, 2):
				for xx in range(0, C, 2):
					var c := img.get_pixel(X0 + gx * C + xx, Y0 + gy * C + yy)
					if c.r < 0.35 and c.g > 0.67 and c.b > 0.78:
						cy += 1
					elif c.b > 0.47 and c.b - c.r > 0.27 and c.b - c.g > 0.27:
						cnt += 1
			if cnt + cy >= 4 or cy >= 2:
				hit[gy * gw + gx] = 1
	var seen := PackedByteArray()
	seen.resize(gw * gh)
	var out := []
	for i in gw * gh:
		if hit[i] == 0 or seen[i] == 1:
			continue
		var st := [i]
		seen[i] = 1
		var n := 0
		var mnx := gw
		var mxx := 0
		var mny := gh
		var mxy := 0
		while not st.is_empty():
			var k: int = st.pop_back()
			n += 1
			var kx := k % gw
			var ky := k / gw
			mnx = mini(mnx, kx)
			mxx = maxi(mxx, kx)
			mny = mini(mny, ky)
			mxy = maxi(mxy, ky)
			for dy in [-1, 0, 1]:
				for dx in [-1, 0, 1]:
					var nx: int = kx + dx
					var ny: int = ky + dy
					if nx >= 0 and ny >= 0 and nx < gw and ny < gh:
						var j := ny * gw + nx
						if hit[j] == 1 and seen[j] == 0:
							seen[j] = 1
							st.append(j)
		var bw := mxx - mnx + 1
		var bh := mxy - mny + 1
		if n >= 25 and bw >= 5 and bh >= 5 and bw <= 12 and bh <= 12 and absi(bw - bh) <= 3 and float(n) / (bw * bh) >= 0.5:
			out.append(Vector2i(X0 + (mnx + mxx + 1) * C / 2, Y0 + (mny + mxy + 1) * C / 2))
	return out

## Weiße/graue Beute-Kugeln (durchsichtige Blase mit Fragezeichen): farblose, helle Pixel in einem runden Fleck ~45 px
static func white_orbs(img: Image) -> Array:
	var W := img.get_width()
	var H := img.get_height()
	var X0 := int(0.229 * W)
	var Y0 := int(0.111 * H)
	var X1 := int(0.771 * W)
	var Y1 := int(0.685 * H)
	var C := maxi(4, int(8.0 * W / 1920.0))
	var gw := (X1 - X0) / C
	var gh := (Y1 - Y0) / C
	var hit := PackedByteArray()
	hit.resize(gw * gh)
	for gy in gh:
		for gx in gw:
			var n := 0
			for yy in range(0, C, 2):
				for xx in range(0, C, 2):
					var c := img.get_pixel(X0 + gx * C + xx, Y0 + gy * C + yy)
					var mx := maxf(c.r, maxf(c.g, c.b))
					var mn := minf(c.r, minf(c.g, c.b))
					if mx - mn < 0.157 and (c.r + c.g + c.b) / 3.0 > 0.47 and c.b >= c.r - 0.03:
						n += 1
			if n >= 3:
				hit[gy * gw + gx] = 1
	var seen := PackedByteArray()
	seen.resize(gw * gh)
	var out := []
	for i in gw * gh:
		if hit[i] == 0 or seen[i] == 1:
			continue
		var st := [i]
		seen[i] = 1
		var n := 0
		var mnx := gw
		var mxx := 0
		var mny := gh
		var mxy := 0
		while not st.is_empty():
			var k: int = st.pop_back()
			n += 1
			var kx := k % gw
			var ky := k / gw
			mnx = mini(mnx, kx)
			mxx = maxi(mxx, kx)
			mny = mini(mny, ky)
			mxy = maxi(mxy, ky)
			for dy in [-1, 0, 1]:
				for dx in [-1, 0, 1]:
					var nx: int = kx + dx
					var ny: int = ky + dy
					if nx >= 0 and ny >= 0 and nx < gw and ny < gh:
						var j := ny * gw + nx
						if hit[j] == 1 and seen[j] == 0:
							seen[j] = 1
							st.append(j)
		var bw := mxx - mnx + 1
		var bh := mxy - mny + 1
		if n >= 18 and bw >= 5 and bh >= 5 and bw <= 8 and bh <= 8 and absi(bw - bh) <= 2 and float(n) / (bw * bh) >= 0.45:
			out.append(Vector2i(X0 + (mnx + mxx + 1) * C / 2, Y0 + (mny + mxy + 1) * C / 2))
	return out

## Eigene Units an den grünen Lebensbalken. Ergebnis {"board": [Punkte], "bench": [Punkte]} (Punkt = Körpermitte)
static func units(img: Image) -> Dictionary:
	var W := img.get_width()
	var H := img.get_height()
	var y0 := int(0.13 * H)
	var y1 := int(0.72 * H)
	var x0 := int(0.17 * W)
	var x1 := int(0.80 * W)
	var bars := []
	var y := y0
	while y < y1:
		var x := x0
		while x < x1:
			var c := img.get_pixel(x, y)
			if c.g > 0.55 and c.r < 0.25 and c.b < 0.28:
				var xs := x
				var gap := 0
				var last := x
				while x < x1 and gap <= 3:
					var c2 := img.get_pixel(x, y)
					if c2.g > 0.4 and c2.r < 0.3 and c2.b < 0.3:
						gap = 0
						last = x
					else:
						gap += 1
					x += 1
				x = last + 1
				var blen := x - xs
				if blen >= int(0.012 * W) and blen <= int(0.06 * W):
					var p := Vector2i(xs, y)
					var dup := false
					for b in bars:
						if absi(b.y - p.y) < int(0.02 * H) and absi(b.x - p.x) < int(0.03 * W):
							dup = true
							break
					if not dup:
						bars.append(p)
			x += 1
		y += 2
	var board := []
	var bench := []
	for b in bars:
		var body := Vector2i(b.x + int(0.012 * W), b.y + int(0.045 * H))
		if b.y > int(0.62 * H):
			bench.append(body)
		else:
			board.append(body)
	return {"board": board, "bench": bench}

## Welche Item-Plätze links sind belegt? Ergebnis: Array von Bildschirm-Punkten (Mitte des Platzes)
static func item_slots(img: Image) -> Array:
	var r := rect(img, R_ITEMS)
	var out := []
	var h := float(r.size.y) / ITEM_SLOTS
	for i in ITEM_SLOTS:
		var cy := int(r.position.y + h * (i + 0.5))
		var cx := r.position.x + r.size.x / 2
		var bright := 0
		var n := 0
		for yy in range(-8, 9, 4):
			for xx in range(-8, 9, 4):
				var c := img.get_pixel(cx + xx, cy + yy)
				n += 1
				if c.get_luminance() > 0.2 or c.s > 0.35:
					bright += 1
		if bright * 2 >= n:
			out.append(Vector2i(cx, cy))
	return out

## Ist rechts ein Unit-Infofenster offen (deckt die Spielerliste ab)?
static func info_panel_open(img: Image) -> bool:
	var W := img.get_width()
	var H := img.get_height()
	var dark := 0
	var n := 0
	for y in range(int(0.12 * H), int(0.30 * H), 6):
		for x in range(int(0.93 * W), int(0.99 * W), 6):
			n += 1
			if img.get_pixel(x, y).get_luminance() < 0.12:
				dark += 1
	return dark * 10 >= n * 7
