# operations.gd
# This file is part of Astropolis
# Copyright 2019-2023 Charlie Whitfield, all rights reserved
# *****************************************************************************
class_name Operations

# Arrays indexed by operation_type, except where noted.
#
# 'public_capacities' and 'est_' financials are Facility & Player only.
# 'op_logics' and 'op_commands' are Facility only.
# All vars are Interface read-only except for 'op_commands', which has the only
# data that flows Interface -> Server. Use API to set!
#
# Each op_group has 1 or more operations and is (for all purposes) the sum of
# its operations. Some op_groups can shift more easily among their ops (e.g.,
# refining). Others shift only over very long periods (e.g., iron mines don't
# change into mineral mines overnight, but may shift slowly by attrition and
# replacement).

enum OpLogics { # current state and why
	IS_IDLE_UNPROFITABLE,
	IS_IDLE_COMMAND,
	MINIMIZE_UNPROFITABLE,
	MINIMIZE_COMMAND,
	MAINTAIN_COMMAND,
	RUN_50_PERCENT_COMMAND,
	MAXIMIZE_NEW_MARKET,
	MAXIMIZE_PROFITABLE,
	MAXIMIZE_SHORTAGES,
	MAXIMIZE_COMMITMENTS,
	MAXIMIZE_COMMAND,
	N_OP_LOGICS,
}

enum OpCommands {
	AUTOMATE, # self-manage for shortages, commitments or profit
	IDLE, # caution! some ops are hard to restart!
	MINIMIZE, # winddown to idle or low rate, depending on operation
	MAINTAIN,
	RUN_50_PERCENT,
	MAXIMIZE, # windup to max
	N_OP_COMMANDS,
}

enum { # _dirty_values
	DIRTY_LFQ_REVENUE = 1,
	DIRTY_LFQ_GROSS_OUTPUT = 1 << 1,
	DIRTY_LFQ_NET_INCOME = 1 << 2,
	DIRTY_TOTAL_POWER = 1 << 3,
	DIRTY_MANUFACTURING = 1 << 4,
	DIRTY_CONSTRUCTIONS = 1 << 5,
}

const ivutils := preload("res://ivoyager/static/utils.gd")
const utils := preload("res://astropolis_public/static/utils.gd")
const netrefs := preload("res://astropolis_public/static/netrefs.gd")


# save/load persistence for server only
const PERSIST_MODE := IVEnums.PERSIST_PROCEDURAL
const PERSIST_PROPERTIES := [
	"yq",
	"lfq_revenue",
	"lfq_gross_output",
	"lfq_net_income",
	"total_power",
	"manufacturing",
	"constructions",
	"crews",
	"capacities",
	"rates",
	"public_capacities",
	"est_revenues",
	"est_gross_incomes",
	"op_logics",
	"op_commands",
	
	"has_financials",
	"_is_facility",
	
	"_dirty_values",
	"_dirty_crew",
	"_dirty_capacities_1",
	"_dirty_capacities_2",
	"_dirty_rates_1",
	"_dirty_rates_2",
	"_dirty_public_capacities_1",
	"_dirty_public_capacities_2",
	"_dirty_est_revenues_1",
	"_dirty_est_revenues_2",
	"_dirty_est_gross_incomes_1",
	"_dirty_est_gross_incomes_2",
	"_dirty_op_logics_1",
	"_dirty_op_logics_2",
	"_dirty_op_commands_1",
	"_dirty_op_commands_2",
]

# Interface read-only! Data flows server -> interface.
var yq := -1 # last sync, = year * 4 + (quarter - 1)
var lfq_revenue := 0.0 # last 4 quarters
var lfq_gross_output := 0.0 # revenue w/ some exceptions; = "economy"
var lfq_net_income := 0.0
var total_power := 0.0 # DEPRECIATE - we have a method
var manufacturing := 0.0 # present mass rate of manufactured products; DEPRECIATE for method
var constructions := 0.0 # total mass of all constructions

