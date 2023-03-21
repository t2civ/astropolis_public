# astro_gui.gd
# This file is part of Astropolis
# Copyright 2019-2023 Charlie Whitfield, all rights reserved
# *****************************************************************************
class_name AstroGUI
extends Control
const SCENE := "res://astropolis_public/gui_panels/astro_gui.tscn"


const PERSIST_MODE := IVEnums.PERSIST_PROPERTIES_ONLY # child GUIs are persisted


func _ready():
	IVGlobal.connect("system_tree_built_or_loaded", self, "_on_system_tree_built_or_loaded")
	IVGlobal.connect("simulator_started", self, "show")
	IVGlobal.connect("about_to_free_procedural_nodes", self, "hide")
	IVGlobal.connect("show_hide_gui_requested", self, "show_hide_gui")
	hide()


func _on_system_tree_built_or_loaded(is_new_game: bool) -> void:
	if !is_new_game:
		return
	var info_panel: InfoPanel = IVFiles.make_object_or_scene(InfoPanel)
	info_panel.set_build_subpanels(true)
	add_child(info_panel)
	info_panel.set_anchors_and_margins_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE)


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_all_gui"):
		show_hide_gui()
	else:
		return # input NOT handled!
	get_tree().set_input_as_handled()


func show_hide_gui(is_toggle := true, is_show := true) -> void:
	if !IVGlobal.state.is_system_built:
		return
	visible = !visible if is_toggle else is_show
