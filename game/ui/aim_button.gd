class_name AimButton
extends Control

signal aim_changed(direction: Vector2)
signal fired(direction: Vector2)
signal canceled

@export var radius := 120.0
@export var cancel_radius := 30.0
@export var label := "HOOK"

var _touch := -1
var _drag := Vector2.ZERO
var _left_center := false


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed and _touch == -1 and _center().distance_to(event.position) <= _button_radius():
			_touch = event.index
			_drag = Vector2.ZERO
			_left_center = false
			get_viewport().set_input_as_handled()
		elif not event.pressed and event.index == _touch:
			_touch = -1
			_release()
		queue_redraw()
	elif event is InputEventScreenDrag and event.index == _touch:
		_drag = (event.position - _center()).limit_length(radius)
		if _drag.length() > cancel_radius:
			_left_center = true
			aim_changed.emit(_drag.normalized())
		get_viewport().set_input_as_handled()
		queue_redraw()


func is_aiming() -> bool:
	return _touch != -1 and _drag.length() > cancel_radius


func aim_direction() -> Vector2:
	return _drag.normalized()


func _release() -> void:
	if _drag.length() > cancel_radius:
		fired.emit(_drag.normalized())
	elif _left_center:
		canceled.emit()
	else:
		fired.emit(Vector2.ZERO)
	_drag = Vector2.ZERO


func _center() -> Vector2:
	return get_global_rect().get_center()


func _button_radius() -> float:
	return minf(size.x, size.y) * 0.5


func _draw() -> void:
	var center := size * 0.5
	var r := _button_radius()
	var pressed := _touch != -1
	draw_circle(center, r, Color(0.1, 0.12, 0.16, 0.55 if pressed else 0.4))
	draw_arc(center, r, 0.0, TAU, 48, Color(1, 1, 1, 0.6), 3.0, true)
	if pressed:
		draw_arc(center, cancel_radius, 0.0, TAU, 32, Color(1, 0.4, 0.4, 0.7), 2.0, true)
		draw_circle(center + _drag, r * 0.32, Color(1, 1, 1, 0.75))
	var font := get_theme_default_font()
	var font_size := 22
	var text_size := font.get_string_size(label, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
	draw_string(font, center + Vector2(-text_size.x * 0.5, text_size.y * 0.3), label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(1, 1, 1, 0.3 if pressed else 0.9))
