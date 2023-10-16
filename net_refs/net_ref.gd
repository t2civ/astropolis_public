# net_ref.gd
# This file is part of Astropolis
# Copyright 2019-2023 Charlie Whitfield, all rights reserved
# *****************************************************************************
class_name NetRef
extends RefCounted

# Abstract base class for data classes that are optimized for network sync.
# Only changes are synched. Most NetRef changes are synched at Facility level
# and propagated to Body, Player and Proxies. Exception: Compositions are
# synched at Body level without propagation (TODO: propagate to Proxies).

const ivutils := preload("res://addons/ivoyager_core/static/utils.gd")
const utils := preload("res://astropolis_public/static/utils.gd")
const LOG2_64 := Utils.LOG2_64


static var tables: Dictionary = IVTableData.tables
static var table_n_rows: Dictionary = IVTableData.table_n_rows


var _float_data: Array[float]
var _int_data: Array[int]
var _float_offset: int
var _int_offset: int


func get_server_init() -> Array:
	# Facility only. Keep reference safe.
	return []


func sync_server_init(_data: Array) -> void:
	# Facility only. May keep nested array references.
	pass


func take_server_delta(_data: Array) -> void:
	# facility accumulator only; zero accumulators and dirty flags
	pass


func add_server_delta(_data: Array) -> void:
	# any target
	pass


func get_interface_dirty() -> Array:
	return []


func sync_interface_dirty(_data: Array) -> void:
	pass


# container sync

func _append_dirty_ints(array: Array[int], flags: int, bits_offset := 0) -> void:
	_int_data.append(flags)
	while flags:
		var lsb := flags & -flags
		var i: int = LOG2_64[lsb] + bits_offset
		_int_data.append(array[i])
		flags &= ~lsb


func _append_dirty_floats(array: Array[float], flags: int, bits_offset := 0) -> void:
	_int_data.append(flags)
	while flags:
		var lsb := flags & -flags
		var i: int = LOG2_64[lsb] + bits_offset
		_float_data.append(array[i])
		flags &= ~lsb


func _append_and_zero_dirty_floats(array: Array[float], flags: int, bits_offset := 0) -> void:
	_int_data.append(flags)
	while flags:
		var lsb := flags & -flags
		var i: int = LOG2_64[lsb] + bits_offset
		_float_data.append(array[i])
		array[i] = 0.0
		flags &= ~lsb


func _set_dirty_ints(array: Array[int], bits_offset := 0) -> void:
	var flags := _int_data[_int_offset]
	_int_offset += 1
	while flags:
		var lsb := flags & -flags
		var i: int = LOG2_64[lsb] + bits_offset
		array[i] = _int_data[_int_offset]
		_int_offset += 1
		flags &= ~lsb


func _set_dirty_floats(array: Array[float], bits_offset := 0) -> void:
	var flags := _int_data[_int_offset]
	_int_offset += 1
	while flags:
		var lsb := flags & -flags
		var i: int = LOG2_64[lsb] + bits_offset
		array[i] = _float_data[_float_offset]
		_float_offset += 1
		flags &= ~lsb


func _add_dirty_floats(array: Array[float], bits_offset := 0) -> void:
	var flags: int = _int_data[_int_offset]
	_int_offset += 1
	while flags:
		var lsb := flags & -flags
		var i: int = LOG2_64[lsb] + bits_offset
		array[i] += _float_data[_float_offset]
		_float_offset += 1
		flags &= ~lsb

