# itab_populations.gd
# This file is part of Astropolis
# https://t2civ.com
# *****************************************************************************
# Copyright 2019-2026 Charlie Whitfield; ALL RIGHTS RESERVED
# Astropolis is a registered trademark of Charlie Whitfield in the US
# *****************************************************************************
class_name ITabPopulations
extends MarginContainer

## "Populations" tab subpanel for [InfoPanel]. Shows a facility's residents, one population type
## at a time, in three views.
##
## [b]Demog[/b]: the head count, the share in each life stage, each unfolding to its age
## buckets, and the vital rates. [b]Needs[/b]: how well each need is met, by tier; a need unfolds
## to its satisfiers, with the facility's unmet rate and local price for each. [b]Means[/b]: the
## residents' wealth, what it buys, and the work they offer at the wage. A body with one facility
## shows as that facility. Header and row tooltips define the values; the model behind them is
## POPULATION_MODEL.md.

const SCENE := "res://public/ui/itab_populations.tscn"  ## Scene file for instancing.

enum {
	TAB_DEMOGRAPHY,
	TAB_NEEDS,
	TAB_MEANS,
}

enum {
	TONE_NORMAL,
	TONE_WARNING,
	TONE_ALERT,
}

const N_CELLS := 5
const SUBGROUP_INDENT := 25

const TAB_NAMES: Array[StringName] = [ # by TAB_; node names auto-translate as tab titles
	&"TAB_POP_DEMOGRAPHY",
	&"TAB_POP_NEEDS",
	&"TAB_POP_MEANS",
]
const STAGE_TEXTS: Array[String] = ["Young", "Adult", "Elder"] # by Enums.LifeStages
const TIER_TEXTS: Array[String] = ["Existence", "Wellbeing", "Fulfillment"] # by Enums.NeedTiers
const TIER_TOOLTIPS: Array[String] = [ # by Enums.NeedTiers
	"Without it an individual stops, within weeks. Below its type's threshold, people starve.",
	"Going without is chronic: shorter lives and a push to leave, over years.",
	"What sentient beings require. Going without means fewer children and less able workers.",
]
const TYPE_COLUMN_TOOLTIPS: Array[String] = [ # by TAB_
	"The population type shown: its heads, their shares by life stage and age, and its vital\nrates.",
	"The share of the type's want for each need that it got, smoothed over about a month\nfor an existence need and a quarter for the others.",
	"The type's wealth and what it buys, and the work it offers.",
]
const SATISFIER_HEADERS: Array[String] = ["Unmet\n(/d)", "Local\n($)"]
const SATISFIER_TOOLTIPS: Array[String] = [
	("What the facility's clear left unmet of what its users asked, row units per day:"
			+ "\nresidents and operations alike."),
	"The facility's local price, $ per row unit.",
]

const NO_VALUE := "—" ## Applies, but has no value now.
const NOT_APPLICABLE := "·" ## Doesn't apply to this type.
const WARNING_COLOR := Color(1.0, 0.75, 0.3)
const ALERT_COLOR := Color(1.0, 0.4, 0.4)
const BAR_COLOR := Color(0.62, 0.62, 0.62)
const SECTION_COLOR := Color(0.62, 0.62, 0.62)

const PERSIST_MODE := IVGlobal.PERSIST_PROCEDURAL  ## Save/load mode (procedural node).
## Member names persisted by save/load.
const PERSIST_PROPERTIES: Array[StringName] = [
	&"population_type",
	&"current_tab",
	&"_on_ready_tab",
]

# persisted
## The population type chosen, shown wherever it lives; -1 until one is chosen, which shows the
## most populous.
var population_type := -1
var current_tab: int = TAB_DEMOGRAPHY
var _on_ready_tab: int = TAB_DEMOGRAPHY

# not persisted
## Min width of each value column.
var column_width := 58.0
## Width of the bar left of the value columns.
var bar_width := 64.0
## Min width of the gutter right of the value columns.
var cell_gutter := 8.0
## Foldable title left-lead (fold-icon + style-box margin); aligns the header with line titles.
var foldable_indent := 20.0
## Trailing spacer on the out-of-scroll header; offsets its columns to match the in-scroll
## content past the vertical scrollbar.
var scroll_correction := 7.0

var _selection_manager: AstroSelectionManager
var _suppress_tab_listener := true

