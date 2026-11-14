# itab_build.gd
# This file is part of Astropolis
# https://t2civ.com
# *****************************************************************************
# Copyright 2019-2026 Charlie Whitfield; ALL RIGHTS RESERVED
# Astropolis is a registered trademark of Charlie Whitfield in the US
# *****************************************************************************
class_name ITabBuild
extends MarginContainer

## "Build" tab subpanel for [InfoPanel]. Shows what the selected facility builds.
##
## The Projects subtab lists the facility's buildouts, its capital projects
## ([method FacilityProxy.get_operations_buildouts]), in three groups, each a line summed over its
## buildouts and a row each when unfolded: its expansions, unfolded at first; its replacement, its
## standing buildouts, folded at first; and its teardowns, unfolded at first. A row shows its units
## built, or taken down, of those planned, or a replacement's schedule a year; its pace, the draw
## that bound it in the pace's tooltip; when it would be done at that pace and how far it has
## slipped past its schedule; what it has spent; and what its units would return a year at
## capital's prices, or that it waits, its units earning nothing past their keep, or is paused. A
## row's tooltip names who ordered it and the operation its units go to. Read-only: ordering,
## pausing and cancelling from a row wait for the player's orders, and the Modules subtab, each
## module's plant, is a placeholder (PRODUCTION_MODEL.md, "Buildouts", the Build tab).

const SCENE := "res://public/ui/itab_build.tscn"  ## Scene file for instancing.

const SUBGROUP_INDENT := 25
const N_COLUMNS := 6

const NO_VALUE := "—" ## Applies, but has no value now.

# The Modules subtab's placeholder text.
const MODULES_PLACEHOLDER := """WIP

Each module's units in service, what wears of them a year,
its operations' rooms past what is in flight, its build time
and whether the planner builds it, where you will order buildouts."""

const PERSIST_MODE := IVGlobal.PERSIST_PROCEDURAL  ## Save/load mode (procedural node).
## Member names persisted by save/load.
const PERSIST_PROPERTIES: Array[StringName] = [
	&"current_tab",
	&"_on_ready_tab",
]

# persisted
var current_tab := 0
var _on_ready_tab := 0

# not persisted
var base_column_width := 55.0  ## Min width of each value column, before the GUI size multiplier.

# table indexing, cached so proxy-thread reads stay safe
var _db_tables := IVTableData.db_tables
var _module_names: Array[StringName] = _db_tables[&"modules"][&"name"]
var _population_names: Array[StringName] = _db_tables[&"populations"][&"name"]
var _operation_names: Array[StringName] = _db_tables[&"operations"][&"name"]
var _operation_sublabels: Array[StringName] = _db_tables[&"operations"][&"sublabel"]
var _resource_names: Array[StringName] = _db_tables[&"resources"][&"name"]
var _orderer_texts: Array[String] = ["the planner", "its AI", "its player"]

var _selection_manager: AstroSelectionManager
var _suppress_tab_listener := true

# built in code (see _build_ui)
var _tab_container: TabContainer
var _no_projects_label: Label
var _header: HBoxContainer
var _header_labels: Array[Label] = []
var _empty_label: Label
var _expansions_group: ProjectGroup
var _replacement_group: ProjectGroup
var _teardowns_group: ProjectGroup

@warning_ignore("unsafe_property_access")
@onready var _memory: Dictionary = get_parent().memory # group open states


func _ready() -> void:
	IVStateManager.about_to_free_procedural_nodes.connect(_clear_procedural)
	visibility_changed.connect(_update_tab)
	_selection_manager = IVSelectionManager.get_selection_manager(self)
	_selection_manager.selection_changed.connect(_update_tab)
	_build_ui()
	_tab_container.tab_changed.connect(_select_tab)
	var gui_size: int = IVSettingsManager.get_setting(&"gui_size")
	_resize(gui_size)
	IVSettingsManager.changed.connect(_settings_listener)
	_tab_container.set_current_tab(_on_ready_tab)
	_suppress_tab_listener = false
	_update_tab()


func _clear_procedural() -> void:
	if _selection_manager:
		_selection_manager.selection_changed.disconnect(_update_tab)
		_selection_manager = null
	visibility_changed.disconnect(_update_tab)
	_tab_container.tab_changed.disconnect(_select_tab)
	IVSettingsManager.changed.disconnect(_settings_listener)


