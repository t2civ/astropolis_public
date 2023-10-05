# interface.gd
# This file is part of Astropolis
# Copyright 2019-2023 Charlie Whitfield, all rights reserved
# *****************************************************************************
class_name Interface

# DO NOT MODIFY THIS FILE! To modify AI, see comments in '_base_ai.gd' files.
#
# Warning! This object lives and dies on the AI Server thread! Some access from
# other threads is possible (e.g., from main thread GUI), but see:
# https://docs.godotengine.org/en/latest/tutorials/performance/thread_safe_apis.html


signal interface_changed(object_type, class_id, data) # on ai thread only!

# don't emit these directly; use API below
signal persist_data_changed(network_id, data)


enum { # _dirty flags
	DIRTY_YQ = 1,
	DIRTY_BASE = 1 << 1,
	DIRTY_OPERATIONS = 1 << 2,
	DIRTY_INVENTORY = 1 << 3,
	DIRTY_FINANCIALS = 1 << 4,
	DIRTY_POPULATION = 1 << 5,
	DIRTY_BIOME = 1 << 6,
	DIRTY_METAVERSE = 1 << 7,
	DIRTY_COMPOSITIONS = 1 << 8,
}

enum { # sync_svr_type
	SYNC_SVR_OPERATIONS,
	SYNC_SVR_INVENTORY,
	SYNC_SVR_FINANCIALS,
	SYNC_SVR_POPULATION,
	SYNC_SVR_BIOME,
	SYNC_SVR_METAVERSE,
}

const INTERVAL := 7.0 * IVUnits.DAY

var interface_id := -1
var name := "" # unique & immutable
var gui_name := "" # mutable for display ("" for player means hide from GUI)
var yq := -1 # year * 4 + (quarter - 1); never set for BodyInterface w/out a facility
var last_interval := -INF
var next_interval := -INF

# Append member names for save/load persistence; nested containers ok; NO OBJECTS!
# Must be set at _init()!
var persist := [
	"yq",
	"last_interval",
	"next_interval",
]

# components
var operations: Operations
var inventory: Inventory
var financials: Financials
var population: Population
var biome: Biome
var metaverse: Metaverse

var use_this_ai := false # read-only

# localized globals
var times: Array = IVGlobal.times # [time (s, J2000), engine_time (s), solar_day (d)] (floats)
var date: Array = IVGlobal.date # Gregorian [year, month, day] (ints)
var clock: Array = IVGlobal.clock # UT [hour, minute, second] (ints)
var tables: Dictionary = IVTableData.tables
var table_n_rows: Dictionary = IVTableData.table_n_rows

# private
var _dirty := 0
@warning_ignore("unused_private_class_variable")
var _is_local_player := false # gives GUI access
@warning_ignore("unused_private_class_variable")
var _is_server_ai := false
@warning_ignore("unused_private_class_variable")
var _is_local_use_ai := false # local player sets/unsets


# *****************************************************************************
# Common API

func get_population_and_crew(population_type: int) -> float:
	var population_number := population.get_number(population_type) if population else 0.0
	var crew := operations.get_crew(population_type) if operations else 0.0
	return population_number + crew


func get_population_and_crew_total() -> float:
	var population_number := population.get_number_total() if population else 0.0
	var crew := operations.get_crew_total() if operations else 0.0
	return population_number + crew


# *****************************************************************************
# Main thread public

#func player_use_ai(use_ai: bool) -> void:
#	if !_is_local_player:
#		return
#	_is_local_use_ai = use_ai
#	_reset_ai()


# *****************************************************************************
# AI thread


# subclass overrides

func process_ai(time: float) -> void:
	# Called every one to several frames (unless excessive AI processing). You
	# probably shouldn't override this. Consider process_ai_interval() instead.
	if time > next_interval:
		if next_interval == -INF: # init
			last_interval = time
			next_interval = time + randf_range(0.0, INTERVAL) # stagger AI processing
			process_ai_init()
		else:
			var delta := time - last_interval
			last_interval = time
			while next_interval < time:
				next_interval += INTERVAL
			process_ai_interval(delta)
	if _dirty:
		_sync_ai_changes()


func process_ai_init() -> void:
	# Called once before first process_ai_interval().
	pass


func process_ai_interval(_delta: float) -> void:
	# Called once per INTERVAL (unless excessive AI processing). Most component
	# changes happen every INTERVAL time, so this is a good place for most AI
	# processing.
	pass


func process_ai_new_quarter() -> void:
	# Called after component histories have updated for the new quarter.
	# Never called for BodyInterface w/out a facility.
	pass


# *****************************************************************************
# sync

func sync_server_init(_data: Array) -> void:
	pass


func sync_server_dirty(_data: Array) -> void:
	pass


func _sync_ai_changes() -> void:
	_dirty = 0



# *****************************************************************************
# Internal main thread

#func set_player(is_local_player: bool, is_server_ai: bool) -> void:
#	_is_local_player = is_local_player
#	_is_server_ai = is_server_ai
#	_reset_ai()
#
#
#func _reset_ai() -> void:
#	use_this_ai = _is_server_ai or (_is_local_player and (_is_local_use_ai or AIGlobal.is_autoplay))
