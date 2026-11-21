class_name Calib
extends Control
## Einmalig festlegen, wo auf deinem Bildschirm Shop, Gold, Level, Stage und Augments sind.
## Läuft direkt im TFT-Boss-Fenster, das dafür kurz bildschirmfüllend wird.

signal finished(rects: Dictionary)
signal changed(rects: Dictionary)
signal cancelled

const NAMES := {"shop": "Shop", "gold": "Gold", "level": "Level", "stage": "Stage", "items": "Item-Plätze", "augs": "Augments", "hp": "Mein Leben", "lobby": "Leben aller Spieler", "traits": "Trait-Leiste"}
const ORDER := ["shop", "gold", "level", "stage", "items", "augs", "hp", "lobby", "traits"]
const LOBBY_SLOTS := 8
const TRAIT_SLOTS := 8
const MULTI := {"items": ITEM_SLOTS, "lobby": LOBBY_SLOTS, "traits": TRAIT_SLOTS}
const STEPS := [
	["shop", "Zieh einen Rahmen um alle 5 Shop-Karten. Nur die Karten, ohne Level- und Reroll-Knopf links."],
	["gold", "Zieh einen Rahmen eng um deine Gold-Zahl."],
	["level", "Zieh einen Rahmen eng um die Level-Zahl. Nur die Zahl, ohne „Lvl.“."],
	["stage", "Zieh einen Rahmen eng um die Stage-Anzeige oben, zum Beispiel 3-2."],
	["items", "Rahmen von der Oberkante des obersten Item-Platzes bis zur Unterkante des untersten ziehen, auch über die leeren. Die dünnen Linien müssen zwischen den Plätzen liegen. Wenn nicht: mit − und + die Anzahl ändern."],
	["augs", "Rahmen um alle 3 Augment-Karten (geht nur, solange eine Augment-Wahl offen ist)."],
	["hp", "Rahmen mit etwas Abstand um deine eigene Lebens-Zahl (in der Spielerliste rechts oder unter deinem Portrait)."],
	["traits", "Rahmen um die ganze Trait-Leiste links, mit Symbolen, Namen und Zahlen (z. B. „Juggernaut 2“), vom obersten bis zum untersten Eintrag."],
	["lobby", "Rahmen um die Lebens-Zahlen aller 8 Spieler in der Liste rechts, von der obersten bis zur untersten Zahl, nur die Zahlen-Spalte. Die Linien müssen zwischen den Spielern liegen, sonst mit − und + anpassen."],
]
const COLORS := {"traits": Color("8fd0ff"), "hp": Color("ff6b6b"), "lobby": Color("ffa0a0"), "items": Color("ff6fae"), "shop": Color("7be07b"), "gold": Color("f5c542"), "level": Color("6fd3ff"), "stage": Color("ff9a4a"), "augs": Color("c48cff")}

var img: Image
var rects := {}
var step := 0
var only := ""
var drag_from := Vector2(-1, -1)
var drag_to := Vector2(-1, -1)
var info: Label
var slot_row: HBoxContainer
var slot_lbl: Label
var panel: PanelContainer
var layer: Control

