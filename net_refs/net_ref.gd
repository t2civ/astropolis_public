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

const ivutils := preload("res://ivoyager/static/utils.gd")
const utils := preload("res://astropolis_public/static/utils.gd")
const LOG2_64 := Utils.LOG2_64


func get_server_init() -> Array:
	# Facility only. Keep reference safe.
	return []


func sync_server_init(_data: Array) -> void:
	# Facility only. May keep nested array references.
	pass


func propagate_component_init(_data: Array) -> void:
	# non-facilities only
	pass


func get_server_changes(_data: Array) -> void:
	# facility accumulator only; zero accumulators and dirty flags
	pass


func sync_server_changes(_data: Array, _k: int) -> int:
	# any target
	return 0


func get_interface_dirty() -> Array:
	return []


func sync_interface_dirty(_data: Array) -> void:
	pass


static func _append_dirty(data: Array, values: Array, flags: int, index_offset := 0) -> void:
	data.append(flags)
	while flags:
		var lsb := flags & -flags
		var i: int = LOG2_64[lsb] + index_offset
		data.append(values[i])
		flags &= ~lsb


static func _append_and_zero_dirty(data: Array, values: Array, flags: int, index_offset := 0) -> void:
	data.append(flags)
	while flags:
		var lsb := flags & -flags
		var i: int = LOG2_64[lsb] + index_offset
		data.append(values[i])
		values[i] = 0.0
		flags &= ~lsb


static func _set_dirty(data: Array, to: Array, data_offset := 0, index_offset := 0) -> int:
	var flags: int = data[data_offset]
	data_offset += 1
	while flags:
		var lsb := flags & -flags
		var i: int = LOG2_64[lsb] + index_offset
		to[i] = data[data_offset]
		data_offset += 1
		flags &= ~lsb
	return data_offset


static func _add_dirty(data: Array, to: Array, data_offset := 0, index_offset := 0) -> int:
	var flags: int = data[data_offset]
	data_offset += 1
	while flags:
		var lsb := flags & -flags
		var i: int = LOG2_64[lsb] + index_offset
		to[i] += data[data_offset]
		data_offset += 1
		flags &= ~lsb
	return data_offset


# '_bshift' versions more optimal if flags right-biased or not sparse

static func _append_dirty_bshift(data: Array, values: Array, flags: int, index_offset := 0) -> void:
	data.append(flags)
	while flags:
		if flags & 1:
			data.append(values[index_offset])
		index_offset += 1
		flags >>= 1

static func _append_and_zero_dirty_bshift(data: Array, values: Array, flags: int, index_offset := 0) -> void:
	data.append(flags)
	while flags:
		if flags & 1:
			data.append(values[index_offset])
			values[index_offset] = 0.0
		index_offset += 1
		flags >>= 1


static func _set_dirty_bshift(data: Array, to: Array, data_offset := 0, index_offset := 0) -> int:
	var flags: int = data[data_offset]
	data_offset += 1
	while flags:
		if flags & 1:
			to[index_offset] = data[data_offset]
			data_offset += 1
		index_offset += 1
		flags >>= 1
	return data_offset


static func _add_dirty_bshift(data: Array, to: Array, data_offset := 0, index_offset := 0) -> int:
	var flags: int = data[data_offset]
	data_offset += 1
	while flags:
		if flags & 1:
			to[index_offset] += data[data_offset]
			data_offset += 1
		index_offset += 1
		flags >>= 1
	return data_offset

