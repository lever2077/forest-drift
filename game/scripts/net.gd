# Online play (autoload "Net": it stays alive while maps load, so the
# connection does too). One player hosts, the others join with the host's
# address. Godot's ENet networking over UDP; port 7777 by default.
#
#  * The host decides the map and biome. Players who join (or are connected
#    when the host changes map) load into it automatically.
#  * Every player sends their car's position, rotation, steering, speed and
#    skin ~20 times a second; everyone else draws that car (remote_car.gd).
#  * The host also shares the time of day and the weather.
#  * Ping: each player times a round trip to the host once a second.
#
# Nothing here decides points or damage: driving, scoring and the car's own
# crashes stay on each player's own computer.
extends Node

signal status_changed(text: String)
signal players_changed

const DEFAULT_PORT := 7777
const SEND_RATE := 20.0

var my_name := "Player"
var players := {}          # peer id -> {name, car, skin, map, xf, steer, speed, brake, t}
var status := "Offline"
var ping_ms := -1.0
var host_map := -1         # host only: the map (and biome) everyone should be on
var host_biome := ""

var _send_t := 0.0
var _ping_t := 0.0
var _world_t := 0.0

func is_online() -> bool:
	return multiplayer.multiplayer_peer != null and not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer) \
		and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED

func is_host() -> bool:
	return is_online() and multiplayer.is_server()

func is_client() -> bool:
	return is_online() and not multiplayer.is_server()

func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_failed)
	multiplayer.server_disconnected.connect(_on_server_gone)

# ---------------------------------------------------------------- host / join / leave
func host(port := DEFAULT_PORT) -> String:
	leave()
	var p := ENetMultiplayerPeer.new()
	var err := p.create_server(port, 8)
	if err != OK:
		_set_status("Couldn't host on port %d (is the game already hosting?)" % port)
		return status
	multiplayer.multiplayer_peer = p
	_set_status("Hosting on port %d - pick a map, friends join you" % port)
	players_changed.emit()
	return status

# address: "1.2.3.4", "1.2.3.4:7777" or a name like "abc.playit.gg:12345"
func join(address: String) -> String:
	leave()
	var a := address.strip_edges()
	var port := DEFAULT_PORT
	var colon := a.rfind(":")
	if colon > 0 and a.substr(colon + 1).is_valid_int():
		port = int(a.substr(colon + 1))
		a = a.substr(0, colon)
	if a == "":
		_set_status("Type the host's address first")
		return status
	var p := ENetMultiplayerPeer.new()
	var err := p.create_client(a, port)
	if err != OK:
		_set_status("Couldn't connect to %s:%d" % [a, port])
		return status
	multiplayer.multiplayer_peer = p
	_set_status("Connecting to %s:%d ..." % [a, port])
	return status

func leave() -> void:
	if multiplayer.multiplayer_peer and not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer):
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	players.clear()
	ping_ms = -1.0
	host_map = -1
	_set_status("Offline")
	players_changed.emit()

func _set_status(t: String) -> void:
	print("NET: ", t)
	status = t
	status_changed.emit(t)

func _on_connected() -> void:
	_set_status("Connected - the host picks the map")
	_say_hello()

func _on_failed() -> void:
	leave()
	_set_status("Couldn't reach the host (check the address, and that they're hosting)")

func _on_server_gone() -> void:
	leave()
	_set_status("The host left the game")

func _on_peer_connected(id: int) -> void:
	print("NET: peer %d connected (host map %d)" % [id, host_map])
	_say_hello(id)
	if is_host() and host_map >= 0:
		go_map.rpc_id(id, host_map, host_biome)

func _on_peer_disconnected(id: int) -> void:
	players.erase(id)
	players_changed.emit()

func _say_hello(to := 0) -> void:
	var main = _main()
	var car_id := String(main.Profile.equipped_car) if main else "car_350z"
	var skin := String(main.Profile.equipped_skin) if main else "skin_stock"
	if to == 0:
		hello.rpc(my_name, car_id, skin)
	else:
		hello.rpc_id(to, my_name, car_id, skin)

