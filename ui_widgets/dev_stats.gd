# dev_stats.gd
# This file is part of Astropolis
# https://t2civ.com
# *****************************************************************************
# Copyright 2019-2026 Charlie Whitfield; ALL RIGHTS RESERVED
# Astropolis is a registered trademark of Charlie Whitfield in the US
# *****************************************************************************
class_name DevStats
extends MarginContainer

## Multi-target development-stats table. Shows population, economy, power,
## manufacturing, etc. as rows × proxy targets as columns.
##
## The population line folds: its title holds each target's total, each person counted once where
## they are, the staff on loan and crew where they work, and it unfolds to each type's. Value
## columns are of a fixed width, right aligned, so every row's line up with the population line's
## title.
##
## Used by [ITabDevelopment] and the standalone development panel. Calls
## proxy methods on the proxy thread, then builds the rows on the main
## thread.


## Emitted whenever the rows are rebuilt with [param has_stats] true if any
## target has data.
signal has_stats_changed(has_stats: bool)

## The population line's title lead, its fold arrow and separation, at which the other rows'
## labels start so that theirs line up with its title.
const FOLD_INDENT := 20.0
## The least space between a row's label and its first value.
const LABEL_GAP := 10.0

# GUI values - parent should set only once at init
## Display string for zero values. Set to [code]""[/code] to print zeros
## with units instead of a placeholder.
var zero_value := "-"
## If true, missing proxies still get a column (with no data).
var show_missing_proxy := true
## If false, rows that have no data across all targets are skipped.
var force_rows := true
## Minimum number of columns including the row-label column. Pads with empty
## columns if there are fewer targets than this.
var min_columns := 3
## Component name (string property on [Proxy]) that must exist for a
## target to count as having data.
var required_component := &"operations"
## Min width of each target's column, before the GUI size's multiplier.
var column_width := 80.0
## Format of the population line and its types' rows.
var population_format := IVQFormat.named_number.bind(3, IVQFormat.TextFormat.SHORT_MIXED_CASE,
		true)


## Per-row spec of the rows below the population line:
## [code][label, getter_method, format_callable][/code]. Override to add or remove development
## metrics.
var content: Array[Array] = [
	# label_txt, target_path
	[&"LABEL_ECONOMY", &"get_development_economy", IVQFormat.modified_named_number.bind(3,
			IVQFormat.TextFormat.SHORT_MIXED_CASE, false, 999999.5, "$", "",
			1.0 / IVUnits.unit_multipliers[&"$"])],
	[&"LABEL_POWER", &"get_development_power", IVQFormat.prefixed_unit.bind(&"W")],
	[&"LABEL_CONSTRUCTIONS", &"get_development_constructions", IVQFormat.prefixed_unit.bind(&"t")],
	[&"LABEL_MANUFACTURING", &"get_development_manufacturing", IVQFormat.prefixed_unit.bind(&"t/h")],
	[&"LABEL_INFORMATION", &"get_development_information", IVQFormat.prefixed_unit.bind(&"bit")],
	[&"LABEL_COMPUTATION", &"get_development_computation", IVQFormat.prefixed_unit.bind(&"flop/s")],
	[&"LABEL_BIOMASS", &"get_development_biomass", IVQFormat.dynamic_unit.bind(
			&"mass_g_kg_prefixed_t")],
	[&"LABEL_BIOPRODUCTIVITY", &"get_development_bioproductivity", IVQFormat.prefixed_unit.bind(
			&"t/h")],
	[&"LABEL_BIODIVERSITY", &"get_development_biodiversity", IVQFormat.prefixed_unit.bind(&"spp")],
]

## Proxy names to query, one per column.
var targets: Array[StringName] = [&"LOCUS_PLANET_EARTH", &"JOIN_OFFWORLD"]
## Header text per column (translated keys); if non-empty, used instead of
## the proxy's own name.
var column_names: Array[StringName] = [&"PLANET_EARTH", &"TXT_OFF_EARTH"]
## Fallback header per column when [member column_names] is empty and the
## target proxy is missing. Empty entries fall back to the target string.
var fallback_names: Array[StringName] = [&"", &""]

var _rows := VBoxContainer.new()
var _header: StatsRow
var _population: PopulationLine
var _stats_rows: Array[StatsRow] = []


func _ready() -> void:
	_rows.add_theme_constant_override(&"separation", 0)
	_rows.mouse_filter = MOUSE_FILTER_IGNORE
	_rows.hide()
	add_child(_rows)


## Replaces [member targets], [member column_names], and
## [member fallback_names], then triggers an update.
func update_targets(targets_: Array[StringName], column_names_: Array[StringName] = [],
		fallback_names_: Array[StringName] = []) -> void:
	targets = targets_
	column_names = column_names_
	fallback_names = fallback_names_
	update()


## Refreshes the rows by dispatching to the proxy thread. No-op while sim threads
## are stopped (menu, save/load) — the proxy thread isn't draining then.
func update() -> void:
	if !IVStateManager.is_threads_allowed():
		return
	MainThreadGlobal.call_proxy_thread(_set_data.bind(targets, column_names, fallback_names))


