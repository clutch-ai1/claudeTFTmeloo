extends Control
## TFT Boss: Ich sage, was zu tun ist. Du klickst.

const SETTINGS := "user://einstellungen.json"
const TICK := 0.6
const AUG_STAGES := [21, 32, 42]
const KIND_COLOR := {"aug": "c48cff", "item": "6fd3ff", "buy": "7be07b", "level": "f5c542", "roll": "ff9a4a", "info": "a9a6c4"}
const NUM_NAME := {"stage": "Stage", "level": "Level", "gold": "Gold", "hp": "dein Leben", "lobby": "Leben eines Spielers"}
const NUM_EXAMPLE := {"stage": "3-2", "level": "6", "gold": "34", "hp": "78", "lobby": "64"}
## PvP-Runden pro Stage (x-4 ist Karussell, x-7 PvE)
const PVP_ROUNDS := [1, 2, 3, 5, 6]

var vision := Vision.new()
var pilot := Autopilot.new()
var auto_on := false
var auto_title := ""
var auto_next_ms := 0
var auto_pending := {}           # Shop-Platz -> Zeit, bis wann er als "gerade gekauft" gilt
var auto_tried := {}             # Shop-Platz -> Unit, die schon versucht wurde (Kauf ging nicht durch)
var auto_log: Array = []
var auto_last_img_size := Vector2i.ZERO
var btn_auto: Button
var scouting := false
var scouted_stage := ""
var stage_changed_ms := 0
var btn_scout: Button
var btn_admin: Button
var blocked_seen := 0
var use_ocr := false
var ocr_msg := ""
var ocr_last_log := 0
var shop_empty_since := [0, 0, 0, 0, 0]
const REC_MAX := 200
var rec_count := 0
var rec_stage := ""
var lbl_auto: RichTextLabel
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
var round_hp := -1                # Leben zu Beginn der aktuellen Runde
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
var preview_box: PanelContainer
var preview_flow: HFlowContainer
var preview_tex := {}            # Bereich -> TextureRect

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
	_log_file("Start, Version 7, Bildschirm %d" % screen_idx)
	if OS.get_name() == "Windows" and pilot.start():
		await get_tree().create_timer(2.5).timeout
		var info := pilot.ocr_info()
		use_ocr = info.begins_with("OK")
		ocr_msg = "Texterkennung an (%s)" % info.substr(3) if use_ocr else "Texterkennung nicht verfügbar: " + info
		_log_file(ocr_msg)
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
		pilot.stop()

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

	var pap := _panel(Color("2a1630"))
	var vap := VBoxContainer.new()
	var hap := HBoxContainer.new()
	var tap := _title("AUTOPILOT  (die KI klickt selbst, F8 = sofort aus)")
	tap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hap.add_child(tap)
	btn_auto = Button.new()
	btn_auto.text = "Autopilot starten"
	btn_auto.pressed.connect(_toggle_auto)
	hap.add_child(btn_auto)
	btn_scout = Button.new()
	btn_scout.text = "Jetzt scouten"
	btn_scout.pressed.connect(func(): _scout(true))
	hap.add_child(btn_scout)
	btn_admin = Button.new()
	btn_admin.text = "Als Admin neu starten"
	btn_admin.visible = false
	btn_admin.pressed.connect(func():
		_save_settings()
		pilot.stop()
		Autopilot.restart_as_admin()
		get_tree().quit())
	vap.add_child(btn_admin)
	vap.add_child(hap)
	lbl_auto = _rich()
	lbl_auto.add_theme_font_size_override("normal_font_size", 14)
	vap.add_child(lbl_auto)
	pap.add_child(vap)
	v.add_child(pap)

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

	# Was ich sehe: kleine Live-Bilder der kalibrierten Bereiche
	preview_box = _panel(Color("1a1829"))
	var vpv := VBoxContainer.new()
	vpv.add_child(_title("WAS ICH SEHE  (sitzt ein Rahmen falsch: Kalibrieren ▾ und den Bereich neu ziehen)"))
	preview_flow = HFlowContainer.new()
	vpv.add_child(preview_flow)
	preview_box.add_child(vpv)
	v.add_child(preview_box)
	details.append(preview_box)

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
	var plan_txt: String = {"win": "[color=#7be07b]Winstreak[/color]", "loss": "[color=#ff9a4a]Lossstreak[/color]"}.get(brain.plan, "[color=#a9a6c4]normal[/color]")
	var res_txt := "".join(brain.results.slice(maxi(0, brain.results.size() - 8))) if brain.results.size() > 0 else "-"
	var rank := brain.hp_rank()
	var head := "Plan: %s  ·  Runden: %s  ·  Leben: %s%s" % [plan_txt, res_txt, str(brain.hp) if brain.hp >= 0 else "-", ("  ·  Platz %d nach Leben" % rank) if rank > 0 else ""]
	if brain.win_chance >= 0.0:
		var wcol := "7be07b" if brain.win_chance >= 0.55 else ("ff9a4a" if brain.win_chance <= 0.42 else "f5c542")
		head += "\n[color=#%s][b]Siegchance %d %%[/b][/color]  [color=#a9a6c4](deine Traits %.1f, Gegner Ø %.1f, stärkster %.1f)[/color]" % [wcol, int(brain.win_chance * 100), brain.my_score, _avg(brain.opp_scores), brain.opp_scores.max()]
	if brain.plan_why != "":
		head += "\n[color=#a9a6c4]%s[/color]" % brain.plan_why
	var tline := head + "\n[b]%s[/b]  [color=#a9a6c4](%s-Tier, %s, Ø Platz %.2f)[/color]%s" % [tg["name"], tg["tier"], Brain.style_de(tg), float(tg["avg"]), "  [color=#7be07b]fest[/color]" if brain.locked else "  [color=#a9a6c4]noch flexibel[/color]"]
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
	for it in brain.consumables:
		var l2 := Label.new()
		l2.text = "◆ " + Meta.comp_de(it)
		l2.add_theme_color_override("font_color", Color("e8c27a"))
		items_flow.add_child(l2)

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
	var r: Array = rects[key]
	for sr in Calib.split(key, Rect2(Vector2.ZERO, Vector2(whole.get_size())), int(r[4]) if r.size() > 4 else 0):
		var ri := Rect2i(sr)
		ri.size = ri.size.max(Vector2i(2, 2))
		out.append(whole.get_region(ri.intersection(Rect2i(Vector2i.ZERO, whole.get_size()))))
	return out