func setup(screen_img: Image, old: Dictionary, key: String = "") -> void:
	img = screen_img
	rects = old.duplicate()
	only = key
	for i in STEPS.size():
		if STEPS[i][0] == key:
			step = i
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var tr := TextureRect.new()
	tr.texture = ImageTexture.create_from_image(img)
	tr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tr.show_behind_parent = true
	add_child(tr)

	panel = PanelContainer.new()
	panel.position = Vector2(20, 20)
	panel.custom_minimum_size = Vector2(560, 0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.07, 0.13, 0.94)
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(12)
	panel.add_theme_stylebox_override("panel", sb)
	var v := VBoxContainer.new()
	info = Label.new()
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.custom_minimum_size = Vector2(540, 0)
	info.add_theme_font_size_override("font_size", 20)
	v.add_child(info)
	var h := HBoxContainer.new()
	var btns := [["Speichern", _next], ["Abbrechen", _cancel], ["Panel verschieben", _move_panel]] if only != "" else [["Weiter", _next], ["Überspringen", _skip], ["Zurück", _back], ["Abbrechen", _cancel], ["Panel verschieben", _move_panel]]
	for b in btns:
		var btn := Button.new()
		btn.text = b[0]
		btn.add_theme_font_size_override("font_size", 18)
		btn.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
		btn.focus_mode = Control.FOCUS_NONE
		btn.pressed.connect(b[1])
		h.add_child(btn)
	v.add_child(h)
	slot_row = HBoxContainer.new()
	var minus := Button.new()
	minus.text = "  −  "
	minus.add_theme_font_size_override("font_size", 18)
	minus.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	minus.focus_mode = Control.FOCUS_NONE
	minus.pressed.connect(func(): _slots_add(-1))
	slot_lbl = Label.new()
	slot_lbl.add_theme_font_size_override("font_size", 18)
	var plus := Button.new()
	plus.text = "  +  "
	plus.add_theme_font_size_override("font_size", 18)
	plus.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	plus.focus_mode = Control.FOCUS_NONE
	plus.pressed.connect(func(): _slots_add(1))
	slot_row.add_child(minus)
	slot_row.add_child(slot_lbl)
	slot_row.add_child(plus)
	slot_row.mouse_filter = Control.MOUSE_FILTER_PASS
	v.add_child(slot_row)
	panel.add_child(v)
	# Nur die Knöpfe fangen die Maus, sonst kann man auch durch das Panel hindurch Rahmen ziehen
	panel.mouse_filter = Control.MOUSE_FILTER_PASS
	v.mouse_filter = Control.MOUSE_FILTER_PASS
	h.mouse_filter = Control.MOUSE_FILTER_PASS
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(panel)
	# Rahmen werden über dem Panel gezeichnet, damit man sie immer sieht
	layer = Control.new()
	layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.draw.connect(_draw_layer)
	add_child(layer)
	_update_info()

func _slots_add(d: int) -> void:
	var key: String = STEPS[step][0]
	if not rects.has(key):
		return
	var r: Array = rects[key]
	var n: int = int(r[4]) if r.size() > 4 else int(MULTI.get(key, 1))
	n = clampi(n + d, 1, 16)
	if r.size() > 4:
		r[4] = n
	else:
		r.append(n)
	changed.emit(rects)
	_update_info()

func _update_info() -> void:
	var s: Array = STEPS[step]
	if slot_row:
		var k: String = s[0]
		slot_row.visible = MULTI.has(k)
		var cnt: int = int(rects[k][4]) if rects.has(k) and rects[k].size() > 4 else int(MULTI.get(k, 1))
		slot_lbl.text = "  Plätze: %d  " % cnt
	info.remove_theme_color_override("font_color")
	if only != "":
		var st := "Rahmen gesetzt. „Speichern“ oder Enter drücken, oder neu ziehen." if rects.has(only) else "Mit der Maus einen Rahmen ziehen, dann „Speichern“."
		info.text = "%s kalibrieren\n%s\n\n%s" % [NAMES[only], s[1], st]
		_redraw()
		return
	var done := " (Rahmen gesetzt)" if rects.has(s[0]) else ""
	info.text = "Schritt %d von %d%s\n%s\n\nMit der Maus einen Rahmen ziehen, dann „Weiter“. Enter, Leertaste und Esc gehen auch." % [step + 1, STEPS.size(), done, s[1]]
	_redraw()

func _norm(p: Vector2) -> Vector2:
	return Vector2(clampf(p.x / size.x, 0, 1), clampf(p.y / size.y, 0, 1))