## Refreshes the build tab. Wired to [InfoTabContainer]'s shared 1 s timer.
func timer_update() -> void:
	_update_tab()


func _build_ui() -> void:
	_tab_container = TabContainer.new()
	_tab_container.size_flags_horizontal = SIZE_EXPAND_FILL
	_tab_container.size_flags_vertical = SIZE_EXPAND_FILL
	add_child(_tab_container)

	_no_projects_label = Label.new()
	_no_projects_label.text = "Select a facility to see what it builds."
	_no_projects_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_no_projects_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_no_projects_label.hide()
	add_child(_no_projects_label)

	var projects_tab := VBoxContainer.new()
	projects_tab.name = "TAB_PROJECTS"  # node name auto-translates as tab title (gui.csv)
	_tab_container.add_child(projects_tab)
	_header = HBoxContainer.new()
	var header_spacer := Control.new()
	header_spacer.size_flags_horizontal = SIZE_EXPAND_FILL
	_header.add_child(header_spacer)
	for text: String in ["Built", "Pace\n(%)", "Done in\n(y)", "Slip\n(y)", "Spent\n($M)",
			"Return\n(%/y)"]:
		var label := Label.new()
		label.text = text
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_header.add_child(label)
		_header_labels.append(label)
	projects_tab.add_child(_header)
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = SIZE_EXPAND_FILL
	scroll.size_flags_vertical = SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	projects_tab.add_child(scroll)
	var groups := VBoxContainer.new()
	groups.size_flags_horizontal = SIZE_EXPAND_FILL
	scroll.add_child(groups)
	_expansions_group = ProjectGroup.new(_memory, &"build_expansions", false, base_column_width)
	groups.add_child(_expansions_group)
	_replacement_group = ProjectGroup.new(_memory, &"build_replacement", true, base_column_width)
	groups.add_child(_replacement_group)
	_teardowns_group = ProjectGroup.new(_memory, &"build_teardowns", false, base_column_width)
	groups.add_child(_teardowns_group)
	_empty_label = Label.new()
	_empty_label.text = "No buildouts."
	_empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty_label.hide()
	projects_tab.add_child(_empty_label)

	var modules_label := Label.new()
	modules_label.name = "TAB_BUILD_MODULES"
	modules_label.text = MODULES_PLACEHOLDER
	modules_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	modules_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_tab_container.add_child(modules_label)


func _select_tab(tab: int) -> void:
	if !_suppress_tab_listener:
		_on_ready_tab = tab
	current_tab = tab
	_update_tab()


func _update_tab(_dummy := false) -> void:
	if !visible or !IVStateManager.is_threads_allowed() or !_selection_manager:
		return
	var target_name := _selection_manager.get_name()
	if current_tab == 0 and MainThreadGlobal.has_development(target_name):
		MainThreadGlobal.call_proxy_thread(_get_proxy_data.bind(target_name))
	elif current_tab == 0:
		_update_no_projects()


func _resize(gui_size: int) -> void:
	const SCROLL_CORRECTION := 7.0
	var column_width := base_column_width * IVCoreSettings.gui_size_multipliers[gui_size]
	for i in _header_labels.size():
		var width := column_width if i < _header_labels.size() - 1 else column_width + SCROLL_CORRECTION
		_header_labels[i].custom_minimum_size.x = width


func _settings_listener(setting: StringName, value: Variant) -> void:
	if setting == &"gui_size":
		var gui_size: int = value
		_resize(gui_size)


# ******************************* PROXY THREAD ********************************

