class_name Calib
extends Window
## Einmalig festlegen, wo auf deinem Bildschirm Shop, Gold, Level, Stage und Augments sind.

signal finished(rects: Dictionary)

const STEPS := [
	["shop", "Zieh einen Rahmen um alle 5 Shop-Karten. Nur die Karten, ohne Level- und Reroll-Knopf links."],
	["gold", "Zieh einen Rahmen eng um deine Gold-Zahl."],
	["level", "Zieh einen Rahmen eng um die Level-Zahl. Nur die Zahl, ohne „Lvl.“."],
	["stage", "Zieh einen Rahmen eng um die Stage-Anzeige oben, zum Beispiel 3-2."],
	["augs", "Nur wenn gerade eine Augment-Wahl offen ist: Rahmen um alle 3 Augment-Karten. Sonst Leertaste zum Überspringen."],
]
const COLORS := {"shop": Color("7be07b"), "gold": Color("f5c542"), "level": Color("6fd3ff"), "stage": Color("ff9a4a"), "augs": Color("c48cff")}

var img: Image
var rects := {}
var step := 0
var drag_from := Vector2(-1, -1)
var drag_to := Vector2(-1, -1)
var overlay: Control
var info: Label

func setup(screen_img: Image, old: Dictionary) -> void:
	img = screen_img
	rects = old.duplicate()
	borderless = true
	transient = false
	exclusive = false
	unresizable = true
	always_on_top = true
	var tr := TextureRect.new()
	tr.texture = ImageTexture.create_from_image(img)
	tr.set_anchors_preset(Control.PRESET_FULL_RECT)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(tr)
	overlay = Control.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.draw.connect(_draw_overlay)
	overlay.gui_input.connect(_on_input)
	add_child(overlay)
	var panel := PanelContainer.new()
	panel.position = Vector2(20, 20)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.07, 0.13, 0.92)
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(12)
	panel.add_theme_stylebox_override("panel", sb)
	info = Label.new()
	info.add_theme_font_size_override("font_size", 20)
	panel.add_child(info)
	add_child(panel)
	_update_info()

func _update_info() -> void:
	var s: Array = STEPS[step]
	info.text = "Schritt %d von %d: %s\n\nMaus ziehen = Rahmen  ·  Enter = weiter  ·  Leertaste = überspringen  ·  Rücktaste = zurück  ·  Esc = abbrechen" % [step + 1, STEPS.size(), s[1]]
	overlay.queue_redraw()

func _norm(p: Vector2) -> Vector2:
	var sz := Vector2(overlay.size)
	return Vector2(clampf(p.x / sz.x, 0, 1), clampf(p.y / sz.y, 0, 1))

func _on_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		if e.pressed:
			drag_from = e.position
			drag_to = e.position
		else:
			drag_to = e.position
			var a := _norm(drag_from)
			var b := _norm(drag_to)
			var r := Rect2(a.min(b), (a - b).abs())
			if r.size.x > 0.003 and r.size.y > 0.003:
				rects[STEPS[step][0]] = [r.position.x, r.position.y, r.size.x, r.size.y]
			drag_from = Vector2(-1, -1)
		overlay.queue_redraw()
	elif e is InputEventMouseMotion and drag_from.x >= 0:
		drag_to = e.position
		overlay.queue_redraw()

func _input(e: InputEvent) -> void:
	if not (e is InputEventKey and e.pressed):
		return
	match e.keycode:
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			_next()
		KEY_BACKSPACE:
			step = maxi(0, step - 1)
			_update_info()
		KEY_ESCAPE:
			queue_free()

func _next() -> void:
	step += 1
	if step >= STEPS.size():
		finished.emit(rects)
		queue_free()
		return
	_update_info()

func _draw_overlay() -> void:
	var sz := Vector2(overlay.size)
	for k in rects.keys():
		var r: Array = rects[k]
		var rr := Rect2(r[0] * sz.x, r[1] * sz.y, r[2] * sz.x, r[3] * sz.y)
		var col: Color = COLORS.get(k, Color.WHITE)
		overlay.draw_rect(rr, col, false, 3.0)
		overlay.draw_string(ThemeDB.fallback_font, rr.position + Vector2(4, -6), k, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, col)
		var parts := 5 if k == "shop" else (3 if k == "augs" else 1)
		for i in range(1, parts):
			var x := rr.position.x + rr.size.x * i / parts
			overlay.draw_line(Vector2(x, rr.position.y), Vector2(x, rr.end.y), col, 1.0)
	if drag_from.x >= 0:
		overlay.draw_rect(Rect2(drag_from.min(drag_to), (drag_from - drag_to).abs()), Color.WHITE, false, 2.0)
