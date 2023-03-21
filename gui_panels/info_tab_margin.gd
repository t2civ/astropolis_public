# info_tab_margin.gd
# This file is part of Astropolis
# Copyright 2019-2023 Charlie Whitfield, all rights reserved
# *****************************************************************************
class_name InfoTabMargin
extends MarginContainer

# Added by code to allow persistence of info subpanels.

const PERSIST_MODE := IVEnums.PERSIST_PROCEDURAL

var info_tab_container: InfoTabContainer

var _is_new := false


func _init(is_new := false) -> void:
	if !is_new:
		return
	_is_new = true
	info_tab_container = InfoTabContainer.new(true)


func _ready() -> void:
	name = "InfoTabMargin"
	mouse_filter = MOUSE_FILTER_IGNORE
#	margin_top = -4 # not working as expected
#	margin_bottom = -4
#	margin_left = -4
#	margin_right = -4
	set("custom_constants/margin_top", 27) # TODO: Settings GUI_SIZE listener
	if _is_new:
		add_child(info_tab_container)

