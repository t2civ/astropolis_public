# astro_selection_manager.gd
# This file is part of Astropolis
# https://t2civ.com
# *****************************************************************************
# Copyright 2019-2026 Charlie Whitfield; ALL RIGHTS RESERVED
# Astropolis is a registered trademark of Charlie Whitfield in the US
# *****************************************************************************
class_name AstroSelectionManager
extends IVSelectionManager

## Astropolis subclass of [IVSelectionManager] that adds [Proxy] selections, facilities and
## loci, alongside ivoyager's [code]IVBody[/code] / [code]IVSmallBodiesGroup[/code] selections.
##
## Registers itself as the [code]IVSelectionManager[/code] replacement at
## static init and registers [member MainThreadGlobal.proxies_by_name] as
## an additional selection-name source so any [Proxy] can be selected by
## name.[br][br]
##
## Selecting an [IVBody] with a locus selects what
## [method MainThreadGlobal.get_body_selection_redirect] names instead: a body is selected as its
## locus, or as a facility there. Only a body without a locus is selected itself. The selection
## follows the body's redirect while it changes, as it does while the proxies come up, until
## something else is selected.


# The body selected last, which the selection stands for until something else is selected.
var _selected_body_name: StringName


static func _static_init() -> void:
	replacement_subclass = AstroSelectionManager
	add_selection_dictionary(MainThreadGlobal.proxies_by_name)


func _init() -> void:
	super()
	MainThreadGlobal.proxies_ready.connect(_on_proxies_ready)
	MainThreadGlobal.body_selection_redirect_changed.connect(_on_body_selection_redirect_changed)


## Selects [param object] as [method IVSelectionManager.select] does, selecting an [IVBody] with
## a locus as its locus or a facility there.
func select(object: Object, suppress_camera_move := false) -> void:
	var body := object as IVBody
	_selected_body_name = body.name if body else &""
	super(_get_redirect(object), suppress_camera_move)


## As [method IVSelectionManager.select_by_name], but a proxy's name fails without a warning
## until the proxies are ready. The selection a load restores is made once they are.
func select_by_name(name: StringName, suppress_camera_move := false) -> bool:
	if !MainThreadGlobal.proxies_ready_emitted and !IVBody.bodies.has(name):
		return false
	return super(name, suppress_camera_move)


func _clear_procedural() -> void:
	super()
	_selected_body_name = &""


func _get_redirect(object: Object) -> Object:
	var body := object as IVBody
	if !body:
		return object
	var redirect_name := MainThreadGlobal.get_body_selection_redirect(body.name)
	if !redirect_name:
		return object
	var redirect := MainThreadGlobal.get_proxy_by_name(redirect_name)
	return redirect if redirect else object


# Selects the body the selection stands for again, where that now selects something else.
func _follow_redirect() -> void:
	if !_selected_body_name:
		return
	var body := IVBody.bodies[_selected_body_name]
	if _get_redirect(body) != selection:
		select(body, true)


func _on_proxies_ready() -> void:
	if !selection and _selection_name:
		select_by_name(_selection_name, true)
		return
	_follow_redirect()


func _on_body_selection_redirect_changed(body_name: StringName) -> void:
	if body_name == _selected_body_name:
		_follow_redirect()
