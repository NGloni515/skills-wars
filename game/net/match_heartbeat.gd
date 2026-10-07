class_name MatchHeartbeat
extends Node

const INTERVAL := 5.0
const REQUEST_TIMEOUT := 4.0
const GIVE_UP_MSEC := 60000

var _url: String
var _headers: PackedStringArray
var _stats: Callable
var _http := HTTPRequest.new()
var _wait := 0.0
var _last_success_msec := 0


func _init(backend_url: String, room_code: String, secret: String, stats: Callable) -> void:
	_url = "%s/v1/internal/rooms/%s/heartbeat" % [backend_url.trim_suffix("/"), room_code]
	_headers = ["Content-Type: application/json", "x-match-secret: %s" % secret]
	_stats = stats


func _ready() -> void:
	_http.timeout = REQUEST_TIMEOUT
	_http.request_completed.connect(_on_request_completed)
	add_child(_http)
	_last_success_msec = Time.get_ticks_msec()


func _process(delta: float) -> void:
	_wait -= delta
	if _wait > 0.0:
		return
	_wait = INTERVAL
	_http.request(_url, _headers, HTTPClient.METHOD_POST, JSON.stringify(_stats.call()))
	if Time.get_ticks_msec() - _last_success_msec > GIVE_UP_MSEC:
		_shut_down("lost contact with the backend")


func _on_request_completed(result: int, status: int, _response_headers: PackedStringArray, _body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS:
		return
	if status >= 200 and status < 300:
		_last_success_msec = Time.get_ticks_msec()
	elif status == 401 or status == 404:
		_shut_down("the backend no longer knows this room (%d)" % status)


func _shut_down(reason: String) -> void:
	print("Shutting down: %s" % reason)
	set_process(false)
	get_tree().quit()