# table indexing
var _db_tables := IVTableData.db_tables
var _n_populations: int = IVTableData.table_n_rows[&"populations"]
var _n_needs: int = IVTableData.table_n_rows[&"needs"]
var _population_names: Array[StringName] = _db_tables[&"populations"][&"name"]
var _bucket_widths: Array[Array] = _db_tables[&"populations"][&"bucket_widths"]
var _first_adult_buckets: Array[int] = _db_tables[&"populations"][&"first_adult_bucket"]
var _first_elder_buckets: Array[int] = _db_tables[&"populations"][&"first_elder_bucket"]
var _starvation_thresholds: Array[float] = _db_tables[&"populations"][&"starvation_threshold"]
var _work_resources: Array[int] = _db_tables[&"populations"][&"work_resource"]
var _need_names: Array[StringName] = _db_tables[&"needs"][&"name"]
var _need_tiers: Array[int] = _db_tables[&"needs"][&"tier"]
var _resource_names: Array[StringName] = _db_tables[&"resources"][&"name"]
var _trade_units: Array[StringName] = _db_tables[&"resources"][&"trade_unit"]
var _trade_unit_multipliers := ThreadsafeGlobal.resource_trade_unit_multipliers
# By [type * _n_needs + need]: whether the type has a want for the need, and the resources that
# fill its wants for it.
var _has_wants := PackedByteArray()
var _satisfiers: Array[PackedInt32Array] = []

# Blank icon used as the fold-arrow override for a line that doesn't unfold; keeps the title's
# left lead while hiding the (non-functional) arrow.
var _fold_icon_substitute := MeshTexture.new()

# built in code (see _build_ui)
var _tab_container: TabContainer
var _no_populations_label: Label
var _headers: Array[PopulationsHeaderRow] = []
var _content_vboxes: Array[VBoxContainer] = []

@warning_ignore("unsafe_property_access")
@onready var _memory: Dictionary = get_parent().memory # line open states


# ********************************** STATIC ***********************************

static func _make_cell_label() -> Label:
	var label := Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.clip_text = true
	label.mouse_filter = MOUSE_FILTER_PASS  # for its tooltip; clicks still reach a foldable
	return label


static func _apply_cells(labels: Array[Label], cells: PackedStringArray,
		tooltips: PackedStringArray, tones: PackedByteArray) -> void:
	for i in labels.size():
		var label := labels[i]
		if i >= cells.size():
			label.hide()
			continue
		label.show()
		label.text = cells[i]
		label.tooltip_text = tooltips[i]
		_apply_tone(label, tones[i])


static func _apply_tone(label: Label, tone: int) -> void:
	match tone:
		TONE_WARNING:
			label.add_theme_color_override(&"font_color", WARNING_COLOR)
		TONE_ALERT:
			label.add_theme_color_override(&"font_color", ALERT_COLOR)
		_:
			label.remove_theme_color_override(&"font_color")


static func _get_tone_color(tone: int) -> Color:
	match tone:
		TONE_WARNING:
			return WARNING_COLOR
		TONE_ALERT:
			return ALERT_COLOR
	return BAR_COLOR


# ************************* VIRTUAL & IMPLEMENTATION **************************

func _ready() -> void:
	IVStateManager.about_to_free_procedural_nodes.connect(_clear_procedural)
	visibility_changed.connect(_update_tab)
	_selection_manager = IVSelectionManager.get_selection_manager(self)
	_selection_manager.selection_changed.connect(_update_tab)
	_fold_icon_substitute.image_size.x = 16  # match the fold-arrow width
	_index_satisfiers()
	_build_ui()
	_tab_container.set_current_tab(_on_ready_tab)
	_suppress_tab_listener = false
	_update_tab()


func _clear_procedural() -> void:
	if _selection_manager:
		_selection_manager.selection_changed.disconnect(_update_tab)
		_selection_manager = null
	visibility_changed.disconnect(_update_tab)
	_tab_container.tab_changed.disconnect(_select_tab)


## Refreshes the active populations tab. Wired to [InfoTabContainer]'s shared 1 s timer.
func timer_update() -> void:
	_update_tab()


func _index_satisfiers() -> void:
	var wants_table: Dictionary[StringName, Array] = _db_tables[&"wants"]
	var want_populations := PackedInt32Array(wants_table[&"population"])
	var want_needs := PackedInt32Array(wants_table[&"need"])
	var want_inputs := Utils.to_array_of_packed_int32(wants_table[&"in_inventory"])
	_has_wants.resize(_n_populations * _n_needs)
	_satisfiers.resize(_n_populations * _n_needs)
	for want in want_populations.size():
		var index := want_populations[want] * _n_needs + want_needs[want]
		_has_wants[index] = 1
		var satisfiers := _satisfiers[index]
		for resource_type in want_inputs[want]:
			if !satisfiers.has(resource_type):
				satisfiers.append(resource_type)
		_satisfiers[index] = satisfiers


