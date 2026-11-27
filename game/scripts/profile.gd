# The player's save: points, items and car skin. It lives in user:// (on Windows
# %APPDATA%\Godot\app_userdata\Forest Drift), so everyone who downloads the game
# starts fresh with their own save, and updates never touch it. Everything is
# static so it survives the scene reloads between the menu and the maps.
extends RefCounted

const SAVE_PATH := "user://profile.cfg"
const OLD_INDEX := "user://players.cfg"    # v1.2-1.3 had named players on one computer
static var PATH := SAVE_PATH
static var dev_path := ""                  # dev aid: --profile=<file> uses that file instead

# ---------------------------------------------------------------- skins
# Every skin, by item id. "color" is the car's paint. The stock skin is always
# owned and never shows up in a cache.
const STOCK_SKIN := "skin_stock"
const SKINS := {
	"skin_stock":     {"name": "Grey", "color": Color(0.32, 0.33, 0.34)},
	# S tier
	"skin_white":     {"name": "White",      "color": Color(0.9, 0.9, 0.9)},
	"skin_black":     {"name": "Black",      "color": Color(0.012, 0.012, 0.015)},
	# A tier
	"skin_fuchsia":   {"name": "Fuchsia",    "color": Color(0.95, 0.0, 0.95)},
	"skin_skyblue":   {"name": "Blue",       "color": Color(0.0, 0.66, 0.95)},
	"skin_cyan":      {"name": "Cyan",       "color": Color(0.0, 0.95, 0.95)},
	"skin_turquoise": {"name": "Turquoise",  "color": Color(0.25, 0.86, 0.8)},
	# B tier
	"skin_yellow":    {"name": "Yellow",     "color": Color(1.0, 0.72, 0.0)},
	"skin_orange":    {"name": "Orange",     "color": Color(1.0, 0.45, 0.0)},
	"skin_purple":    {"name": "Purple",     "color": Color(0.42, 0.0, 1.0)},
	# C tier
	"skin_red":       {"name": "Red",        "color": Color(0.75, 0.0, 0.0)},
	"skin_blue":      {"name": "Dark Blue",  "color": Color(0.0, 0.0, 0.95)},
	"skin_green":     {"name": "Green",      "color": Color(0.0, 0.56, 0.27)},
	"skin_pink":      {"name": "Pink",       "color": Color(1.0, 0.5, 1.0)},
	# no longer in any cache: kept so skins people already own still work
	"skin_silver":    {"name": "Silver",     "color": Color(0.42, 0.43, 0.45)},
	"skin_teal":      {"name": "Teal",       "color": Color(0.02, 0.35, 0.35)},
}

# Basic Cache odds by tier: [chance, skins]. The chance is split evenly between
# the skins in that tier. (60 + 20 + 10 + 5 = 95: the odds are relative, so
# that works out to 63.2% / 21.1% / 10.5% / 5.3%.)
const BASIC_TIERS := [
	[60.0, ["skin_red", "skin_blue", "skin_green", "skin_pink"]],                   # C
	[20.0, ["skin_yellow", "skin_orange", "skin_purple"]],                          # B
	[10.0, ["skin_fuchsia", "skin_skyblue", "skin_cyan", "skin_turquoise"]],        # A
	[5.0, ["skin_white", "skin_black"]],                                            # S
]

# Neon skins: the Basic colours, but the paint glows in that colour ("neon":
# true; car_model.set_paint makes it emissive). neon_<x> is skin_<x> lit up.
# The Neon Cache has its own tiers. Its odds are percentages (they add up to
# 100): the better tiers are a touch rarer than the Basic Cache's
# (63.2 / 21.1 / 10.5 / 5.3 %), never by more than 0.5 percentage points.
const NEON_TIERS := [
	[64.0, ["neon_red", "neon_blue", "neon_green", "neon_black"]],               # C
	[21.0, ["neon_yellow", "neon_purple", "neon_pink"]],                         # B
	[10.2, ["neon_skyblue", "neon_turquoise", "neon_orange"]],                   # A
	[4.8, ["neon_white", "neon_fuchsia", "neon_cyan"]],                          # S
]

