class_name LanDiscovery
extends Node

signal games_changed(games: Array)

const PORT := 7778
const GAME_TAG := "skills-wars"
const ANNOUNCE_INTERVAL := 1.0
const EXPIRY_MSEC := 3500

var _socket := PacketPeerUDP.new()
var _announcement: Callable
var _announce_timer := 0.0
var _listening := false
var _games := {}


func announce(info_provider: Callable) -> void:
	_announcement = info_provider
	_socket.set_broadcast_enabled(true)
	_socket.set_dest_address("255.255.255.255", PORT)


func listen() -> Error:
	# Some Android devices only deliver broadcasts to sockets that have broadcast enabled.
	_socket.set_broadcast_enabled(true)
	var error := _socket.bind(PORT)
	_listening = error == OK
	return error


func _process(delta: float) -> void:
	if _announcement.is_valid():
		_announce_timer -= delta
		if _announce_timer <= 0.0:
			_announce_timer = ANNOUNCE_INTERVAL
			var info: Dictionary = _announcement.call()
			info.merge({"game": GAME_TAG, "protocol": Net.PROTOCOL})
			_socket.put_packet(JSON.stringify(info).to_utf8_buffer())
	if _listening:
		_receive()


func _receive() -> void:
	var changed := false
	var now := Time.get_ticks_msec()
	while _socket.get_available_packet_count() > 0:
		var packet := _socket.get_packet()
		var address := _socket.get_packet_ip()
		var info = JSON.parse_string(packet.get_string_from_utf8())
		if not info is Dictionary or info.get("game") != GAME_TAG or info.get("protocol") != Net.PROTOCOL:
			continue
		if not _games.has(address):
			changed = true
		_games[address] = {
			"address": address,
			"port": int(info.get("port", Net.DEFAULT_PORT)),
			"name": str(info.get("name", "Game")).left(32),
			"players": int(info.get("players", 0)),
			"seen": now,
		}
	for address: String in _games.keys():
		if now - _games[address].seen > EXPIRY_MSEC:
			_games.erase(address)
			changed = true
	if changed:
		games_changed.emit(_games.values())


func _exit_tree() -> void:
	_socket.close()