func _build_ui() -> void:
	_tab_container = TabContainer.new()
	_tab_container.size_flags_horizontal = SIZE_EXPAND_FILL
	_tab_container.size_flags_vertical = SIZE_EXPAND_FILL
	add_child(_tab_container)

	_no_populations_label = Label.new()
	_no_populations_label.text = "LABEL_NO_POPULATIONS"
	_no_populations_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_no_populations_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_no_populations_label.hide()
	add_child(_no_populations_label)

	var n_tabs := TAB_NAMES.size()
	_headers.resize(n_tabs)
	_content_vboxes.resize(n_tabs)
	for tab in n_tabs:
		var tab_vbox := VBoxContainer.new()
		tab_vbox.name = TAB_NAMES[tab]
		_tab_container.add_child(tab_vbox)

		var header := PopulationsHeaderRow.new(column_width, bar_width, cell_gutter,
				foldable_indent, scroll_correction)
		header.type_selected.connect(_select_type)
		tab_vbox.add_child(header)

		var scroll := ScrollContainer.new()
		scroll.size_flags_horizontal = SIZE_EXPAND_FILL
		scroll.size_flags_vertical = SIZE_EXPAND_FILL
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		tab_vbox.add_child(scroll)
		var content := VBoxContainer.new()
		content.size_flags_horizontal = SIZE_EXPAND_FILL
		content.size_flags_vertical = SIZE_EXPAND_FILL
		scroll.add_child(content)

		_headers[tab] = header
		_content_vboxes[tab] = content

	_tab_container.tab_changed.connect(_select_tab)


func _select_tab(tab: int) -> void:
	if !_suppress_tab_listener:
		_on_ready_tab = tab
	current_tab = tab
	_update_tab()


func _select_type(type: int) -> void:
	population_type = type
	_update_tab()


func _update_tab(_dummy := false) -> void:
	if !visible or !IVStateManager.is_threads_allowed():
		return
	var target_name := _selection_manager.get_name()
	if !MainThreadGlobal.has_development(target_name):
		_update_no_populations()
		return
	MainThreadGlobal.call_proxy_thread(_get_proxy_data.bind(target_name, current_tab,
			population_type))


func _update_no_populations() -> void:
	_tab_container.hide()
	_no_populations_label.show()


# ******************************* PROXY THREAD ********************************

func _get_proxy_data(target_name: StringName, tab: int, chosen_type: int) -> void:
	var proxy := Proxy.get_proxy_by_name(target_name)
	if proxy:
		var body := proxy as BodyProxy
		if body and body.facilities.size() == 1:
			proxy = body.facilities[0]
	var facility := proxy as FacilityProxy
	if !facility:
		_update_no_populations.call_deferred()
		return
	var data := PopulationsData.new()
	for type in _n_populations:
		if facility.get_population_number(type) > 0.0:
			data.types.append(type)
	if data.types.is_empty():
		_update_no_populations.call_deferred()
		return
	data.types.sort_custom(func(a: int, b: int) -> bool:
		return facility.get_population_number(a) > facility.get_population_number(b))
	var shown_type := chosen_type if data.types.has(chosen_type) else data.types[0]
	data.columns.append(_get_facility_column(facility, shown_type))
	if tab == TAB_NEEDS:
		_get_satisfier_values(facility, shown_type, data)
	_update_tab_display.call_deferred(tab, data)


func _get_facility_column(facility: FacilityProxy, type: int) -> ColumnData:
	var column := ColumnData.new()
	column.population_type = type
	column.number = facility.get_population_number(type)
	for stage in Enums.LifeStages.size():
		column.stage_numbers.append(facility.get_population_stage_number(type, stage))
	for bucket in _bucket_widths[type].size() + 1:
		column.bucket_numbers.append(facility.get_population_bucket_number(type, bucket))
	column.birth_rate = facility.get_population_birth_rate(type)
	column.death_rate = facility.get_population_death_rate(type)
	column.starvation_rate = facility.get_population_starvation_rate(type)
	column.life_expectancy = facility.get_population_life_expectancy(type)
	column.satisfactions.resize(_n_needs)
	for need in _n_needs:
		column.satisfactions[need] = (facility.get_population_satisfaction(type, need)
				if _has_wants[type * _n_needs + need] else NAN)
	column.wealth = facility.get_population_wealth(type)
	column.years_of_wants = facility.get_population_years_of_wants(type)
	column.participation = facility.get_population_participation(type)
	var work_resource := _work_resources[type]
	column.wage = (facility.get_inventory_local_price(work_resource) if work_resource != -1
			else NAN)
	return column


