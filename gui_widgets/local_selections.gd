# local_selections.gd
# This file is part of Astropolis
# Copyright 2019-2023 Charlie Whitfield, all rights reserved
# *****************************************************************************
extends ScrollContainer

# Contains local selections for info panel navigation:
#    Spacefaring Polities (-> polity at body proxy)
#    Space Agencies (-> local facility)
#    Space Companies (-> local facility)
#    Offworld Facilities (-> in orbit or satellite bodies w/ facility)
#    System Facilities (star selection only; -> in orbit or satellite bodies w/ facility)

const PLAYER_CLASS_POLITY := Enums.PlayerClasses.PLAYER_CLASS_POLITY
const PLAYER_CLASS_AGENCY := Enums.PlayerClasses.PLAYER_CLASS_AGENCY
const PLAYER_CLASS_COMPANY := Enums.PlayerClasses.PLAYER_CLASS_COMPANY
const IS_STAR := IVEnums.BodyFlags.IS_STAR

var section_names := [
	# FIXME
	tr(&"LABEL_SPACEFARING_POLITIES"),
	tr(&"LABEL_SPACE_AGENCIES"),
	tr(&"LABEL_SPACE_COMPANIES"),
	tr(&"LABEL_OFFWORLD_FACILITIES"),
	tr(&"LABEL_SYSTEM_FACILITIES"),
]

var open_prefix := "\u2304   "
var closed_prefix := ">   "
var sub_prefix := "       "
var is_open_sections := [false, false, false, true, true]

var _state: Dictionary = IVGlobal.state
var _interfaces_by_name: Dictionary = MainThreadGlobal.interfaces_by_name
var _facilities_by_holder: Dictionary = MainThreadGlobal.facilities_by_holder

var _pressed_lookup := {} # interfaces or section int, indexed by label.text
var _selection_manager: SelectionManager

var _polities := []
var _agencies := []
var _companies := []
var _offworld := []
var _system := []

var _section_arrays := [_polities, _agencies, _companies, _offworld, _system]
var _n_sections := section_names.size()


@onready var _vbox: VBoxContainer = $VBox


func _ready() -> void:
	IVGlobal.simulator_started.connect(_update)
	IVGlobal.about_to_free_procedural_nodes.connect(_clear)
	_update()


func _clear() -> void:
	_selection_manager = null
	_polities.clear()
	_agencies.clear()
	_companies.clear()
	_offworld.clear()
	_system.clear()
	_pressed_lookup.clear()
	for child in _vbox.get_children():
		child.queue_free()


func _init_after_system_built() -> void:
	_selection_manager = IVSelectionManager.get_selection_manager(self)
	_selection_manager.selection_changed.connect(_update)
	var section := 0
	while section < _n_sections:
		var section_text: String = section_names[section]
		_pressed_lookup[open_prefix + section_text] = section
		_pressed_lookup[closed_prefix + section_text] = section
		section += 1


func _update(_dummy = 0) -> void:
	if !_state.is_system_built:
		return
	if !_selection_manager:
		_init_after_system_built()
	var selection := _selection_manager.get_selection()
	if selection:
		_set_selections(selection)


func _set_selections(selection: IVSelection) -> void:
	_polities.clear()
	_agencies.clear()
	_companies.clear()
	_offworld.clear()
	_system.clear()
	var body_name := selection.get_body_name()
	var body: IVBody = IVGlobal.bodies[body_name]
	if body.flags & IS_STAR:
		_set_selections_recursive(body, _system, true)
	else:
		_set_selections_recursive(body, _offworld, true)
	_update_labels()


func _set_selections_recursive(body: IVBody, bodies_array: Array, root_call := false) -> void:
	
	if _facilities_by_holder.has(body.name):
		
		# add all players w/ facility here
		var body_name: StringName = body.name
		var facilities: Array = _facilities_by_holder[body_name]
		var n_facilities := facilities.size()
		var i := 0
		while i < n_facilities:
			var facility_name: StringName = facilities[i]
			var facility_interface: FacilityInterface = _interfaces_by_name[facility_name]
			var player_name := facility_interface.player.name
			var player_interface: PlayerInterface = _interfaces_by_name[player_name]
			var gui_name := player_interface.gui_name
			if !gui_name: # hidden player
				i += 1
				continue
			var label_text := sub_prefix + gui_name
			var player_class_array: Array
			match player_interface.player_class:
				PLAYER_CLASS_POLITY:
					player_class_array = _polities
				PLAYER_CLASS_AGENCY:
					player_class_array = _agencies
				PLAYER_CLASS_COMPANY:
					player_class_array = _companies
				_:
					assert(false, "Unknown player_class")
			
			if !player_class_array.has(label_text):
				player_class_array.append(label_text)
				_pressed_lookup[label_text] = facility_name
			elif player_interface.homeworld == body_name: # replace existing facility
				_pressed_lookup[label_text] = facility_name
			i += 1
		
		if !root_call:
			# add body
			var body_interface: BodyInterface = _interfaces_by_name[body_name]
			var label_text := sub_prefix + body_interface.gui_name
			bodies_array.append(label_text)
			_pressed_lookup[label_text] = body_name
	
	for satellite in body.satellites:
		_set_selections_recursive(satellite, bodies_array)
	
	# TODO: Sort results in some sensible way


func _update_labels() -> void:
	var n_labels := _vbox.get_child_count()
	var child_index := 0
	var section := 0
	while section < _n_sections:
		var section_data: Array = _section_arrays[section]
		var n_items := section_data.size()
		while n_labels <= n_items + child_index: # enough if open
			var label := Label.new()
			label.mouse_filter = MOUSE_FILTER_PASS
			label.gui_input.connect(_on_gui_input.bind(label))
			_vbox.add_child(label)
			n_labels += 1
		var is_open: bool = is_open_sections[section]
		var label: Label = _vbox.get_child(child_index)
		child_index += 1
		if n_items == 0:
			label.hide()
		elif !is_open:
			label.text = closed_prefix + section_names[section]
			label.show()
		else:
			label.text = open_prefix + section_names[section]
			label.show()
			for label_text in section_data:
				label = _vbox.get_child(child_index)
				label.show()
				label.text = label_text
				child_index += 1
		section += 1
	while child_index < n_labels:
		var label: Label = _vbox.get_child(child_index)
		label.hide()
		child_index += 1


func _on_gui_input(event: InputEvent, label: Label) -> void:
	var event_mouse_button := event as InputEventMouseButton
	if !event_mouse_button:
		return
	if !event_mouse_button.pressed:
		return
	if event_mouse_button.button_index != MOUSE_BUTTON_LEFT:
		return
	# 'lookup' will either be an integer (section index) or string (selection target)
	var lookup = _pressed_lookup.get(label.text)
	if typeof(lookup) == TYPE_INT: # toggle section
		is_open_sections[lookup] = !is_open_sections[lookup]
		_update_labels()
	else:
		_selection_manager.select_prefer_facility(lookup)

