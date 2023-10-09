# itab_information.gd
# This file is part of Astropolis
# Copyright 2019-2023 Charlie Whitfield, all rights reserved
# *****************************************************************************
class_name ITabInformation
extends MarginContainer
const SCENE := "res://astropolis_public/gui_panels/itab_information.tscn"


signal header_changed(new_header)

const PERSIST_MODE := IVEnums.PERSIST_PROCEDURAL
const PERSIST_PROPERTIES := []

var _selection_manager: SelectionManager


func _ready() -> void:
	visibility_changed.connect(_update_selection)
	_selection_manager = IVSelectionManager.get_selection_manager(self)
	_selection_manager.selection_changed.connect(_update_selection)
	_update_selection()


func timer_update() -> void:
	pass


func _update_selection(_suppress_camera_move := false) -> void:
	if !visible:
		return
	if !_selection_manager.has_selection():
		return
	var selection_name := _selection_manager.get_body_name()
	var header := (tr(selection_name) + "  -  " + tr(&"LABEL_INFORMATION"))
	header_changed.emit(header)

