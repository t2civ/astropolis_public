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
#   Operations - on init or never
#   Inventory  - on init or never
#   Financials - on init or never
#   Population - on init or never
#   Biome      - on init or never
#   Metaverse  - on init or never

const OBJECT_TYPE = Enums.Objects.PROXY

static var proxy_interfaces: Array[ProxyInterface] = [] # indexed by proxy_id

# read-only!
var proxy_id := -1


func _init() -> void:
	super()


static func get_or_make_proxy(proxy_name: StringName, proxy_gui_name := "",
		has_operations := true, has_inventory := false, has_financials := false,
		has_population := true, has_biome := true, has_metaverse := true) -> ProxyInterface:
	# Proxy names should be prefixed 'PROXY_' and must be unique.
	var proxy_interface: ProxyInterface = interfaces_by_name.get(proxy_name)
	if proxy_interface:
		return proxy_interface
	if !proxy_gui_name:
		proxy_gui_name = AIGlobal.tr(proxy_name)
	AIGlobal.proxy_requested.emit(proxy_name, proxy_gui_name,
			has_operations, has_inventory, has_financials,
			has_population, has_biome, has_metaverse)
	proxy_interface = interfaces_by_name.get(proxy_name)
	assert(proxy_interface)
	return proxy_interface



# *****************************************************************************
# sync - DON'T MODIFY!

func sync_server_init(data: Array) -> void:
	proxy_id = data[2]
	name = data[3]
	gui_name = data[4]
	var has_operations: bool = data[5]
	var has_inventory: bool = data[6]
	var has_financials: bool = data[7]
	var has_population: bool = data[8]
	var has_biome: bool = data[9]
	var has_metaverse: bool = data[10]
	if has_operations:
		operations = Operations.new(true, has_financials)
	if has_inventory:
		inventory = Inventory.new(true)
	if has_financials:
		financials = Financials.new(true)
	if has_population:
		population = Population.new(true)
	if has_biome:
		biome = Biome.new(true)
	if has_metaverse:
		metaverse = Metaverse.new(true)


func propagate_component_init(data: Array, indexes: Array) -> void:
	# only components we already have
	if operations and data[indexes[0]]:
		operations.propagate_component_init(data[indexes[0]])
	if inventory and data[indexes[1]]:
		inventory.propagate_component_init(data[indexes[1]])
	if financials and data[indexes[2]]:
		financials.propagate_component_init(data[indexes[2]])
	if population and data[indexes[3]]:
		population.propagate_component_init(data[indexes[3]])
	if biome and data[indexes[4]]:
		biome.propagate_component_init(data[indexes[4]])
	if metaverse and data[indexes[5]]:
		metaverse.propagate_component_init(data[indexes[5]])
	assert(data[indexes[6]] >= yq)
	yq = data[indexes[6]]


func propagate_component_changes(data: Array, indexes: Array) -> void:
	# only components we already have
	var dirty: int = data[1]
	if operations and dirty & DIRTY_OPERATIONS:
		operations.sync_server_delta(data, indexes[0])
	if inventory and dirty & DIRTY_INVENTORY:
		inventory.sync_server_delta(data, indexes[1])
	if financials and dirty & DIRTY_FINANCIALS:
		financials.sync_server_delta(data, indexes[2])
	if population and dirty & DIRTY_POPULATION:
		population.sync_server_delta(data, indexes[3])
	if biome and dirty & DIRTY_BIOME:
		biome.sync_server_delta(data, indexes[4])
	if metaverse and dirty & DIRTY_METAVERSE:
		metaverse.sync_server_delta(data, indexes[5])
	assert(data[0] >= yq)
	if data[0] > yq:
		if yq == -1:
			yq = data[0]
		else:
			yq = data[0]
			process_ai_new_quarter() # after component histories have updated


