# proxy_interface.gd
# This file is part of Astropolis
# Copyright 2019-2023 Charlie Whitfield, all rights reserved
# *****************************************************************************
class_name ProxyInterface
extends Interface

# DO NOT MODIFY THIS FILE! To modify AI, see comments in '_base_ai.gd' files.
#
# Warning! This object lives and dies on the AI thread! Containers and many
# methods are not threadsafe. Accessing non-container properties is safe.
#
# Proxies represent collections of facilites that may be useful for GUI data
# display or possibly AI. Init and and data sync originate from
# FacilityInterface (unlike other Interfaces, there is no corresponding server
# object).
#
# See FacilityInterface._add_proxies() for existing proxies. Override this
# method to add or modify.
#
# Proxy optional components:
#   Operations - on server init or never
#   Inventory  - on server init or never
#   Financials - on server init or never
#   Population - on server init or never
#   Biome      - on server init or never
#   Metaverse  - on server init or never


static var proxy_interfaces: Array[ProxyInterface] = [] # indexed by proxy_id


var operations: Operations
var inventory: Inventory
var financials: Financials
var population: Population
var biome: Biome
var metaverse: Metaverse



# read-only!
var proxy_id := -1


func _init() -> void:
	super()
	entity_type = ENTITY_PROXY


# *****************************************************************************
# interface API

func get_total_population() -> float:
	var total_population := 0.0
	if population:
		total_population = population.get_number_total()
	if operations:
		total_population += operations.get_crew_total()
	return total_population


func get_total_population_by_type(population_type: int) -> float:
	var total_population := 0.0
	if population:
		total_population = population.get_number(population_type)
	if operations:
		total_population += operations.get_crew(population_type)
	return total_population


# *****************************************************************************
# sync - DON'T MODIFY!

func set_server_init(data: Array) -> void:
	proxy_id = data[2]
	name = data[3]
	gui_name = data[4]
	var operations_data: Array = data[5]
	var inventory_data: Array = data[6]
	var financials_data: Array = data[7]
	var population_data: Array = data[8]
	var biome_data: Array = data[9]
	var metaverse_data: Array = data[10]
	if operations_data:
		operations = Operations.new(true, !financials_data.is_empty())
		operations.set_server_init(operations_data)
	if inventory_data:
		inventory = Inventory.new(true)
		inventory.set_server_init(inventory_data)
	if financials_data:
		financials = Financials.new(true)
		financials.set_server_init(financials_data)
	if population_data:
		population = Population.new(true)
		population.set_server_init(population_data)
	if biome_data:
		biome = Biome.new(true)
		biome.set_server_init(biome_data)
	if metaverse_data:
		metaverse = Metaverse.new(true)
		metaverse.set_server_init(metaverse_data)


func propagate_server_delta(data: Array) -> void:
	# only components we already have
	var int_data: Array[int] = data[0]
	var dirty: int = int_data[1]
	if operations and dirty & DIRTY_OPERATIONS:
		operations.add_server_delta(data)
	if inventory and dirty & DIRTY_INVENTORY:
		inventory.add_server_delta(data)
	if financials and dirty & DIRTY_FINANCIALS:
		financials.add_server_delta(data)
	if population and dirty & DIRTY_POPULATION:
		population.add_server_delta(data)
	if biome and dirty & DIRTY_BIOME:
		biome.add_server_delta(data)
	if metaverse and dirty & DIRTY_METAVERSE:
		metaverse.add_server_delta(data)
	assert(int_data[0] >= run_qtr)
	if int_data[0] > run_qtr:
		if run_qtr == -1:
			run_qtr = int_data[0]
		else:
			run_qtr = int_data[0]
			process_ai_new_quarter() # after component histories have updated