func _update_preview(img: Image) -> void:
	if compact or not preview_box.is_visible_in_tree():
		return
	for k in Calib.ORDER:
		if not rects.has(k):
			if preview_tex.has(k):
				preview_tex[k].get_parent().queue_free()
				preview_tex.erase(k)
			continue
		var crop := _crop(img, k)
		if not preview_tex.has(k):
			var vb := VBoxContainer.new()
			var tr := TextureRect.new()
			tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			var lab := Label.new()
			lab.text = Calib.NAMES[k]
			lab.add_theme_font_size_override("font_size", 11)
			lab.add_theme_color_override("font_color", Color("8a87a6"))
			vb.add_child(tr)
			vb.add_child(lab)
			preview_flow.add_child(vb)
			preview_tex[k] = tr
		var tr2: TextureRect = preview_tex[k]
		var hgt := 34.0 if k in ["gold", "level", "stage"] else (90.0 if k == "items" else 46.0)
		var asp := float(crop.get_width()) / maxf(1.0, float(crop.get_height()))
		tr2.custom_minimum_size = Vector2(clampf(hgt * asp, 24.0, 420.0), hgt)
		tr2.texture = ImageTexture.create_from_image(crop)

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
	_update_preview(img)

	# Texterkennung: liest Stage, Gold, Level, Leben, Spielerliste, Traits und Shop-Namen direkt
	var done_ocr := {}
	if use_ocr:
		var res := _ocr_tick(img)
		done_ocr = res["done"]
		if res["changed"]:
			changed = true
		seen.append_array(res["seen"])

	# Zahlen (ohne Texterkennung: gelernte Ziffern)
	for key in ["stage", "level", "gold"]:
		if not rects.has(key) or done_ocr.has(key):
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
			_ask({"kind": "num", "key": key, "glyphs": r["glyphs"], "meta": r.get("meta", []), "img": crop})
		seen.append("%s %s" % [NUM_NAME[key], t if t != "" else "-"])

	# Eigenes Leben
	if rects.has("hp") and not done_ocr.has("hp"):
		var crop_hp := _crop(img, "hp")
		var rh := vision.read_number("hp", crop_hp)
		if rh["ok"] and str(rh["text"]).is_valid_int():
			var h := int(rh["text"])
			if h >= 0 and h <= 100 and h != brain.hp:
				brain.hp = h
				changed = true
		elif rh["glyphs"].size() > 0 and _in_game():
			_ask({"kind": "num", "key": "hp", "glyphs": rh["glyphs"], "meta": rh.get("meta", []), "img": crop_hp})
		seen.append("Leben %s" % (str(brain.hp) if brain.hp >= 0 else "-"))
	# Leben aller Spieler
	if rects.has("lobby") and _in_game() and not done_ocr.has("lobby"):
		var hs := []
		var ls := _slots(img, "lobby")
		for i in ls.size():
			var rl := vision.read_number("lobby%d" % i, ls[i])
			if rl["ok"] and str(rl["text"]).is_valid_int():
				hs.append(int(rl["text"]))
			elif rl["glyphs"].size() > 0:
				_ask({"kind": "num", "key": "lobby", "glyphs": rl["glyphs"], "meta": rl.get("meta", []), "img": ls[i]})
		if hs != brain.lobby_hp:
			brain.lobby_hp = hs
			changed = true

	var active := _in_game() or not rects.has("stage")

	# Eigene Trait-Stärke (nicht während des Scoutens, dann zeigt die Leiste den Gegner)
	if rects.has("traits") and active and not scouting and not done_ocr.has("traits"):
		var ts := _trait_score(img, true)
		if ts["ok"] and absf(ts["score"] - brain.my_score) > 0.01:
			brain.my_score = ts["score"]
			brain.update_win_chance()
			changed = true
		seen.append("Traits %s" % (str(snappedf(brain.my_score, 0.1)) if brain.my_score >= 0 else "?"))

	# Shop
	if rects.has("shop") and active and not done_ocr.has("shop"):
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
		var cons := []
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
			elif Meta.CONSUMABLES.has(lab):
				cons.append(lab)
			elif lab != Vision.EMPTY and lab != Vision.IGNORE:
				done.append(lab)
		if comps != brain.comps_have or done != brain.items_have or cons != brain.consumables:
			brain.comps_have = comps
			brain.items_have = done
			brain.consumables = cons
			changed = true
		var n := 0
		for k in comps.values():
			n += k
		seen.append("Items: %d Komponenten, %d fertig, %d Verbrauch%s" % [n, done.size(), cons.size(), ", %d unbekannt" % unknown if unknown > 0 else ""])

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
	auto_last_img_size = img.get_size()
	if auto_on and not scouting and brain.stage != "" and rec_stage != brain.stage and Time.get_ticks_msec() - stage_changed_ms > 2500:
		rec_stage = brain.stage
		_record(img, "eigenes")
	if changed:
		_refresh_all()
		changed = false
	_autopilot_step()
	lbl_seen.text = "Erkannt: %s  ·  %d ms" % ["  ·  ".join(seen), Time.get_ticks_msec() - t0]
	if changed:
		_refresh_all()
	busy = false

