# biome.gd
# This file is part of Astropolis
# Copyright 2019-2023 Charlie Whitfield, all rights reserved
# *****************************************************************************
class_name Biome
extends NetRef


enum { # _dirty_values
	DIRTY_BIOPRODUCTIVITY = 1,
	DIRTY_BIOMASS = 1 << 1,
	DIRTY_DIVERSITY_MODEL = 1 << 2,
}


# save/load persistence for server only
const PERSIST_MODE := IVEnums.PERSIST_PROCEDURAL
const PERSIST_PROPERTIES := [
	&"yq",
	&"bioproductivity",
	&"biomass",
	&"diversity_model",
	&"_dirty_values",
]

var yq := -1 # last sync, = year * 4 + (quarter - 1)
var bioproductivity := 0.0
var biomass := 0.0
var diversity_model: Dictionary # see comments in static/utils.gd, get_diversity_index()

# TODO: histories including biodiversity using get_biodiversity()


var _dirty_values := 0



func _init(is_new := false) -> void:
	if !is_new: # game load
		return
	diversity_model = {}

# ********************************** READ *************************************
# NOT all threadsafe!

func get_biodiversity() -> float:
	# NOT THREADSAFE !!!!
	return utils.get_diversity_index(diversity_model)


func get_species_richness() -> float:
	# NOT THREADSAFE !!!!
	# total number of species
	return utils.get_species_richness(diversity_model)
 
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
		bioproductivity,
		biomass,
		diversity_model.duplicate(),
	]


func sync_server_init(data: Array) -> void:
	# facility only; keeps dict reference!
	yq = data[0]
	bioproductivity = data[1]
	biomass = data[2]
	diversity_model = data[3]


func propagate_component_init(data: Array) -> void:
	# non-facilities only; reference-safe
	var svr_yq: int = data[0]
	assert(svr_yq >= yq, "Load order different than process order?")
	yq = svr_yq # TODO: histories
	bioproductivity += data[1]
	biomass += data[2]
	utils.add_to_diversity_model(diversity_model, data[3])


func get_server_changes(data: Array) -> void:
	# facility accumulator only; zero accumulators and dirty flags
	data.append(_dirty_values)
	if _dirty_values & DIRTY_BIOPRODUCTIVITY:
		data.append(bioproductivity)
		bioproductivity = 0.0
	if _dirty_values & DIRTY_BIOMASS:
		data.append(biomass)
		biomass = 0.0
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
	if flags & DIRTY_BIOPRODUCTIVITY:
		bioproductivity += data[k]
		k += 1
	if flags & DIRTY_BIOMASS:
		biomass += data[k]
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

