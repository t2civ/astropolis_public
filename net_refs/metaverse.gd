# metaverse.gd
# This file is part of Astropolis
# Copyright 2019-2023 Charlie Whitfield, all rights reserved
# *****************************************************************************
class_name Metaverse
extends NetRef


enum { # _dirty_values
	DIRTY_COMPUTATIONS = 1,
	DIRTY_DIVERSITY_MODEL = 1 << 1,
}

# save/load persistence for server only
const PERSIST_MODE := IVEnums.PERSIST_PROCEDURAL
const PERSIST_PROPERTIES: Array[StringName] = [
	&"computations",
	&"diversity_model",
	&"run_qtr",
	&"_dirty_values",
]

var computations := 0.0
var diversity_model: Dictionary # see comments in static/utils.gd, get_diversity_index()

# TODO: histories including information using get_information()

var run_qtr := -1 # last sync, = year * 4 + (quarter - 1)

var _dirty_values := 0


func _init(is_new := false) -> void:
	if !is_new: # loaded game
		return
	diversity_model = {}
 
# ********************************** READ *************************************
# NOT all threadsafe!

func get_information() -> float:
	# NOT THREADSAFE !!!!
	return utils.get_shannon_entropy(diversity_model) # in 'bits'



# ****************************** SERVER MODIFY ********************************

func change_sp_group_abundance(key: int, change: float) -> void:
	assert(change == floor(change), "Expected integral value!")
	if diversity_model.has(key):
		diversity_model[key] += change
		if diversity_model[key] == 0.0:
			diversity_model.erase(key)
	elif change != 0.0:
		diversity_model[key] = change





# ********************************** SYNC *************************************


func get_server_init() -> Array:
	# facility only; reference-safe
	return [
		run_qtr,
		computations,
		diversity_model.duplicate(),
	]


func sync_server_init(data: Array) -> void:
	# facility only; keeps dict reference!
	run_qtr = data[0]
	computations = data[1]
	diversity_model = data[2]


func take_server_delta(data: Array) -> void:
	# facility accumulator only; zero accumulators and dirty flags
	
	_int_data = data[0]
	_float_data = data[1]
	
	_int_data[12] = _int_data.size()
	_int_data[13] = _float_data.size()
	
	_int_data.append(_dirty_values)
	if _dirty_values & DIRTY_COMPUTATIONS:
		_float_data.append(computations)
		computations = 0.0
	
	if _dirty_values & DIRTY_DIVERSITY_MODEL:
		_int_data.append(diversity_model.size())
		for key: int in diversity_model: # has changes only
			_int_data.append(key)
			_float_data.append(diversity_model[key])
		diversity_model.clear()
	_dirty_values = 0


func add_server_delta(data: Array) -> void:
	# any target; reference safe
	
	_int_data = data[0]
	_float_data = data[1]
	
	_int_offset = _int_data[12]
	_float_offset = _int_data[13]
	
	var svr_qtr := _int_data[0]
	run_qtr = svr_qtr # TODO: histories

	var flags := _int_data[_int_offset]
	_int_offset += 1
	if flags & DIRTY_COMPUTATIONS:
		computations += _float_data[_float_offset]
		_float_offset += 1
	
	if flags & DIRTY_DIVERSITY_MODEL:
		var size := _int_data[_int_offset]
		_int_offset += 1
		var i := 0
		while i < size:
			var key := _int_data[_int_offset]
			_int_offset += 1
			var change := _float_data[_float_offset]
			_float_offset += 1
			if diversity_model.has(key):
				diversity_model[key] += change
				if diversity_model[key] == 0.0:
					diversity_model.erase(key)
			else:
				diversity_model[key] = change
			i += 1