# ---------------------------------------------------------------- messages
@rpc("any_peer", "reliable")
func hello(p_name: String, car_id: String, skin: String) -> void:
	var id := multiplayer.get_remote_sender_id()
	var p: Dictionary = players.get(id, {})
	p["name"] = p_name.substr(0, 20)
	p["car"] = car_id
	p["skin"] = skin
	if not p.has("map"):
		p["map"] = -1
	players[id] = p
	players_changed.emit()

# host -> everyone: drive this map in this biome
@rpc("authority", "reliable")
func go_map(map_idx: int, biome: String) -> void:
	print("NET: host says map %d biome %s" % [map_idx, biome])
	var main = _main()
	if main and main.has_method("net_go_map"):
		main.net_go_map(map_idx, biome)

# a car's state, ~20 times a second, from whoever is driving it
@rpc("any_peer", "unreliable_ordered")
func car_state(map_idx: int, pos: Vector3, rot: Quaternion, steer: float, speed: float, brake: bool) -> void:
	var id := multiplayer.get_remote_sender_id()
	if not players.has(id):
		players[id] = {"name": "Player %d" % id, "car": "car_350z", "skin": "skin_stock"}
	var p: Dictionary = players[id]
	p["map"] = map_idx
	p["xf"] = Transform3D(Basis(rot), pos)
	p["steer"] = steer
	p["speed"] = speed
	p["brake"] = brake
	p["t"] = Time.get_ticks_msec()

# host -> everyone: time of day and weather
@rpc("authority", "unreliable")
func world(time_h: float, weather: int) -> void:
	var main = _main()
	if main and main.envc and is_instance_valid(main.envc) and not main.unloading:
		main.envc.time_h = time_h
		if main.envc.weather != weather:
			main.envc.set_weather(weather)

@rpc("any_peer", "unreliable")
func ping(t: int) -> void:
	pong.rpc_id(multiplayer.get_remote_sender_id(), t)

@rpc("any_peer", "unreliable")
func pong(t: int) -> void:
	ping_ms = float(Time.get_ticks_msec() - t)

# ---------------------------------------------------------------- per frame
func _process(delta: float) -> void:
	if not is_online():
		return
	var main = _main()
	if main == null:
		return
	var car = main.car
	# send our car (only while driving a map)
	_send_t -= delta
	if car and is_instance_valid(car) and main.started and _send_t <= 0.0:
		_send_t = 1.0 / SEND_RATE
		var gt: Transform3D = car.global_transform
		car_state.rpc(main.map_choice, gt.origin, gt.basis.get_rotation_quaternion(), float(car.steer), float(car.speed),
			car.in_brake > 0.1)
	# ping the host
	if is_client():
		_ping_t -= delta
		if _ping_t <= 0.0:
			_ping_t = 1.0
			ping.rpc_id(1, Time.get_ticks_msec())
	# the host shares the time of day and weather
	if is_host() and main.envc and main.started:
		_world_t -= delta
		if _world_t <= 0.0:
			_world_t = 2.0
			world.rpc(main.envc.time_h, main.envc.weather)

# the host's map changed (or it loaded one): tell everyone
func host_started_map(map_idx: int, biome: String) -> void:
	if not is_host():
		return
	host_map = map_idx
	host_biome = biome
	go_map.rpc(map_idx, biome)

func ping_text() -> String:
	if not is_online():
		return "Ping: offline (single-player)"
	if is_host():
		return "Hosting  |  %d player%s" % [players.size() + 1, "" if players.size() == 0 else "s"]
	return "Ping: %d ms" % int(ping_ms) if ping_ms >= 0.0 else "Ping: ..."

func _main():
	var s := get_tree().current_scene
	return s if s and s.has_method("net_go_map") else null
