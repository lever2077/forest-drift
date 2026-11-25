# In-game updater: asks GitHub for the latest release, and if it's newer than
# VERSION downloads its game-update.zip, unpacks it over the game folder and
# restarts the game.
#
# Releasing an update:  bump VERSION below, then run  tools\release.ps1
# (it zips the game, tags v<VERSION> and uploads the GitHub release).
extends Node

const VERSION := "1.12.0"
const GITHUB_REPO := "lever2077/forest-drift"
const UPDATE_ASSET := "game-update.zip"
const API_URL := "https://api.github.com/repos/%s/releases/latest"

signal status_changed(text: String, can_install: bool)

# remembered across the scene reloads so the check only runs once per launch
static var latest_tag := ""
static var asset_url := ""
static var checked := false

var http: HTTPRequest
var busy := false

func _ready() -> void:
	http = HTTPRequest.new()
	http.max_redirects = 10
	http.timeout = 60.0
	add_child(http)

func current_version() -> String:
	for a in OS.get_cmdline_user_args():   # dev aid: --fakeversion=0.0.1
		if a.begins_with("--fakeversion="):
			return a.substr(14)
	return VERSION

static func _parse(v: String) -> Array:
	var out := []
	for p in v.trim_prefix("v").split("."):
		out.append(int(p))
	while out.size() < 3:
		out.append(0)
	return out

static func is_newer(remote: String, local: String) -> bool:
	var a := _parse(remote)
	var b := _parse(local)
	for i in 3:
		if a[i] != b[i]:
			return a[i] > b[i]
	return false

func update_available() -> bool:
	return latest_tag != "" and asset_url != "" and is_newer(latest_tag, current_version())

func check() -> void:
	if busy:
		return
	if checked:
		_report_check()
		return
	busy = true
	status_changed.emit("Checking for updates...", false)
	var err := http.request(API_URL % GITHUB_REPO, ["User-Agent: ForestDrift-Updater", "Accept: application/vnd.github+json"])
	if err != OK:
		busy = false
		status_changed.emit("Couldn't check for updates", false)
		return
	var res: Array = await http.request_completed
	busy = false
	var code: int = res[1]
	if res[0] == HTTPRequest.RESULT_SUCCESS and code == 404:
		status_changed.emit("No releases published yet  (v%s)" % current_version(), false)
		return
	if res[0] != HTTPRequest.RESULT_SUCCESS or code != 200:
		status_changed.emit("Couldn't check for updates (offline?)" if code == 0 else "Couldn't check for updates (HTTP %d)" % code, false)
		return
	var data = JSON.parse_string((res[3] as PackedByteArray).get_string_from_utf8())
	if not (data is Dictionary):
		status_changed.emit("Couldn't read the update info", false)
		return
	checked = true
	latest_tag = String(data.get("tag_name", ""))
	asset_url = ""
	for a in data.get("assets", []):
		if a is Dictionary and a.get("name", "") == UPDATE_ASSET:
			asset_url = String(a.get("browser_download_url", ""))
	_report_check()

func _report_check() -> void:
	if update_available():
		status_changed.emit("Update available: %s  (you have v%s)" % [latest_tag, current_version()], true)
	else:
		status_changed.emit("Up to date  (v%s)" % current_version(), false)

func install() -> void:
	if busy or not update_available():
		return
	busy = true
	status_changed.emit("Downloading %s ..." % latest_tag, false)
	var zip_path := OS.get_user_data_dir().path_join("update.zip")
	http.download_file = zip_path
	var err := http.request(asset_url, ["User-Agent: ForestDrift-Updater"])
	if err != OK:
		_fail("Download failed to start")
		return
	var res: Array = await http.request_completed
	http.download_file = ""
	if res[0] != HTTPRequest.RESULT_SUCCESS or res[1] != 200:
		_fail("Download failed (HTTP %d)" % res[1])
		return
	status_changed.emit("Installing %s ..." % latest_tag, false)
	await get_tree().process_frame
	var n := _unpack(zip_path)
	if n < 0:
		_fail("Couldn't unpack the update")
		return
	DirAccess.remove_absolute(zip_path)
	status_changed.emit("Updated to %s - restarting..." % latest_tag, false)
	await get_tree().create_timer(1.0).timeout
	# relaunch the same Godot with the same project folder, then close this one
	var game_dir := ProjectSettings.globalize_path("res://")
	OS.create_process(OS.get_executable_path(), ["--path", game_dir])
	get_tree().quit()

func _fail(text: String) -> void:
	busy = false
	status_changed.emit(text, true)

# unzip over the game folder; returns files written or -1
func _unpack(zip_path: String) -> int:
	var zr := ZIPReader.new()
	if zr.open(zip_path) != OK:
		return -1
	var root := ProjectSettings.globalize_path("res://")
	var n := 0
	for f in zr.get_files():
		if f.ends_with("/") or f.contains(".."):
			continue
		var dest := root.path_join(f)
		DirAccess.make_dir_recursive_absolute(dest.get_base_dir())
		var fa := FileAccess.open(dest, FileAccess.WRITE)
		if fa == null:
			zr.close()
			return -1
		fa.store_buffer(zr.read_file(f))
		fa.close()
		n += 1
	zr.close()
	return n