func _on_stage(t: String) -> void:
	var sn := Brain.stage_num(t)
	if sn <= 12 and last_stage_num >= 21:
		_new_game()
	# Ergebnis der Runde, die gerade zu Ende ging: Leben verloren = Niederlage
	var prev := last_stage_num
	if prev >= 21 and (prev % 10) in PVP_ROUNDS and round_hp >= 0 and brain.hp >= 0 and sn > prev:
		brain.results.append("L" if brain.hp < round_hp else "W")
		if auto_on:
			_log("Runde %d-%d: %s" % [prev / 10, prev % 10, "verloren" if brain.hp < round_hp else "gewonnen"])
	round_hp = brain.hp
	last_stage_num = sn
	brain.stage = t
	stage_changed_ms = Time.get_ticks_msec()
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
		"tier":
			prompt_q.text = "Welche Stufe hat dieser Trait (Farbe des Symbols)?"
			prompt_edit.placeholder_text = "Knopf anklicken"
		"item":
			prompt_q.text = "Welches Item liegt auf Item-Platz %d (von oben)?" % (p["slot"] + 1)
			prompt_edit.placeholder_text = "Fertiges Item? Namen tippen"
	_fill_quick()
	_prompt_typed("")
	prompt_box.visible = true

func _fill_quick() -> void:
	for c in prompt_quick.get_children():
		c.queue_free()
	if prompt.get("kind", "") == "tier":
		for t in [["Inaktiv (grau)", "inaktiv"], ["Bronze", "bronze"], ["Silber", "silber"], ["Gold", "gold"], ["Prismatisch", "prisma"], ["Leer / kein Trait", Vision.EMPTY]]:
			var lab: String = t[1]
			_btn(prompt_quick, t[0], func(): _answer(lab))
		return
	if prompt.get("kind", "") != "item":
		return
	for k in Meta.components:
		_btn(prompt_quick, Meta.comp_de(k), func(): _answer(k))
	_btn(prompt_quick, "Leer", func(): _answer(Vision.EMPTY))
	var l := Label.new()
	l.text = "Verbrauchsitems:"
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", Color("e8c27a"))
	prompt_quick.add_child(l)
	for k in Meta.CONSUMABLES.keys():
		_btn(prompt_quick, Meta.CONSUMABLES[k], func(): _answer(k))

