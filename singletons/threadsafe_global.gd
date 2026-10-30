# threadsafe_global.gd
# This file is part of Astropolis
# https://t2civ.com
# *****************************************************************************
# Copyright 2019-2026 Charlie Whitfield; ALL RIGHTS RESERVED
# Astropolis is a registered trademark of Charlie Whitfield in the US
# *****************************************************************************
extends Node

## Singleton [ThreadsafeGlobal] holds data accessible from any thread.

## Multipliers to convert trade unit -> internal sim unit, indexed by
## resource_type. Thread-safe.
var resource_trade_unit_multipliers: PackedFloat64Array

# game start options: set while threads are stopped, before a game starts or loads, and kept in
# its saves (see set_start_options); thread-safe to read once it runs
## Name of this machine's own player, the one its human chose and the home of its GUI: by default
## the first playable player that starts the game. Under [member sandbox_access_all_players] its
## human plays every playable player, and this one is still its own. Which players a human plays
## is [member PlayerProxy.human].
var local_player_name := &""
## True in a sandbox game whose human players found facilities for free. Nothing founds a facility
## yet.
var sandbox_free_new_facilities := false
## True in a sandbox game whose human players' treasuries are never short: what one lacks it is
## granted, booked as a grant, never borrowed or drawn from its residents.
var sandbox_unlimited_money := false
## True in a sandbox game whose human plays every playable player.
var sandbox_access_all_players := false

var _default_local_player_name := &""


func _ready() -> void:
	IVGlobal.data_tables_postprocessed.connect(_on_data_tables_postprocessed, CONNECT_ONE_SHOT)
	IVStateManager.simulator_exited.connect(reset_start_options)


func _on_data_tables_postprocessed() -> void:
	var n_resources := IVTableData.table_n_rows[&"resources"]
	var trade_units: Array[StringName] = IVTableData.db_tables[&"resources"][&"trade_unit"]
	resource_trade_unit_multipliers.resize(n_resources)
	for resource_type in n_resources:
		var unit := trade_units[resource_type]
		resource_trade_unit_multipliers[resource_type] = IVQConvert.to_internal(1.0, unit)
	var playable_names := get_playable_start_players()
	if !playable_names.is_empty():
		_default_local_player_name = playable_names[0]
	local_player_name = _default_local_player_name


## Returns the names of the players a human may play at the start of a new game: those
## [code]players.tsv[/code] starts the game with and marks playable, in table order.
func get_playable_start_players() -> Array[StringName]:
	var names: Array[StringName] = IVTableData.db_tables[&"players"][&"name"]
	var playables: Array[bool] = IVTableData.db_tables[&"players"][&"playable"]
	var playable_names: Array[StringName] = []
	for player_type in IVTableData.get_db_true_rows(&"players", &"start"):
		if playables[player_type]:
			playable_names.append(names[player_type])
	return playable_names


## Returns true in a sandbox game: one whose human players have free new facilities or unlimited
## money.
func is_sandbox() -> bool:
	return sandbox_free_new_facilities or sandbox_unlimited_money


## Returns the game's start options, for its saves and for [method set_start_options].
func get_start_options() -> Dictionary:
	return {
		&"local_player_name": local_player_name,
		&"sandbox_free_new_facilities": sandbox_free_new_facilities,
		&"sandbox_unlimited_money": sandbox_unlimited_money,
		&"sandbox_access_all_players": sandbox_access_all_players,
	}


## Sets the game's start options from [param options], as [method get_start_options] gives them.
## Call only while threads are stopped: before [method IVStateManager.start] for a new game, or as
## a game loads. A game started without it has the defaults: the first playable player, and no
## sandbox.
func set_start_options(options: Dictionary) -> void:
	local_player_name = options[&"local_player_name"]
	sandbox_free_new_facilities = options[&"sandbox_free_new_facilities"]
	sandbox_unlimited_money = options[&"sandbox_unlimited_money"]
	sandbox_access_all_players = options[&"sandbox_access_all_players"]


## Restores the default start options. Runs on exit to the splash screen, so a game started next
## without [method set_start_options] doesn't inherit the last one's.
func reset_start_options() -> void:
	local_player_name = _default_local_player_name
	sandbox_free_new_facilities = false
	sandbox_unlimited_money = false
	sandbox_access_all_players = false