static func _neon_tiers() -> Array:
	return NEON_TIERS

# rarity colours by tier: C grey, B blue, A orange, S red (crate roll, inventory)
const RARITY_COLORS := [Color(0.62, 0.64, 0.68), Color(0.25, 0.5, 1.0), Color(1.0, 0.55, 0.1), Color(0.95, 0.15, 0.15)]

# a skin's rarity tier from the cache it comes from (neon skins from the Neon
# Cache, the rest from the Basic Cache); -1 for the stock skin and old skins
# that no cache gives any more
static func skin_tier(id: String) -> int:
	return item_tier("neon" if id.begins_with("neon_") else "basic", id)

# tier of an item in a cache: 0 = C, 1 = B, 2 = A, 3 = S (-1 if not in it)
static func item_tier(cache_id: String, id: String) -> int:
	var tiers := cache_tiers(cache_id)
	for i in tiers.size():
		if (tiers[i][1] as Array).has(id):
			return i
	return -1

static func _skin(id: String) -> Dictionary:
	if SKINS.has(id):
		return SKINS[id]
	if id.begins_with("neon_"):
		var base := "skin_" + id.substr(5)
		if SKINS.has(base):
			return {"name": "Neon " + String(SKINS[base]["name"]), "color": SKINS[base]["color"], "neon": true}
	return {}

static func is_skin(id: String) -> bool:
	return not _skin(id).is_empty()

static func skin_neon(id: String) -> bool:
	return bool(_skin(id).get("neon", false))

# ---------------------------------------------------------------- caches
# Opening a cache costs "price" points and gives one random item, rolled by
# tier (cache_tiers). Duplicates stack in the inventory.
const CACHES := [
	{"id": "basic", "name": "Basic Cache", "price": 100},
	{"id": "neon", "name": "Neon Cache", "price": 1000, "tint": Color(0.2, 1.0, 0.9)},
]

static func cache_tiers(id: String) -> Array:
	match id:
		"basic":
			return BASIC_TIERS
		"neon":
			return _neon_tiers()
	return []

# one weighted roll: pick a tier by its chance, then a skin in it at random
static func _roll(tiers: Array) -> String:
	var total := 0.0
	for t in tiers:
		if not (t[1] as Array).is_empty():
			total += float(t[0])
	var r := randf() * total
	for t in tiers:
		var ids: Array = t[1]
		if ids.is_empty():
			continue
		r -= float(t[0])
		if r < 0.0:
			return ids[randi() % ids.size()]
	var last: Array = tiers[tiers.size() - 1][1]
	return last[randi() % last.size()]

# ---------------------------------------------------------------- cars
# Every car you can drive (Inventory > Cars). "model" picks the visual model:
# "" = the built-in 350Z, otherwise the downloaded body kit + rims in
# res://models/cars/. All cars use the same driving physics.
const STOCK_CAR := "car_350z"
const CARS := {
	"car_350z": {"name": "350Z Nismo (original)", "info": "the built-in car, full damage model", "model": ""},
	"car_cc96_2": {"name": "CC96 Sport", "info": "IceMaan CC96 with a wing: soft body, doors, bonnet, bumpers, wing, lights and glass all break", "model": "cc96", "body": 2, "rims": 2, "spoiler": true},
}
static var equipped_car := STOCK_CAR

static func equip_car(id: String) -> void:
	load_profile()
	if CARS.has(id):
		equipped_car = id
		save_profile()

static var points := 0
static var inventory := {}     # item id -> count
static var equipped_skin := STOCK_SKIN
static var redeemed: Array = []   # codes already used on this save (each works once)
static var _loaded := false