func _prompt_typed(s: String) -> void:
	for c in prompt_sugg.get_children():
		c.queue_free()
	if prompt.is_empty():
		return
	var kind: String = prompt["kind"]
	if kind == "num":
		_btn(prompt_sugg, "Gerade nicht im Spiel", func(): _skip(20.0))
		return
	if kind == "tier":
		_btn(prompt_sugg, "Später (30 s)", func(): _skip(30.0))
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
		var msg := vision.learn_number(prompt["glyphs"], s, prompt.get("meta", []))
		if msg == "":
			_close_prompt()
			_refresh_all()
		else:
			prompt_q.text = msg
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

# ================================================================= Autopilot

func _auto_status(t: String) -> void:
	var lines := ["[b]%s[/b]" % t]
	for l in auto_log.slice(maxi(0, auto_log.size() - 4)):
		lines.append("[color=#a9a6c4]%s[/color]" % l)
	lbl_auto.text = "\n".join(lines)

func _log(t: String) -> void:
	_log_file("Autopilot: " + t)
	var tm := Time.get_time_dict_from_system()
	auto_log.append("%02d:%02d:%02d  %s" % [tm["hour"], tm["minute"], tm["second"], t])
	if auto_log.size() > 30:
		auto_log.pop_front()

func _toggle_auto() -> void:
	if auto_on:
		_auto_off("Autopilot aus.")
		return
	if rects.is_empty() or not rects.has("shop") or not rects.has("gold"):
		_auto_status("Erst Shop und Gold kalibrieren.")
		return
	if not pilot.start():
		_auto_status(pilot.error)
		return
	btn_auto.disabled = true
	for i in range(3, 0, -1):
		_auto_status("Wechsle jetzt ins TFT-Fenster ... %d" % i)
		await get_tree().create_timer(1.0).timeout
	var st := pilot.state()
	btn_auto.disabled = false
	if st.get("dead", false):
		_auto_status("Der Eingabe-Helfer läuft nicht (PowerShell blockiert?).")
		return
	if not st.get("admin", true):
		btn_admin.visible = true
		_auto_status("TFT läuft mit Adminrechten, deshalb blockiert Windows meine Klicks. Klick auf „Als Admin neu starten“ und bestätige die Windows-Frage.")
		return
	blocked_seen = int(st.get("blocked", 0))
	auto_title = st["title"]
	# Maus-Selbsttest: Cursor bewegen und zurücklesen
	var before := pilot.cursor()
	var test := DisplayServer.screen_get_position(screen_idx) + DisplayServer.screen_get_size(screen_idx) / 2
	pilot.move(test)
	await get_tree().create_timer(0.15).timeout
	var after := pilot.cursor()
	pilot.move(before)
	_log_file("Maus-Test: Ziel %s, Ergebnis %s, Admin %s, Fenster '%s'" % [str(test), str(after), str(st.get("admin")), auto_title])
	if (after - test).length() > 3:
		_auto_status("Maus-Test fehlgeschlagen: Windows lässt mich die Maus nicht bewegen. Als Administrator starten.")
		btn_admin.visible = true
		return
	if auto_title == "" or auto_title == get_window().title:
		_auto_status("TFT war nicht vorne. Nochmal starten und in den 3 Sekunden ins Spiel klicken.")
		return
	auto_on = true
	timer.wait_time = 0.35
	running = true
	_update_run_btn()
	btn_auto.text = "Autopilot stoppen"
	_log("an, steuert: " + auto_title)
	_auto_status("Autopilot an. F8 schaltet aus.")

