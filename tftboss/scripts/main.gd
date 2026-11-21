extends Control
## TFT Boss: Ich sage, was zu tun ist. Du klickst.

const SETTINGS := "user://einstellungen.json"
const TICK := 0.6
const AUG_STAGES := [21, 32, 42]
const KIND_COLOR := {"aug": "c48cff", "item": "6fd3ff", "buy": "7be07b", "level": "f5c542", "roll": "ff9a4a", "info": "a9a6c4"}
const NUM_NAME := {"stage": "Stage", "level": "Level", "gold": "Gold"}
const NUM_EXAMPLE := {"stage": "3-2", "level": "6", "gold": "34"}

var vision := Vision.new()
var brain := Brain.new()
var rects := {}
var screen_idx := 0
var running := true
var compact := false

var prev_shop: Array = ["", "", "", "", ""]
var empty_ticks: Array = [0, 0, 0, 0, 0]
var aug_off_stage := ""
var aug_seen_full := false
var last_stage_num := 0
var stage_seen_ms := -100000      # wann die Stage zuletzt sicher gelesen wurde
var unknown_prev := {}            # Platz -> Fingerabdruck vom letzten Durchlauf (erst fragen, wenn stabil)
var busy := false

var prompt: Dictionary = {}
var skip_until := {}

# UI
var timer: Timer
var lbl_do: RichTextLabel
var lbl_seen: Label
var lbl_target: RichTextLabel
var lbl_data: Label
var btn_run: Button
var btn_compact: Button
var opt_screen: OptionButton
var prompt_box: PanelContainer
var prompt_img: TextureRect
var prompt_q: Label
var prompt_edit: LineEdit
var prompt_quick: HFlowContainer
var prompt_sugg: HFlowContainer
var details: Array = []          # Panels, die im Kompakt-Modus verschwinden
var comp_title: Label
var comp_grid: GridContainer
var items_flow: HFlowContainer
var units_flow: HFlowContainer
var unit_edit: LineEdit
var augs_flow: HFlowContainer
var aug_edit: LineEdit

func _ready() -> void:
	vision.load_db()
	_load_settings()
	_build_ui()
	timer = Timer.new()
	timer.wait_time = TICK
	timer.timeout.connect(_tick)
	add_child(timer)
	timer.start()
	Meta.loaded.connect(_refresh_all)
	_refresh_all()

# ================================================================= Einstellungen

func _load_settings() -> void:
	if not FileAccess.file_exists(SETTINGS):
		return
	var j = JSON.parse_string(FileAccess.get_file_as_string(SETTINGS))
	if typeof(j) != TYPE_DICTIONARY:
		return
	rects = j.get("rects", {})
	screen_idx = int(j.get("screen", 0))
	compact = bool(j.get("compact", false))
	if j.has("win"):
		var w: Array = j["win"]
		var p := Vector2i(int(w[0]), int(w[1]))
		# nur übernehmen, wenn die Position auf einem Bildschirm liegt
		for i in DisplayServer.get_screen_count():
			if Rect2i(DisplayServer.screen_get_position(i), DisplayServer.screen_get_size(i)).has_point(p + Vector2i(20, 20)):
				get_window().position = p
				break

func _save_settings() -> void:
	var wp := get_window().position
	var f := FileAccess.open(SETTINGS, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"rects": rects, "screen": screen_idx, "win": [wp.x, wp.y], "compact": compact}))

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_save_settings()

# ================================================================= UI

func _panel(bg: Color) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(10)
	p.add_theme_stylebox_override("panel", sb)
	return p

func _title(t: String) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", 13)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_color_override("font_color", Color("a9a6c4"))
	return l

func _small(t: String = "") -> Label:
	var l := Label.new()
	l.text = t
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", Color("8a87a6"))
	return l

