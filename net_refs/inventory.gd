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
const PERSIST_PROPERTIES := [
	&"yq",
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
var yq := -1 # last sync, = year * 4 + (quarter - 1)
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
		yq,
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
	yq = data[0]
	reserves = data[1]
	markets = data[2]
	in_transits = data[3]
	contracteds = data[4]
	prices = data[5]
	bids = data[6]
	asks = data[7]


func propagate_component_init(data: Array) -> void:
	# non-facilities only
	var svr_yq: int = data[0]
	assert(svr_yq >= yq, "Load order different than process order?")
	yq = svr_yq # TODO: histories
	utils.add_to_float_array_with_array(reserves, data[1])
	utils.add_to_float_array_with_array(markets, data[2])
	utils.add_to_float_array_with_array(in_transits, data[3])
	utils.add_to_float_array_with_array(contracteds, data[4])
	utils.fill_array(prices, data[5])
	utils.fill_array(bids, data[6])
	utils.fill_array(asks, data[7])


func get_server_changes(data: Array) -> void:
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


func sync_server_changes(data: Array, k: int) -> int:
	# any target
	var svr_yq: int = data[0]
	yq = svr_yq # TODO: histories

	k = _add_dirty(data, reserves, k)
	k = _add_dirty(data, reserves, k, 64)
	k = _add_dirty(data, markets, k)
	k = _add_dirty(data, markets, k, 64)
	k = _add_dirty(data, in_transits, k)
	k = _add_dirty(data, in_transits, k, 64)
	k = _add_dirty(data, contracteds, k)
	k = _add_dirty(data, contracteds, k, 64)
	k = _set_dirty(data, prices, k)     # not accumulator!
	k = _set_dirty(data, prices, k, 64) # not accumulator!
	k = _set_dirty(data, bids, k)     # not accumulator!
	k = _set_dirty(data, bids, k, 64) # not accumulator!
	k = _set_dirty(data, asks, k)     # not accumulator!
	k = _set_dirty(data, asks, k, 64) # not accumulator!
	
	return k