var crews: Array # indexed by population_type (can have crew w/out Population component)

var capacities: Array
var rates: Array # =mass_flow if has_mass_flow (?)

# Facility, Player only (has_financials = true)
var public_capacities: Array # =capacities if public sector, 0.0 if private sector
var est_revenues: Array # per year at current rate & prices
var est_gross_incomes: Array # per year at current prices


# Facility only
var op_logics: Array # enum; Facility only

# Facility only. 'op_commands' are AI or player settable from FacilityInterface.
# Use API! (Direct change will break!) Data flows Interface -> Server.
var op_commands: Array # enum; Facility only


var has_financials := false
var _is_facility := false

# server dirty data (dirty indexes as bit flags)
var _dirty_values := 0 # enum DIRTY_ flags
var _dirty_crews := 0 # max 64
var _dirty_capacities_1 := 0
var _dirty_capacities_2 := 0 # max 128
var _dirty_rates_1 := 0
var _dirty_rates_2 := 0 # max 128
var _dirty_public_capacities_1 := 0
var _dirty_public_capacities_2 := 0 # max 128
var _dirty_est_revenues_1 := 0
var _dirty_est_revenues_2 := 0 # max 128
var _dirty_est_gross_incomes_1 := 0
var _dirty_est_gross_incomes_2 := 0 # max 128
var _dirty_op_logics_1 := 0
var _dirty_op_logics_2 := 0 # max 128
var _dirty_op_commands_1 := 0
var _dirty_op_commands_2 := 0 # max 128

# indexing & table data
var _tables: Dictionary = IVGlobal.tables
var _table_operations: Dictionary = _tables.operations
var _n_operations: int = _tables.n_operations
var _op_groups_operations: Array = _tables.op_groups_operations # array of arrays


func _init(is_new := false, has_financials_ := false, is_facility := false) -> void:
	if !is_new: # game load
		return
	has_financials = has_financials_
	_is_facility = is_facility
	crews = ivutils.init_array(_tables.n_populations, 0.0)
	capacities = ivutils.init_array(_n_operations, 0.0)
	rates = capacities.duplicate()
	if !has_financials_:
		return
	public_capacities  = capacities.duplicate()
	est_revenues = capacities.duplicate()
	est_gross_incomes = capacities.duplicate()
	if !is_facility:
		return
	op_logics = ivutils.init_array(_n_operations, OpLogics.IS_IDLE_UNPROFITABLE)
	op_commands = ivutils.init_array(_n_operations, OpCommands.AUTOMATE)


# ********************************** READ *************************************
# all threadsafe


func get_crew(population_type: int) -> float:
	return crews[population_type]


func get_crew_total() -> float:
	return utils.get_float_array_sum(crews)


func get_capacity(type: int) -> float:
	return capacities[type]


func get_public_portion(type: int) -> float:
	# always 0.0 - 1.0
	if capacities[type] == 0.0:
		return 0.0
	return public_capacities[type] / capacities[type]


func get_utilization(type: int) -> float:
	if capacities[type] == 0.0:
		return 0.0
	return rates[type] / capacities[type]


func get_power(type: int) -> float:
	return rates[type] * _table_operations.power[type]


func get_power_total() -> float:
	var operation_powers: Array = _table_operations.power
	var sum := 0.0
	var i := 0
	while i < _n_operations:
		sum += rates[i] * operation_powers[i]
		i += 1
	return sum


func get_gui_flow(type: int) -> float:
	return rates[type] * _table_operations.gui_flow[type]


func get_fuel_burn(type: int) -> float:
	return rates[type] * _table_operations.fuel_burn[type]


func get_extraction_rate(type: int) -> float:
	return rates[type] * _table_operations.extraction_rate[type]


func get_mass_flow(type: int) -> float:
	return rates[type] * _table_operations.mass_flow[type]


