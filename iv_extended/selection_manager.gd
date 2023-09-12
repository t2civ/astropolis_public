# selection_manager.gd
# This file is part of Astropolis
# Copyright 2019-2023 Charlie Whitfield, all rights reserved
# *****************************************************************************
class_name SelectionManager
extends IVSelectionManager

# Everything here works on the main thread! NOT THREADSAFE!
#
# We use I, Voyager's selection system almost as is. This extended class adds
# methods for making Facility and Proxy selections (static for camera access).
#
# For facility selection: 
#   name              = Facility.name
#   gui_name          = Facility.gui_name (something like 'Moon / NASA')
#   up_selection_name = Body.name
#
# As above for proxy (body/polity) selection.
#
# TODO: Depreciate unused 'is_body' and 'spatial' in base I, Voyager class?

const PLAYER_CLASS_POLITY := Enums.PlayerClasses.PLAYER_CLASS_POLITY

var all_suffix := " / " + tr(&"LABEL_ALL")


static func get_or_make_selection(selection_name: String) -> IVSelection:
	var selection_: IVSelection = IVGlobal.selections.get(selection_name)
	if selection_:
		return selection_
	if IVGlobal.bodies.has(selection_name): # its a Body in the system
		return make_selection_for_body(selection_name)
	elif selection_name.begins_with("FACILITY_"):
		return make_selection_for_facility(selection_name)
	assert(false, "Missing body or unsupported selection type: " + selection_name)
	return null


static func make_selection_for_facility(facility_name: String) -> IVSelection:
	var gui_name: String = MainThreadGlobal.get_gui_name(facility_name)
	var body_name: String = MainThreadGlobal.get_facility_body(facility_name)
	var body_selection := get_or_make_selection(body_name)
	var selection_ := _duplicate_body_selection(body_selection)
	selection_.name = facility_name
	selection_.gui_name = gui_name
	selection_.up_selection_name = body_name
	IVGlobal.selections[facility_name] = selection_
	return selection_


static func _duplicate_body_selection(body_selection: IVSelection) -> IVSelection:
	var selection_ := IVSelection.new()
	for property in body_selection.PERSIST_PROPERTIES:
		selection_.set(property, body_selection.get(property))
	selection_.texture_2d = body_selection.texture_2d
	selection_.texture_slice_2d = body_selection.texture_slice_2d
	return selection_


func select_body(body: IVBody, _suppress_camera_move := false) -> void:
	# We override base method so navigation GUI sends us to a facility, usually.
	# Use select_by_name() if you really need the body.
	select_prefer_facility(body.name)


func select_prefer_facility(selection_name: String) -> void:
	if selection_name.begins_with("FACILITY_"):
		var selection_ := get_or_make_selection(selection_name)
		select(selection_)
		return
	
	# New prioritized selection when body selected:
	#  1. If exactly one facility at body, go to that (common for small bodies).
	#  2. If local player has facility at body, go to that.
	#  3. Otherwise, go to body.
	var facilities: Array = MainThreadGlobal.get_facilities(selection_name)
	if facilities.size() == 1:
		var selection_ := get_or_make_selection(facilities[0])
		select(selection_)
		return
	var local_player_name: String = MainThreadGlobal.local_player_name
	for facility_name in facilities:
		var loop_player: String = MainThreadGlobal.get_facility_player(facility_name)
		if loop_player == local_player_name:
			var selection_ := get_or_make_selection(facility_name)
			select(selection_)
			return
	var selection_ := get_or_make_selection(selection_name)
	select(selection_)


func get_body_gui_name() -> String:
	var body_name := get_body_name()
	if !body_name:
		return ""
	return MainThreadGlobal.get_gui_name(body_name)


func get_info_panel_data() -> Array:
	# [target_name, header_text, is_developed] or empty array
	# target is proxy in some cases; header_text is already translated
	var selection_name := get_name()
	if !selection_name:
		return []
	if selection_name.begins_with("FACILITY_"):
		var player_name: String = MainThreadGlobal.get_facility_player(selection_name)
		var player_class := MainThreadGlobal.get_player_class(player_name)
		if player_class == PLAYER_CLASS_POLITY:
			# polity proxy (combines polity player, agency & companies)
			var body_name := get_body_name()
			var polity_name: String = MainThreadGlobal.get_facility_polity(selection_name)
			var proxy_name := "PROXY_" + body_name + "_" + polity_name
			var header := get_gui_name()
			return [proxy_name, header, true]
		# agency or company facility is the target
		return [selection_name, get_gui_name(), true]
	# must be body selection
	var body_name := get_body_name()
	assert(body_name == selection_name)
	var body_flags := MainThreadGlobal.get_body_flags(body_name)
	if body_flags & BodyFlags.IS_STAR:
		# solar system
		var system_name := "SYSTEM_" + body_name
		var proxy_name := "PROXY_" + system_name
		return [proxy_name, tr(system_name) + all_suffix, true]
	# body is the target
	var header := get_gui_name()
	var is_developed := false
	if MainThreadGlobal.get_n_facilities(body_name) > 0: # has facilities
		header += all_suffix
		is_developed = true
	return [body_name, header, is_developed]