func _auto_off(why: String) -> void:
	auto_on = false
	timer.wait_time = TICK
	btn_auto.text = "Autopilot starten"
	_log(why)
	_auto_status(why)

func _gpos(key: String, idx: int) -> Vector2i:
	## Mitte eines Platzes in Bildschirm-Koordinaten
	var r: Array = rects[key]
	var W := float(auto_last_img_size.x)
	var H := float(auto_last_img_size.y)
	var whole := Rect2(float(r[0]) * W, float(r[1]) * H, float(r[2]) * W, float(r[3]) * H)
	var parts := Calib.split(key, whole, int(r[4]) if r.size() > 4 else 0)
	var c: Vector2 = parts[clampi(idx, 0, parts.size() - 1)].get_center()
	return DisplayServer.screen_get_position(screen_idx) + Vector2i(c)

func _autopilot_step() -> void:
	if not auto_on:
		return
	var st := pilot.state()
	if st.get("dead", false):
		_auto_off("Eingabe-Helfer beendet, Autopilot aus.")
		return
	if st["panic"]:
		_auto_off("F8 gedrückt, Autopilot aus.")
		return
	if int(st.get("blocked", 0)) > blocked_seen:
		blocked_seen = int(st.get("blocked", 0))
		btn_admin.visible = true
		_auto_off("Windows hat meine Klicks blockiert. TFT Boss als Administrator starten (Knopf unten).")
		return
	if st["title"] != auto_title:
		_auto_status("Pausiert: TFT ist nicht im Vordergrund.")
		return
	var now := Time.get_ticks_msec()
	if now < auto_next_ms:
		return
	if not _in_game():
		_auto_status("Wartet auf ein Spiel (Stage nicht erkannt).")
		return
	if scouting:
		_auto_status("Scoutet die Gegner ...")
		return
	var snum := Brain.stage_num(brain.stage)
	if scouted_stage != brain.stage and (snum % 10) in PVP_ROUNDS and snum >= 21 and now - stage_changed_ms > 1200 and rects.has("lobby") and rects.has("traits"):
		_scout()
		return
	for k in auto_pending.keys():
		if auto_pending[k] < now:
			auto_pending.erase(k)
	# Geklickt, aber die Karte ist noch da: Kauf ging nicht (Bank voll, zu wenig Gold). Nicht nochmal versuchen.
	for k in auto_tried.keys():
		if brain.shop[k] != auto_tried[k]:
			auto_tried.erase(k)
	for a in brain.advise():
		match a["k"]:
			"aug":
				if rects.has("augs"):
					pilot.click(_gpos("augs", a["idx"]))
					_log("Augment: " + str(brain.aug_offer[a["idx"]]))
					auto_next_ms = now + 1500
					_auto_status("Nimmt Augment.")
					return
			"buy":
				var sl: int = a["slot"]
				if auto_pending.has(sl) or auto_tried.get(sl, "") == a["u"]:
					continue
				pilot.click(_gpos("shop", sl))
				auto_pending[sl] = now + 2500
				auto_tried[sl] = a["u"]
				_log("Kauft %s (Platz %d)" % [a["u"], sl + 1])
				auto_next_ms = now + 450
				_auto_status("Kauft %s." % a["u"])
				return
			"level":
				if brain.gold >= 4:
					pilot.key(Autopilot.VK_F)
					_log("Level-XP gekauft (F)")
					auto_next_ms = now + 700
					_auto_status("Kauft XP.")
					return
			"roll":
				if brain.gold > int(a.get("until", 50)) + 1:
					pilot.key(Autopilot.VK_D)
					vision.cache.clear()
					_log("Rollt (D), %d Gold" % brain.gold)
					auto_next_ms = now + 1100
					_auto_status("Rollt.")
					return
	_auto_status("Nichts zu tun, wartet.")