func _rich() -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.scroll_active = false
	r.selection_enabled = false
	return r

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color("14121f")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var m := MarginContainer.new()
	m.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for s in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + s, 10)
	scroll.add_child(m)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	m.add_child(v)

	# Kopf
	var head := HBoxContainer.new()
	var t := Label.new()
	t.text = "TFT Boss"
	t.add_theme_font_size_override("font_size", 22)
	t.add_theme_color_override("font_color", Color("f5c542"))
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	btn_compact = Button.new()
	btn_compact.pressed.connect(func():
		compact = not compact
		_apply_compact()
		_save_settings())
	head.add_child(btn_compact)
	btn_run = Button.new()
	btn_run.pressed.connect(func():
		running = not running
		_update_run_btn())
	head.add_child(btn_run)
	_update_run_btn()
	v.add_child(head)

	var row := HBoxContainer.new()
	var b_cal := MenuButton.new()
	b_cal.text = "Kalibrieren ▾"
	b_cal.flat = false
	var pm := b_cal.get_popup()
	pm.about_to_popup.connect(func():
		pm.clear()
		for i in Calib.ORDER.size():
			var k: String = Calib.ORDER[i]
			pm.add_item(("✓  " if rects.has(k) else "○  ") + Calib.NAMES[k], i)
		pm.add_separator()
		pm.add_item("Alle der Reihe nach", 100))
	pm.id_pressed.connect(func(id):
		_start_calibration("" if id == 100 else Calib.ORDER[id]))
	row.add_child(b_cal)
	var b_new := Button.new()
	b_new.text = "Neues Spiel"
	b_new.pressed.connect(_new_game)
	row.add_child(b_new)
	opt_screen = OptionButton.new()
	for i in DisplayServer.get_screen_count():
		opt_screen.add_item("Bildschirm %d" % (i + 1), i)
	if opt_screen.item_count > 0:
		opt_screen.select(clampi(screen_idx, 0, opt_screen.item_count - 1))
	opt_screen.item_selected.connect(func(i):
		screen_idx = i
		vision.cache.clear()
		_save_settings())
	row.add_child(opt_screen)
	v.add_child(row)
	details.append(row)

	# Was jetzt zu tun ist
	var pdo := _panel(Color("1f1c33"))
	var vdo := VBoxContainer.new()
	vdo.add_child(_title("JETZT MACHEN"))
	lbl_do = _rich()
	lbl_do.add_theme_font_size_override("normal_font_size", 19)
	lbl_do.add_theme_font_size_override("bold_font_size", 19)
	vdo.add_child(lbl_do)
	pdo.add_child(vdo)
	v.add_child(pdo)

	# Lernfrage
	prompt_box = _panel(Color("3a2a12"))
	var vp := VBoxContainer.new()
	vp.add_child(_title("KURZ HELFEN (pro Bild nur einmal nötig)"))
	prompt_q = Label.new()
	prompt_q.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vp.add_child(prompt_q)
	prompt_img = TextureRect.new()
	prompt_img.custom_minimum_size = Vector2(0, 90)
	prompt_img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	prompt_img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	prompt_img.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	vp.add_child(prompt_img)
	prompt_quick = HFlowContainer.new()
	vp.add_child(prompt_quick)
	prompt_edit = LineEdit.new()
	prompt_edit.placeholder_text = "Tippen ..."
	prompt_edit.text_changed.connect(_prompt_typed)
	prompt_edit.text_submitted.connect(_prompt_submit)
	vp.add_child(prompt_edit)
	prompt_sugg = HFlowContainer.new()
	vp.add_child(prompt_sugg)
	prompt_box.add_child(vp)
	prompt_box.visible = false
	v.add_child(prompt_box)

	# Ziel-Comp
	var pt := _panel(Color("1a1829"))
	var vt := VBoxContainer.new()
	vt.add_child(_title("ZIEL-COMP"))
	lbl_target = _rich()
	vt.add_child(lbl_target)
	pt.add_child(vt)
	v.add_child(pt)
	details.append(pt)

	# Items
	var pc := _panel(Color("1a1829"))
	var vc := VBoxContainer.new()
	comp_title = _title("")
	vc.add_child(comp_title)
	comp_grid = GridContainer.new()
	comp_grid.columns = 5
	vc.add_child(comp_grid)
	items_flow = HFlowContainer.new()
	vc.add_child(items_flow)
	pc.add_child(vc)
	v.add_child(pc)
	details.append(pc)

	# Units
	var pu := _panel(Color("1a1829"))
	var vu := VBoxContainer.new()
	vu.add_child(_title("MEINE UNITS  (Käufe zähle ich selbst. Klick = 1 weg, z. B. nach Verkauf)"))
	units_flow = HFlowContainer.new()
	vu.add_child(units_flow)
	unit_edit = LineEdit.new()
	unit_edit.placeholder_text = "Unit hinzufügen (Name + Enter)"
	unit_edit.text_submitted.connect(func(s):
		var n := _match(s, Meta.unit_names)
		if n != "":
			brain.owned[n] = brain.owned.get(n, 0) + 1
		unit_edit.text = ""
		_refresh_all())
	vu.add_child(unit_edit)
	pu.add_child(vu)
	v.add_child(pu)
	details.append(pu)

	# Augments
	var pa := _panel(Color("1a1829"))
	var va := VBoxContainer.new()
	va.add_child(_title("MEINE AUGMENTS  (Klick = entfernen)"))
	augs_flow = HFlowContainer.new()
	va.add_child(augs_flow)
	aug_edit = LineEdit.new()
	aug_edit.placeholder_text = "Augment hinzufügen (Name + Enter)"
	aug_edit.text_submitted.connect(func(s):
		var n := _match(s, Meta.aug_names)
		if n != "" and not n in brain.my_augs:
			brain.my_augs.append(n)
		aug_edit.text = ""
		_refresh_all())
	va.add_child(aug_edit)
	pa.add_child(va)
	v.add_child(pa)
	details.append(pa)

	lbl_seen = _small()
	v.add_child(lbl_seen)
	lbl_data = _small()
	v.add_child(lbl_data)
	details.append(lbl_data)
	var b_forget := Button.new()
	b_forget.text = "Gelernte Bilder löschen"
	b_forget.flat = true
	b_forget.pressed.connect(func():
		vision.forget_all()
		_refresh_all())
	v.add_child(b_forget)
	details.append(b_forget)
	_apply_compact()