# v1.2-1.3 kept named players in user://players/. Bring the last one played
# back into the single save, once, and keep the old files as a backup.
static func _migrate_players() -> void:
	if not FileAccess.file_exists(OLD_INDEX):
		return
	var cf := ConfigFile.new()
	if cf.load(OLD_INDEX) == OK:
		var name := String(cf.get_value("players", "current", ""))
		var safe := ""
		for ch in name:
			safe += ch if (ch.is_valid_identifier() or ch.is_valid_int()) else "_"
		var f := "user://players/%s.cfg" % safe
		if name != "" and FileAccess.file_exists(f):
			DirAccess.copy_absolute(f, SAVE_PATH)
	# keep a backup, but make sure the index is gone so this only ever runs once
	# (a rename onto an existing file fails on Windows)
	DirAccess.remove_absolute(OLD_INDEX + ".old")
	DirAccess.rename_absolute(OLD_INDEX, OLD_INDEX + ".old")
	if FileAccess.file_exists(OLD_INDEX):
		DirAccess.remove_absolute(OLD_INDEX)

static func load_profile() -> void:
	if _loaded:
		return
	_loaded = true
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--profile="):
			dev_path = a.substr(10)
	if dev_path != "":
		PATH = dev_path
	else:
		_migrate_players()
		PATH = SAVE_PATH
	points = 0
	inventory = {}
	equipped_skin = STOCK_SKIN
	equipped_car = STOCK_CAR
	redeemed = []
	var cf := ConfigFile.new()
	if cf.load(PATH) == OK:
		points = int(cf.get_value("profile", "points", 0))
		var inv = cf.get_value("profile", "inventory", {})
		inventory = inv if inv is Dictionary else {}
		equipped_skin = String(cf.get_value("profile", "skin", STOCK_SKIN))
		if not owns(equipped_skin):
			equipped_skin = STOCK_SKIN
		equipped_car = String(cf.get_value("profile", "car", STOCK_CAR))
		var rc = cf.get_value("profile", "codes", [])
		redeemed = rc if rc is Array else []
		if not CARS.has(equipped_car):
			equipped_car = STOCK_CAR

static func save_profile() -> void:
	var cf := ConfigFile.new()
	cf.set_value("profile", "points", points)
	cf.set_value("profile", "inventory", inventory)
	cf.set_value("profile", "skin", equipped_skin)
	cf.set_value("profile", "car", equipped_car)
	cf.set_value("profile", "codes", redeemed)
	cf.save(PATH)

static func add_points(n: int) -> void:
	load_profile()
	points = max(points + n, 0)
	save_profile()

static func item_name(id: String) -> String:
	if is_skin(id):
		return _skin(id)["name"]
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
	var tiers := cache_tiers(id)
	if c.is_empty() or points < int(c["price"]) or tiers.is_empty():
		return ""
	points -= int(c["price"])
	var won := _roll(tiers)
	inventory[won] = item_count(won) + 1
	save_profile()
	return won

static func skin_color(id: String) -> Color:
	if is_skin(id):
		return _skin(id)["color"]
	return SKINS.get(id, SKINS[STOCK_SKIN])["color"]

static func equip_skin(id: String) -> void:
	load_profile()
	if is_skin(id) and owns(id):
		equipped_skin = id
		save_profile()

# ---------------------------------------------------------------- codes
# Settings > Codes. Each code works once per save. Typing is not case-sensitive.
const CODES := {
	"forestdrift": {"points": 50000},
}

# returns [ok, message] for the Settings panel
static func redeem_code(text: String) -> Array:
	load_profile()
	var key := text.strip_edges().to_lower()
	if key == "":
		return [false, "Type a code first."]
	if not CODES.has(key):
		return [false, "That code doesn't exist."]
	if redeemed.has(key):
		return [false, "You've already used that code."]
	var reward: Dictionary = CODES[key]
	var pts := int(reward.get("points", 0))
	points += pts
	redeemed.append(key)
	save_profile()
	return [true, "Code redeemed: +%d points!" % pts]
