# info_panel.gd
# This file is part of Astropolis
# Copyright 2019-2023 Charlie Whitfield, all rights reserved
# *****************************************************************************
class_name InfoPanel
extends PanelContainer
const SCENE := "res://astropolis_public/gui_panels/info_panel.tscn"

# InfoTabMargin, InfoTabContainer, and the subpanels are added procedurally so
# they can be saved and restored on game load.
# 'selection_manager' points to AstroGUI.selection_manager if this is the
# original (unpinned) InfoPanel. If this is a cloned (pinned) InfoPanel, then
# it has its own SelectionManager instance.

signal clone_and_pin_requested(info_panel)


const PERSIST_MODE := IVEnums.PERSIST_PROCEDURAL
const PERSIST_PROPERTIES := [
	&"anchor_top",
	&"anchor_left",
	&"anchor_right",
	&"anchor_bottom",
	&"selection_manager",
	&"is_pinned",
	&"header_text",
]

# persisted
var selection_manager: SelectionManager
var is_pinned := false
var header_text := ""


var _build_subpanels := false
var _selection: IVSelection

@onready var _header_label: Label = $HeaderLabel


func _ready() -> void:
	IVGlobal.about_to_free_procedural_nodes.connect(_clear)
	($TRButtons/Pin as Button).pressed.connect(_clone_and_pin)
	if is_pinned:
		($TRButtons/Close as Button).pressed.connect(_close)
		_init_after_system()
	else:
		IVGlobal.system_tree_ready.connect(_init_after_system, CONNECT_ONE_SHOT)
		($TRButtons/Close as Button).hide()
	if header_text:
		_set_header(header_text)


func _clear() -> void:
#	parent_selection_manager = null
	selection_manager = null
	_selection = null


func set_build_subpanels(build_subpanels: bool) -> void:
	_build_subpanels = build_subpanels


func _init_after_system(_dummy := false) -> void:
	if !selection_manager:
		# This is the original (non-cloned) InfoPanel and a new game!
		@warning_ignore("unsafe_property_access")
		selection_manager = get_parent().get_parent().selection_manager
	if _build_subpanels:
		var info_tab_margin := InfoTabMargin.new(true)
		add_child(info_tab_margin)
	await get_tree().process_frame
	var itc: InfoTabContainer = get_node("InfoTabMargin/InfoTabContainer")
	var subpanels := itc.subpanels
	for subpanel in subpanels:
		@warning_ignore("unsafe_method_access")
		subpanel.header_changed.connect(_set_header)


func _set_header(header_text_: String) -> void:
	header_text = header_text_
	_header_label.text = header_text_


func _clone_and_pin() -> void:
	clone_and_pin_requested.emit(self)


func _close() -> void:
	queue_free()
