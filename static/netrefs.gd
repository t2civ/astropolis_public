# netrefs.gd
# This file is part of Astropolis
# Copyright 2019-2023 Charlie Whitfield, all rights reserved
# *****************************************************************************
class_name Netrefs

# Highly specific functions for Net Ref data sync

const LOG2_64 := Utils.LOG2_64



static func append_dirty(data: Array, values: Array, flags: int, index_offset := 0) -> void:
	data.append(flags)
	while flags:
		var lsb := flags & -flags
		var i: int = LOG2_64[lsb] + index_offset
		data.append(values[i])
		flags &= ~lsb


static func append_and_zero_dirty(data: Array, values: Array, flags: int, index_offset := 0) -> void:
	data.append(flags)
	while flags:
		var lsb := flags & -flags
		var i: int = LOG2_64[lsb] + index_offset
		data.append(values[i])
		values[i] = 0.0
		flags &= ~lsb


static func set_dirty(data: Array, to: Array, data_offset := 0, index_offset := 0) -> int:
	var flags: int = data[data_offset]
	data_offset += 1
	while flags:
		var lsb := flags & -flags
		var i: int = LOG2_64[lsb] + index_offset
		to[i] = data[data_offset]
		data_offset += 1
		flags &= ~lsb
	return data_offset


static func add_dirty(data: Array, to: Array, data_offset := 0, index_offset := 0) -> int:
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

static func append_dirty_bshift(data: Array, values: Array, flags: int, index_offset := 0) -> void:
	data.append(flags)
	while flags:
		if flags & 1:
			data.append(values[index_offset])
		index_offset += 1
		flags >>= 1

static func append_and_zero_dirty_bshift(data: Array, values: Array, flags: int, index_offset := 0) -> void:
	data.append(flags)
	while flags:
		if flags & 1:
			data.append(values[index_offset])
			values[index_offset] = 0.0
		index_offset += 1
		flags >>= 1


static func set_dirty_bshift(data: Array, to: Array, data_offset := 0, index_offset := 0) -> int:
	var flags: int = data[data_offset]
	data_offset += 1
	while flags:
		if flags & 1:
			to[index_offset] = data[data_offset]
			data_offset += 1
		index_offset += 1
		flags >>= 1
	return data_offset


static func add_dirty_bshift(data: Array, to: Array, data_offset := 0, index_offset := 0) -> int:
	var flags: int = data[data_offset]
	data_offset += 1
	while flags:
		if flags & 1:
			to[index_offset] += data[data_offset]
			data_offset += 1
		index_offset += 1
		flags >>= 1
	return data_offset