func _get_satisfier_values(facility: FacilityProxy, type: int, data: PopulationsData) -> void:
	for need in _n_needs:
		for resource_type in _satisfiers[type * _n_needs + need]:
			data.unmet_rates[resource_type] = facility.get_inventory_unmet_rate(resource_type)
			data.local_prices[resource_type] = facility.get_inventory_local_price(resource_type)


# ******************************** MAIN THREAD ********************************

func _update_tab_display(tab: int, data: PopulationsData) -> void:
	_no_populations_label.hide()
	_tab_container.show()
	var shown_type := data.columns[0].population_type
	var headers := PackedStringArray()
	var tooltips := PackedStringArray()
	for column in data.columns:
		headers.append(_get_type_header(column.population_type))
		tooltips.append(TYPE_COLUMN_TOOLTIPS[tab])
	if tab == TAB_NEEDS:
		headers.append_array(SATISFIER_HEADERS)
		tooltips.append_array(SATISFIER_TOOLTIPS)
	var lines: Array[LineData]
	match tab:
		TAB_DEMOGRAPHY:
			lines = _get_demography_lines(data)
		TAB_NEEDS:
			lines = _get_needs_lines(data)
		_:
			lines = _get_means_lines(data)
	var is_bar_shown := tab != TAB_MEANS
	var type_texts := PackedStringArray()
	for type in data.types:
		type_texts.append(tr(_population_names[type]))
	_headers[tab].set_header(data.types, type_texts, shown_type, headers, tooltips,
			is_bar_shown)

	var content := _content_vboxes[tab]
	var n_lines := lines.size()
	var n_children := content.get_child_count()
	while n_children < n_lines:
		content.add_child(PopulationsLine.new(_memory, column_width, bar_width, cell_gutter,
				_fold_icon_substitute))
		n_children += 1
	for i in n_lines:
		var line: PopulationsLine = content.get_child(i)
		line.set_line(lines[i], is_bar_shown)
		line.show()
	for i in range(n_lines, n_children):
		var unused_line: Control = content.get_child(i)
		unused_line.hide()


func _get_demography_lines(data: PopulationsData) -> Array[LineData]:
	const YEAR := IVUnits.YEAR
	var column := data.columns[0]
	var type := column.population_type
	var number := column.number
	var lines: Array[LineData] = []
	var heads := _make_line("Heads", [_format_heads(number)], [_format_named(number)])
	lines.append(heads)
	var bucket_texts := _get_bucket_texts(type)
	for stage in Enums.LifeStages.size():
		var stage_number := column.stage_numbers[stage]
		var share := stage_number / number if number > 0.0 else NAN
		var line := _make_line(STAGE_TEXTS[stage] + " (%)", [_format_share(share)],
				[_format_named(stage_number) + " heads"])
		line.memory_key = "POP_STAGE_%d" % stage
		line.share = share
		var first_bucket := 0
		var end_bucket := _first_adult_buckets[type]
		if stage == Enums.LifeStages.LIFE_STAGE_ADULT:
			first_bucket = end_bucket
			end_bucket = _first_elder_buckets[type]
		elif stage == Enums.LifeStages.LIFE_STAGE_ELDER:
			first_bucket = _first_elder_buckets[type]
			end_bucket = column.bucket_numbers.size()
		for bucket in range(first_bucket, end_bucket):
			var bucket_number := column.bucket_numbers[bucket]
			var bucket_share := bucket_number / number if number > 0.0 else NAN
			var row := _make_line(bucket_texts[bucket], [_format_share(bucket_share)],
					[_format_named(bucket_number) + " heads"])
			row.share = bucket_share
			line.rows.append(row)
		lines.append(line)
	var per_thousand := 1000.0 * YEAR / number if number > 0.0 else NAN
	lines.append(_make_line("Births (/k·y)", [_format_value(column.birth_rate * per_thousand)],
			["Births a year per thousand heads, over about a quarter."]))
	lines.append(_make_line("Deaths (/k·y)", [_format_value(column.death_rate * per_thousand)],
			["Deaths a year per thousand heads, starvation's included, over about a quarter."]))
	var starvation := column.starvation_rate * per_thousand
	var starvation_line := _make_line("Starvation (/k·y)", [_format_value(starvation)],
			["Deaths a year per thousand heads for want of life support, over about a quarter."])
	if starvation > 0.0:
		starvation_line.tones[0] = TONE_ALERT
	lines.append(starvation_line)
	var increase := (column.birth_rate - column.death_rate) * per_thousand / 10.0
	lines.append(_make_line("Natural increase (%/y)", [_format_value(increase, true)],
			["Births less deaths, a percent of the heads a year."]))
	lines.append(_make_line("Life expectancy (y)",
			[_format_value(column.life_expectancy / YEAR)],
			["The mean lifetime of a newborn at the present death rates."]))
	return lines


