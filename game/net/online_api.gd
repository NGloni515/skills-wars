class_name OnlineApi
extends Node

const TIMEOUT_SECONDS := 20.0
const ERRORS := {
	400: "Room codes are 4 letters.",
	404: "There's no room with that code.",
	409: "That room is full.",
	429: "Too many tries. Wait a minute and try again.",
	503: "All servers are busy. Try again soon.",
}


func quick_play() -> Dictionary:
	return await _post("/v1/rooms/quick-play", {})


func create_room(visibility := "private") -> Dictionary:
	return await _post("/v1/rooms", {"visibility": visibility})


func join_room(code: String) -> Dictionary:
	return await _post("/v1/rooms/%s/join" % code.strip_edges().to_upper().uri_encode(), {})


func _post(path: String, body: Dictionary) -> Dictionary:
	var http := HTTPRequest.new()
	http.timeout = TIMEOUT_SECONDS
	add_child(http)
	var headers := ["Content-Type: application/json", "x-game-protocol: %d" % Net.PROTOCOL]
	var error := http.request(Net.backend_url + path, headers, HTTPClient.METHOD_POST, JSON.stringify(body))
	if error != OK:
		http.queue_free()
		return {"error": "The online server address doesn't look right."}
	var response: Array = await http.request_completed
	http.queue_free()
	return _parse(response[0], response[1], response[3])


static func _parse(result: int, status: int, body: PackedByteArray) -> Dictionary:
	if result != HTTPRequest.RESULT_SUCCESS:
		return {"error": "Couldn't reach the online server."}
	var data: Variant = JSON.parse_string(body.get_string_from_utf8())
	if status >= 200 and status < 300 and data is Dictionary and data.has_all(["code", "host", "port"]):
		return data
	if status == HTTPClient.RESPONSE_UPGRADE_REQUIRED and data is Dictionary and data.has("protocol"):
		return {"error": Net.version_mismatch_message(int(data.protocol), true)}
	return {"error": ERRORS.get(status, "The online server had a problem (%d)." % status)}
