class_name SnapshotCodec
extends RefCounted

enum Field { S8, U8, S16, S32, F32, BOOL }

# Must list HeroState.to_row(), PowerUpState.to_row() and TrapState.to_row() fields in order.
const HERO := [
	Field.S32, Field.U8, Field.U8,
	Field.F32, Field.F32, Field.F32, Field.BOOL,
	Field.U8, Field.S32, Field.U8, Field.S32,
	Field.F32, Field.F32, Field.F32, Field.S32,
	Field.S32, Field.U8, Field.U8, Field.U8, Field.U8,
	Field.BOOL, Field.F32, Field.BOOL, Field.BOOL, Field.S32,
	Field.S32, Field.BOOL, Field.BOOL, Field.F32, Field.F32, Field.F32, Field.S32,
	Field.BOOL, Field.S32,
	Field.U8, Field.U8, Field.U8, Field.U8,
]
const POWERUP := [Field.S32, Field.U8, Field.F32, Field.F32, Field.S32]
const TRAP := [Field.S32, Field.U8, Field.S32, Field.F32, Field.F32, Field.S32, Field.BOOL, Field.F32]
const HEADER := [Field.S32, Field.S16, Field.S16, Field.U8, Field.S32, Field.S8, Field.BOOL]


static func encode(snapshot: Array) -> PackedByteArray:
	var stream := StreamPeerBuffer.new()
	_write_fields(stream, HEADER, [snapshot[0], snapshot[2], snapshot[3], snapshot[4], snapshot[5], snapshot[6], snapshot[7]])
	_write_rows(stream, HERO, snapshot[1])
	_write_rows(stream, POWERUP, snapshot[8])
	_write_rows(stream, TRAP, snapshot[9])
	return stream.data_array


static func decode(bytes: PackedByteArray) -> Array:
	var stream := StreamPeerBuffer.new()
	stream.data_array = bytes
	var header := _read_fields(stream, HEADER)
	var heroes := _read_rows(stream, HERO)
	var powerups := _read_rows(stream, POWERUP)
	var traps := _read_rows(stream, TRAP)
	return [header[0], heroes, header[1], header[2], header[3], header[4], header[5], header[6], powerups, traps]


static func _write_rows(stream: StreamPeerBuffer, schema: Array, rows: Array) -> void:
	stream.put_u8(rows.size())
	for row: Array in rows:
		_write_fields(stream, schema, row)


static func _read_rows(stream: StreamPeerBuffer, schema: Array) -> Array:
	var rows := []
	for i in stream.get_u8():
		rows.append(_read_fields(stream, schema))
	return rows


static func _write_fields(stream: StreamPeerBuffer, schema: Array, values: Array) -> void:
	for i in schema.size():
		match schema[i]:
			Field.S8: stream.put_8(values[i])
			Field.U8: stream.put_u8(values[i])
			Field.S16: stream.put_16(values[i])
			Field.S32: stream.put_32(values[i])
			Field.F32: stream.put_float(values[i])
			Field.BOOL: stream.put_u8(1 if values[i] else 0)


static func _read_fields(stream: StreamPeerBuffer, schema: Array) -> Array:
	var values := []
	values.resize(schema.size())
	for i in schema.size():
		match schema[i]:
			Field.S8: values[i] = stream.get_8()
			Field.U8: values[i] = stream.get_u8()
			Field.S16: values[i] = stream.get_16()
			Field.S32: values[i] = stream.get_32()
			Field.F32: values[i] = stream.get_float()
			Field.BOOL: values[i] = stream.get_u8() != 0
	return values