func _get_needs_lines(data: PopulationsData) -> Array[LineData]:
	var column := data.columns[0]
	var type := column.population_type
	var lines: Array[LineData] = []
	for tier in TIER_TEXTS.size():
		var section := _make_line(TIER_TEXTS[tier], [], [])
		section.is_section = true
		section.title_tooltip = TIER_TOOLTIPS[tier]
		lines.append(section)
		for need in _n_needs:
			if _need_tiers[need] != tier:
				continue
			var satisfaction := column.satisfactions[need]
			if is_nan(satisfaction):
				lines.append(_make_line(tr(_need_names[need]), [NOT_APPLICABLE, "", ""],
						["The type has no want for it.", "", ""]))
				continue
			var tone := _get_satisfaction_tone(type, need, satisfaction)
			var line := _make_line(tr(_need_names[need]),
					[_format_percent(satisfaction), "", ""], ["", "", ""])
			line.tones[0] = tone
			line.share = satisfaction
			line.bar_tone = tone
			line.memory_key = "POP_" + _need_names[need]
			for resource_type in _satisfiers[type * _n_needs + need]:
				var multiplier := _trade_unit_multipliers[resource_type]
				var unmet_rate: float = data.unmet_rates.get(resource_type, 0.0)
				var local_price: float = data.local_prices.get(resource_type, NAN)
				var row := _make_line(_get_resource_title(resource_type), ["",
						_format_rate(unmet_rate, multiplier), _format_price(local_price * multiplier)],
						["", "", ""])
				if unmet_rate > 0.0:
					row.tones[1] = TONE_WARNING
				line.rows.append(row)
			lines.append(line)
	return lines


func _get_means_lines(data: PopulationsData) -> Array[LineData]:
	var column := data.columns[0]
	var type := column.population_type
	var lines: Array[LineData] = []
	var wealth_per_head := column.wealth / column.number if column.number > 0.0 else NAN
	lines.append(_make_line("Wealth ($)", [_format_money(column.wealth)],
			["$" + _format_named(column.wealth)]))
	lines.append(_make_line("Wealth a head ($)", [_format_money(wealth_per_head)], [""]))
	lines.append(_make_line("Years of wants (y)", [_format_value(column.years_of_wants)],
			["What the wealth buys: the years of the type's wants it would pay for at local"
			+ "\nprices. It compares across places, as purchasing-power parity does."]))
	lines.append(_make_line("Participation (%)", [_format_percent(column.participation)],
			["The most of its able hours the type offers."]))
	var work_resource := _work_resources[type]
	if work_resource != -1:
		var unit := _trade_units[work_resource]
		lines.append(_make_line("Wage ($/%s)" % unit,
				[_format_price(column.wage * _trade_unit_multipliers[work_resource])],
				["The local price of %s, what the residents' work earns." % tr(
				_resource_names[work_resource]).to_lower()]))
	return lines


func _make_line(title: String, cells: Array[String], tooltips: Array[String]) -> LineData:
	var line := LineData.new()
	line.title = title
	line.cells = PackedStringArray(cells)
	line.tooltips = PackedStringArray(tooltips)
	line.tones.resize(cells.size()) # TONE_NORMAL
	return line


# An existence need below its type's starvation threshold kills; any shortfall in one shows.
func _get_satisfaction_tone(type: int, need: int, satisfaction: float) -> int:
	if _need_tiers[need] != Enums.NeedTiers.NEED_TIER_EXISTENCE:
		return TONE_NORMAL
	if satisfaction < _starvation_thresholds[type]:
		return TONE_ALERT
	if roundi(satisfaction * 100.0) < 100:
		return TONE_WARNING
	return TONE_NORMAL


# Each age bucket's bounds in years, the last open-ended.
func _get_bucket_texts(type: int) -> PackedStringArray:
	var widths: Array = _bucket_widths[type]
	var texts := PackedStringArray()
	var start := 0.0
	for width: float in widths:
		var end := start + width / IVUnits.YEAR
		texts.append("%s–%s y" % [_format_years(start), _format_years(end)])
		start = end
	texts.append("%s+ y" % _format_years(start))
	return texts


func _get_type_header(type: int) -> String:
	return tr(_population_names[type]).replace(" ", "\n")


func _get_resource_title(resource_type: int) -> String:
	var title := tr(_resource_names[resource_type])
	var trade_unit := _trade_units[resource_type]
	if trade_unit == &"1":
		return title
	return "%s (%s)" % [title, trade_unit]


