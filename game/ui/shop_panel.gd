class_name ShopPanel
extends PanelContainer

signal buy_requested(upgrade: int)

const FILLED_PIP := "●"
const EMPTY_PIP := "○"

var _rows: Array[Dictionary] = []
@onready var _gold: Label = %Gold
@onready var _list: VBoxContainer = %Upgrades


func _ready() -> void:
	%Close.pressed.connect(hide)
	for upgrade in HookSkill.UPGRADE_NAMES.size():
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 14)
		var title := _label(HookSkill.UPGRADE_NAMES[upgrade], 24)
		title.custom_minimum_size.x = 150
		var pips := _label("", 24)
		pips.custom_minimum_size.x = 150
		var button := Button.new()
		button.custom_minimum_size = Vector2(150, 56)
		button.add_theme_font_size_override("font_size", 22)
		button.pressed.connect(buy_requested.emit.bind(upgrade))
		row.add_child(title)
		row.add_child(pips)
		row.add_child(button)
		_list.add_child(row)
		_rows.append({"pips": pips, "button": button})


func refresh(gold: int, levels: Array[int], costs: PackedInt32Array, open_for_business: bool) -> void:
	_gold.text = "%d gold" % gold
	for upgrade in _rows.size():
		var level := levels[upgrade]
		var row := _rows[upgrade]
		row.pips.text = FILLED_PIP.repeat(level) + EMPTY_PIP.repeat(costs.size() - level)
		var button: Button = row.button
		if level >= costs.size():
			button.text = "Max"
			button.disabled = true
		else:
			button.text = "%d" % costs[level]
			button.disabled = not open_for_business or gold < costs[level]


static func _label(text: String, size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	return label
