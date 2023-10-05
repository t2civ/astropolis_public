# main_thread_global.gd
# This file is part of Astropolis
# Copyright 2019-2023 Charlie Whitfield, all rights reserved
# *****************************************************************************
extends Node

# Singleton "MainThreadGlobal".
#
# This global provides safe data access on the main thread, mainly for GUI.
# Note that Interfaces gotten here are not threadsafe! For Interface access on
# the main thread, use only Interface methods marked 'threadsafe'.

signal interface_added(interface)
signal ai_thread_called(object, method, data)


const utils := preload("res://astropolis_public/static/utils.gd")

var local_player_name := "PLAYER_NASA"
var home_facility_name := "FACILITY_PLANET_EARTH_PLAYER_NASA"

# Access on main thread only!

var interfaces_by_name := {} # PLANET_EARTH, PLAYER_NASA, etc.
var facilities_by_holder := {} # [facility names] indexed by body & player names


# *****************************************************************************

func _ready() -> void:
	IVGlobal.about_to_free_procedural_nodes.connect(_clear)


func _clear() -> void:
	interfaces_by_name.clear()
	facilities_by_holder.clear()


# *****************************************************************************
# Access on main thread only!

func call_on_ai_thread(object: Object, method: String, data := []) -> void:
	# object method must have 'data: Array' as its single required arg
	ai_thread_called.emit(object, method, data)


func get_interface_by_name(interface_name: String) -> Interface:
	# Returns null if doesn't exist.
	# This method is safe on main thread, but the Interface is not!
	return interfaces_by_name.get(interface_name)


func get_gui_name(interface_name: String) -> String:
	# return is translated
	var interface: Interface = interfaces_by_name.get(interface_name)
	if !interface:
		return ""
	return interface.gui_name


func get_body_flags(body_name: String) -> int:
	var interface: BodyInterface = interfaces_by_name.get(body_name)
	if !interface:
		return 0
	return interface.body_flags


func get_facility_body(facility_name: String) -> String:
	var interface: FacilityInterface = interfaces_by_name.get(facility_name)
	if !interface:
		return ""
	return interface.body_name


func get_facility_player(facility_name: String) -> String:
	var interface: FacilityInterface = interfaces_by_name.get(facility_name)
	if !interface:
		return ""
	return interface.player_name


func get_facility_polity(facility_name: String) -> String:
	var interface: FacilityInterface = interfaces_by_name.get(facility_name)
	if !interface:
		return ""
	return interface.polity_name


func get_facilities(body_or_player_name: String) -> Array:
	if !facilities_by_holder.has(body_or_player_name):
		return []
	return facilities_by_holder[body_or_player_name]


func get_n_facilities(body_or_player_name: String) -> int:
	if !facilities_by_holder.has(body_or_player_name):
		return 0
	var facilities: Array = facilities_by_holder[body_or_player_name]
	return facilities.size()


func get_player_facility_at_body(player_name: String, body_name: String) -> String:
	var body_facilities := get_facilities(body_name)
	for facility_name in body_facilities:
		var interface: FacilityInterface = interfaces_by_name.get(facility_name)
		if interface.player_name == player_name:
			return interface.name
	return ""


func get_player_class(player_name: String) -> int:
	var interface: PlayerInterface = interfaces_by_name.get(player_name)
	if interface:
		return interface.player_class
	return -1

