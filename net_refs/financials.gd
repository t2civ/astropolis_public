# financials.gd
# This file is part of Astropolis
# Copyright 2019-2023 Charlie Whitfield, all rights reserved
# *****************************************************************************
class_name Financials
extends NetRef

# Changes propagate from Facility to Player only.
#
# Income and cash flow items are cummulative for current quarter.
# Balance items are running.

enum { # _dirty_values
	DIRTY_REVENUE = 1,
}

const PERSIST_MODE := IVEnums.PERSIST_PROCEDURAL
const PERSIST_PROPERTIES: Array[StringName] = [
	&"yq",
	&"revenue",
	&"accountings",
	&"_dirty_values",
	&"_dirty_accountings",
]

# interface sync
var yq := -1 # last sync, = year * 4 + (quarter - 1)
var revenue := 0.0 # positive values of INC_STMT_GROSS
var accountings: Array[float]

# TODO:
# var items: Dictionary # facility only?


var _dirty_values := 0
var _dirty_accountings := 0


func _init(is_new := false) -> void:
	if !is_new: # game load
		return
	
	# debug dev
	var n_accountings := 10
	
	accountings = ivutils.init_array(n_accountings, 0.0, TYPE_FLOAT)


func get_server_init() -> Array:
	# facility only; reference-safe
	return [
		yq,
		revenue,
		accountings.duplicate(),
	]


func sync_server_init(data: Array) -> void:
	# facility only; keeps array reference!
	yq = data[0]
	revenue = data[1]
	accountings = data[2]


func propagate_component_init(data: Array) -> void:
	# non-facilities only; reference-safe
	var svr_yq: int = data[0]
	assert(svr_yq >= yq, "Load order different than process order?")
	yq = svr_yq # TODO: histories
	revenue += data[1]
	var data_array: Array[float] = data[2]
	utils.add_to_float_array_with_array(accountings, data_array)


func take_server_delta(data: Array) -> void:
	# facility accumulator only; zero accumulators and dirty flags
	data.append(_dirty_values)
	if _dirty_values & DIRTY_REVENUE:
		data.append(revenue)
		revenue = 0.0
	_dirty_values = 0
	_append_and_zero_dirty(data, accountings, _dirty_accountings)
	_dirty_accountings = 0


func sync_server_delta(data: Array, k: int) -> int:
	# any target; reference safe
	var svr_yq: int = data[0]
	yq = svr_yq # TODO: histories
	var flags: int = data[k]
	k += 1
	if flags & DIRTY_REVENUE:
		revenue += data[k]
		k += 1
	k = _add_dirty(data, accountings, k)
	return k

