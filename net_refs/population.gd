# population.gd
# This file is part of Astropolis
# Copyright 2019-2023 Charlie Whitfield, all rights reserved
# *****************************************************************************
class_name Population
extends NetRef

# Arrays indexed by population_type unless noted otherwise.

# save/load persistence for server only
const PERSIST_MODE := IVEnums.PERSIST_PROCEDURAL
const PERSIST_PROPERTIES: Array[StringName] = [
	&"run_qtr",
	&"numbers",
	&"growth_rates",
	&"carrying_capacities",
	&"immigration_attractions",
	&"emigration_pressures",
	&"history_numbers",
	&"_is_facility",
	&"_dirty_numbers",
	&"_dirty_carrying_capacities",
	&"_dirty_growth_rates",
	&"_dirty_immigration_attractions",
	&"_dirty_emigration_pressures",
]

# Interface read-only! All data flows server -> interface.
var run_qtr := -1 # last sync, = year * 4 + (quarter - 1)
var numbers: Array[float]
var growth_rates: Array[float] # Facility only
var carrying_capacities: Array[float] # Facility only; indexed by carrying_capacity_group
var immigration_attractions: Array[float] # Facility only
var emigration_pressures: Array[float] # Facility only
var history_numbers: Array[Array] # Array for ea pop type; [..., qrt_before_last, last_qrt]

var _is_facility := false

# server dirty data (dirty indexes as bit flags; max 64)
var _dirty_numbers := 0
var _dirty_growth_rates := 0
var _dirty_carrying_capacities := 0
var _dirty_immigration_attractions := 0
var _dirty_emigration_pressures := 0

var _n_populations: int = table_n_rows[&"populations"]
var _table_populations: Dictionary = tables[&"populations"]
var _carrying_capacity_groups: Array[int] = _table_populations[&"carrying_capacity_group"]
var _carrying_capacity_group2s: Array[int] = _table_populations[&"carrying_capacity_group2"]


func _init(is_new := false, is_facility := false) -> void:
	if !is_new: # game load
		return
	numbers = ivutils.init_array(_n_populations, 0.0, TYPE_FLOAT)
	history_numbers = ivutils.init_array(_n_populations, [] as Array[float], TYPE_ARRAY)
	if !is_facility:
		return
	_is_facility = true
	growth_rates = numbers.duplicate()
	var n_carrying_capacity_groups: int = table_n_rows.carrying_capacity_groups
	carrying_capacities = ivutils.init_array(n_carrying_capacity_groups, 0.0, TYPE_FLOAT)
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
		run_qtr,
		numbers.duplicate(),
		history_numbers.duplicate(true),
		growth_rates.duplicate(),
		carrying_capacities.duplicate(),
		immigration_attractions.duplicate(),
		emigration_pressures.duplicate(),
	]


func sync_server_init(data: Array) -> void:
	# facility only; keeps array references!
	run_qtr = data[0]
	numbers = data[1]
	history_numbers = data[2]
	growth_rates = data[3]
	carrying_capacities = data[4]
	immigration_attractions = data[5]
	emigration_pressures = data[6]


func propagate_component_init(data: Array) -> void:
	# non-facilities only; reference-safe
	var svr_qtr: int = data[0]
	assert(svr_qtr >= run_qtr, "Load order different than process order?")
	var data_array: Array[float] = data[1]
	utils.add_to_float_array_with_array(numbers, data_array)
	
	# expand history arrays as needed (at end and/or front) to handle this data
	var add_history_numbers: Array[Array] = data[2]
	var add_history_size: int = add_history_numbers[0].size()
	var history_size: int = history_numbers[0].size()
	if run_qtr == -1:
		run_qtr = svr_qtr - add_history_size # set to begining of this history
	while run_qtr < svr_qtr: # expand history end (append for newer quarters)
		var i := 0
		while i < _n_populations:
			history_numbers[i].append(0.0)
			i += 1
		history_size += 1
		run_qtr += 1
	while add_history_size > history_size: # expand history front (push_front for older quarters)
		var i := 0
		while i < _n_populations:
			history_numbers[i].push_front(0.0)
			i += 1
		history_size += 1
	
	# add history (history arrays are expanded and run_qtr is aligned with svr_qtr)
	var quarter := -1 # history indexed from back!
	while quarter >= -add_history_size:
		var i := 0
		while i < _n_populations:
			history_numbers[i] += add_history_numbers[i]
			i += 1
		quarter -= 1


func take_server_delta(data: Array) -> void:
	# facility accumulator only; zero values and dirty flags
	
	_int_data = data[0]
	_float_data = data[1]
	
	_append_and_zero_dirty_floats(numbers, _dirty_numbers)
	_dirty_numbers = 0
	_append_and_zero_dirty_floats(growth_rates, _dirty_growth_rates)
	_dirty_growth_rates = 0
	_append_and_zero_dirty_floats(carrying_capacities, _dirty_carrying_capacities)
	_dirty_carrying_capacities = 0
	_append_and_zero_dirty_floats(immigration_attractions, _dirty_immigration_attractions)
	_dirty_immigration_attractions = 0
	_append_and_zero_dirty_floats(emigration_pressures, _dirty_emigration_pressures)
	_dirty_emigration_pressures = 0


func add_server_delta(data: Array) -> void:
	# any target; reference safe
	
	_int_data = data[0]
	_float_data = data[1]
	_int_offset = data[-1]
	_float_offset = data[-2]
	
	var svr_qtr: int = _int_data[0]
	if run_qtr < svr_qtr:
		_update_history(svr_qtr) # before new quarter changes
	
	_add_dirty_floats(numbers)
	
	if !_is_facility:
		data[-1] = _int_offset
		data[-2] = _float_offset
		return
	
	_add_dirty_floats(growth_rates)
	_add_dirty_floats(carrying_capacities)
	_add_dirty_floats(immigration_attractions)
	_add_dirty_floats(emigration_pressures)
	
	data[-1] = _int_offset
	data[-2] = _float_offset


func _update_history(svr_qtr: int) -> void:
	if run_qtr == -1: # new - no history to save yet
		run_qtr = svr_qtr
		return
	while run_qtr < svr_qtr: # loop in case we missed a quarter
		var i := 0
		while i < _n_populations:
			history_numbers[i].append(numbers[i])
			i += 1
		run_qtr += 1

