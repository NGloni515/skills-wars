class_name AimButton
extends Control

signal aim_changed(direction: Vector2)
signal fired(direction: Vector2)
signal canceled
signal pressed_down
signal released
signal fired_vector(vector: Vector2)

@export var radius := 120.0
@export var cancel_radius := 30.0
@export var label := "HOOK"
@export var hold_to_cast := false

var cooldown_left := 0.0:
	set(value):
		if not is_equal_approx(cooldown_left, value):
			cooldown_left = value
			queue_redraw()
var cooldown_total := 1.0
var cast_progress := 0.0:
	set(value):
		if not is_equal_approx(cast_progress, value):
			cast_progress = value
			queue_redraw()

var _touch := -1
var _drag := Vector2.ZERO
var _left_center := false


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed and _touch == -1 and cooldown_left <= 0.0 and _center().distance_to(event.position) <= _button_radius():
			_touch = event.index
			_drag = Vector2.ZERO
			_left_center = false
			get_viewport().set_input_as_handled()
			if hold_to_cast:
				pressed_down.emit()
		elif not event.pressed and event.index == _touch:
			_touch = -1
			if hold_to_cast:
				_drag = Vector2.ZERO
				released.emit()
			else:
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
	return _touch != -1 and (hold_to_cast or _drag.length() > cancel_radius)


func aim_vector() -> Vector2:
	return _drag / radius if _drag.length() > cancel_radius else Vector2.ZERO


func aim_direction() -> Vector2:
	return _drag.normalized() if _drag.length() > cancel_radius else Vector2.ZERO


func _release() -> void:
	if _drag.length() > cancel_radius:
		fired.emit(_drag.normalized())
		fired_vector.emit(_drag / radius)
	elif _left_center:
		canceled.emit()
	else:
		fired.emit(Vector2.ZERO)
		fired_vector.emit(Vector2.ZERO)
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
		if not hold_to_cast:
			draw_arc(center, cancel_radius, 0.0, TAU, 32, Color(1, 0.4, 0.4, 0.7), 2.0, true)
		draw_circle(center + _drag, r * 0.32, Color(1, 1, 1, 0.75))
	if cast_progress > 0.0:
		draw_arc(center, r - 4.0, -PI / 2.0, -PI / 2.0 + TAU * cast_progress, 48, Color(1.0, 0.82, 0.3, 0.95), 8.0, true)
	var font := get_theme_default_font()
	if cooldown_left > 0.0:
		_draw_cooldown(center, r)
		_draw_centered(font, center, "%d" % ceili(cooldown_left), 46, Color(1, 1, 1, 0.95))
	else:
		_draw_centered(font, center, label, 22, Color(1, 1, 1, 0.3 if pressed else 0.9))


func _draw_cooldown(center: Vector2, r: float) -> void:
	var fraction := clampf(cooldown_left / maxf(cooldown_total, 0.01), 0.0, 1.0)
	var points := PackedVector2Array([center])
	var steps := 48
	for i in steps + 1:
		var angle := -PI / 2.0 + TAU * fraction * i / steps
		points.append(center + Vector2(cos(angle), sin(angle)) * r)
	if fraction > 0.0:
		draw_colored_polygon(points, Color(0.02, 0.03, 0.06, 0.55))


func _draw_centered(font: Font, center: Vector2, text: String, font_size: int, color: Color) -> void:
	var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
	draw_string_outline(font, center + Vector2(-text_size.x * 0.5, text_size.y * 0.3), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 6, Color(0, 0, 0, 0.6))
	draw_string(font, center + Vector2(-text_size.x * 0.5, text_size.y * 0.3), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