# ******************************* PROXY THREAD ********************************

func _set_data(targets_: Array[StringName], column_names_: Array[StringName],
		fallback_names_: Array[StringName]) -> void:
	# get Proxies and check required components
	var proxies: Array[Proxy] = []
	var has_data := false
	for target in targets_:
		var proxy := Proxy.get_proxy_by_name(target)
		if proxy:
			if proxy.get(required_component):
				has_data = true
			else:
				proxy = null
		if proxy or show_missing_proxy:
			proxies.append(proxy) # may be null
	if !has_data:
		_no_data.call_deferred()
		return

	var n_proxies := proxies.size()
	var n_spacers := maxi(min_columns - 1 - n_proxies, 0)

	var headers := PackedStringArray()
	for i in n_proxies:
		var proxy: Proxy = proxies[i]
		var use_name := ""
		if column_names_:
			use_name = column_names_[i]
		elif proxy:
			# tr() is main thread only; its Label translates the name.
			use_name = proxy.gui_name if proxy.gui_name else String(proxy.name)
		elif fallback_names_[i]:
			use_name = fallback_names_[i]
		else:
			use_name = targets_[i]
		headers.append(use_name)

	var population_rows: Array[Array] = []
	var population_names: Array[StringName] = IVTableData.db_tables[&"populations"][&"name"]
	for population_type in population_names.size():
		var values := _get_values(proxies, &"get_development_population", population_type)
		var has_people := false
		for value: Variant in values:
			has_people = has_people or (value != null and value)
		if has_people:
			population_rows.append([population_names[population_type],
					_format_cells(values, population_format, n_spacers)])

	var stats_rows: Array[Array] = []
	for line_array in content:
		var method: StringName = line_array[1]
		var format_callable: Callable = line_array[2]
		var values := _get_values(proxies, method)
		if !force_rows and values.all(func(value: Variant) -> bool: return value == null):
			continue
		var row_text: String = line_array[0]
		stats_rows.append([row_text, _format_cells(values, format_callable, n_spacers)])

	var data := {
		&"headers": _pad(headers, n_spacers),
		&"population": _format_cells(_get_values(proxies, &"get_development_population"),
				population_format, n_spacers),
		&"population_rows": population_rows,
		&"stats_rows": stats_rows,
	}
	_build.call_deferred(data)


# Each proxy's value of [param method], with [param argument] where it is given, null for a
# missing proxy.
func _get_values(proxies: Array[Proxy], method: StringName, argument: Variant = null) -> Array:
	var values := []
	for proxy in proxies:
		var value: Variant = null
		if proxy:
			value = proxy.call(method) if argument == null else proxy.call(method, argument)
		values.append(value)
	return values


func _format_cells(values: Array, format_callable: Callable, n_spacers: int) -> PackedStringArray:
	var cells := PackedStringArray()
	for value: Variant in values:
		if value != null and (value or !zero_value):
			var text: String = format_callable.call(value)
			cells.append(text)
		else:
			cells.append(zero_value)
	return _pad(cells, n_spacers)


static func _pad(cells: PackedStringArray, n_spacers: int) -> PackedStringArray:
	for i in n_spacers:
		cells.append("")
	return cells


# ******************************** MAIN THREAD ********************************

func _no_data() -> void:
	_rows.hide()
	has_stats_changed.emit(false)


func _build(data: Dictionary) -> void:
	var headers: PackedStringArray = data[&"headers"]
	var population: PackedStringArray = data[&"population"]
	var population_rows: Array[Array] = data[&"population_rows"]
	var stats_rows: Array[Array] = data[&"stats_rows"]
	if !_header: # the rows read the GUI size, a setting there is only once the game runs
		_header = StatsRow.new(FOLD_INDENT, column_width)
		_rows.add_child(_header)
		_population = PopulationLine.new(FOLD_INDENT, column_width)
		_rows.add_child(_population)
	_header.set_row("", headers)
	_population.set_line(tr(&"LABEL_POPULATION"), population, population_rows)
	var n_rows := stats_rows.size()
	while _stats_rows.size() < n_rows:
		var row := StatsRow.new(FOLD_INDENT, column_width)
		_rows.add_child(row)
		_stats_rows.append(row)
	for i in _stats_rows.size():
		var row := _stats_rows[i]
		row.visible = i < n_rows
		if i < n_rows:
			var label: StringName = stats_rows[i][0]
			var cells: PackedStringArray = stats_rows[i][1]
			row.set_row(tr(label), cells)
	has_stats_changed.emit(true)
	_rows.show()


