# ai_global.gd
# This file is part of Astropolis
# Copyright 2019-2023 Charlie Whitfield, all rights reserved
# *****************************************************************************
extends Node

# Singleton "AIGlobal".
#
# Indexes Interface instances and provides API for use on the AI thread.
# Containers and methods in this singleton are NOT THREADSAFE!
#
# Be aware that Godot SceneTree - including GUI! - runs on the main thread.
# See MainThreadGlobal for related API usable on the main thread.
#
# To call main thread from AI thread, use call_deferred().

# emit on ai thread only!
signal interface_added(interface)
signal proxy_requested(proxy_name, gui_name, has_operations, has_inventory, has_financials,
	has_population, has_biome, has_metaverse)
signal interface_changed(object_type, class_id, data)

signal player_owner_changed(fixme) # FIXME - added for NetworkLobby; not hooked up anywhere else


var verbose := false
var verbose2 := false
var is_autoplay := false

var is_multiplayer_server := false
var is_multiplayer_client := false

var local_player_name := &"PLAYER_NASA"

# *****************************************************************************
# Access on AI thread only! NOT THREADSAFE!

# Interfaces
var interfaces: Array[Interface] = [] # indexed by interface_id
var interfaces_by_name := {} # PLANET_EARTH, PLAYER_NASA, PROXY_OFFWORLD, etc.
var facility_interfaces: Array[Interface] = [] # indexed by facility_id
var body_interfaces: Array[Interface] = [] # indexed by body_id
var player_interfaces: Array[Interface] = [] # indexed by player_id
var proxy_interfaces: Array[Interface] = [] # indexed by proxy_id
var trader_interfaces: Array[Interface] = [] # indexed by trader_id


# *****************************************************************************
# Main thread init and destroy

func _ready() -> void:
	IVGlobal.about_to_free_procedural_nodes.connect(_clear_procedural)


func _clear_procedural() -> void:
	interfaces.clear()
	interfaces_by_name.clear()
	facility_interfaces.clear()
	body_interfaces.clear()
	player_interfaces.clear()
	proxy_interfaces.clear()
	trader_interfaces.clear()


# *****************************************************************************
# Access on AI thread only! NOT THREADSAFE!

func get_interface_by_name(interface_name: StringName) -> Interface:
	# Returns null if doesn't exist.
	return interfaces_by_name.get(interface_name)


func get_gui_name(interface_name: StringName) -> String:
	# return is translated
	var interface: Interface = interfaces_by_name.get(interface_name)
	if !interface:
		return ""
	return interface.gui_name


func get_body_name(interface_name: StringName) -> StringName:
	# Return is useful (not &"") for facility and body.
	var interface: Interface = interfaces_by_name.get(interface_name)
	if !interface:
		return &""
	return interface.get_body_name()


func get_body_flags(interface_name: StringName) -> int:
	# Return is useful (not 0) for facility and body.
	var interface: Interface = interfaces_by_name.get(interface_name)
	if !interface:
		return 0
	return interface.get_body_flags()


func get_player_name(interface_name: StringName) -> StringName:
	# Return is useful (not -1) for facility and player.
	var interface: Interface = interfaces_by_name.get(interface_name)
	if !interface:
		return &""
	return interface.get_player_name()


func get_player_class(interface_name: StringName) -> int:
	# Return is useful (not -1) for facility and player.
	var interface: Interface = interfaces_by_name.get(interface_name)
	if !interface:
		return -1
	return interface.get_player_class()


func get_polity_name(interface_name: StringName) -> StringName:
	# Return is useful (not &"") for facility and player.
	var interface: Interface = interfaces_by_name.get(interface_name)
	if !interface:
		return &""
	return interface.get_polity_name()


func has_facilities(interface_name: StringName) -> bool:
	# Return is useful (possibly true) for body and player.
	var interface: Interface = interfaces_by_name.get(interface_name)
	if !interface:
		return false
	return interface.has_facilities()


func get_facilities(interface_name: StringName) -> Array[Interface]:
	# Return is useful (possibly not empty) for body and player.
	var interface: Interface = interfaces_by_name.get(interface_name)
	if !interface:
		return []
	return interface.get_facilities()


func get_or_make_proxy(proxy_name: StringName, gui_name := "",
		has_operations := true, has_inventory := false, has_financials := false,
		has_population := true, has_biome := true, has_metaverse := true) -> Interface:
	# Proxy names should be prefixed 'PROXY_' and must be unique.
	# Access immediately after this method in containers above.
	var proxy_interface: Interface = interfaces_by_name.get(proxy_name)
	if proxy_interface:
		return proxy_interface
	if !gui_name:
		gui_name = tr(proxy_name)
	proxy_requested.emit(proxy_name, gui_name,
			has_operations, has_inventory, has_financials,
			has_population, has_biome, has_metaverse)
	proxy_interface = interfaces_by_name.get(proxy_name)
	assert(proxy_interface)
	return proxy_interface

