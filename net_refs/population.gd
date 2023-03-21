# population.gd
# This file is part of Astropolis
# Copyright 2019-2023 Charlie Whitfield, all rights reserved
# *****************************************************************************
class_name Population

# Arrays indexed by population_type unless noted otherwise.

const ivutils := preload("res://ivoyager/static/utils.gd")
const utils := preload("res://astropolis_public/static/utils.gd")
const netrefs := preload("res://astropolis_public/static/netrefs.gd")

# save/load persistence for server only
const PERSIST_MODE := IVEnums.PERSIST_PROCEDURAL
const PERSIST_PROPERTIES := [
	"yq",
	"numbers",
	"growth_rates",
	"carrying_capacities",
	"immigration_attractions",
	"emigration_pressures",
	"history_numbers",
	"_is_facility",
	"_dirty_numbers",
	"_dirty_carrying_capacities",
	"_dirty_growth_rates",
	"_dirty_immigration_attractions",
	"_dirty_emigration_pressures",
]

# Interface read-only! All data flows server -> interface.
var yq := -1 # last sync, = year * 4 + (quarter - 1)
var numbers: Array
var growth_rates: Array # Facility only
var carrying_capacities: Array # Facility only; indexed by carrying_capacity_group
var immigration_attractions: Array # Facility only
var emigration_pressures: Array # Facility only
var history_numbers: Array # Array for ea pop type; [..., qrt_before_last, last_qrt]

var _is_facility := false

# server dirty data (dirty indexes as bit flags; max 64)
var _dirty_numbers := 0
var _dirty_growth_rates := 0
var _dirty_carrying_capacities := 0
var _dirty_immigration_attractions := 0
var _dirty_emigration_pressures := 0

var _tables: Dictionary = IVGlobal.tables
var _n_populations: int = _tables.n_populations
var _table_populations: Dictionary = _tables.populations
var _carrying_capacity_groups: Array = _table_populations.carrying_capacity_group
var _carrying_capacity_group2s: Array = _table_populations.carrying_capacity_group2


func _init(is_new := false, is_facility := false) -> void:
	if !is_new: # game load
		return
	numbers = ivutils.init_array(_n_populations, 0.0)
	history_numbers = ivutils.init_array(_n_populations, [])
	if !is_facility:
		return
	_is_facility = true
	growth_rates = numbers.duplicate()
	carrying_capacities = ivutils.init_array(_tables.n_carrying_capacity_groups, 0.0)
	immigration_attractions = numbers.duplicate()
	emigration_pressures = numbers.duplicate()


# ********************************* READ **************************************


func get_number(population_type: int) -> float:
	return numbers[population_type]


func get_number_total() -> float:
	return utils.get_float_array_sum(numbers)


func get_carrying_capacity_for_population(population_type: int) -> float:
	# sums the carrying_capacities that this population can occupy
	var group: int = _carrying_capacity_groups[population_type]
	var group2: int = _carrying_capacity_group2s[population_type]
	var carrying_capacity: float = carrying_capacities[group]
	if group2 != -1:
		carrying_capacity += carrying_capacities[group2]
	return carrying_capacity


func get_number_for_carrying_capacity_group(carrying_capacity_group: int) -> float:
	# sums all populations that share this carrying_capacity_group
	var number := 0.0
	var i := 0
	while i < _n_populations:
		if _carrying_capacity_groups[i] == carrying_capacity_group \
				or _carrying_capacity_group2s[i] == carrying_capacity_group:
			number += numbers[i]
		i += 1
	return number


func get_effective_pk_ratio(population_type: int) -> float:
	# 'p/k' is 'population / carrying_capacity' from classic growth model:
	# https://en.wikipedia.org/wiki/Population_growth
	# This function attempts to account for populations that share overlapping
	# carrying_capacity_group. I.e., they can occupy the same "space", while
	# either may have alternative spaces to live in.
	# Returns INF if carrying_capacity == 0.0.

	var carrying_capacity := get_carrying_capacity_for_population(population_type)
	if carrying_capacity == 0.0:
		return INF
	var init_ratio: float = numbers[population_type] / carrying_capacity
	var group: int = _carrying_capacity_groups[population_type]
	# Sum ratios for populations that share our primary space. This will give
	# smaller penalty from other populations that have large alternative spaces
	# (due to large denominator).
	var pk_ratio := INF
	if carrying_capacities[group] > 0.0:
		pk_ratio = init_ratio
		var i := 0
		while i < _n_populations:
			if i != population_type and numbers[i] > 0.0:
				if _carrying_capacity_groups[i] == group or _carrying_capacity_group2s[i] == group:
					pk_ratio += numbers[i] / get_carrying_capacity_for_population(i)
			i += 1
	
	var group2: int = _carrying_capacity_group2s[population_type]
	if group2 == -1:
		return pk_ratio
	
	# Do sum ratio for populations that share our secondary space. Perhaps this
	# space is less occupied and will give more favorable ratio.
	var pk_ratio2 := INF
	if carrying_capacities[group2] > 0.0:
		pk_ratio2 = init_ratio
		var i := 0
		while i < _n_populations:
			if i != population_type and numbers[i] > 0.0:
				if _carrying_capacity_groups[i] == group2 or _carrying_capacity_group2s[i] == group2:
					pk_ratio2 += numbers[i] / get_carrying_capacity_for_population(i)
			i += 1
	
	if pk_ratio2 < pk_ratio:
		return pk_ratio2
	return pk_ratio