func get_manufacturing_mass_flow_total() -> float:
	var mass_flows: Array = _table_operations.mass_flow
	var sum := 0.0
	for type in _tables.is_manufacturing_operations:
		sum += rates[type] * mass_flows[type]
	return sum


func get_est_revenue(type: int) -> float:
	if !has_financials:
		return NAN
	return est_revenues[type]


func get_est_gross_income(type: int) -> float:
	if !has_financials:
		return NAN
	return est_gross_incomes[type]


func get_est_gross_margin(type: int) -> float:
	if !has_financials:
		return NAN
	if est_revenues[type] == 0.0:
		return NAN
	return est_gross_incomes[type] / est_revenues[type]


func get_n_operations_in_same_group(type: int) -> int:
	var op_group: int = _table_operations.op_group[type]
	var op_group_ops: Array = _op_groups_operations[op_group]
	return op_group_ops.size()


func is_singular(type: int) -> bool:
	var op_group: int = _table_operations.op_group[type]
	var op_group_ops: Array = _op_groups_operations[op_group]
	return op_group_ops.size() == 1


func get_n_operations_in_group(op_group: int) -> int:
	var op_group_ops: Array = _op_groups_operations[op_group]
	return op_group_ops.size()


func get_group_utilization(op_group: int) -> float:
	var sum_capacities := 0.0
	for type in _op_groups_operations[op_group]:
		sum_capacities += capacities[type]
	if sum_capacities == 0.0:
		return 0.0
	var sum_rates := 0.0
	for type in _op_groups_operations[op_group]:
		sum_rates += rates[type]
	return sum_rates / sum_capacities


func get_group_power(op_group: int) -> float:
	var powers: Array = _table_operations.power
	var sum := 0.0
	for type in _op_groups_operations[op_group]:
		sum += rates[type] * powers[type]
	return sum


func get_group_gui_flow(op_group: int) -> float:
	var gui_flows: Array = _table_operations.gui_flow
	var sum := 0.0
	for type in _op_groups_operations[op_group]:
		sum += rates[type] * gui_flows[type]
	return sum


func get_group_est_revenue(op_group: int) -> float:
	if !has_financials:
		return NAN
	var sum := 0.0
	for type in _op_groups_operations[op_group]:
		sum += est_revenues[type]
	return sum


func get_group_est_gross_income(op_group: int) -> float:
	if !has_financials:
		return NAN
	var sum := 0.0
	for type in _op_groups_operations[op_group]:
		sum += est_gross_incomes[type]
	return sum


func get_group_est_gross_margin(op_group: int) -> float:
	if !has_financials:
		return NAN
	var sum_income := 0.0
	var sum_revenue := 0.0
	for type in _op_groups_operations[op_group]:
		sum_income += est_gross_incomes[type]
		sum_revenue += est_revenues[type]
	if sum_revenue == 0.0:
		return NAN
	return sum_income / sum_revenue


# **************************** INTERFACE MODIFY *******************************

func set_op_command(type: int, command: int) -> void:
	assert(command < OpCommands.N_OP_COMMANDS)
	if op_commands[type] == command:
		return
	op_commands[type] = command
	if type < 64:
		_dirty_op_commands_1 |= 1 << type
	else:
		_dirty_op_commands_2 |= 1 << (type - 64)


# ****************************** SERVER MODIFY ********************************


func change_crew(population_type: int, change: float) -> void:
	crews[population_type] += change
	_dirty_crews |= 1 << population_type


func change_capacity(type: int, change: float) -> void:
	capacities[type] += change
	if type < 64:
		_dirty_capacities_1 |= 1 << type
	else:
		_dirty_capacities_2 |= 1 << (type - 64)


func change_rate(type: int, change: float) -> void:
	rates[type] += change
	if type < 64:
		_dirty_rates_1 |= 1 << type
	else:
		_dirty_rates_2 |= 1 << (type - 64)


func change_public_capacity(type: int, change: float) -> void:
	public_capacities[type] += change
	if type < 64:
		_dirty_public_capacities_1 |= 1 << type
	else:
		_dirty_public_capacities_2 |= 1 << (type - 64)


