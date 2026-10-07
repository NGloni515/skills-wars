extends Node

signal join_failed(reason: String)

# Bump whenever RPCs, input packets or the snapshot layout change: builds with different numbers can't play together.
const PROTOCOL := 3
const DEFAULT_PORT := 7777
const MAX_CLIENTS := 7
const MAX_NAME_LENGTH := 16
const GAME_SCENE := "res://match/game.tscn"
const MENU_SCENE := "res://ui/main_menu.tscn"
const DEFAULT_BACKEND_URL := "http://127.0.0.1:3000"

enum Handshake { HELLO = 1, ACCEPTED = 2, REJECTED = 3 }

var dedicated := false
var fill_bots := false
var bot_count := 0
var port := DEFAULT_PORT
var player_name := "Player"
var simulated_lag_ms := 0
var autopilot := false
var launch := {}
var backend_url := DEFAULT_BACKEND_URL
var room_code := ""


func _ready() -> void:
	launch = _parse_args(OS.get_cmdline_user_args())
	if OS.has_feature("dedicated_server"):
		launch["server"] = ""
	simulated_lag_ms = int(launch.get("lag", 0))
	autopilot = launch.has("autopilot")
	player_name = clean_name(Settings.get_value("player", "name", player_name))
	backend_url = Settings.get_value("online", "backend_url", backend_url)
	if launch.has("name"):
		player_name = clean_name(launch["name"])
	if launch.has("backend"):
		backend_url = launch["backend"]
	var scene_multiplayer := multiplayer as SceneMultiplayer
	scene_multiplayer.auth_callback = _on_auth
	scene_multiplayer.peer_authenticating.connect(_on_peer_authenticating)
	scene_multiplayer.peer_authentication_failed.connect(_on_authentication_failed)
	Loading.canceled.connect(_on_loading_canceled)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(leave)


func run_launch_args() -> bool:
	var launch_port := int(launch.get("port", DEFAULT_PORT))
	var bots := int(launch.get("bots", 0))
	var fill := launch.has("fill")
	if launch.has("print-protocol"):
		print("protocol=%d" % PROTOCOL)
		get_tree().quit()
	elif launch.has("server"):
		room_code = launch.get("room", "")
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


func join_room(connection: Dictionary) -> Error:
	var error := join(connection.host, int(connection.port), "Joining room %s…" % connection.code)
	if error == OK:
		room_code = connection.code
	return error


func practice() -> void:
	room_code = ""
	dedicated = false
	fill_bots = true
	bot_count = 0
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	Loading.change_scene(GAME_SCENE, "Starting practice…", true)


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
	print("Server listening on port %d (%s, protocol %d)" % [server_port, "dedicated" if headless else "host", PROTOCOL])
	if headless:
		get_tree().change_scene_to_file.call_deferred(GAME_SCENE)
	else:
		Loading.change_scene(GAME_SCENE, "Opening your game…", true)
	return OK


func join(address: String, server_port: int, message := "") -> Error:
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_client(address, server_port)
	if error != OK:
		return error
	dedicated = false
	fill_bots = false
	bot_count = 0
	port = server_port
	multiplayer.multiplayer_peer = peer
	Loading.show_connecting(message if not message.is_empty() else "Connecting to %s…" % address)
	return OK


func leave() -> void:
	var was_dedicated := dedicated
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	dedicated = false
	room_code = ""
	if was_dedicated:
		get_tree().quit()
		return
	Loading.change_scene(MENU_SCENE, "Back to the menu…")


func set_player_name(raw: String) -> void:
	player_name = clean_name(raw)
	Settings.set_value("player", "name", player_name)


func set_backend_url(raw: String) -> void:
	backend_url = raw.strip_edges().trim_suffix("/")
	Settings.set_value("online", "backend_url", backend_url)


func local_address() -> String:
	for address in IP.get_local_addresses():
		if address.begins_with("192.168.") or address.begins_with("10.") or _is_private_172(address):
			return address
	return "127.0.0.1"


static func clean_name(raw: String) -> String:
	var cleaned := raw.strip_edges().replace("[", "").replace("]", "").left(MAX_NAME_LENGTH)
	return cleaned if not cleaned.is_empty() and NameFilter.is_allowed(cleaned) else "Player"


static func version_mismatch_message(other_protocol: int, online: bool) -> String:
	if other_protocol > PROTOCOL:
		return "A new version of Skills Wars is out. Update the game to play with others."
	if online:
		return "The servers are being updated. Try again in a few minutes."
	return "That game is running an older version of Skills Wars."


func _on_peer_authenticating(peer_id: int) -> void:
	if not multiplayer.is_server():
		(multiplayer as SceneMultiplayer).send_auth(peer_id, _handshake(Handshake.HELLO))


func _on_auth(peer_id: int, data: PackedByteArray) -> void:
	var scene_multiplayer := multiplayer as SceneMultiplayer
	var kind := data.decode_u8(0) if data.size() >= 5 else 0
	var their_protocol := data.decode_u32(1) if data.size() >= 5 else 0
	if multiplayer.is_server():
		var accepted := kind == Handshake.HELLO and their_protocol == PROTOCOL
		scene_multiplayer.send_auth(peer_id, _handshake(Handshake.ACCEPTED if accepted else Handshake.REJECTED))
		if accepted:
			scene_multiplayer.complete_auth(peer_id)
		else:
			print("Rejected peer %d: protocol %d, server speaks %d" % [peer_id, their_protocol, PROTOCOL])
	elif kind == Handshake.ACCEPTED:
		scene_multiplayer.complete_auth(peer_id)
	else:
		_fail_join.call_deferred(version_mismatch_message(their_protocol, not room_code.is_empty()))


func _on_authentication_failed(_peer_id: int) -> void:
	if not multiplayer.is_server() and not multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		_fail_join("Couldn't join that game.")


static func _handshake(kind: Handshake) -> PackedByteArray:
	var bytes := PackedByteArray()
	bytes.resize(5)
	bytes.encode_u8(0, kind)
	bytes.encode_u32(1, PROTOCOL)
	return bytes


func _fail_join(reason: String) -> void:
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	room_code = ""
	Loading.close()
	print("Join failed: %s" % reason)
	join_failed.emit(reason)


func _on_connected() -> void:
	print("Connected as peer %d" % multiplayer.get_unique_id())
	Loading.change_scene(GAME_SCENE, "Loading the match…", true)


func _on_loading_canceled() -> void:
	if not multiplayer.multiplayer_peer is OfflineMultiplayerPeer and not multiplayer.is_server():
		_fail_join("Canceled.")


func _on_connection_failed() -> void:
	_fail_join("Could not reach the host.")


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
