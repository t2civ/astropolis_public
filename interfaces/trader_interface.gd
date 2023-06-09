# trader_interface.gd
# This file is part of Astropolis
# Copyright 2019-2023 Charlie Whitfield, all rights reserved
# *****************************************************************************
class_name TraderInterface
extends Interface

# DO NOT MODIFY THIS CLASS! See comments in "Base AI" classes to override AI.

const OBJECT_TYPE := Enums.Objects.TRADER



# sync from server
var trader_id := -1
var facility_id := -1
var player_id := -1
var body_id := -1
var is_spaceport := false

# sync to server
var market_requests: Array # bool; markets we want, indexed by resource_id

# don't sync (server doesn't care)
var bids := IVUtils.init_array(tables.n_resources, 0.0)
var asks := IVUtils.init_array(tables.n_resources, 0.0)


# shared from other interfaces
var facility_interface: FacilityInterface

# localized indexing
var n_resources: int = tables.n_resources



func process_ai(_time: float) -> void:
	pass


# *****************************************************************************
# Trader API

func set_market_request(resource_type: int, open: bool) -> void:
	if market_requests[resource_type] == open:
		return
	_dirty |= DIRTY_BASE
	market_requests[resource_type] = open


func place_order(_order: Array) -> void:
	pass


func attempt_cancel_order(_order_id: int) -> void:
	pass


func attempt_replace_order(_order_id: int, _new_order: Array) -> void:
	pass


# *****************************************************************************
# sync from server

func sync_server_init(data: Array) -> void:
	trader_id = data[0]
	name = data[1]
	facility_id = data[2]
	player_id = data[3]
	body_id = data[4]
	is_spaceport = data[5]
	market_requests = data[6]
	# Trader is associated with a Facility and shares its Inventory
	facility_interface = AIGlobal.facility_interfaces[facility_id]
	assert(facility_interface)
	inventory = facility_interface.inventory


func sync_infrequent(data: Array) -> void:
	player_id = data[0]
	body_id = data[1]
	is_spaceport = data[2]


# *****************************************************************************
# sync to server

func sync_server() -> void: # AI should call at end of process()
	if !_dirty:
		return
	# Update to new system

	_dirty = 0


