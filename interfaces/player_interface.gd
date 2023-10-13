# player_interface.gd
# This file is part of Astropolis
# Copyright 2019-2023 Charlie Whitfield, all rights reserved
# *****************************************************************************
class_name PlayerInterface
extends Interface

# DO NOT MODIFY THIS FILE! To modify AI, see comments in '_base_ai.gd' files.
#
# Warning! This object lives and dies on the AI thread! Containers and many
# methods are not threadsafe. Accessing non-container properties is safe.
#
# Player required components:
#   Operations - on init
#   Financials - on init
#   Population - on init
#   Biome      - on init
#   Metaverse  - on init
#
# Players are never removed, but they are effectively dead if is_facilities == false.

static var player_interfaces: Array[PlayerInterface] = [] # indexed by player_id

# public read-only
var player_id := -1
var player_class := -1 # PlayerClasses enum
var part_of: PlayerInterface # non-polity players only!
var polity_name: StringName
var homeworld := ""
var is_facilities := true # 'alive' player test

var facilities: Array[Interface] = [] # resizable container - not threadsafe!


func _init() -> void:
	super()
	entity_type = ENTITY_PLAYER
	operations = Operations.new(true, true)
	financials = Financials.new(true)
	population = Population.new(true)
	biome = Biome.new(true)
	metaverse = Metaverse.new(true)


func _clear_circular_references() -> void:
	# down hierarchy only
	facilities.clear()


# *****************************************************************************
# interface API


func get_player_name() -> StringName:
	return name


func get_player_class() -> int:
	return player_class


func get_polity_name() -> StringName:
	return polity_name


func has_facilities() -> bool:
	return is_facilities


func get_facilities() -> Array[Interface]:
	# AI thread only!
	return facilities


# *****************************************************************************
# sync

func sync_server_init(data: Array) -> void:
	player_id = data[2]
	name = data[3]
	gui_name = data[4]
	player_class = data[5]
	var part_of_name: StringName = data[6]
	part_of = interfaces_by_name[part_of_name] if part_of_name else null
	polity_name = data[7]
	homeworld = data[8]


func sync_server_dirty(data: Array) -> void:
	var dirty: int = data[0]
	var k := 1
	if dirty & DIRTY_BASE:
		gui_name = data[k]
		player_class = data[k + 1]
		var part_of_name: StringName = data[k + 2]
		part_of = interfaces_by_name[part_of_name] if part_of_name else null
		polity_name = data[k + 3]
		homeworld = data[k + 4]


func propagate_component_init(data: Array, indexes: Array[int]) -> void:
	var component_data: Array = data[indexes[0]]
	operations.propagate_component_init(component_data)
	# skip inventory
	component_data = data[indexes[2]]
	financials.propagate_component_init(component_data)
	component_data = data[indexes[3]]
	if component_data:
		population.propagate_component_init(component_data)
	component_data = data[indexes[4]]
	if component_data:
		biome.propagate_component_init(component_data)
	component_data = data[indexes[5]]
	if component_data:
		metaverse.propagate_component_init(component_data)
	assert(data[indexes[6]] >= run_qtr)
	run_qtr = data[indexes[6]]


func propagate_component_changes(data: Array, indexes: Array[int]) -> void:
	var dirty: int = data[1]
	if dirty & DIRTY_OPERATIONS:
		operations.add_server_delta(data, indexes[0])
	# skip inventory
	if dirty & DIRTY_FINANCIALS:
		financials.add_server_delta(data, indexes[2])
	if dirty & DIRTY_POPULATION:
		population.add_server_delta(data, indexes[3])
	if dirty & DIRTY_BIOME:
		biome.add_server_delta(data, indexes[4])
	if dirty & DIRTY_METAVERSE:
		metaverse.add_server_delta(data, indexes[5])
	
	assert(data[0] >= run_qtr)
	if data[0] > run_qtr:
		if run_qtr == -1:
			run_qtr = data[0]
		else:
			run_qtr = data[0]
			process_ai_new_quarter() # after component histories have updated


func add_facility(facility: Interface) -> void:
	assert(!facilities.has(facility))
	facilities.append(facility)
	is_facilities = true


func remove_facility(facility: Interface) -> void:
	facilities.erase(facility)
	is_facilities = !facilities.is_empty()