func _format_heads(number: float) -> String:
	return IVQFormat.prefixed_unit(number, &"").strip_edges()


func _format_money(dollars: float) -> String:
	if is_nan(dollars):
		return NO_VALUE
	return IVQFormat.prefixed_unit(dollars, &"").strip_edges()


func _format_named(number: float) -> String:
	if is_nan(number):
		return NO_VALUE
	return IVQFormat.named_number(number, 3, IVQFormat.TextFormat.SHORT_LOWER_CASE, true,
			999.5)


func _format_value(value: float, is_signed := false) -> String:
	if is_nan(value) or is_inf(value):
		return NO_VALUE
	if !value:
		return "0"
	var text := IVQFormat.number(value, 3)
	return "+" + text if is_signed and value > 0.0 else text


func _format_years(years: float) -> String:
	if is_equal_approx(years, roundf(years)):
		return str(roundi(years))
	return "%.1f" % years


func _format_share(share: float) -> String:
	return _format_value(share * 100.0)


func _format_percent(share: float) -> String:
	if is_nan(share):
		return NO_VALUE
	return "%.f" % (share * 100.0)


func _format_price(unit_price: float) -> String:
	if !(unit_price > 0.0):
		return NO_VALUE
	return IVQFormat.number(unit_price, 3)


# Formats [param rate], in sim units per second, as trade units per day.
func _format_rate(rate: float, multiplier: float) -> String:
	if !rate:
		return "0"
	return IVQFormat.number(rate * IVUnits.DAY / multiplier, 2)


# ****************************** INNER CLASSES ********************************
# Columns are right-anchored, as in itab_markets.gd: a line is a full-width foldable whose
# title is the native title and whose bar and value cells are a right-aligned title control;
# its rows and the out-of-scroll header end at the same right edge, the header past the vertical
# scrollbar by a trailing spacer.

class PopulationsData extends RefCounted:
	# What the selection shows, gathered on the proxy thread. Rates are sim units per second,
	# prices sim units.
	var types: Array[int] = [] # present, most populous first
	var columns: Array[ColumnData] = []
	var unmet_rates: Dictionary[int, float] = {} # by satisfier resource
	var local_prices: Dictionary[int, float] = {} # by satisfier resource


class ColumnData extends RefCounted:
	# One population type's values.
	var population_type: int
	var number: float
	var stage_numbers := PackedFloat64Array() # by Enums.LifeStages
	var bucket_numbers := PackedFloat64Array()
	var birth_rate: float
	var death_rate: float
	var starvation_rate: float
	var life_expectancy: float
	var satisfactions := PackedFloat64Array() # by need; NAN where the type has no want for it
	var wealth: float
	var years_of_wants: float
	var participation: float
	var wage: float # local price of the type's work resource; NAN without one


class LineData extends RefCounted:
	# One line of a view, formatted on the main thread.
	var title: String
	var title_tooltip := ""
	var memory_key := "" # "" for a line that doesn't unfold
	var is_section := false
	var share := NAN # the bar's fill; NAN shows none
	var bar_tone: int = TONE_NORMAL
	var cells := PackedStringArray()
	var tooltips := PackedStringArray()
	var tones := PackedByteArray()
	var rows: Array[LineData] = [] # what the line unfolds to


