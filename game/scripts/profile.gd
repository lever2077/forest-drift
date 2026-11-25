# Player profile: points, the items you own and the skin on your car.
# Saved to user://profile.cfg (separate from settings.cfg). Everything is static
# so it survives the scene reloads between the menu and the maps.
extends RefCounted

static var PATH := "user://profile.cfg"   # dev aid: --profile=<file> uses another file

# ---------------------------------------------------------------- skins
# Every skin, by item id. "color" is the car's paint. The stock skin is always
# owned and never shows up in a cache.
const STOCK_SKIN := "skin_stock"
const SKINS := {
	"skin_stock":  {"name": "Gloss Black (stock)", "color": Color(0.012, 0.012, 0.015)},
	"skin_red":    {"name": "Racing Red",    "color": Color(0.55, 0.02, 0.02)},
	"skin_blue":   {"name": "Deep Blue",     "color": Color(0.02, 0.08, 0.45)},
	"skin_green":  {"name": "Forest Green",  "color": Color(0.03, 0.22, 0.06)},
	"skin_yellow": {"name": "Sunburst Yellow", "color": Color(0.75, 0.55, 0.02)},
	"skin_orange": {"name": "Blaze Orange",  "color": Color(0.8, 0.22, 0.01)},
	"skin_purple": {"name": "Midnight Purple", "color": Color(0.17, 0.03, 0.3)},
	"skin_white":  {"name": "Pearl White",   "color": Color(0.8, 0.8, 0.78)},
	"skin_silver": {"name": "Silver",        "color": Color(0.42, 0.43, 0.45)},
	"skin_pink":   {"name": "Hot Pink",      "color": Color(0.75, 0.08, 0.35)},
	"skin_teal":   {"name": "Teal",          "color": Color(0.02, 0.35, 0.35)},
}

# ---------------------------------------------------------------- caches
# Opening a cache costs "price" points and gives one random item from "items"
# (equal odds). Duplicates stack in the inventory.
const CACHES := [
	{
		"id": "basic",
		"name": "Basic Cache",
		"price": 100,
		"info": "One random solid-colour skin",
		"items": ["skin_red", "skin_blue", "skin_green", "skin_yellow", "skin_orange",
			"skin_purple", "skin_white", "skin_silver", "skin_pink", "skin_teal"],
	},
]

static var points := 0
static var inventory := {}     # item id -> count
static var equipped_skin := STOCK_SKIN
static var _loaded := false

static func load_profile() -> void:
	if _loaded:
		return
	_loaded = true
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--profile="):
			PATH = a.substr(10)
	var cf := ConfigFile.new()
	if cf.load(PATH) == OK:
		points = int(cf.get_value("profile", "points", 0))
		var inv = cf.get_value("profile", "inventory", {})
		inventory = inv if inv is Dictionary else {}
		equipped_skin = String(cf.get_value("profile", "skin", STOCK_SKIN))
		if not owns(equipped_skin):
			equipped_skin = STOCK_SKIN

static func save_profile() -> void:
	var cf := ConfigFile.new()
	cf.set_value("profile", "points", points)
	cf.set_value("profile", "inventory", inventory)
	cf.set_value("profile", "skin", equipped_skin)
	cf.save(PATH)

static func add_points(n: int) -> void:
	load_profile()
	points = max(points + n, 0)
	save_profile()

static func item_name(id: String) -> String:
	if SKINS.has(id):
		return SKINS[id]["name"]
	return id

static func item_count(id: String) -> int:
	load_profile()
	return int(inventory.get(id, 0))

static func owns(id: String) -> bool:
	return id == STOCK_SKIN or int(inventory.get(id, 0)) > 0

static func add_item(id: String, count := 1) -> void:
	load_profile()
	inventory[id] = item_count(id) + count
	save_profile()

static func remove_item(id: String, count := 1) -> void:
	load_profile()
	var n := item_count(id) - count
	if n > 0:
		inventory[id] = n
	else:
		inventory.erase(id)
		if equipped_skin == id:
			equipped_skin = STOCK_SKIN
	save_profile()

static func find_cache(id: String) -> Dictionary:
	for c in CACHES:
		if c["id"] == id:
			return c
	return {}

# pay for a cache and roll it: returns the item id won, or "" if you can't afford it
static func open_cache(id: String) -> String:
	load_profile()
	var c := find_cache(id)
	if c.is_empty() or points < int(c["price"]) or c["items"].is_empty():
		return ""
	points -= int(c["price"])
	var won: String = c["items"][randi() % c["items"].size()]
	inventory[won] = item_count(won) + 1
	save_profile()
	return won

static func skin_color(id: String) -> Color:
	return SKINS.get(id, SKINS[STOCK_SKIN])["color"]

static func equip_skin(id: String) -> void:
	load_profile()
	if SKINS.has(id) and owns(id):
		equipped_skin = id
		save_profile()
