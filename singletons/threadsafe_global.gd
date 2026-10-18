# threadsafe_global.gd
# This file is part of Astropolis
# https://t2civ.com
# *****************************************************************************
# Copyright 2019-2026 Charlie Whitfield; ALL RIGHTS RESERVED
# Astropolis is a registered trademark of Charlie Whitfield in the US
# *****************************************************************************
extends Node

## Singleton [ThreadsafeGlobal] holds data accessible from any thread.

## An order book's integer price counts this many to the dollar: cents, the quote currency's
## smallest unit (TRADE_MODEL.md, "Orders: bids and asks").
const UNIT_PRICES_PER_USD := 100.0

## Multipliers to convert trade unit -> internal sim unit, indexed by
## resource_type. Thread-safe.
var resource_trade_unit_multipliers: PackedFloat64Array
## Multipliers to convert a price in USD per sim unit -> an order book's integer price per trade
## unit ([constant UNIT_PRICES_PER_USD]), indexed by resource_type. Thread-safe.
var resource_unit_price_multipliers: PackedFloat64Array

# game
var local_player_name := &"PLAYER_NASA"  ## Name of the local player at game start.
var home_facility_name := &"FACILITY_PLANET_EARTH_PLAYER_NASA"  ## Name of the local player's home facility.



func _ready() -> void:
	IVGlobal.data_tables_postprocessed.connect(_on_data_tables_postprocessed, CONNECT_ONE_SHOT)


func _on_data_tables_postprocessed() -> void:
	var n_resources := IVTableData.table_n_rows[&"resources"]
	var trade_units: Array[StringName] = IVTableData.db_tables[&"resources"][&"trade_unit"]
	resource_trade_unit_multipliers.resize(n_resources)
	resource_unit_price_multipliers.resize(n_resources)
	for resource_type in n_resources:
		var unit := trade_units[resource_type]
		resource_trade_unit_multipliers[resource_type] = IVQConvert.to_internal(1.0, unit)
		resource_unit_price_multipliers[resource_type] = (
				resource_trade_unit_multipliers[resource_type] * UNIT_PRICES_PER_USD)