class PopulationsHeaderRow extends HBoxContainer:
	# The type picker fills the left; the column headers sit over the value cells.

	signal type_selected(type: int)

	var _indent_spacer := Control.new()
	var _type_button := OptionButton.new()
	var _fill_spacer := Control.new()
	var _bar_spacer := Control.new()
	var _cells: Array[Label] = []
	var _trailing_spacer := Control.new()
	var _types: Array[int] = []
	var _column_width: float
	var _bar_width: float
	var _cell_gutter: float
	var _foldable_indent: float
	var _scroll_correction: float


	func _init(column_width: float, bar_width: float, cell_gutter: float, foldable_indent: float,
			scroll_correction: float) -> void:
		_column_width = column_width
		_bar_width = bar_width
		_cell_gutter = cell_gutter
		_foldable_indent = foldable_indent
		_scroll_correction = scroll_correction
		size_flags_horizontal = SIZE_FILL
		add_theme_constant_override(&"separation", 0)  # explicit gutters/widths only
		add_child(_indent_spacer)
		_type_button.size_flags_vertical = SIZE_SHRINK_CENTER
		_type_button.tooltip_text = "The population type shown"
		_type_button.item_selected.connect(_on_item_selected)
		add_child(_type_button)
		_fill_spacer.size_flags_horizontal = SIZE_EXPAND_FILL
		add_child(_fill_spacer)
		add_child(_bar_spacer)
		_cells.resize(N_CELLS)
		for i in N_CELLS:
			var cell := ITabPopulations._make_cell_label()
			add_child(cell)
			_cells[i] = cell
		add_child(_trailing_spacer)
		var gui_size: int = IVSettingsManager.get_setting(&"gui_size")
		_resize(gui_size)
		IVSettingsManager.changed.connect(_settings_listener)


	func set_header(types: Array[int], type_texts: PackedStringArray, shown_type: int,
			headers: PackedStringArray, tooltips: PackedStringArray, is_bar_shown: bool) -> void:
		if types != _types:
			_types = types.duplicate()
			_type_button.clear()
			for i in types.size():
				_type_button.add_item(type_texts[i], types[i])
		_type_button.select(_type_button.get_item_index(shown_type))
		_bar_spacer.visible = is_bar_shown
		var tones := PackedByteArray()
		tones.resize(headers.size())
		ITabPopulations._apply_cells(_cells, headers, tooltips, tones)


	func _on_item_selected(index: int) -> void:
		type_selected.emit(_type_button.get_item_id(index))


	func _resize(gui_size: int) -> void:
		var multiplier := IVCoreSettings.gui_size_multipliers[gui_size]
		_indent_spacer.custom_minimum_size.x = _foldable_indent * multiplier
		_bar_spacer.custom_minimum_size.x = _bar_width * multiplier
		_trailing_spacer.custom_minimum_size.x = (_cell_gutter + _scroll_correction) * multiplier
		var cell_width := _column_width * multiplier
		for cell in _cells:
			cell.custom_minimum_size.x = cell_width


	func _settings_listener(setting: StringName, value: Variant) -> void:
		if setting == &"gui_size":
			var gui_size: int = value
			_resize(gui_size)


class PopulationsLine extends FoldableContainer:
	# One line: the native title shows its name, a right-aligned title control its bar and
	# cells, and it unfolds to its rows. One with no rows gets a blank fold-icon substitute and
	# can't be unfolded.

	var _rows_vbox := VBoxContainer.new()
	var _bar: PopulationsBar
	var _cells: Array[Label] = []
	var _gutter := Control.new()
	var _memory: Dictionary
	var _fold_icon_substitute: Texture2D
	var _column_width: float
	var _bar_width: float
	var _cell_gutter: float
	var _memory_key: String
	var _is_singular: bool


	func _init(memory: Dictionary, column_width: float, bar_width: float, cell_gutter: float,
			fold_icon_substitute: Texture2D) -> void:
		_memory = memory
		_column_width = column_width
		_bar_width = bar_width
		_cell_gutter = cell_gutter
		_fold_icon_substitute = fold_icon_substitute
		size_flags_horizontal = SIZE_FILL  # full width; cells right-align to the content edge
		var block := HBoxContainer.new()
		block.add_theme_constant_override(&"separation", 0)  # explicit gutters/widths only
		_bar = PopulationsBar.new(bar_width)
		block.add_child(_bar)
		_cells.resize(N_CELLS)
		for i in N_CELLS:
			var cell := ITabPopulations._make_cell_label()
			block.add_child(cell)
			_cells[i] = cell
		block.add_child(_gutter)
		add_title_bar_control(block)
		add_child(_rows_vbox)
		folding_changed.connect(_on_folding_changed)
		var gui_size: int = IVSettingsManager.get_setting(&"gui_size")
		_resize(gui_size)
		IVSettingsManager.changed.connect(_settings_listener)


	func set_line(line: LineData, is_bar_shown: bool) -> void:
		title = line.title
		tooltip_text = line.title_tooltip
		if line.is_section:
			add_theme_color_override(&"font_color", SECTION_COLOR)
			add_theme_color_override(&"collapsed_font_color", SECTION_COLOR)
		else:
			remove_theme_color_override(&"font_color")
			remove_theme_color_override(&"collapsed_font_color")
		_bar.visible = is_bar_shown
		_bar.set_share(line.share, line.bar_tone)
		ITabPopulations._apply_cells(_cells, line.cells, line.tooltips, line.tones)
		_memory_key = line.memory_key
		if line.rows.is_empty():
			add_theme_icon_override(&"folded_arrow", _fold_icon_substitute)
			_is_singular = true
			folded = true
		else:
			remove_theme_icon_override(&"folded_arrow")
			_is_singular = false
			folded = _memory.get(_memory_key, true)  # start closed

		var n_rows := line.rows.size()
		var n_children := _rows_vbox.get_child_count()
		while n_children < n_rows:
			_rows_vbox.add_child(PopulationsRow.new(_column_width, _bar_width, _cell_gutter,
					SUBGROUP_INDENT))
			n_children += 1
		for i in n_rows:
			var row: PopulationsRow = _rows_vbox.get_child(i)
			row.set_row(line.rows[i], is_bar_shown)
			row.show()
		for i in range(n_rows, n_children):
			var unused_row: Control = _rows_vbox.get_child(i)
			unused_row.hide()


	func _on_folding_changed(is_folded_: bool) -> void:
		if !_is_singular:
			_memory[_memory_key] = is_folded_
			return
		if !is_folded_:  # a line with no rows can't be unfolded
			fold()


	func _resize(gui_size: int) -> void:
		var multiplier := IVCoreSettings.gui_size_multipliers[gui_size]
		_gutter.custom_minimum_size.x = _cell_gutter * multiplier
		var cell_width := _column_width * multiplier
		for cell in _cells:
			cell.custom_minimum_size.x = cell_width


	func _settings_listener(setting: StringName, value: Variant) -> void:
		if setting == &"gui_size":
			var gui_size: int = value
			_resize(gui_size)