func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		if e.pressed:
			drag_from = e.position
			drag_to = e.position
		elif drag_from.x >= 0:
			drag_to = e.position
			var a := _norm(drag_from)
			var b := _norm(drag_to)
			var r := Rect2(a.min(b), (a - b).abs())
			if r.size.x > 0.003 and r.size.y > 0.003:
				var key: String = STEPS[step][0]
				var cnt: int = int(rects[key][4]) if rects.has(key) and rects[key].size() > 4 else 0
				rects[key] = [r.position.x, r.position.y, r.size.x, r.size.y]
				if MULTI.has(key):
					rects[key].append(cnt if cnt > 0 else MULTI[key])
				changed.emit(rects)
				var px := Rect2(drag_from.min(drag_to), (drag_from - drag_to).abs())
				if px.intersects(panel.get_rect()):
					_move_panel()
			drag_from = Vector2(-1, -1)
			_update_info()
		_redraw()
		accept_event()
	elif e is InputEventMouseMotion and drag_from.x >= 0:
		drag_to = e.position
		_redraw()
		accept_event()

func _input(e: InputEvent) -> void:
	if not (e is InputEventKey and e.pressed):
		return
	match e.keycode:
		KEY_ENTER, KEY_KP_ENTER:
			_next()
		KEY_SPACE:
			if only == "":
				_skip()
		KEY_BACKSPACE:
			if only == "":
				_back()
		KEY_ESCAPE:
			_cancel()
		_:
			return
	get_viewport().set_input_as_handled()

var _done := false

func _next() -> void:
	if _done:
		return
	if only != "":
		if rects.has(only):
			_done = true
			finished.emit(rects)
		else:
			info.text = "%s kalibrieren\n[!] Erst einen Rahmen ziehen, dann „Speichern“." % NAMES[only]
			info.add_theme_color_override("font_color", Color("ff9a4a"))
		return
	step += 1
	if step >= STEPS.size():
		_done = true
		finished.emit(rects)
		return
	_update_info()

func _skip() -> void:
	_next()

func _back() -> void:
	step = maxi(0, step - 1)
	_update_info()

func _cancel() -> void:
	if _done:
		return
	_done = true
	cancelled.emit()

func _move_panel() -> void:
	# Panel in die andere Ecke, falls es etwas verdeckt
	if panel.position.x < size.x / 2:
		panel.position = Vector2(size.x - panel.size.x - 20, size.y - panel.size.y - 20)
	else:
		panel.position = Vector2(20, 20)

func _redraw() -> void:
	if layer:
		layer.queue_redraw()

func _draw_layer() -> void:
	for k in rects.keys():
		var r: Array = rects[k]
		var rr := Rect2(r[0] * size.x, r[1] * size.y, r[2] * size.x, r[3] * size.y)
		var col: Color = COLORS.get(k, Color.WHITE)
		layer.draw_rect(rr, col, false, 3.0)
		layer.draw_string(ThemeDB.fallback_font, rr.position + Vector2(4, -6), NAMES.get(k, k), HORIZONTAL_ALIGNMENT_LEFT, -1, 18, col)
		for sr in Calib.split(k, rr, int(r[4]) if r.size() > 4 else 0):
			layer.draw_rect(sr, col, false, 1.0)
	if drag_from.x >= 0:
		layer.draw_rect(Rect2(drag_from.min(drag_to), (drag_from - drag_to).abs()), Color.WHITE, false, 2.0)

## Teilt einen Bereich in seine Plätze auf (Shop 5, Augments 3, Items automatisch nach Form).
const ITEM_SLOTS := 10

static func split(key: String, r: Rect2, count: int = 0) -> Array:
	var out := []
	var n := 1
	var vertical := false
	match key:
		"shop":
			n = 5
		"augs":
			n = 3
		"items":
			vertical = r.size.y >= r.size.x
			n = count if count > 0 else ITEM_SLOTS
		"lobby":
			vertical = r.size.y >= r.size.x
			n = count if count > 0 else LOBBY_SLOTS
		"traits":
			vertical = true
			n = count if count > 0 else TRAIT_SLOTS
	for i in n:
		if vertical:
			out.append(Rect2(r.position.x, r.position.y + r.size.y * i / n, r.size.x, r.size.y / n))
		else:
			out.append(Rect2(r.position.x + r.size.x * i / n, r.position.y, r.size.x / n, r.size.y))
	return out