# Gathers the selected facility's buildouts for display: each group's line and rows, each as
# ProjectRow.set_row reads them.
func _get_proxy_data(target_name: StringName) -> void:
	const BUILDOUT_EXPANSION := FacilityProxy.BuildoutKinds.BUILDOUT_EXPANSION
	const BUILDOUT_REPLACEMENT := FacilityProxy.BuildoutKinds.BUILDOUT_REPLACEMENT
	const GROUP_NAMES: Array[String] = ["Expansions", "Replacement", "Teardowns"]
	var proxy := Proxy.get_proxy_by_name(target_name)
	if !(proxy is FacilityProxy):
		_update_no_projects.call_deferred()
		return
	var facility_proxy: FacilityProxy = proxy
	var now := facility_proxy.interval_time
	var groups := [[], [], []] # expansions, replacements, teardowns
	var spents := PackedFloat64Array([0.0, 0.0, 0.0])
	var paceds := PackedFloat64Array([0.0, 0.0, 0.0])
	var costs := PackedFloat64Array([0.0, 0.0, 0.0])
	for buildout in facility_proxy.get_operations_buildouts():
		var kind: int = buildout[&"kind"]
		var group := 0 if kind == BUILDOUT_EXPANSION else (1 if kind == BUILDOUT_REPLACEMENT else 2)
		var rows: Array = groups[group]
		rows.append(_get_row(buildout, now))
		var spent: float = buildout[&"spent"]
		var rate: float = buildout[&"rate"]
		var unit_cost: float = buildout[&"unit_cost"]
		var pace: float = buildout[&"pace"]
		spents[group] += spent
		if rate > 0.0 and unit_cost > 0.0:
			costs[group] += rate * unit_cost
			paceds[group] += rate * unit_cost * pace
	var lines := []
	for group in 3:
		var rows: Array = groups[group]
		lines.append([
			GROUP_NAMES[group], "", "%d" % rows.size(),
			paceds[group] / costs[group] if costs[group] > 0.0 else NAN, &"", NAN, NAN,
			spents[group] / IVUnits.unit_multipliers[&"$M"], NAN, "",
		])
	_update_display.call_deferred(lines, groups)


# One buildout's row: its name, its tooltip, what it built, its pace and what bound it, when it
# would be done and how far it slipped, what it spent, what it returns and its state.
func _get_row(buildout: Dictionary, now: float) -> Array:
	const BUILDOUT_REPLACEMENT := FacilityProxy.BuildoutKinds.BUILDOUT_REPLACEMENT
	const BUILDOUT_TEARDOWN := FacilityProxy.BuildoutKinds.BUILDOUT_TEARDOWN
	var kind: int = buildout[&"kind"]
	var module_type: int = buildout[&"module"]
	var op_type: int = buildout[&"operation"]
	var population_type: int = buildout[&"population"]
	var orderer: int = buildout[&"orderer"]
	var binding: int = buildout[&"binding"]
	var units: float = buildout[&"units"]
	var built: float = buildout[&"built"]
	var left: float = buildout[&"left"]
	var rate: float = buildout[&"rate"]
	var start: float = buildout[&"start"]
	var pace: float = buildout[&"pace"]
	var spent: float = buildout[&"spent"]
	var return_rate: float = buildout[&"return"]
	var is_paused: bool = buildout[&"paused"]
	var tooltip := "Ordered by " + _orderer_texts[orderer]
	if op_type != -1:
		var sublabel := _operation_sublabels[op_type]
		tooltip += ", for " + String(sublabel if sublabel else _operation_names[op_type])
	var built_text := ""
	var done_in := NAN
	var slip := NAN
	if kind != BUILDOUT_REPLACEMENT:
		built_text = "%s/%s" % [IVQFormat.metric_number(built), IVQFormat.metric_number(units)]
		var paced := rate * pace
		done_in = left / paced if paced > 0.0 else INF
		if rate > 0.0:
			slip = (now + done_in) - (start + units / rate)
		done_in /= IVUnits.YEAR
		slip /= IVUnits.YEAR
	else:
		built_text = "%s/y" % IVQFormat.metric_number(rate * IVUnits.YEAR)
	var state := ""
	if is_paused:
		state = "paused"
	elif kind != BUILDOUT_TEARDOWN and !(return_rate > 0.0):
		state = "waits"
	# A commissioning's units are a made population type's individuals.
	return [
		_module_names[module_type] if module_type != -1 else _population_names[population_type],
		tooltip, built_text, pace,
		_resource_names[binding] if binding != -1 and pace < 1.0 else &"",
		done_in, slip, spent / IVUnits.unit_multipliers[&"$M"], return_rate, state,
	]


# ******************************** MAIN THREAD ********************************

func _update_no_projects() -> void:
	_tab_container.hide()
	_no_projects_label.show()


func _update_display(lines: Array, groups: Array) -> void:
	_no_projects_label.hide()
	_tab_container.show()
	var expansions: Array = groups[0]
	var replacements: Array = groups[1]
	var teardowns: Array = groups[2]
	var expansions_line: Array = lines[0]
	var replacement_line: Array = lines[1]
	var teardowns_line: Array = lines[2]
	_expansions_group.set_lines(expansions_line, expansions)
	_expansions_group.visible = !expansions.is_empty()
	_replacement_group.set_lines(replacement_line, replacements)
	_replacement_group.visible = !replacements.is_empty()
	_teardowns_group.set_lines(teardowns_line, teardowns)
	_teardowns_group.visible = !teardowns.is_empty()
	_empty_label.visible = (expansions.is_empty() and replacements.is_empty()
			and teardowns.is_empty())
	_header.visible = !_empty_label.visible