func _apply_compact() -> void:
	btn_compact.text = "Alles zeigen" if compact else "Kompakt"
	for d in details:
		d.visible = not compact

func _update_run_btn() -> void:
	btn_run.text = "Pause" if running else "Start"

func _match(s: String, names: Array) -> String:
	var q := s.strip_edges().to_lower()
	if q == "":
		return ""
	for n in names:
		if n.to_lower() == q:
			return n
	for n in names:
		if n.to_lower().begins_with(q):
			return n
	for n in names:
		if q in n.to_lower():
			return n
	return ""

# ================================================================= Anzeige

func _refresh_all() -> void:
	_render_items()
	_render_units()
	_render_augs()
	_render_advice()
	lbl_data.text = "Daten: %s, Stand %s, %d Comps  ·  Gelernt: %d Units, %d Items, %d Augments, %d Zeichen" % [Meta.source, Meta.updated_text(), Meta.comps.size(), vision.count("shop"), vision.count("item"), vision.count("aug"), vision.count("glyph")]

func _render_advice() -> void:
	var lines := []
	if rects.is_empty():
		lines.append("[color=#f5c542]Zuerst kalibrieren: Im Spiel auf „Kalibrieren ▾“ klicken und einen Bereich wählen, zum Beispiel Shop. Jeder Bereich wird sofort gespeichert, die anderen kannst du später machen.[/color]")
	else:
		var adv := brain.advise()
		var i := 1
		for a in adv:
			var col: String = KIND_COLOR.get(a["k"], "ffffff")
			if a["k"] == "info":
				lines.append("[color=#%s]%s[/color]" % [col, a["t"]])
			else:
				lines.append("[color=#%s][b]%d.[/b] %s[/color]" % [col, i, a["t"]])
				i += 1
	if not rects.is_empty():
		var miss := []
		for k in Calib.ORDER:
			if not rects.has(k):
				miss.append(Calib.NAMES[k])
		if miss.size() > 0:
			lines.append("[font_size=13][color=#8a87a6]Noch nicht kalibriert: %s[/color][/font_size]" % ", ".join(miss))
	lbl_do.text = "\n".join(lines)
	var tg := brain.target
	if tg.is_empty():
		lbl_target.text = "Noch keine."
		return
	var tline := "[b]%s[/b]  [color=#a9a6c4](%s-Tier, %s, Ø Platz %.2f)[/color]%s" % [tg["name"], tg["tier"], Brain.style_de(tg), float(tg["avg"]), "  [color=#7be07b]fest[/color]" if brain.locked else "  [color=#a9a6c4]noch flexibel[/color]"]
	var carry: Array = tg.get("carry", [])
	var items := []
	if carry.size() > 0:
		items = Brain.items_for(tg, carry[0])
	tline += "\nCarry: %s  ·  Items: %s" % [", ".join(carry), ", ".join(items)]
	tline += "\nEndboard: %s" % ", ".join(Brain.late_board(tg))
	var rk := brain.ranked_comps()
	if rk.size() > 2:
		tline += "\n[color=#8a87a6]Alternativen: %s, %s[/color]" % [rk[1]["c"]["name"], rk[2]["c"]["name"]]
	lbl_target.text = tline

