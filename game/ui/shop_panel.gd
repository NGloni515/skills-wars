class_name ShopPanel
extends PanelContainer

signal buy_requested(upgrade: int)

const ICONS: Array[Texture2D] = [
	preload("res://fx/textures/upgrade_hook_range.png"), preload("res://fx/textures/upgrade_hook_speed.png"),
	preload("res://fx/textures/upgrade_hook_size.png"), preload("res://fx/textures/upgrade_hook_cooldown.png"),
	preload("res://fx/textures/upgrade_arrow_speed.png"), preload("res://fx/textures/upgrade_arrow_stun.png"),
	preload("res://fx/textures/upgrade_trap_size.png"), preload("res://fx/textures/upgrade_trap_cooldown.png"),
]
const SKILL_ICONS: Array[Texture2D] = [
	preload("res://fx/textures/skill_hook.png"), preload("res://fx/textures/skill_arrow.png"),
	preload("res://fx/textures/skill_trap.png"),
]
const COIN := preload("res://fx/textures/icon_gold.png")
const STAR := preload("res://fx/textures/star.png")
const FILLED_PIP := "●"
const EMPTY_PIP := "○"
const CARD_WIDTH := 150
const GOLD := Color(0.98, 0.78, 0.25)
const BORDERS := {&"normal": Color(0.3, 0.38, 0.52), &"affordable": GOLD, &"maxed": Color(0.45, 0.85, 0.5)}

var starred := -1

var _cards: Array[Dictionary] = []
var _tabs: Array[Button] = []
var _gold: Label
var _levels: Array[int] = []
var _styles := {}


func _ready() -> void:
	starred = Settings.get_value("shop", "starred", -1)
	for state: StringName in BORDERS:
		_styles[state] = _card_style(BORDERS[state], 3 if state == &"affordable" else 2)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	add_child(row)
	row.add_child(_build_side())
	var cards := HBoxContainer.new()
	cards.add_theme_constant_override("separation", 10)
	row.add_child(cards)
	var stars := ButtonGroup.new()
	stars.allow_unpress = true
	for kind in Upgrades.COUNT:
		var card := _build_card(kind, stars)
		cards.add_child(card.panel)
		_cards.append(card)
	var close := Button.new()
	close.text = "✕"
	close.custom_minimum_size = Vector2(48, 48)
	close.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	close.add_theme_font_size_override("font_size", 24)
	close.pressed.connect(hide)
	row.add_child(close)
	_select_tab(Upgrades.Skill.HOOK)


func toggle() -> void:
	visible = not visible


func refresh(definition: HeroDefinition, gold: int, levels: Array[int], costs: PackedInt32Array, open_for_business: bool) -> void:
	_gold.text = str(gold)
	var affordable_tabs := {}
	for kind in _cards.size():
		var card: Dictionary = _cards[kind]
		var level := levels[kind]
		var cost := Upgrades.next_cost(levels, costs, kind)
		var maxed := cost < 0
		card.pips.text = FILLED_PIP.repeat(level) + EMPTY_PIP.repeat(costs.size() - level)
		card.value.text = _value_text(definition, kind, level, maxed)
		var buy: Button = card.buy
		buy.text = "MAX" if maxed else str(cost)
		buy.icon = null if maxed else COIN
		buy.disabled = maxed or not open_for_business or gold < cost
		var state := &"maxed" if maxed else (&"affordable" if not buy.disabled else &"normal")
		if card.state != state:
			card.panel.add_theme_stylebox_override("panel", _styles[state])
			card.state = state
		if state == &"affordable":
			affordable_tabs[Upgrades.SKILL_OF[kind]] = true
		if _levels.size() == levels.size() and level > _levels[kind] and visible:
			_pop(card.icon)
	_levels = levels.duplicate()
	for skill in _tabs.size():
		_tabs[skill].text = Upgrades.SKILL_NAMES[skill] + ("  •" if affordable_tabs.has(skill) else "")


func _select_tab(skill: int) -> void:
	_tabs[skill].button_pressed = true
	for kind in _cards.size():
		_cards[kind].panel.visible = Upgrades.SKILL_OF[kind] == skill
	reset_size()


