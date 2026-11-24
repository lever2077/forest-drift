# Player profile: the points you spend in the Cache and the items you own.
# Saved to user://profile.cfg (separate from settings.cfg). Everything is static
# so it survives the scene reloads between the menu and the maps.
extends RefCounted

const PATH := "user://profile.cfg"

# Items for sale in the Cache. Add entries here and they show up in the Cache tab:
#   {"id": "neon_blue", "name": "Blue Underglow", "price": 5000, "info": "Glows blue under the car"}
# "id" must be unique - it's what gets stored in the inventory.
const CACHE_ITEMS := []

static var points := 0
static var inventory := {}     # item id -> count
static var _loaded := false

static func load_profile() -> void:
	if _loaded:
		return
	_loaded = true
	var cf := ConfigFile.new()
	if cf.load(PATH) == OK:
		points = int(cf.get_value("profile", "points", 0))
		var inv = cf.get_value("profile", "inventory", {})
		inventory = inv if inv is Dictionary else {}

static func save_profile() -> void:
	var cf := ConfigFile.new()
	cf.set_value("profile", "points", points)
	cf.set_value("profile", "inventory", inventory)
	cf.save(PATH)

static func add_points(n: int) -> void:
	load_profile()
	points = max(points + n, 0)
	save_profile()

static func find_item(id: String) -> Dictionary:
	for it in CACHE_ITEMS:
		if it["id"] == id:
			return it
	return {}

static func item_count(id: String) -> int:
	load_profile()
	return int(inventory.get(id, 0))

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
	save_profile()

# spend points on a Cache item; false if it doesn't exist or you can't afford it
static func buy(id: String) -> bool:
	load_profile()
	var it := find_item(id)
	if it.is_empty() or points < int(it["price"]):
		return false
	points -= int(it["price"])
	inventory[id] = item_count(id) + 1
	save_profile()
	return true
