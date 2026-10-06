extends Node

signal join_failed(reason: String)

const DEFAULT_PORT := 7777
const MAX_CLIENTS := 7
const MAX_NAME_LENGTH := 16
const GAME_SCENE := "res://match/game.tscn"
const MENU_SCENE := "res://ui/main_menu.tscn"
const SETTINGS_PATH := "user://settings.cfg"

var dedicated := false
var fill_bots := false
var bot_count := 0
var port := DEFAULT_PORT
var player_name := "Player"
var simulated_lag_ms := 0
var autopilot := false
var launch := {}


func _ready() -> void:
	launch = _parse_args(OS.get_cmdline_user_args())
	if OS.has_feature("dedicated_server"):
		launch["server"] = ""
	simulated_lag_ms = int(launch.get("lag", 0))
	autopilot = launch.has("autopilot")
	_load_settings()
	if launch.has("name"):
		player_name = clean_name(launch["name"])
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(leave)


func run_launch_args() -> bool:
	var launch_port := int(launch.get("port", DEFAULT_PORT))
	var bots := int(launch.get("bots", 0))
	var fill := launch.has("fill")
	if launch.has("server"):
		start_server(launch_port, true, fill, bots)
	elif launch.has("host"):
		start_server(launch_port, false, fill, bots)
	elif launch.has("join"):
		join(launch["join"], launch_port)
	elif launch.has("practice"):
		practice()
	else:
		return false
	return true


func practice() -> void:
	dedicated = false
	fill_bots = true
	bot_count = 0
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	get_tree().change_scene_to_file.call_deferred(GAME_SCENE)


func start_server(server_port: int, headless: bool, fill: bool, bots := 0) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_server(server_port, MAX_CLIENTS)
	if error != OK:
		return error
	multiplayer.multiplayer_peer = peer
	port = server_port
	dedicated = headless
	fill_bots = fill
	bot_count = bots
	print("Server listening on port %d (%s)" % [server_port, "dedicated" if headless else "host"])
	get_tree().change_scene_to_file.call_deferred(GAME_SCENE)
	return OK


func join(address: String, server_port: int) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_client(address, server_port)
	if error != OK:
		return error
	dedicated = false
	fill_bots = false
	bot_count = 0
	port = server_port
	multiplayer.multiplayer_peer = peer
	return OK


func leave() -> void:
	var was_dedicated := dedicated
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	dedicated = false
	if was_dedicated:
		get_tree().quit()
		return
	get_tree().change_scene_to_file.call_deferred(MENU_SCENE)


func set_player_name(raw: String) -> void:
	player_name = clean_name(raw)
	var settings := ConfigFile.new()
	settings.load(SETTINGS_PATH)
	settings.set_value("player", "name", player_name)
	settings.save(SETTINGS_PATH)


func local_address() -> String:
	for address in IP.get_local_addresses():
		if address.begins_with("192.168.") or address.begins_with("10.") or _is_private_172(address):
			return address
	return "127.0.0.1"


static func clean_name(raw: String) -> String:
	var cleaned := raw.strip_edges().replace("[", "").replace("]", "").left(MAX_NAME_LENGTH)
	return cleaned if not cleaned.is_empty() else "Player"


func _load_settings() -> void:
	var settings := ConfigFile.new()
	if settings.load(SETTINGS_PATH) == OK:
		player_name = clean_name(settings.get_value("player", "name", player_name))


func _on_connected() -> void:
	print("Connected as peer %d" % multiplayer.get_unique_id())
	get_tree().change_scene_to_file.call_deferred(GAME_SCENE)


func _on_connection_failed() -> void:
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	join_failed.emit("Could not reach the host.")


static func _is_private_172(address: String) -> bool:
	if not address.begins_with("172."):
		return false
	var second := int(address.get_slice(".", 1))
	return second >= 16 and second <= 31


static func _parse_args(args: PackedStringArray) -> Dictionary:
	var parsed := {}
	for arg in args:
		if not arg.begins_with("--"):
			continue
		var key_value := arg.substr(2).split("=", true, 1)
		parsed[key_value[0]] = key_value[1] if key_value.size() > 1 else ""
	return parsed