func _value_text(definition: HeroDefinition, kind: int, level: int, maxed: bool) -> String:
	var now := Upgrades.format_stat(kind, Upgrades.stat(definition, kind, level))
	if maxed:
		return "%s %s" % [now, Upgrades.UNITS[kind]]
	var next := Upgrades.format_stat(kind, Upgrades.stat(definition, kind, level + 1))
	return "%s → %s %s" % [now, next, Upgrades.UNITS[kind]]


func _on_star_toggled(on: bool, kind: int) -> void:
	if on:
		starred = kind
	elif starred == kind:
		starred = -1
	Settings.set_value("shop", "starred", starred)


func _build_side() -> Control:
	var side := VBoxContainer.new()
	side.custom_minimum_size.x = 124
	side.add_theme_constant_override("separation", 8)
	var group := ButtonGroup.new()
	for skill in Upgrades.SKILL_NAMES.size():
		var tab := Button.new()
		tab.toggle_mode = true
		tab.button_group = group
		tab.custom_minimum_size = Vector2(0, 46)
		tab.alignment = HORIZONTAL_ALIGNMENT_LEFT
		tab.icon = SKILL_ICONS[skill]
		tab.add_theme_constant_override("icon_max_width", 26)
		tab.add_theme_font_size_override("font_size", 20)
		tab.pressed.connect(_select_tab.bind(skill))
		side.add_child(tab)
		_tabs.append(tab)
	var gold_row := HBoxContainer.new()
	gold_row.add_child(_icon(COIN, 24))
	_gold = _label("0", 22)
	_gold.add_theme_color_override("font_color", GOLD)
	gold_row.add_child(_gold)
	side.add_child(gold_row)
	return side


func _build_card(kind: int, stars: ButtonGroup) -> Dictionary:
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = CARD_WIDTH
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	panel.add_child(column)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 6)
	column.add_child(top)
	var icon := _icon(ICONS[kind], 44)
	top.add_child(icon)
	var titles := VBoxContainer.new()
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.add_theme_constant_override("separation", -4)
	titles.add_child(_label(Upgrades.NAMES[kind], 20))
	var pips := _label("", 14)
	pips.add_theme_color_override("font_color", GOLD)
	titles.add_child(pips)
	top.add_child(titles)
	var star := Button.new()
	star.toggle_mode = true
	star.button_group = stars
	star.flat = true
	star.icon = STAR
	star.expand_icon = true
	star.custom_minimum_size = Vector2(40, 40)
	star.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	for state in ["icon_normal_color", "icon_hover_color", "icon_focus_color"]:
		star.add_theme_color_override(state, Color(1.0, 1.0, 1.0, 0.25))
	for state in ["icon_pressed_color", "icon_hover_pressed_color"]:
		star.add_theme_color_override(state, GOLD)
	star.button_pressed = starred == kind
	star.toggled.connect(_on_star_toggled.bind(kind))
	top.add_child(star)
	var value := _label("", 16)
	value.add_theme_color_override("font_color", Color(0.8, 0.88, 1.0))
	value.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(value)
	var buy := Button.new()
	buy.custom_minimum_size = Vector2(0, 46)
	buy.add_theme_constant_override("icon_max_width", 24)
	buy.add_theme_font_size_override("font_size", 22)
	buy.pressed.connect(buy_requested.emit.bind(kind))
	column.add_child(buy)
	return {"panel": panel, "icon": icon, "pips": pips, "value": value, "buy": buy, "state": &""}


func _pop(icon: Control) -> void:
	var tween := create_tween()
	tween.tween_property(icon, "scale", Vector2.ONE * 1.45, 0.08)
	tween.tween_property(icon, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


static func _card_style(border: Color, width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.16, 0.28, 0.92)
	style.border_color = border
	style.set_border_width_all(width)
	style.set_corner_radius_all(12)
	style.set_content_margin_all(8)
	return style


static func _icon(texture: Texture2D, size: int) -> TextureRect:
	var icon := TextureRect.new()
	icon.texture = texture
	icon.custom_minimum_size = Vector2(size, size)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.pivot_offset = Vector2(size, size) / 2.0
	return icon


static func _label(text: String, size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	return label
