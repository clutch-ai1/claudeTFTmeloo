extends Node
## Lädt die Comp-Daten (gleiche Daten wie der Comp-Planer) und hält sie bereit.

signal loaded

const URL := "https://clutch-ai1.github.io/claudeTFTmeloo/data.json"
const CACHE := "user://data.json"

var D: Dictionary = {}
var units: Dictionary = {}      # Name -> Unit
var comps: Array = []
var augs: Dictionary = {}       # Name -> Augment
var aug_names: Array = []
var unit_names: Array = []
var recipes: Dictionary = {}    # Item -> [Komponente, Komponente]
var components: Array = []
var item_names: Array = []      # fertige Items (ohne Komponenten)
var traits: Dictionary = {}     # Trait -> [Stufen]
var source := ""

const COMP_DE := {
	"B.F. Sword": "Schwert", "Recurve Bow": "Bogen", "Needlessly Large Rod": "Stab",
	"Tear Of The Goddess": "Träne", "Chain Vest": "Weste", "Negatron Cloak": "Mantel",
	"Giant's Belt": "Gürtel", "Sparring Gloves": "Handschuh", "Spatula": "Spatel",
	"Frying Pan": "Pfanne",
}

func _ready() -> void:
	var txt := ""
	if FileAccess.file_exists(CACHE):
		txt = FileAccess.get_file_as_string(CACHE)
		source = "gespeichert"
	if not _apply(txt):
		_apply(FileAccess.get_file_as_string("res://data/data.json"))
		source = "mitgeliefert"
	var http := HTTPRequest.new()
	http.timeout = 20.0
	add_child(http)
	http.request_completed.connect(_on_done)
	http.request(URL + "?t=" + str(int(Time.get_unix_time_from_system())))

func _on_done(result: int, code: int, _h: PackedStringArray, body: PackedByteArray) -> void:
	if result == HTTPRequest.RESULT_SUCCESS and code == 200:
		var txt := body.get_string_from_utf8()
		if _apply(txt):
			var f := FileAccess.open(CACHE, FileAccess.WRITE)
			if f:
				f.store_string(txt)
			source = "live"
	loaded.emit()

func _apply(txt: String) -> bool:
	if txt == "":
		return false
	var j = JSON.parse_string(txt)
	if typeof(j) != TYPE_DICTIONARY or not j.has("comps"):
		return false
	D = j
	units.clear()
	for u in j["units"]:
		units[u["n"]] = u
	unit_names = units.keys()
	unit_names.sort_custom(func(a, b): return units[a]["c"] < units[b]["c"] or (units[a]["c"] == units[b]["c"] and a < b))
	comps = j["comps"]
	augs.clear()
	for a in j["augs"]:
		augs[a["n"]] = a
	aug_names = augs.keys()
	aug_names.sort()
	recipes = j["recipes"]
	traits = j.get("traits", {})
	var cs := {}
	for r in recipes.values():
		for c in r:
			cs[c] = true
	components = cs.keys()
	components.sort()
	var low := {}
	for c in components:
		low[c.to_lower()] = true
	item_names = []
	for it in j.get("items", recipes.keys()):
		if not low.has(str(it).to_lower()):
			item_names.append(str(it))
	for it in recipes.keys():
		if not it in item_names:
			item_names.append(it)
	item_names.sort()
	return true

func updated_text() -> String:
	var t := str(D.get("updated", ""))
	return t.substr(0, 16).replace("T", " ")

func comp_de(c: String) -> String:
	return COMP_DE.get(c, c)

func cost(u: String) -> int:
	return int(units[u]["c"]) if units.has(u) else 0