# ================================================================= Scouten

## Stärke der Traits in der Leiste links. Ergebnis {"score", "ok", "rows"}
func _trait_score(img: Image, ask: bool) -> Dictionary:
	var rows := _slots(img, "traits")
	var score := 0.0
	var ok := true
	var labels := []
	for i in rows.size():
		var row: Image = rows[i]
		var h := row.get_height()
		var icon := row.get_region(Rect2i(0, 0, mini(h, row.get_width()), h))
		var r := vision.read_tier("trait%d" % i, icon)
		var lab: String = r["l"]
		if lab == "":
			ok = false
			if ask:
				_ask_stable("trait%d" % i, {"kind": "tier", "sig": r["s"], "img": icon, "slot": i})
		elif Vision.TIERS.has(lab):
			score += Vision.TIERS[lab]
		labels.append(lab)
	return {"score": score, "ok": ok, "rows": labels}

## Klickt alle Gegner in der Spielerliste an, liest ihre Trait-Leiste und kehrt zum eigenen Board zurück.
func _scout(manual: bool = false) -> void:
	if scouting:
		return
	if not (rects.has("lobby") and rects.has("traits")):
		_auto_status("Zum Scouten „Leben aller Spieler“ und „Trait-Leiste“ kalibrieren.")
		return
	if not pilot.ok and not pilot.start():
		_auto_status(pilot.error)
		return
	if brain.hp < 0 or brain.lobby_hp.size() < 2:
		_auto_status("Scouten geht erst, wenn dein Leben und die Spielerliste erkannt werden.")
		return
	var me := brain.lobby_hp.find(brain.hp)
	if me < 0:
		_auto_status("Ich finde dich nicht in der Spielerliste (dein Leben passt zu keinem Eintrag).")
		return
	if manual:
		for i in range(3, 0, -1):
			_auto_status("Scouten startet, wechsle ins TFT-Fenster ... %d" % i)
			await get_tree().create_timer(1.0).timeout
	scouting = true
	var n := brain.lobby_hp.size()
	var scores := []
	for i in n:
		if i == me or int(brain.lobby_hp[i]) <= 0:
			continue
		pilot.click(_gpos("lobby", i))
		await get_tree().create_timer(0.45).timeout
		var shot := DisplayServer.screen_get_image(screen_idx)
		if shot == null or shot.is_empty():
			continue
		_record(shot, "gegner%d" % (i + 1))
		if use_ocr and rects.has("traits"):
			var tt := pilot.ocr([_ocr_png(shot.get_region(_rect_px(shot, "traits")), "scout_traits", 2)])
			if tt.size() == 1:
				var tc := OcrRead.traits(str(tt[0]), Meta.traits.keys())
				scores.append(OcrRead.trait_power(tc))
				_log_file("Gegner %d: %s" % [i + 1, str(tc)])
			continue
		var ts := _trait_score(shot, true)
		if ts["ok"]:
			scores.append(ts["score"])
	pilot.click(_gpos("lobby", me))
	await get_tree().create_timer(0.3).timeout
	scouting = false
	scouted_stage = brain.stage
	if scores.size() > 0:
		brain.opp_scores = scores
		brain.update_win_chance()
		var best := 0.0
		for x in scores:
			best = maxf(best, x)
		_log("Gescoutet: %d Gegner, Ø %.1f, stärkster %.1f, du %.1f" % [scores.size(), _avg(scores), best, brain.my_score])
	else:
		_log("Scouten: Trait-Stufen noch unbekannt, bitte die Fragen beantworten.")
	_refresh_all()

