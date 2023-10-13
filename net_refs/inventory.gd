# inventory.gd
# This file is part of Astropolis
# Copyright 2019-2023 Charlie Whitfield, all rights reserved
# *****************************************************************************
class_name Inventory
extends NetRef

# Arrays indexed by resource_type. Facility and (sometimes) Proxy have an
# Inventory. 'prices', 'bids' and 'asks' are common for polity at specific body.

# In trade units or in internal units????

# save/load persistence for server only
const PERSIST_MODE := IVEnums.PERSIST_PROCEDURAL
const PERSIST_PROPERTIES: Array[StringName] = [
	&"run_qtr",
	&"reserves",
	&"markets",
	&"in_transits",
	&"contracteds",
	&"prices",
	&"bids",
	&"asks",
	&"_dirty_reserves_1",
	&"_dirty_reserves_2",
	&"_dirty_internal_markets_1",
	&"_dirty_internal_markets_2",
	&"_dirty_markets_1",
	&"_dirty_markets_2",
	&"_dirty_in_transits_1",
	&"_dirty_in_transits_2",
	&"_dirty_contracteds_1",
	&"_dirty_contracteds_2",
	&"_dirty_prices_1",
	&"_dirty_prices_2",
	&"_dirty_bids_1",
	&"_dirty_bids_2",
	&"_dirty_asks_1",
	&"_dirty_asks_2",
]


# Interface read-only! Data flows server -> interface.
var run_qtr := -1 # last sync, = year * 4 + (quarter - 1)
var reserves: Array[float] # exists here; we may need it (>= 0.0)
var markets: Array[float] # exists here; Trader may commit (>= 0.0)
var in_transits: Array[float] # on the way (>= 0.0), probably under contract
var contracteds: Array[float] # sum of all contracts (+/-), here or elsewhere
var prices: Array[float] # last sale or set by Exchange (NAN if no price)
var bids: Array[float] # NAN if none
var asks: Array[float] # NAN if none

var _dirty_reserves_1 := 0
var _dirty_reserves_2 := 0 # max 128
var _dirty_markets_1 := 0
var _dirty_markets_2 := 0 # max 128
var _dirty_in_transits_1 := 0
var _dirty_in_transits_2 := 0 # max 128
var _dirty_contracteds_1 := 0
var _dirty_contracteds_2 := 0 # max 128
var _dirty_prices_1 := 0
var _dirty_prices_2 := 0 # max 128
var _dirty_bids_1 := 0
var _dirty_bids_2 := 0 # max 128
var _dirty_asks_1 := 0
var _dirty_asks_2 := 0 # max 128



func _init(is_new := false) -> void:
	if !is_new: # game load
		return
	var n_resources: int = IVTableData.table_n_rows.resources
	reserves = ivutils.init_array(n_resources, 0.0, TYPE_FLOAT)
	markets = reserves.duplicate()
	in_transits = reserves.duplicate()
	contracteds = reserves.duplicate()
	prices = ivutils.init_array(n_resources, NAN, TYPE_FLOAT)
	bids = prices.duplicate()
	asks = prices.duplicate()


# ********************************** READ *************************************
# all threadsafe

func get_in_stock(type: int) -> float:
	return reserves[type] + markets[type]


# ****************************** SERVER MODIFY ********************************

func change_reserve(type: int, change: float) -> void:
	reserves[type] += change
	if type < 64:
		_dirty_reserves_1 |= 1 << type
	else:
		_dirty_reserves_2 |= 1 << (type - 64)


func set_price(type: int, value: float) -> void:
	prices[type] = value
	if type < 64:
		_dirty_prices_1 |= 1 << type
	else:
		_dirty_prices_2 |= 1 << (type - 64)
	

# ********************************** SYNC *************************************

func get_server_init() -> Array:
	# facility only; reference-safe
	return [
		run_qtr,
		reserves.duplicate(),
		markets.duplicate(),
		in_transits.duplicate(),
		contracteds.duplicate(),
		prices.duplicate(),
		bids.duplicate(),
		asks.duplicate(),
	]