func _render_items() -> void:
	var auto := rects.has("items")
	comp_title.text = "MEINE ITEMS  (erkenne ich selbst, links neben der Bank)" if auto else "MEINE KOMPONENTEN  (Linksklick +1, Rechtsklick -1. Kalibriere „items“, dann erkenne ich sie selbst)"
	for c in comp_grid.get_children():
		c.queue_free()
	for k in Meta.components:
		var b := Button.new()
		var n: int = brain.comps_have.get(k, 0)
		b.text = "%s\n%d" % [Meta.comp_de(k), n]
		b.custom_minimum_size = Vector2(0, 42)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", 12)
		b.clip_text = true
		if n > 0:
			b.add_theme_color_override("font_color", Color("7be07b"))
			b.add_theme_color_override("font_disabled_color", Color("7be07b"))
		if auto:
			b.disabled = true
		else:
			b.gui_input.connect(func(e):
				if e is InputEventMouseButton and e.pressed:
					if e.button_index == MOUSE_BUTTON_LEFT:
						brain.comps_have[k] = brain.comps_have.get(k, 0) + 1
					elif e.button_index == MOUSE_BUTTON_RIGHT:
						brain.comps_have[k] = maxi(0, brain.comps_have.get(k, 0) - 1)
					else:
						return
					_refresh_all())
		comp_grid.add_child(b)
	for c in items_flow.get_children():
		c.queue_free()
	for it in brain.items_have:
		var l := Label.new()
		l.text = "● " + it
		l.add_theme_color_override("font_color", Color("6fd3ff"))
		items_flow.add_child(l)

func _render_units() -> void:
	for c in units_flow.get_children():
		c.queue_free()
	var names: Array = brain.owned.keys()
	names.sort_custom(func(a, b): return Meta.cost(a) < Meta.cost(b))
	for n in names:
		var b := Button.new()
		b.text = "%s ×%d" % [n, brain.owned[n]]
		b.pressed.connect(func():
			brain.owned[n] -= 1
			if brain.owned[n] <= 0:
				brain.owned.erase(n)
			_refresh_all())
		units_flow.add_child(b)

func _render_augs() -> void:
	for c in augs_flow.get_children():
		c.queue_free()
	for n in brain.my_augs:
		var b := Button.new()
		b.text = n
		b.pressed.connect(func():
			brain.my_augs.erase(n)
			_refresh_all())
		augs_flow.add_child(b)

# ================================================================= Lesen

func _crop(img: Image, key: String) -> Image:
	var r: Array = rects[key]
	var W := img.get_width()
	var H := img.get_height()
	var rr := Rect2i(int(float(r[0]) * W), int(float(r[1]) * H), maxi(2, int(float(r[2]) * W)), maxi(2, int(float(r[3]) * H)))
	return img.get_region(rr.intersection(Rect2i(0, 0, W, H)))

func _slots(img: Image, key: String) -> Array:
	var whole := _crop(img, key)
	var out := []
	for sr in Calib.split(key, Rect2(Vector2.ZERO, Vector2(whole.get_size()))):
		var ri := Rect2i(sr)
		ri.size = ri.size.max(Vector2i(2, 2))
		out.append(whole.get_region(ri.intersection(Rect2i(Vector2i.ZERO, whole.get_size()))))
	return out

func _in_game() -> bool:
	return Time.get_ticks_msec() - stage_seen_ms < 20000