func _avg(a: Array) -> float:
	var s := 0.0
	for x in a:
		s += float(x)
	return s / maxf(1.0, float(a.size()))

# ================================================================= Aufnahmen

## Speichert Bilder für den späteren Board-Scanner: Desktop\TFT Boss\aufnahmen
func _rec_dir() -> String:
	var d := OS.get_system_dir(OS.SYSTEM_DIR_DESKTOP).path_join("TFT Boss").path_join("aufnahmen")
	DirAccess.make_dir_recursive_absolute(d)
	return d

func _record(img: Image, what: String) -> void:
	if img == null or img.is_empty() or rec_count >= REC_MAX:
		return
	var st := brain.stage.replace("-", "_") if brain.stage != "" else "x"
	var t := Time.get_datetime_string_from_system().replace(":", "").replace("-", "").replace("T", "_")
	var path := _rec_dir().path_join("%s_%s_%s.jpg" % [t, st, what])
	if img.save_jpg(path, 0.9) == OK:
		rec_count += 1

# ================================================================= Texterkennung (OCR)

func _ocr_dir() -> String:
	var d := ProjectSettings.globalize_path("user://ocr")
	DirAccess.make_dir_recursive_absolute(d)
	return d

## Speichert einen Ausschnitt vergrößert (Texterkennung liest größere Schrift besser)
func _ocr_png(img: Image, name: String, scale: int = 2) -> String:
	var c := img.duplicate() as Image
	if scale > 1:
		c.resize(c.get_width() * scale, c.get_height() * scale, Image.INTERPOLATE_CUBIC)
	var path := _ocr_dir().path_join(name + ".png")
	c.save_png(path)
	return path

func _rect_px(img: Image, key: String) -> Rect2i:
	var r: Array = rects[key]
	var W := img.get_width()
	var H := img.get_height()
	return Rect2i(int(float(r[0]) * W), int(float(r[1]) * H), maxi(2, int(float(r[2]) * W)), maxi(2, int(float(r[3]) * H))).intersection(Rect2i(0, 0, W, H))

