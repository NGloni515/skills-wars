extends Control

@onready var _name: LineEdit = %PlayerName
@onready var _address: LineEdit = %Address
@onready var _room_code: LineEdit = %RoomCode
@onready var _backend_url: LineEdit = %BackendUrl
@onready var _fill_bots: CheckBox = %FillBots
@onready var _games: VBoxContainer = %LanGames
@onready var _searching: Label = %Searching
@onready var _status: Label = %Status
@onready var _online_buttons: Array[Button] = [%QuickPlay, %CreateRoom, %JoinRoom]

var _online: OnlineApi
var _attempt := 0


func _ready() -> void:
	if Net.run_launch_args():
		return
	_online = OnlineApi.new()
	add_child(_online)
	_name.text = Net.player_name
	_name.text_changed.connect(_on_name_changed)
	%Settings.pressed.connect(%SettingsPanel.show)
	_backend_url.text = Net.backend_url
	_backend_url.text_changed.connect(Net.set_backend_url)
	%QuickPlay.pressed.connect(_play_online.bind(_online.quick_play))
	%CreateRoom.pressed.connect(_play_online.bind(_online.create_room))
	%JoinRoom.pressed.connect(_join_room_code)
	_room_code.text_submitted.connect(func(_code: String) -> void: _join_room_code())
	%Practice.pressed.connect(Net.practice)
	%Host.pressed.connect(_on_host_pressed)
	%Join.pressed.connect(func() -> void: _join(_address.text.strip_edges(), Net.DEFAULT_PORT))
	Net.join_failed.connect(_on_join_failed)
	Loading.canceled.connect(_on_loading_canceled)
	var discovery := LanDiscovery.new()
	add_child(discovery)
	discovery.games_changed.connect(_show_games)
	if discovery.listen() != OK:
		_searching.text = "Can't search for games on this network."
	if Net.launch.has("quickplay"):
		_play_online(_online.quick_play)
	elif Net.launch.has("join-room"):
		_room_code.text = Net.launch["join-room"]
		_join_room_code()


func _on_name_changed(raw: String) -> void:
	Net.set_player_name(raw)
	var allowed := raw.strip_edges().is_empty() or NameFilter.is_allowed(raw)
	_status.text = "" if allowed else "That name isn't allowed. Others will see \"Player\"."


func _join_room_code() -> void:
	var code := _room_code.text.strip_edges().to_upper()
	if code.length() != 4:
		_status.text = "Type the 4-letter room code."
		return
	_play_online(_online.join_room.bind(code))


func _play_online(request: Callable) -> void:
	_attempt += 1
	var attempt := _attempt
	_set_online_busy(true)
	_status.text = ""
	Loading.show_connecting("Finding a game…")
	var connection: Dictionary = await request.call()
	if attempt != _attempt:
		return
	if connection.has("error"):
		Loading.close()
		_status.text = connection.error
		_set_online_busy(false)
		return
	if Net.join_room(connection) != OK:
		Loading.close()
		_status.text = "Couldn't connect to the game server."
		_set_online_busy(false)


func _on_loading_canceled() -> void:
	_attempt += 1
	_set_online_busy(false)


func _set_online_busy(busy: bool) -> void:
	for button in _online_buttons:
		button.disabled = busy


func _on_join_failed(reason: String) -> void:
	_status.text = reason
	_set_online_busy(false)


func _on_host_pressed() -> void:
	if Net.start_server(Net.DEFAULT_PORT, false, _fill_bots.button_pressed) != OK:
		_status.text = "Could not open port %d." % Net.DEFAULT_PORT


func _join(address: String, port: int) -> void:
	if address.is_empty():
		_status.text = "Type the host's address first."
		return
	_status.text = "Connecting to %s…" % address
	if Net.join(address, port) != OK:
		_status.text = "That address doesn't look right."


func _show_games(games: Array) -> void:
	for child in _games.get_children():
		child.queue_free()
	_searching.visible = games.is_empty()
	for game: Dictionary in games:
		var button := Button.new()
		button.custom_minimum_size = Vector2(0, 60)
		button.add_theme_font_size_override("font_size", 24)
		var players := "1 player" if game.players == 1 else "%d players" % game.players
		button.text = "%s  ·  %s" % [game.name, players]
		button.pressed.connect(_join.bind(game.address, game.port))
		_games.add_child(button)