# Shows [param texts] in [param cells], the value cells of a row or of the population line's title
# held in [param parent], adding cells of [param width] as more are wanted and hiding those not.
static func _set_cells(parent: Control, cells: Array[Label], texts: PackedStringArray,
		width: float) -> void:
	var gui_size: int = IVSettingsManager.get_setting(&"gui_size")
	var multiplier := IVCoreSettings.gui_size_multipliers[gui_size]
	while cells.size() < texts.size():
		var cell := Label.new()
		cell.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cell.custom_minimum_size.x = width * multiplier
		parent.add_child(cell)
		cells.append(cell)
	for c in cells.size():
		var cell := cells[c]
		cell.visible = c < texts.size()
		if c < texts.size():
			cell.text = texts[c]


class StatsRow extends HBoxContainer:
	# One row: its label fills the left past its indent, and its value cells hug the right at the
	# table's column width, so they line up with the population line's title cells.

	var _indent_spacer := Control.new()
	var _label := Label.new()
	var _gap := Control.new()
	var _cells: Array[Label] = []
	var _indent: float
	var _column_width: float


	func _init(indent: float, column_width: float) -> void:
		_indent = indent
		_column_width = column_width
		mouse_filter = MOUSE_FILTER_IGNORE
		add_theme_constant_override(&"separation", 0)  # explicit indents and widths only
		add_child(_indent_spacer)
		_label.size_flags_horizontal = SIZE_EXPAND_FILL
		add_child(_label)
		add_child(_gap)
		var gui_size: int = IVSettingsManager.get_setting(&"gui_size")
		_resize(gui_size)
		IVSettingsManager.changed.connect(_settings_listener)


	func set_row(label_text: String, cells: PackedStringArray) -> void:
		_label.text = label_text
		DevStats._set_cells(self, _cells, cells, _column_width)


	func _resize(gui_size: int) -> void:
		var multiplier := IVCoreSettings.gui_size_multipliers[gui_size]
		_indent_spacer.custom_minimum_size.x = _indent * multiplier
		_gap.custom_minimum_size.x = DevStats.LABEL_GAP * multiplier
		for cell in _cells:
			cell.custom_minimum_size.x = _column_width * multiplier


	func _settings_listener(setting: StringName, value: Variant) -> void:
		if setting == &"gui_size":
			var gui_size: int = value
			_resize(gui_size)


class PopulationLine extends FoldableContainer:
	# The population: the native title shows its label, a right-aligned title control each target's
	# total, and it unfolds to each type's row. No style box insets its title or its rows, so their
	# cells line up with the table's other rows. With no one of any type it gets a blank fold-icon
	# substitute and can't be unfolded, as the budget tab's leafless groups can't.

	var _block := HBoxContainer.new()
	var _cells: Array[Label] = []
	var _rows_vbox := VBoxContainer.new()
	var _type_rows: Array[StatsRow] = []
	var _fold_icon_substitute := MeshTexture.new()
	var _indent: float
	var _column_width: float
	var _singular := false


	func _init(indent: float, column_width: float) -> void:
		_indent = indent
		_column_width = column_width
		size_flags_horizontal = SIZE_FILL  # full width; cells right-align to the content edge
		var empty := StyleBoxEmpty.new()
		for style: StringName in [&"title_panel", &"title_hover_panel", &"title_collapsed_panel",
				&"title_collapsed_hover_panel", &"panel"]:
			add_theme_stylebox_override(style, empty)
		_block.add_theme_constant_override(&"separation", 0)  # explicit widths only
		_block.mouse_filter = MOUSE_FILTER_IGNORE
		add_title_bar_control(_block)
		_rows_vbox.add_theme_constant_override(&"separation", 0)
		add_child(_rows_vbox)
		folded = true
		_fold_icon_substitute.image_size.x = 16  # match the fold-arrow width
		folding_changed.connect(_on_folding_changed)
		IVSettingsManager.changed.connect(_settings_listener)


	func set_line(title_text: String, cells: PackedStringArray, type_rows: Array[Array]) -> void:
		title = title_text
		DevStats._set_cells(_block, _cells, cells, _column_width)
		var n_rows := type_rows.size()
		var singular := n_rows == 0
		if singular != _singular:
			_singular = singular
			if singular:
				add_theme_icon_override(&"folded_arrow", _fold_icon_substitute)
				folded = true
			else:
				remove_theme_icon_override(&"folded_arrow")
		while _type_rows.size() < n_rows:
			var row := StatsRow.new(2.0 * _indent, _column_width)
			_rows_vbox.add_child(row)
			_type_rows.append(row)
		for i in _type_rows.size():
			var row := _type_rows[i]
			row.visible = i < n_rows
			if i < n_rows:
				var label: StringName = type_rows[i][0]
				var row_cells: PackedStringArray = type_rows[i][1]
				row.set_row(tr(label), row_cells)


	func _on_folding_changed(is_folded_: bool) -> void:
		if _singular and !is_folded_:  # no one to list
			fold()


	func _settings_listener(setting: StringName, value: Variant) -> void:
		if setting == &"gui_size":
			var gui_size: int = value
			var multiplier := IVCoreSettings.gui_size_multipliers[gui_size]
			for cell in _cells:
				cell.custom_minimum_size.x = _column_width * multiplier