func _ocr_tick(img: Image) -> Dictionary:
	var keys := []
	var paths := []
	for k in ["stage", "gold", "level", "hp", "lobby", "traits"]:
		if rects.has(k):
			keys.append(k)
			paths.append(_ocr_png(img.get_region(_rect_px(img, k)), k, 3 if k in ["stage", "gold", "level", "hp"] else 2))
	if rects.has("shop"):
		var sr := _rect_px(img, "shop")
		for i in 5:
			var w := sr.size.x / 5
			# nur die Namenszeile unten auf der Karte
			var nr := Rect2i(sr.position.x + w * i, sr.position.y + int(sr.size.y * 0.76), w, int(sr.size.y * 0.24))
			keys.append("shop%d" % i)
			paths.append(_ocr_png(img.get_region(nr), "shop%d" % i, 3))
	var t0 := Time.get_ticks_msec()
	var texts := pilot.ocr(paths)
	var out := {"done": {}, "changed": false, "seen": []}
	if texts.size() != keys.size():
		_log_file("OCR-Fehler: %d Antworten für %d Bilder" % [texts.size(), keys.size()])
		return out
	var T := {}
	for i in keys.size():
		T[keys[i]] = str(texts[i])
		if str(texts[i]).begins_with("ERR"):
			_log_file("OCR %s: %s" % [keys[i], texts[i]])
	var ch := false
	if T.has("stage"):
		var st := OcrRead.stage(T["stage"])
		if st != "":
			out["done"]["stage"] = true
			stage_seen_ms = Time.get_ticks_msec()
			if st != brain.stage:
				_on_stage(st)
				ch = true
	if T.has("gold"):
		var g := OcrRead.gold(T["gold"])
		if g >= 0:
			out["done"]["gold"] = true
			if g != brain.gold:
				brain.gold = g
				ch = true
	if T.has("level"):
		var lv := OcrRead.level(T["level"])
		if lv > 0:
			out["done"]["level"] = true
			if lv != brain.level:
				brain.level = lv
				ch = true
	if T.has("hp"):
		var h := OcrRead.hp(T["hp"])
		if h >= 0:
			out["done"]["hp"] = true
			if h != brain.hp:
				brain.hp = h
				ch = true
	if T.has("lobby"):
		var lb := OcrRead.lobby(T["lobby"])
		if lb.size() >= 2:
			out["done"]["lobby"] = true
			var hs := lb.map(func(e): return e["hp"])
			if hs != brain.lobby_hp:
				brain.lobby_hp = hs
				ch = true
	if T.has("traits") and not scouting:
		var tc := OcrRead.traits(T["traits"], Meta.traits.keys())
		out["done"]["traits"] = true
		var pw := OcrRead.trait_power(tc)
		brain.my_traits = tc
		if absf(pw - brain.my_score) > 0.01:
			brain.my_score = pw
			brain.update_win_chance()
			ch = true
	if rects.has("shop"):
		out["done"]["shop"] = true
		var names := []
		var now := Time.get_ticks_msec()
		for i in 5:
			var txt: String = T.get("shop%d" % i, "")
			var u := OcrRead.match_name(txt, Meta.unit_names)
			var lab := u if u != "" else (Vision.EMPTY if txt.strip_edges().length() < 2 else "")
			if lab == Vision.EMPTY:
				if shop_empty_since[i] == 0:
					shop_empty_since[i] = now
				# Karte verschwunden: gekauft (nicht beim Neu-Rollen, da kommen sofort neue Namen)
				var clicked: bool = auto_tried.get(i, "") == prev_shop[i]
				if now - shop_empty_since[i] > 500 and Meta.units.has(prev_shop[i]) and (clicked or not auto_on):
					brain.owned[prev_shop[i]] = brain.owned.get(prev_shop[i], 0) + 1
					_log_file("gekauft erkannt: " + prev_shop[i])
					prev_shop[i] = ""
					ch = true
			else:
				shop_empty_since[i] = 0
				if lab != "":
					prev_shop[i] = lab
			if lab != brain.shop[i]:
				brain.shop[i] = lab
				ch = true
			names.append(lab if lab != "" else "?")
		out["seen"].append("Shop: " + " | ".join(names))
	out["changed"] = ch
	out["seen"].append("OCR %d ms" % (Time.get_ticks_msec() - t0))
	if Time.get_ticks_msec() - ocr_last_log > 8000:
		ocr_last_log = Time.get_ticks_msec()
		_log_file("Gelesen: Stage %s, Gold %d, Level %d, Leben %d, Lobby %s, Traits %s, Shop %s" % [brain.stage, brain.gold, brain.level, brain.hp, str(brain.lobby_hp), str(brain.my_traits), str(brain.shop)])
	return out

# ================================================================= Protokoll

func _log_file(t: String) -> void:
	var d := OS.get_system_dir(OS.SYSTEM_DIR_DESKTOP).path_join("TFT Boss")
	DirAccess.make_dir_recursive_absolute(d)
	var path := d.path_join("protokoll.txt")
	var f: FileAccess
	if FileAccess.file_exists(path) and FileAccess.get_file_as_bytes(path).size() < 2000000:
		f = FileAccess.open(path, FileAccess.READ_WRITE)
		if f:
			f.seek_end()
	else:
		f = FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_line("%s  %s" % [Time.get_datetime_string_from_system(), t])
		f.close()