func change_est_revenue(type: int, change: float) -> void:
	est_revenues[type] += change
	if type < 64:
		_dirty_est_revenues_1 |= 1 << type
	else:
		_dirty_est_revenues_2 |= 1 << (type - 64)


func change_est_gross_income(type: int, change: float) -> void:
	est_gross_incomes[type] += change
	if type < 64:
		_dirty_est_gross_incomes_1 |= 1 << type
	else:
		_dirty_est_gross_incomes_2 |= 1 << (type - 64)


func get_dirty_capacities_1() -> int:
	return _dirty_capacities_1


func get_dirty_capacities_2() -> int:
	return _dirty_capacities_2


# ********************************** SYNC *************************************

func get_server_init() -> Array:
	# facility only; reference-safe
	return [
		yq,
		lfq_revenue,
		lfq_gross_output,
		lfq_net_income,
		total_power,
		manufacturing,
		constructions,
		crews.duplicate(),
		capacities.duplicate(),
		rates.duplicate(),
		public_capacities.duplicate(),
		est_revenues.duplicate(),
		est_gross_incomes.duplicate(),
		op_logics.duplicate(),
		op_commands.duplicate(),
	]


func sync_server_init(data: Array) -> void:
	# facility only; keeps array references!
	yq = data[0]
	lfq_revenue = data[1]
	lfq_gross_output = data[2]
	lfq_net_income = data[3]
	total_power = data[4]
	manufacturing = data[5]
	constructions = data[6]
	crews = data[7]
	capacities = data[8]
	rates = data[9]
	public_capacities = data[10]
	est_revenues = data[11]
	est_gross_incomes = data[12]
	op_logics = data[13]
	op_commands = data[14]


func propagate_component_init(data: Array) -> void:
	# non-facilities only
	var svr_yq: int = data[0]
	assert(svr_yq >= yq, "Load order different than process order?")
	yq = svr_yq # TODO: histories
	
	lfq_revenue += data[1]
	lfq_gross_output += data[2]
	lfq_net_income += data[3]
	total_power += data[4]
	manufacturing += data[5]
	constructions += data[6]
	utils.add_to_float_array_with_array(crews, data[7])
	utils.add_to_float_array_with_array(capacities, data[8])
	utils.add_to_float_array_with_array(rates, data[9])
	if !has_financials:
		return
	utils.add_to_float_array_with_array(public_capacities, data[10])
	utils.add_to_float_array_with_array(est_revenues, data[11])
	utils.add_to_float_array_with_array(est_gross_incomes, data[12])


