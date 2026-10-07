extends Node

signal canceled

const SCREEN := preload("res://ui/loading_screen.tscn")
# Never leave players stuck on the loading page if the match never reports in.
const READY_TIMEOUT_MSEC := 15000
# A few rendered frames behind the curtain hide first-use shader stutter.
const SETTLE_FRAMES := 3

var _screen: LoadingScreen
var _path := ""
var _wait_for_ready := false
var _waiting_since := -1
var _settle := 0


func _ready() -> void:
	_screen = SCREEN.instantiate()
	add_child(_screen)
	_screen.cancel_pressed.connect(_on_cancel_pressed)
	set_process(false)


func change_scene(path: String, message: String, wait_for_ready := false) -> void:
	_screen.open(message, true, false)
	_path = path
	_wait_for_ready = wait_for_ready
	_waiting_since = -1
	_settle = 0
	ResourceLoader.load_threaded_request(path)
	set_process(true)


func show_connecting(message: String) -> void:
	_screen.open(message, false, true)


func scene_ready() -> void:
	if _waiting_since >= 0:
		_waiting_since = -1
		_settle = SETTLE_FRAMES


func close() -> void:
	_path = ""
	_waiting_since = -1
	_settle = 0
	_screen.close()
	set_process(false)


func _process(_delta: float) -> void:
	if not _path.is_empty():
		_poll_load()
		return
	if _waiting_since >= 0 and Time.get_ticks_msec() - _waiting_since > READY_TIMEOUT_MSEC:
		scene_ready()
	if _settle > 0:
		_settle -= 1
		if _settle == 0:
			close()


func _poll_load() -> void:
	var progress := []
	match ResourceLoader.load_threaded_get_status(_path, progress):
		ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			_screen.set_progress(progress[0])
		ResourceLoader.THREAD_LOAD_LOADED:
			var scene: PackedScene = ResourceLoader.load_threaded_get(_path)
			_path = ""
			_screen.set_progress(1.0)
			get_tree().change_scene_to_packed(scene)
			if _wait_for_ready:
				_waiting_since = Time.get_ticks_msec()
			else:
				_settle = SETTLE_FRAMES
		_:
			push_error("Could not load %s" % _path)
			close()


func _on_cancel_pressed() -> void:
	close()
	canceled.emit()