class PopulationsRow extends HBoxContainer:
	# One row a line unfolds to. The name fills the left; the bar and cells hug the right so
	# they line up with the line's right-aligned title control.

	var _indent_spacer := Control.new()
	var _name_label := Label.new()
	var _bar: PopulationsBar
	var _cells: Array[Label] = []
	var _gutter := Control.new()
	var _column_width: float
	var _cell_gutter: float
	var _indent: float


	func _init(column_width: float, bar_width: float, cell_gutter: float, indent: float) -> void:
		_column_width = column_width
		_cell_gutter = cell_gutter
		_indent = indent
		size_flags_horizontal = SIZE_FILL
		add_theme_constant_override(&"separation", 0)  # explicit gutters/widths only
		add_child(_indent_spacer)
		_name_label.clip_text = true
		_name_label.size_flags_horizontal = SIZE_EXPAND_FILL
		add_child(_name_label)
		_bar = PopulationsBar.new(bar_width)
		add_child(_bar)
		_cells.resize(N_CELLS)
		for i in N_CELLS:
			var cell := ITabPopulations._make_cell_label()
			add_child(cell)
			_cells[i] = cell
		add_child(_gutter)
		var gui_size: int = IVSettingsManager.get_setting(&"gui_size")
		_resize(gui_size)
		IVSettingsManager.changed.connect(_settings_listener)


	func set_row(line: LineData, is_bar_shown: bool) -> void:
		_name_label.text = line.title
		_bar.visible = is_bar_shown
		_bar.set_share(line.share, line.bar_tone)
		ITabPopulations._apply_cells(_cells, line.cells, line.tooltips, line.tones)


	func _resize(gui_size: int) -> void:
		var multiplier := IVCoreSettings.gui_size_multipliers[gui_size]
		_indent_spacer.custom_minimum_size.x = _indent * multiplier
		_gutter.custom_minimum_size.x = _cell_gutter * multiplier
		var cell_width := _column_width * multiplier
		for cell in _cells:
			cell.custom_minimum_size.x = cell_width


	func _settings_listener(setting: StringName, value: Variant) -> void:
		if setting == &"gui_size":
			var gui_size: int = value
			_resize(gui_size)


class PopulationsBar extends Control:
	# A share as a horizontal bar, from empty to the full width at 1.0.

	var _fill := ColorRect.new()
	var _bar_width: float


	func _init(bar_width: float) -> void:
		_bar_width = bar_width
		mouse_filter = MOUSE_FILTER_IGNORE
		_fill.mouse_filter = MOUSE_FILTER_IGNORE
		_fill.anchor_top = 0.3
		_fill.anchor_bottom = 0.7
		_fill.anchor_left = 0.05
		add_child(_fill)
		var gui_size: int = IVSettingsManager.get_setting(&"gui_size")
		_resize(gui_size)
		IVSettingsManager.changed.connect(_settings_listener)


	func set_share(share: float, tone: int) -> void:
		if is_nan(share):
			_fill.hide()
			return
		_fill.show()
		_fill.anchor_right = 0.05 + 0.9 * clampf(share, 0.0, 1.0)
		_fill.color = ITabPopulations._get_tone_color(tone)


	func _resize(gui_size: int) -> void:
		var multiplier := IVCoreSettings.gui_size_multipliers[gui_size]
		custom_minimum_size.x = _bar_width * multiplier


	func _settings_listener(setting: StringName, value: Variant) -> void:
		if setting == &"gui_size":
			var gui_size: int = value
			_resize(gui_size)