func get_server_changes(data: Array) -> void:
	# facility accumulator only; zero accumulators and dirty flags
	data.append(_dirty_values)
	if _dirty_values & DIRTY_LFQ_REVENUE:
		data.append(lfq_revenue)
		lfq_revenue = 0.0
	if _dirty_values & DIRTY_LFQ_GROSS_OUTPUT:
		data.append(lfq_gross_output)
		lfq_gross_output = 0.0
	if _dirty_values & DIRTY_LFQ_NET_INCOME:
		data.append(lfq_net_income)
		lfq_net_income = 0.0
	if _dirty_values & DIRTY_TOTAL_POWER:
		data.append(total_power)
		total_power = 0.0
	if _dirty_values & DIRTY_MANUFACTURING:
		data.append(manufacturing)
		manufacturing = 0.0
	if _dirty_values & DIRTY_CONSTRUCTIONS:
		data.append(constructions)
		constructions = 0.0
	_dirty_values = 0
	netrefs.append_and_zero_dirty_bshift(data, crews, _dirty_crews)
	netrefs.append_and_zero_dirty(data, capacities, _dirty_capacities_1)
	netrefs.append_and_zero_dirty(data, capacities, _dirty_capacities_2, 64)
	netrefs.append_and_zero_dirty(data, rates, _dirty_rates_1)
	netrefs.append_and_zero_dirty(data, rates, _dirty_rates_2, 64)
	netrefs.append_and_zero_dirty(data, public_capacities, _dirty_public_capacities_1)
	netrefs.append_and_zero_dirty(data, public_capacities, _dirty_public_capacities_2, 64)
	netrefs.append_and_zero_dirty(data, est_revenues, _dirty_est_revenues_1)
	netrefs.append_and_zero_dirty(data, est_revenues, _dirty_est_revenues_2, 64)
	netrefs.append_and_zero_dirty(data, est_gross_incomes, _dirty_est_gross_incomes_1)
	netrefs.append_and_zero_dirty(data, est_gross_incomes, _dirty_est_gross_incomes_2, 64)
	netrefs.append_dirty(data, op_logics, _dirty_op_logics_1) # not accumulator!
	netrefs.append_dirty(data, op_logics, _dirty_op_logics_2, 64)
	_dirty_crews = 0
	_dirty_capacities_1 = 0
	_dirty_capacities_2 = 0
	_dirty_rates_1 = 0
	_dirty_rates_2 = 0
	_dirty_public_capacities_1 = 0
	_dirty_public_capacities_2 = 0
	_dirty_est_revenues_1 = 0
	_dirty_est_revenues_2 = 0
	_dirty_est_gross_incomes_1 = 0
	_dirty_est_gross_incomes_2 = 0
	_dirty_op_logics_1 = 0
	_dirty_op_logics_2 = 0


func sync_server_changes(data: Array, k: int) -> int:
	# any target
	var svr_yq: int = data[0]
	yq = svr_yq # TODO: histories
	
	var flags: int = data[k]
	k += 1
	if flags & DIRTY_LFQ_REVENUE:
		lfq_revenue += data[k]
		k += 1
	if flags & DIRTY_LFQ_GROSS_OUTPUT:
		lfq_gross_output += data[k]
		k += 1
	if flags & DIRTY_LFQ_NET_INCOME:
		lfq_net_income += data[k]
		k += 1
	if flags & DIRTY_TOTAL_POWER:
		total_power += data[k]
		k += 1
	if flags & DIRTY_MANUFACTURING:
		manufacturing += data[k]
		k += 1
	if flags & DIRTY_CONSTRUCTIONS:
		constructions += data[k]
		k += 1

	k = netrefs.add_dirty_bshift(data, crews, k)
	k = netrefs.add_dirty(data, capacities, k)
	k = netrefs.add_dirty(data, capacities, k, 64)
	k = netrefs.add_dirty(data, rates, k)
	k = netrefs.add_dirty(data, rates, k, 64)
	if !has_financials:
		return 0 # never used
	k = netrefs.add_dirty(data, public_capacities, k)
	k = netrefs.add_dirty(data, public_capacities, k, 64)
	k = netrefs.add_dirty(data, est_revenues, k)
	k = netrefs.add_dirty(data, est_revenues, k, 64)
	k = netrefs.add_dirty(data, est_gross_incomes, k)
	k = netrefs.add_dirty(data, est_gross_incomes, k, 64)
	if !_is_facility:
		return 0 # never used
	k = netrefs.set_dirty(data, op_logics, k) # not accumulator!
	k = netrefs.set_dirty(data, op_logics, k, 64)
	return k


func get_interface_dirty() -> Array:
	# TODO: parallel pattern above to get FacilityInterface data
	var data := []
	netrefs.append_dirty(data, op_commands, _dirty_op_commands_1)
	netrefs.append_dirty(data, op_commands, _dirty_op_commands_2, 64)
	_dirty_op_commands_1 = 0
	_dirty_op_commands_2 = 0
	return data


func sync_interface_dirty(data: Array) -> void:
	# TODO: parallel pattern above to set FacilityInterface data
	var k := netrefs.set_dirty(data, op_commands, 0)
	netrefs.set_dirty(data, op_commands, k, 64)



# ******************************** PRIVATE ************************************