func sync_server_init(data: Array) -> void:
	# facility only; keeps array references!
	run_qtr = data[0]
	reserves = data[1]
	markets = data[2]
	in_transits = data[3]
	contracteds = data[4]
	prices = data[5]
	bids = data[6]
	asks = data[7]


func propagate_component_init(data: Array) -> void:
	# non-facilities only
	var svr_qtr: int = data[0]
	assert(svr_qtr >= run_qtr, "Load order different than process order?")
	run_qtr = svr_qtr # TODO: histories
	var data_array: Array[float] = data[1]
	utils.add_to_float_array_with_array(reserves, data_array)
	data_array = data[2]
	utils.add_to_float_array_with_array(markets, data_array)
	data_array = data[3]
	utils.add_to_float_array_with_array(in_transits, data_array)
	data_array = data[4]
	utils.add_to_float_array_with_array(contracteds, data_array)
	data_array = data[5]
	utils.fill_array(prices, data_array)
	data_array = data[6]
	utils.fill_array(bids, data_array)
	data_array = data[7]
	utils.fill_array(asks, data_array)


func take_server_delta(data: Array) -> void:
	# facility accumulator only; zero values and dirty flags
	# optimized for sparse dirty flags (not right-biased)
	_append_and_zero_dirty(data, reserves, _dirty_reserves_1)
	_append_and_zero_dirty(data, reserves, _dirty_reserves_2, 64)
	_append_and_zero_dirty(data, markets, _dirty_markets_1)
	_append_and_zero_dirty(data, markets, _dirty_markets_2, 64)
	_append_and_zero_dirty(data, in_transits, _dirty_in_transits_1)
	_append_and_zero_dirty(data, in_transits, _dirty_in_transits_2, 64)
	_append_and_zero_dirty(data, contracteds, _dirty_contracteds_1)
	_append_and_zero_dirty(data, contracteds, _dirty_contracteds_2, 64)
	_append_dirty(data, prices, _dirty_prices_1)     # not accumulator!
	_append_dirty(data, prices, _dirty_prices_2, 64) # not accumulator!
	_append_dirty(data, bids, _dirty_bids_1)     # not accumulator!
	_append_dirty(data, bids, _dirty_bids_2, 64) # not accumulator!
	_append_dirty(data, asks, _dirty_asks_1)     # not accumulator!
	_append_dirty(data, asks, _dirty_asks_2, 64) # not accumulator!
	_dirty_reserves_1 = 0
	_dirty_reserves_2 = 0
	_dirty_markets_1 = 0
	_dirty_markets_2 = 0
	_dirty_in_transits_1 = 0
	_dirty_in_transits_2 = 0
	_dirty_contracteds_1 = 0
	_dirty_contracteds_2 = 0
	_dirty_prices_1 = 0
	_dirty_prices_2 = 0
	_dirty_bids_1 = 0
	_dirty_bids_2 = 0
	_dirty_asks_1 = 0
	_dirty_asks_2 = 0


func add_server_delta(data: Array) -> void:
	# any target
	var svr_qtr: int = data[0]
	run_qtr = svr_qtr # TODO: histories
	
	_add_dirty(data, reserves)
	_add_dirty(data, reserves, 64)
	_add_dirty(data, markets)
	_add_dirty(data, markets, 64)
	_add_dirty(data, in_transits)
	_add_dirty(data, in_transits, 64)
	_add_dirty(data, contracteds)
	_add_dirty(data, contracteds, 64)
	_set_dirty(data, prices)     # not accumulator!
	_set_dirty(data, prices, 64) # not accumulator!
	_set_dirty(data, bids)     # not accumulator!
	_set_dirty(data, bids, 64) # not accumulator!
	_set_dirty(data, asks)     # not accumulator!
	_set_dirty(data, asks, 64) # not accumulator!