func _tick() -> void:
	if not running or rects.is_empty() or busy:
		return
	busy = true
	var t0 := Time.get_ticks_msec()
	var img := DisplayServer.screen_get_image(screen_idx)
	if img == null or img.is_empty():
		lbl_seen.text = "Kann den Bildschirm nicht lesen. Ist TFT im Modus „Randloses Fenster“ und der richtige Bildschirm gewählt?"
		busy = false
		return
	var seen := []
	var changed := false

	# Zahlen
	for key in ["stage", "level", "gold"]:
		if not rects.has(key):
			continue
		var crop := _crop(img, key)
		var r := vision.read_number(key, crop)
		var t: String = r["text"]
		if r["ok"]:
			match key:
				"stage":
					if Brain.stage_num(t) > 0:
						stage_seen_ms = Time.get_ticks_msec()
						if t != brain.stage:
							_on_stage(t)
							changed = true
				"level":
					if t.is_valid_int() and int(t) <= 11 and int(t) != brain.level:
						brain.level = int(t)
						changed = true
				"gold":
					if t.is_valid_int() and int(t) <= 300 and int(t) != brain.gold:
						brain.gold = int(t)
						changed = true
		elif r["glyphs"].size() > 0:
			_ask({"kind": "num", "key": key, "glyphs": r["glyphs"], "img": crop})
		seen.append("%s %s" % [NUM_NAME[key], t if t != "" else "-"])

	var active := _in_game() or not rects.has("stage")

	# Shop
	if rects.has("shop") and active:
		var names := []
		var slots := _slots(img, "shop")
		for i in slots.size():
			var r := vision.read_slot("shop%d" % i, "shop", slots[i], 9.0)
			var lab: String = r["l"]
			if lab == "":
				_ask_stable("shop%d" % i, {"kind": "shop", "sig": r["s"], "img": slots[i], "slot": i})
			if lab == Vision.EMPTY:
				empty_ticks[i] += 1
				if empty_ticks[i] == 2 and Meta.units.has(prev_shop[i]):
					var u: String = prev_shop[i]
					brain.owned[u] = brain.owned.get(u, 0) + 1
					prev_shop[i] = ""
					changed = true
			else:
				empty_ticks[i] = 0
				if lab != "" and lab != Vision.IGNORE:
					prev_shop[i] = lab
			if lab != brain.shop[i]:
				brain.shop[i] = lab
				changed = true
			names.append(lab if lab != "" else "?")
		seen.append("Shop: " + " | ".join(names))

	# Items links
	if rects.has("items") and active:
		var comps := {}
		var done := []
		var slots := _slots(img, "items")
		var unknown := 0
		for i in slots.size():
			var r := vision.read_slot("item%d" % i, "item", slots[i], 7.0)
			var lab: String = r["l"]
			if lab == "":
				unknown += 1
				_ask_stable("item%d" % i, {"kind": "item", "sig": r["s"], "img": slots[i], "slot": i})
			elif lab in Meta.components:
				comps[lab] = comps.get(lab, 0) + 1
			elif lab != Vision.EMPTY and lab != Vision.IGNORE:
				done.append(lab)
		if comps != brain.comps_have or done != brain.items_have:
			brain.comps_have = comps
			brain.items_have = done
			changed = true
		var n := 0
		for k in comps.values():
			n += k
		seen.append("Items: %d Komponenten, %d fertig%s" % [n, done.size(), ", %d unbekannt" % unknown if unknown > 0 else ""])

	# Augments
	var sn := Brain.stage_num(brain.stage)
	if rects.has("augs") and active and sn in AUG_STAGES and aug_off_stage != brain.stage:
		var offer := []
		var slots := _slots(img, "augs")
		for i in slots.size():
			var r := vision.read_slot("aug%d" % i, "aug", slots[i], 0.0)
			var lab: String = r["l"]
			if lab == "":
				_ask_stable("aug%d" % i, {"kind": "aug", "sig": r["s"], "img": slots[i], "slot": i})
			offer.append(lab if Meta.augs.has(lab) else "")
		var full := offer.size() == 3 and offer.all(func(a): return a != "")
		if full:
			aug_seen_full = true
			if offer != brain.aug_offer:
				brain.aug_offer = offer
				changed = true
		elif aug_seen_full:
			_aug_taken()
			changed = true
		seen.append("Augments: " + " | ".join(offer.map(func(a): return a if a != "" else "?")))
	elif not brain.aug_offer.is_empty():
		_aug_taken()
		changed = true

	if not active and rects.has("stage"):
		seen.append("warte auf ein Spiel")
	lbl_seen.text = "Erkannt: %s  ·  %d ms" % ["  ·  ".join(seen), Time.get_ticks_msec() - t0]
	if changed:
		_refresh_all()
	busy = false

