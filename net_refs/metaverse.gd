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
const PERSIST_PROPERTIES := [
	"computations",
	"diversity_model",
	"yq",
	"_dirty_values",
]

var computations := 0.0
var diversity_model: Dictionary # see comments in static/utils.gd, get_diversity_index()

# TODO: histories including information using get_information()

var yq := -1 # last sync, = year * 4 + (quarter - 1)

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
		yq,
		computations,
		diversity_model.duplicate(),
	]


func sync_server_init(data: Array) -> void:
	# facility only; keeps dict reference!
	yq = data[0]
	computations = data[1]
	diversity_model = data[2]


func propagate_component_init(data: Array) -> void:
	# non-facilities only; reference-safe
	var svr_yq: int = data[0]
	assert(svr_yq >= yq, "Load order different than process order?")
	yq = svr_yq # TODO: histories
	computations += data[1]
	utils.add_to_diversity_model(diversity_model, data[2])


func get_server_changes(data: Array) -> void:
	# facility accumulator only; zero accumulators and dirty flags
	data.append(_dirty_values)
	if _dirty_values & DIRTY_COMPUTATIONS:
		data.append(computations)
		computations = 0.0
	if _dirty_values & DIRTY_DIVERSITY_MODEL:
		data.append(diversity_model.size())
		for key in diversity_model: # has changes only
			data.append(key)
			data.append(diversity_model[key])
		diversity_model.clear()
	_dirty_values = 0


func sync_server_changes(data: Array, k: int) -> int:
	# any target; reference safe
	var svr_yq: int = data[0]
	yq = svr_yq # TODO: histories
	var flags: int = data[k]
	k += 1
	if flags & DIRTY_COMPUTATIONS:
		computations += data[k]
		k += 1
	if flags & DIRTY_DIVERSITY_MODEL:
		var size: int = data[k]
		k += 1
		var i := 0
		while i < size:
			var key: int = data[k]
			k += 1
			var change: float = data[k]
			k += 1
			if diversity_model.has(key):
				diversity_model[key] += change
				if diversity_model[key] == 0.0:
					diversity_model.erase(key)
			else:
				diversity_model[key] = change
			i += 1
	return k







