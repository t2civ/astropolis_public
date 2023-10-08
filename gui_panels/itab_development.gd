# itab_development.gd
# This file is part of Astropolis
# Copyright 2019-2023 Charlie Whitfield, all rights reserved
# *****************************************************************************
class_name ITabDevelopment
extends MarginContainer
const SCENE := "res://astropolis_public/gui_panels/itab_development.tscn"


signal header_changed(new_header)

const BodyFlags: Dictionary = IVEnums.BodyFlags
const BodyFlags2: Dictionary = Enums.BodyFlags2
const PLAYER_CLASS_POLITY := Enums.PlayerClasses.PLAYER_CLASS_POLITY

const PERSIST_MODE := IVEnums.PERSIST_PROCEDURAL
const PERSIST_PROPERTIES := []

var _header_suffix := "  -  " + tr(&"LABEL_DEVELOPMENT")
var _state: Dictionary = IVGlobal.state
var _selection_manager: SelectionManager

@onready var _stats_grid: MarginContainer = $StatsGrid
@onready var _no_dev_label: Label = $NoDevLabel


func _ready() -> void:
	IVGlobal.update_gui_requested.connect(_update_selection)
	visibility_changed.connect(_update_selection)
	@warning_ignore("unsafe_property_access", "unsafe_method_access")
	_stats_grid.has_stats_changed.connect(_update_no_development)
	_selection_manager = IVSelectionManager.get_selection_manager(self)
	_selection_manager.selection_changed.connect(_update_selection)
	@warning_ignore("unsafe_property_access")
	_stats_grid.min_columns = 4
	_update_selection()


func timer_update() -> void:
	@warning_ignore("unsafe_method_access")
	_stats_grid.update()


func _update_no_development(has_stats: bool) -> void:
	_no_dev_label.visible = !has_stats


func _update_selection(_suppress_camera_move := false) -> void:
	if !visible or !_state.is_running:
		return
	var selection_data := _selection_manager.get_info_panel_data()
	if !selection_data:
		return
	var target_name: StringName = selection_data[0]
	var header_text: String = selection_data[1]
	header_text += _header_suffix
	header_changed.emit(header_text)
	
	var selection_name := _selection_manager.get_selection_name()
	
	var body_name: StringName
	var body_flags: int
	var proxy_orbit: StringName
	var proxy_moons_of: StringName
	
	# Below replicates some logic in SelectionManager.get_info_panel_data(); could be cleaned up.
	if selection_name.begins_with("FACILITY_"):
		body_name = MainThreadGlobal.get_facility_body(selection_name)
		body_flags = MainThreadGlobal.get_body_flags(body_name)
		
		if target_name.begins_with("PROXY_"):
			# polity
			var at_body_name := _get_at_body_name(body_flags)
			@warning_ignore("unsafe_method_access")
			_stats_grid.update_targets([target_name], [at_body_name])
			return
		
		# agency or company
		var player_name: StringName = MainThreadGlobal.get_facility_player(selection_name)
		proxy_orbit = StringName("PROXY_ORBIT_" + body_name + "_" + player_name)
		proxy_moons_of = StringName("PROXY_MOONS_OF_" + body_name + "_" + player_name)
	
	else: # body
		assert(IVGlobal.bodies.has(selection_name))
		body_name = selection_name
		body_flags = MainThreadGlobal.get_body_flags(body_name)
		proxy_orbit = StringName("PROXY_ORBIT_" + body_name)
		proxy_moons_of = StringName("PROXY_MOONS_OF_" + body_name)
	
	# at star
	if body_flags & BodyFlags.IS_STAR:
		@warning_ignore("unsafe_method_access")
		_stats_grid.update_targets([&"PROXY_SYSTEM_STAR_SUN"], [&"SYSTEM_SOLAR_SYSTEM"])
		return
	
	var at_body_name := _get_at_body_name(body_flags)
	
	# at spacecraft or small body
	if body_flags & BodyFlags.IS_SPACECRAFT or body_flags & BodyFlags.NO_STABLE_ORBIT:
		@warning_ignore("unsafe_method_access")
		_stats_grid.update_targets([selection_name], [at_body_name])
		return
	
	# at moonless major body
	if not body_flags & BodyFlags2.GUI_HAS_MOONS:
		var targets := [selection_name, proxy_orbit]
		var replacement_names := [at_body_name, &"LABEL_IN_ORBIT"]
		@warning_ignore("unsafe_method_access")
		_stats_grid.update_targets(targets, replacement_names)
		return
	
	# at major body w/ moon(s)
	var at_moon_text := &"LABEL_MOONS"
	if body_name == &"PLANET_EARTH":
		at_moon_text = &"LABEL_LUNAR"
	var targets := [selection_name, proxy_orbit, proxy_moons_of]
	var replacement_names := [at_body_name, &"LABEL_ORBIT", at_moon_text]
	@warning_ignore("unsafe_method_access")
	_stats_grid.update_targets(targets, replacement_names)


func _get_at_body_name(body_flags: int) -> StringName:
	if body_flags & BodyFlags2.IS_STATION:
		return &"LABEL_STATION"
	if body_flags & BodyFlags2.GUI_CLOUDS_SURFACE:
		return &"LABEL_CLOUDS_SURFACE" # Venus
	if body_flags & BodyFlags2.GUI_CLOUDS:
		return &"LABEL_CLOUDS" # gas giants
	return &"LABEL_SURFACE"