func _on_stage(t: String) -> void:
	var sn := Brain.stage_num(t)
	if sn <= 12 and last_stage_num >= 21:
		_new_game()
	last_stage_num = sn
	brain.stage = t
	aug_seen_full = false

func _aug_taken() -> void:
	# Du hast gewählt: ich gehe davon aus, dass du meinen Vorschlag genommen hast.
	if brain.aug_offer.size() == 3:
		var best := ""
		var bs := -1e9
		for a in brain.aug_offer:
			var s := brain.aug_score(a)
			if s > bs:
				bs = s
				best = a
		if best != "" and not best in brain.my_augs:
			brain.my_augs.append(best)
	brain.aug_offer = []
	aug_seen_full = false
	aug_off_stage = brain.stage

func _new_game() -> void:
	brain.reset()
	prev_shop = ["", "", "", "", ""]
	empty_ticks = [0, 0, 0, 0, 0]
	aug_off_stage = ""
	aug_seen_full = false
	last_stage_num = 0
	unknown_prev.clear()
	_close_prompt()
	_refresh_all()

# ================================================================= Lernfragen

## Erst fragen, wenn ein unbekanntes Bild zwei Durchläufe lang gleich bleibt.
## So kommen keine Fragen zu Animationen oder kurzen Übergängen.
func _ask_stable(slot_key: String, p: Dictionary) -> void:
	var s: PackedByteArray = p["sig"]
	var prev: PackedByteArray = unknown_prev.get(slot_key, PackedByteArray())
	unknown_prev[slot_key] = s
	if prev.is_empty() or Vision.dist(s, prev, 6.0) >= 6.0:
		return
	_ask(p)

func _ask(p: Dictionary) -> void:
	if not prompt.is_empty():
		return
	var key := str(p["kind"]) + str(p.get("key", ""))
	if skip_until.get(key, 0) > Time.get_ticks_msec():
		return
	prompt = p
	prompt_img.texture = ImageTexture.create_from_image(p["img"])
	prompt_edit.text = ""
	match p["kind"]:
		"num":
			prompt_q.text = "Was steht hier? (%s, genau wie im Bild, z. B. %s, dann Enter)" % [NUM_NAME[p["key"]], NUM_EXAMPLE[p["key"]]]
			prompt_edit.placeholder_text = "Eintippen + Enter"
		"shop":
			prompt_q.text = "Welcher Champion ist in Shop-Platz %d?" % (p["slot"] + 1)
			prompt_edit.placeholder_text = "2 bis 3 Buchstaben tippen, dann anklicken"
		"aug":
			prompt_q.text = "Welches Augment ist das (%s)?" % Brain.SIDE[p["slot"]]
			prompt_edit.placeholder_text = "Namen tippen, dann anklicken"
		"item":
			prompt_q.text = "Welches Item liegt auf Item-Platz %d (von oben)?" % (p["slot"] + 1)
			prompt_edit.placeholder_text = "Fertiges Item? Namen tippen"
	_fill_quick()
	_prompt_typed("")
	prompt_box.visible = true

func _fill_quick() -> void:
	for c in prompt_quick.get_children():
		c.queue_free()
	if prompt.get("kind", "") != "item":
		return
	for k in Meta.components:
		_btn(prompt_quick, Meta.comp_de(k), func(): _answer(k))
	_btn(prompt_quick, "Leer", func(): _answer(Vision.EMPTY))

func _prompt_typed(s: String) -> void:
	for c in prompt_sugg.get_children():
		c.queue_free()
	if prompt.is_empty():
		return
	var kind: String = prompt["kind"]
	if kind == "num":
		_btn(prompt_sugg, "Gerade nicht im Spiel", func(): _skip(20.0))
		return
	var names: Array = {"shop": Meta.unit_names, "aug": Meta.aug_names, "item": Meta.item_names}[kind]
	var q := s.strip_edges().to_lower()
	if q != "":
		var hits := names.filter(func(n): return n.to_lower().begins_with(q))
		hits.append_array(names.filter(func(n): return q in n.to_lower() and not n.to_lower().begins_with(q)))
		for n in hits.slice(0, 8):
			_btn(prompt_sugg, n, func(): _answer(n))
	if kind == "shop":
		_btn(prompt_sugg, "Leerer Platz", func(): _answer(Vision.EMPTY))
	if kind == "aug":
		_btn(prompt_sugg, "Gerade keine Augment-Wahl", func():
			aug_off_stage = brain.stage
			_close_prompt())
	_btn(prompt_sugg, "Kein Spielbild, ignorieren", func(): _answer(Vision.IGNORE))
	_btn(prompt_sugg, "Später (30 s)", func(): _skip(30.0))

