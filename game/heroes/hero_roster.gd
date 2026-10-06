class_name HeroRoster
extends RefCounted

const ALL: Array[HeroDefinition] = [
	preload("res://heroes/gaff/gaff_definition.tres"),
]


static func index_of(id: StringName) -> int:
	for i in ALL.size():
		if ALL[i].id == id:
			return i
	return 0