# **************************** SERVER ONNLY !!!! ******************************


func change_number(population_type: int, change: float) -> void:
	assert(change == floor(change), "Expected integral value!")
	numbers[population_type] += change
	_dirty_numbers |= 1 << population_type


func change_growth_rate(population_type: int, change: float) -> void:
	growth_rates[population_type] += change
	_dirty_growth_rates |= 1 << population_type


func change_carrying_capacity(carrying_capacity_group: int, change: float) -> void:
	carrying_capacities[carrying_capacity_group] += change
	_dirty_carrying_capacities |= 1 << carrying_capacity_group





# ********************************* SYNC **************************************


func get_server_init() -> Array: # new or loaded game
	# facility only; reference-safe
	return [
		yq,
		numbers.duplicate(),
		history_numbers.duplicate(true),
		growth_rates.duplicate(),
		carrying_capacities.duplicate(),
		immigration_attractions.duplicate(),
		emigration_pressures.duplicate(),
	]


func sync_server_init(data: Array) -> void:
	# facility only; keeps array references!
	yq = data[0]
	numbers = data[1]
	history_numbers = data[2]
	growth_rates = data[3]
	carrying_capacities = data[4]
	immigration_attractions = data[5]
	emigration_pressures = data[6]


func propagate_component_init(data: Array) -> void:
	# non-facilities only; reference-safe
	var svr_yq: int = data[0]
	assert(svr_yq >= yq, "Load order different than process order?")
	utils.add_to_float_array_with_array(numbers, data[1])
	
	# expand history arrays as needed (at end and/or front) to handle this data
	var add_history_numbers: Array = data[2]
	var add_history_size: int = add_history_numbers[0].size()
	var history_size: int = history_numbers[0].size()
	if yq == -1:
		yq = svr_yq - add_history_size # set to begining of this history
	while yq < svr_yq: # expand history end (append for newer quarters)
		var i := 0
		while i < _n_populations:
			history_numbers[i].append(0.0)
			i += 1
		history_size += 1
		yq += 1
	while add_history_size > history_size: # expand history front (push_front for older quarters)
		var i := 0
		while i < _n_populations:
			history_numbers[i].push_front(0.0)
			i += 1
		history_size += 1
	
	# add history (history arrays are expanded and yq is aligned with svr_yq)
	var quarter := -1 # history indexed from back!
	while quarter >= -add_history_size:
		var i := 0
		while i < _n_populations:
			history_numbers[i] += add_history_numbers[i]
			i += 1
		quarter -= 1


func get_server_changes(data: Array) -> void:
	# facility accumulator only; zero values and dirty flags
	# optimized for right-biased dirty flags
	netrefs.append_and_zero_dirty_bshift(data, numbers, _dirty_numbers)
	netrefs.append_and_zero_dirty_bshift(data, growth_rates, _dirty_growth_rates)
	netrefs.append_and_zero_dirty_bshift(data, carrying_capacities, _dirty_carrying_capacities)
	netrefs.append_and_zero_dirty_bshift(data, immigration_attractions, _dirty_immigration_attractions)
	netrefs.append_and_zero_dirty_bshift(data, emigration_pressures, _dirty_emigration_pressures)
	_dirty_numbers = 0
	_dirty_growth_rates = 0
	_dirty_carrying_capacities = 0
	_dirty_immigration_attractions = 0
	_dirty_emigration_pressures = 0


func sync_server_changes(data: Array, k: int) -> int:
	# any target; reference safe
	var svr_yq: int = data[0]
	if yq < svr_yq:
		_update_history(svr_yq) # before new quarter changes
	
	k = netrefs.add_dirty_bshift(data, numbers, k)
	
	if !_is_facility:
		return 0 # not used
	
	k = netrefs.add_dirty_bshift(data, growth_rates, k)
	k = netrefs.add_dirty_bshift(data, carrying_capacities, k)
	k = netrefs.add_dirty_bshift(data, immigration_attractions, k)
	k = netrefs.add_dirty_bshift(data, emigration_pressures, k)
	
	return k


func _update_history(svr_yq: int) -> void:
	if yq == -1: # new - no history to save yet
		yq = svr_yq
		return
	while yq < svr_yq: # loop in case we missed a quarter
		var i := 0
		while i < _n_populations:
			history_numbers[i].append(numbers[i])
			i += 1
		yq += 1