## A group of buildouts, its line summed over them and a row each when unfolded.
class ProjectGroup extends FoldableContainer:

	var _vbox := VBoxContainer.new()
	var _line: ProjectRow
	var _memory: Dictionary
	var _memory_key: StringName
	var _base_column_width: float


	func _init(memory: Dictionary, memory_key: StringName, is_folded_at_first: bool,
			base_column_width: float) -> void:
		_memory = memory
		_memory_key = memory_key
		_base_column_width = base_column_width
		_line = ProjectRow.new(false, base_column_width)
		size_flags_horizontal = SIZE_FILL
		add_child(_vbox)
		add_title_bar_control(_line)
		folded = _memory.get(memory_key, is_folded_at_first)
		folding_changed.connect(_on_folding_changed)


	func set_lines(line: Array, rows: Array) -> void:
		title = line[0]
		_line.set_row(line)
		var n_rows := rows.size()
		var n_children := _vbox.get_child_count()
		while n_children < n_rows:
			_vbox.add_child(ProjectRow.new(true, _base_column_width))
			n_children += 1
		for i in n_children:
			var row: ProjectRow = _vbox.get_child(i)
			if i < n_rows:
				var row_data: Array = rows[i]
				row.set_row(row_data)
				row.show()
			else:
				row.hide()


	func _on_folding_changed(is_folded_now: bool) -> void:
		_memory[_memory_key] = is_folded_now



## A buildout's row, or the replacement line's values beside its title.
class ProjectRow extends HBoxContainer:

	var _name_label: Label # null for a title bar's values
	var _labels: Array[Label] = []
	var _base_column_width: float


	func _init(is_named: bool, base_column_width: float) -> void:
		_base_column_width = base_column_width
		size_flags_horizontal = SIZE_FILL
		if is_named:
			var spacer := Control.new()
			spacer.custom_minimum_size.x = SUBGROUP_INDENT
			add_child(spacer)
			_name_label = Label.new()
			_name_label.size_flags_horizontal = SIZE_EXPAND_FILL
			_name_label.clip_text = true
			_name_label.mouse_filter = MOUSE_FILTER_PASS
			add_child(_name_label)
		for i in N_COLUMNS:
			var label := Label.new()
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			label.mouse_filter = MOUSE_FILTER_PASS
			add_child(label)
			_labels.append(label)
		var gui_size: int = IVSettingsManager.get_setting(&"gui_size")
		_resize(gui_size)
		IVSettingsManager.changed.connect(_settings_listener)


	## Sets the row from [param data]: [name, tooltip, built, pace, binding, done in (y),
	## slip (y), spent ($M), return a year, state].
	func set_row(data: Array) -> void:
		if _name_label:
			var row_name: StringName = data[0]
			_name_label.text = row_name
			_name_label.tooltip_text = data[1]
		var pace: float = data[3]
		var binding: StringName = data[4]
		var done_in: float = data[5]
		var slip: float = data[6]
		var spent: float = data[7]
		var return_rate: float = data[8]
		var state: String = data[9]
		_labels[0].text = data[2]
		_labels[1].text = NO_VALUE if is_nan(pace) else "%.f" % (100.0 * pace)
		_labels[1].tooltip_text = "Bound by " + tr(binding) if binding else ""
		_labels[2].text = _format_years(done_in)
		_labels[3].text = _format_years(slip)
		_labels[4].text = NO_VALUE if is_nan(spent) else IVQFormat.metric_number(spent)
		if state:
			_labels[5].text = state
		else:
			_labels[5].text = NO_VALUE if is_nan(return_rate) else "%.f" % (100.0 * return_rate)


	func _format_years(years: float) -> String:
		if is_nan(years):
			return " "
		if years == INF:
			return "∞"
		return "%.1f" % years


	func _resize(gui_size: int) -> void:
		var column_width := _base_column_width * IVCoreSettings.gui_size_multipliers[gui_size]
		for label in _labels:
			label.custom_minimum_size.x = column_width


	func _settings_listener(setting: StringName, value: Variant) -> void:
		if setting == &"gui_size":
			var gui_size: int = value
			_resize(gui_size)
