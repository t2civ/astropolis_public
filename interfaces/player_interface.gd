# player_interface.gd
# This file is part of Astropolis
# Copyright 2019-2023 Charlie Whitfield, all rights reserved
# *****************************************************************************
class_name PlayerInterface
extends Interface

# DO NOT MODIFY THIS FILE! To modify AI, see comments in '_base_ai.gd' files.
#
# Warning! This object lives and dies on the AI Server thread! Some access from
# other threads is possible (e.g., from main thread GUI), but see:
# https://docs.godotengine.org/en/latest/tutorials/performance/thread_safe_apis.html
#
# Player required components:
#   Operations - on init
#   Financials - on init
#   Population - on init
#   Biome      - on init
#   Metaverse  - on init

const OBJECT_TYPE = Enums.Objects.PLAYER


# public read-only
var player_id := -1
var player_class := -1 # PlayerClasses enum
var part_of_name: String # non-polity players only!
var polity_name: String
var homeworld := ""


func _init() -> void:
	operations = Operations.new(true, true)
	financials = Financials.new(true)
	population = Population.new(true)
	biome = Biome.new(true)
	metaverse = Metaverse.new(true)


# *****************************************************************************
# sync

func sync_server_init(data: Array) -> void:
	player_id = data[2]
	name = data[3]
	gui_name = data[4]
	player_class = data[5]
	part_of_name = data[6]
	polity_name = data[7]
	homeworld = data[8]


func sync_server_dirty(data: Array) -> void:
	var dirty: int = data[0]
	var k := 1
	if dirty & DIRTY_BASE:
		gui_name = data[k]
		player_class = data[k + 1]
		part_of_name = data[k + 2]
		polity_name = data[k + 3]
		homeworld = data[k + 4]


func propagate_component_init(data: Array, indexes: Array) -> void:
	operations.propagate_component_init(data[indexes[0]])
	# skip inventory
	financials.propagate_component_init(data[indexes[2]])
	if data[indexes[3]]:
		population.propagate_component_init(data[indexes[3]])
	if data[indexes[4]]:
		biome.propagate_component_init(data[indexes[4]])
	if data[indexes[5]]:
		metaverse.propagate_component_init(data[indexes[5]])
	assert(data[indexes[6]] >= yq)
	yq = data[indexes[6]]


func propagate_component_changes(data: Array, indexes: Array) -> void:
	var dirty: int = data[1]
	if dirty & DIRTY_OPERATIONS:
		operations.sync_server_changes(data, indexes[0])
	# skip inventory
	if dirty & DIRTY_FINANCIALS:
		financials.sync_server_changes(data, indexes[2])
	if dirty & DIRTY_POPULATION:
		population.sync_server_changes(data, indexes[3])
	if dirty & DIRTY_BIOME:
		biome.sync_server_changes(data, indexes[4])
	if dirty & DIRTY_METAVERSE:
		metaverse.sync_server_changes(data, indexes[5])
	
	assert(data[0] >= yq)
	if data[0] > yq:
		if yq == -1:
			yq = data[0]
		else:
			yq = data[0]
			process_ai_new_quarter() # after component histories have updated