func _btn(parent: Control, t: String, f: Callable) -> void:
	var b := Button.new()
	b.text = t
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(f)
	parent.add_child(b)

func _prompt_submit(s: String) -> void:
	if prompt.is_empty():
		return
	if prompt["kind"] == "num":
		if vision.learn_number(prompt["glyphs"], s):
			_close_prompt()
			_refresh_all()
		else:
			prompt_q.text = "Die Anzahl passt nicht: ich sehe %d Zeichen. Bitte genau so eintippen, wie es im Bild steht." % prompt["glyphs"].size()
		return
	var names: Array = {"shop": Meta.unit_names, "aug": Meta.aug_names, "item": Meta.item_names}[prompt["kind"]]
	var n := _match(s, names)
	if prompt["kind"] == "item" and n == "":
		n = _match(s, Meta.components)
	if n != "":
		_answer(n)

func _answer(label: String) -> void:
	if prompt.is_empty():
		return
	vision.learn(prompt["kind"], prompt["sig"], label)
	_close_prompt()
	_refresh_all()

func _skip(sec: float) -> void:
	var key := str(prompt.get("kind", "")) + str(prompt.get("key", ""))
	skip_until[key] = Time.get_ticks_msec() + int(sec * 1000.0)
	_close_prompt()

func _close_prompt() -> void:
	prompt = {}
	prompt_box.visible = false
	prompt_edit.release_focus()

# ================================================================= Kalibrieren

var calib: Calib = null
var calib_win: Window = null

func _start_calibration(key: String = "") -> void:
	if calib_win != null:
		calib_win.grab_focus()
		return
	running = false
	_update_run_btn()
	_close_prompt()
	var win := get_window()
	var old_pos := win.position
	var sp := DisplayServer.screen_get_position(screen_idx)
	var ss := DisplayServer.screen_get_size(screen_idx)
	# Hauptfenster kurz aus dem Bild schieben, damit es nicht mit fotografiert wird
	win.position = sp + ss + Vector2i(200, 200)
	await get_tree().create_timer(0.35).timeout
	var img := DisplayServer.screen_get_image(screen_idx)
	win.position = old_pos
	if img == null or img.is_empty():
		lbl_seen.text = "Kann den Bildschirm nicht lesen."
		running = true
		_update_run_btn()
		return
	# Eigenes Fenster zum Rahmenziehen. Groß, mit Rand, kein Vollbild.
	var big := Vector2i(int(ss.x * 0.92), int(ss.y * 0.88))
	calib_win = Window.new()
	calib_win.title = "TFT Boss: Kalibrieren" + ("" if key == "" else " (%s)" % Calib.NAMES[key])
	calib_win.size = big
	calib_win.position = sp + (ss - big) / 2
	calib_win.always_on_top = true
	calib_win.transient = false
	calib_win.wrap_controls = false
	calib_win.close_requested.connect(func(): _end_calibration.call_deferred())
	calib = Calib.new()
	calib_win.add_child(calib)
	calib.setup(img, rects, key)
	calib.changed.connect(func(r):
		# sofort speichern, sobald ein Rahmen gezogen ist
		rects = r
		_save_settings())
	calib.finished.connect(func(r):
		rects = r
		_end_calibration.call_deferred())
	calib.cancelled.connect(func(): _end_calibration.call_deferred())
	add_child(calib_win)
	calib_win.show()
	calib_win.grab_focus()

func _end_calibration() -> void:
	if calib_win != null and is_instance_valid(calib_win):
		calib_win.queue_free()
	calib_win = null
	calib = null
	vision.cache.clear()
	unknown_prev.clear()
	_save_settings()
	running = true
	_update_run_btn()
	_refresh_all()
