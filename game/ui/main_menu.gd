extends Control

@onready var _name: LineEdit = %PlayerName
@onready var _address: LineEdit = %Address
@onready var _fill_bots: CheckBox = %FillBots
@onready var _games: VBoxContainer = %LanGames
@onready var _searching: Label = %Searching
@onready var _status: Label = %Status


func _ready() -> void:
	if Net.run_launch_args():
		return
	_name.text = Net.player_name
	_name.text_changed.connect(Net.set_player_name)
	%Practice.pressed.connect(Net.practice)
	%Host.pressed.connect(_on_host_pressed)
	%Join.pressed.connect(func() -> void: _join(_address.text.strip_edges(), Net.DEFAULT_PORT))
	Net.join_failed.connect(func(reason: String) -> void: _status.text = reason)
	var discovery := LanDiscovery.new()
	add_child(discovery)
	discovery.games_changed.connect(_show_games)
	if discovery.listen() != OK:
		_searching.text = "Can't search for games on this network."


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
