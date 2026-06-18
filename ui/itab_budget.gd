# itab_budget.gd
# This file is part of Astropolis
# https://t2civ.com
# *****************************************************************************
# Copyright 2019-2026 Charlie Whitfield; ALL RIGHTS RESERVED
# Astropolis is a registered trademark of Charlie Whitfield in the US
# *****************************************************************************
class_name ITabBudget
extends MarginContainer

## "Budget" tab subpanel for [InfoPanel]. Shows the selected entity's chart of
## accounts as one subtab per financial statement (income, cash flow, balance).
##
## The income statement shows revenue and cost-of-goods groups (each expandable
## to its per-activity leaves) plus a derived gross-profit line. The cash-flow
## statement shows inflow and outflow groups (by per-leaf direction) plus a
## derived net-cash-flow line. The balance statement lights up in a later
## development step.
##
## Each statement is a grid of recent quarters, newest at right. A header row
## labels the quarters ("2025Q1", ...) and its leftmost cell names the USD
## display unit; the "<" / ">" buttons shift the visible quarter window. Display
## values are scaled on the fly so most land in the 1–999 range.
##
## Subtab indices follow [code]Enums.StatementTypes[/code].

const SCENE := "res://public/ui/itab_budget.tscn"  ## Scene file for instancing.

const SUBGROUP_INDENT := 25

# Subtotal indices into the proxy's dense subtotals array; MUST match the
# SUBTOTAL_* order in the financials components (server/proxy).
const SUBTOTAL_REVENUE := 0
const SUBTOTAL_COST_OF_GOODS := 1
const SUBTOTAL_OPERATING_EXPENSE := 8

# Bounds of the available LABEL_USD_* magnitude units (thousands..quintillions).
const USD_MIN_EXPONENT := 1
const USD_MAX_EXPONENT := 6


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
var label_width := 110.0  ## Min width of the leftmost name/label region.
var column_width := 58.0  ## Min width of each quarter column.
var n_visible_quarters := 6  ## Number of quarter columns shown at once.
var arrow_width := 24.0  ## Min width of the "<" / ">" shift buttons and matching row gutters.
var foldable_indent := 20.0  ## Foldable title left-lead (fold-icon + style-box margin); aligns header/footer names with group titles.
var scroll_correction := 7.0  ## Trailing spacer on the out-of-scroll header/footer; offsets their columns to match the in-scroll content past the vertical scrollbar.

# table indexing
var _db_tables := IVTableData.db_tables
var _n_line_items: int = IVTableData.table_n_rows[&"line_items"]
var _item_names: Array[StringName] = _db_tables[&"line_items"][&"name"]
var _item_statements: Array[int] = _db_tables[&"line_items"][&"statement"]
var _statement_keys := Enums.StatementTypes.keys()
var _income_statement := Enums.StatementTypes.STATEMENT_INCOME
var _cash_flow_statement := Enums.StatementTypes.STATEMENT_CASH_FLOW
var _balance_statement := Enums.StatementTypes.STATEMENT_BALANCE
var _usd_inv: float = 1.0 / IVUnits.unit_multipliers[&"$"]

# line_items entity-name keys for leaf rows, rendered via Label auto-translation
# (entities.csv). _item_subtotals maps each leaf to its base income subtotal index
# (SUBTOTAL_REVENUE or SUBTOTAL_COST_OF_GOODS); _item_balance_classes maps each
# balance leaf to its Enums.BalanceClasses. All cached so proxy-thread reads stay safe.
var _item_keys: Array[String] = []
var _item_subtotals := PackedInt32Array()
var _item_balance_classes := PackedInt32Array()

var _selection_manager: AstroSelectionManager
var _suppress_tab_listener := true

# Last data pushed to the main thread, retained so window shifts re-render
# without another proxy-thread round trip. Series are per-quarter, oldest first,
# with the current (incomplete) quarter last.
var _display_name := &""
var _display_tab := -1
var _display_ordinal_qtr := -1
var _display_groups: Array = []  # [[title, subtotal_series, [[leaf_key, leaf_series], ...]], ...]
var _display_footer: Array = []  # [name, series] or []
var _display_unit := ""  # localized USD magnitude-unit label
var _display_scale := 1.0  # internal-value -> display multiplier (USD inverse / 1000^exponent)
var _window_offset := 0  # quarters scrolled back from newest; 0 shows the current quarter

# Blank icon used as the fold-arrow override for a group with no leaves; keeps
# the title's left lead while hiding the (non-functional) arrow.
var _fold_icon_substitute := MeshTexture.new()

# built in code (see _build_ui)
var _tab_container: TabContainer
var _no_budget_label: Label
var _content_vboxes: Array[VBoxContainer] = []
var _scrolls: Array[ScrollContainer] = []
var _headers: Array[BudgetHeaderRow] = []
var _footers: Array[BudgetGroup] = []  # gross-profit line, a leafless foldable
var _empty_labels: Array[Label] = []

@warning_ignore("unsafe_property_access")
@onready var _memory: Dictionary = get_parent().memory # group open states


func _ready() -> void:
	_precompute_display_names()
	IVStateManager.about_to_free_procedural_nodes.connect(_clear_procedural)
	visibility_changed.connect(_update_tab)
	_selection_manager = IVSelectionManager.get_selection_manager(self)
	_selection_manager.selection_changed.connect(_update_tab)
	_fold_icon_substitute.image_size.x = 16  # match the fold-arrow width
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


## Refreshes the active budget subtab. Wired to [InfoTabContainer]'s shared 1 s timer.
func timer_update() -> void:
	_update_tab()


func _precompute_display_names() -> void:
	var item_revenue: Array[bool] = _db_tables[&"line_items"][&"revenue"]
	var item_operating_expense: Array[bool] = _db_tables[&"line_items"][&"operating_expense"]
	var item_balance_classes: Array[int] = _db_tables[&"line_items"][&"balance_class"]
	_item_keys.resize(_n_line_items)
	_item_subtotals.resize(_n_line_items)
	_item_balance_classes.resize(_n_line_items)
	for item in _n_line_items:
		_item_keys[item] = String(_item_names[item])
		if item_operating_expense[item]:
			_item_subtotals[item] = SUBTOTAL_OPERATING_EXPENSE
		else:
			_item_subtotals[item] = SUBTOTAL_REVENUE if item_revenue[item] else SUBTOTAL_COST_OF_GOODS
		_item_balance_classes[item] = item_balance_classes[item]


func _build_ui() -> void:
	_tab_container = TabContainer.new()
	_tab_container.size_flags_horizontal = SIZE_EXPAND_FILL
	_tab_container.size_flags_vertical = SIZE_EXPAND_FILL
	add_child(_tab_container)

	_no_budget_label = Label.new()
	_no_budget_label.text = "No budget data for this selection."
	_no_budget_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_no_budget_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_no_budget_label.hide()
	add_child(_no_budget_label)

	var n_statements := _statement_keys.size()
	_content_vboxes.resize(n_statements)
	_scrolls.resize(n_statements)
	_headers.resize(n_statements)
	_footers.resize(n_statements)
	_empty_labels.resize(n_statements)
	for statement in n_statements:
		var tab := VBoxContainer.new()
		var statement_key: String = _statement_keys[statement]
		tab.name = statement_key  # node name auto-translates as tab title (entities.csv)
		_tab_container.add_child(tab)

		var header := BudgetHeaderRow.new(label_width, column_width, arrow_width,
				foldable_indent, scroll_correction, n_visible_quarters)
		header.shift_requested.connect(_shift_window)
		header.hide()
		tab.add_child(header)

		var scroll := ScrollContainer.new()
		scroll.size_flags_horizontal = SIZE_EXPAND_FILL
		scroll.size_flags_vertical = SIZE_EXPAND_FILL
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		tab.add_child(scroll)
		var content := VBoxContainer.new()
		content.size_flags_horizontal = SIZE_EXPAND_FILL
		content.size_flags_vertical = SIZE_EXPAND_FILL
		scroll.add_child(content)

		# Groups and the gross-profit footer live inside the scroll — the whole
		# statement is one scrollable unit; only the header stays pinned outside.
		# The footer is itself a leafless foldable so it shares the groups' styling.
		var groups_vbox := VBoxContainer.new()
		groups_vbox.size_flags_horizontal = SIZE_EXPAND_FILL
		content.add_child(groups_vbox)

		var footer := BudgetGroup.new(_memory, label_width, column_width, arrow_width,
				n_visible_quarters, _fold_icon_substitute)
		footer.hide()
		content.add_child(footer)

		var empty_label := Label.new()
		empty_label.text = "No line items."
		empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_label.hide()
		tab.add_child(empty_label)

		_content_vboxes[statement] = groups_vbox
		_scrolls[statement] = scroll
		_headers[statement] = header
		_footers[statement] = footer
		_empty_labels[statement] = empty_label

	_tab_container.tab_changed.connect(_select_tab)


func _select_tab(tab: int) -> void:
	if !_suppress_tab_listener:
		_on_ready_tab = tab
	current_tab = tab
	_update_tab()


func _update_tab(_dummy := false) -> void:
	if !visible or !IVStateManager.is_threads_allowed():
		return
	var target_name := _selection_manager.get_name()
	if MainThreadGlobal.has_development(target_name):
		MainThreadGlobal.call_proxy_thread(_get_proxy_data.bind(target_name))
	else:
		_update_no_budget()


func _update_no_budget() -> void:
	_tab_container.hide()
	_no_budget_label.show()


# ******************************* PROXY THREAD ********************************

func _get_proxy_data(target_name: StringName) -> void:
	var proxy := Proxy.get_proxy_by_name(target_name)
	if !proxy or !proxy.has_financials():
		_update_no_budget.call_deferred()
		return

	var tab := current_tab
	var ordinal_qtr := proxy.ordinal_qtr
	var groups := []
	var footer := []

	if tab == _income_statement:
		# Income waterfall: gross profit renders as a leafless subtotal line (between
		# cost-of-goods and the operating-expense group); operating income is the
		# bottom-line footer. The opex group is summed from its leaves (no tracked-
		# subtotal history getter), like the cash-flow groups.
		var subtotals := proxy.get_financials_subtotals()
		var accountings := proxy.get_financials_accountings().duplicate()
		var revenue_history := proxy.get_financials_revenue_history()
		var cogs_history := proxy.get_financials_cost_of_goods_sold_history()
		groups.append(_collect_group(proxy, accountings, SUBTOTAL_REVENUE,
				"SUBTOTAL_REVENUE", subtotals[SUBTOTAL_REVENUE], revenue_history))
		groups.append(_collect_group(proxy, accountings, SUBTOTAL_COST_OF_GOODS,
				"SUBTOTAL_COST_OF_GOODS", subtotals[SUBTOTAL_COST_OF_GOODS], cogs_history))
		var revenue_series := _make_series(revenue_history, subtotals[SUBTOTAL_REVENUE])
		var cogs_series := _make_series(cogs_history, subtotals[SUBTOTAL_COST_OF_GOODS])
		var gross_profit_series := _subtract_series(revenue_series, cogs_series)
		groups.append(["SUBTOTAL_GROSS_PROFIT", gross_profit_series, []])
		var opex_group := _collect_summed_group(proxy, accountings, _income_statement,
				_item_subtotals, SUBTOTAL_OPERATING_EXPENSE, "SUBTOTAL_OPERATING_EXPENSE")
		groups.append(opex_group)
		var opex_series: PackedFloat64Array = opex_group[1]
		footer = ["SUBTOTAL_OPERATING_INCOME", _subtract_series(gross_profit_series, opex_series)]
	elif tab == _cash_flow_statement:
		# Inflow/outflow group series are summed from their leaf series (cash-flow
		# direction is per-leaf; only the net is a tracked subtotal).
		var accountings := proxy.get_financials_accountings().duplicate()
		var inflow_group := _collect_summed_group(proxy, accountings, _cash_flow_statement,
				_item_subtotals, SUBTOTAL_REVENUE, "CASH_INFLOWS")
		var outflow_group := _collect_summed_group(proxy, accountings, _cash_flow_statement,
				_item_subtotals, SUBTOTAL_COST_OF_GOODS, "CASH_OUTFLOWS")
		groups.append(inflow_group)
		groups.append(outflow_group)
		var inflow_series: PackedFloat64Array = inflow_group[1]
		var outflow_series: PackedFloat64Array = outflow_group[1]
		footer = ["SUBTOTAL_NET_CASH_FLOW", _subtract_series(inflow_series, outflow_series)]
	elif tab == _balance_statement:
		var accountings := proxy.get_financials_accountings().duplicate()
		# Asset / liability / equity groups (by per-leaf balance_class); a group with
		# no nonzero leaf is dropped so unused sections stay hidden. No footer (the
		# balancing identity is a later step).
		_append_balance_group(groups, proxy, accountings,
				Enums.BalanceClasses.BALANCE_CLASS_ASSET, "SUBTOTAL_ASSETS")
		_append_balance_group(groups, proxy, accountings,
				Enums.BalanceClasses.BALANCE_CLASS_LIABILITY, "SUBTOTAL_LIABILITIES")
		_append_balance_group(groups, proxy, accountings,
				Enums.BalanceClasses.BALANCE_CLASS_EQUITY, "SUBTOTAL_EQUITY")

	_update_tab_display.call_deferred(target_name, tab, ordinal_qtr, groups, footer)


func _collect_group(proxy: Proxy, accountings: Dictionary[int, float], subtotal: int, title: String,
		subtotal_value: float, subtotal_history: PackedFloat64Array) -> Array:
	# Leaves in table order, matching this group, with any nonzero quarter (the
	# current value drops to 0 right after rollover, so history must count too).
	var rows := []
	for item in _n_line_items:
		if _item_statements[item] != _income_statement:
			continue
		if _item_subtotals[item] != subtotal:
			continue
		var current_value: float = accountings.get(item, 0.0)
		var leaf_series := _make_series(proxy.get_financials_accounting_history(item), current_value)
		if !_has_nonzero(leaf_series):
			continue
		rows.append([_item_keys[item], leaf_series])
	return [title, _make_series(subtotal_history, subtotal_value), rows]


func _collect_summed_group(proxy: Proxy, accountings: Dictionary[int, float], statement: int,
		classifier: PackedInt32Array, class_value: int, title: String) -> Array:
	# Like _collect_group, but the group series is summed from its leaf series
	# rather than read from a tracked subtotal. Used for cash-flow direction groups
	# (classifier _item_subtotals, where only the net is a tracked subtotal) and
	# balance-sheet groups (classifier _item_balance_classes). Leaves in table order,
	# matching this statement and classifier value, with any nonzero quarter.
	var rows := []
	var group_series := PackedFloat64Array()
	for item in _n_line_items:
		if _item_statements[item] != statement:
			continue
		if classifier[item] != class_value:
			continue
		var current_value: float = accountings.get(item, 0.0)
		var leaf_series := _make_series(proxy.get_financials_accounting_history(item), current_value)
		_add_series(group_series, leaf_series)
		if !_has_nonzero(leaf_series):
			continue
		rows.append([_item_keys[item], leaf_series])
	return [title, group_series, rows]


func _append_balance_group(groups: Array, proxy: Proxy, accountings: Dictionary[int, float],
		balance_class: int, title: String) -> void:
	# Appends the balance-class group unless it has no nonzero leaf (keeps empty
	# Liabilities / Equity sections hidden).
	var group := _collect_summed_group(proxy, accountings, _balance_statement,
			_item_balance_classes, balance_class, title)
	var rows: Array = group[2]
	if !rows.is_empty():
		groups.append(group)


func _add_series(into: PackedFloat64Array, add: PackedFloat64Array) -> void:
	if into.size() < add.size():
		into.resize(add.size())
	for q in add.size():
		into[q] += add[q]


func _has_nonzero(series: PackedFloat64Array) -> bool:
	for value in series:
		if value != 0.0:
			return true
	return false


func _make_series(history: PackedFloat64Array, current_value: float) -> PackedFloat64Array:
	var series := history.duplicate()
	series.append(current_value)
	return series


func _subtract_series(a: PackedFloat64Array, b: PackedFloat64Array) -> PackedFloat64Array:
	var n := maxi(a.size(), b.size())
	var result := PackedFloat64Array()
	result.resize(n)
	for q in n:
		var av := a[q] if q < a.size() else 0.0
		var bv := b[q] if q < b.size() else 0.0
		result[q] = av - bv
	return result


# ******************************** MAIN THREAD ********************************

func _update_tab_display(target_name: StringName, tab: int, ordinal_qtr: int,
		groups: Array, footer: Array) -> void:
	_no_budget_label.hide()
	_tab_container.show()

	if target_name != _display_name or tab != _display_tab:
		_window_offset = 0
	_display_name = target_name
	_display_tab = tab
	_display_ordinal_qtr = ordinal_qtr
	_display_groups = groups
	_display_footer = footer

	# Pick the USD display unit so most values land in the 1–999 range.
	var dollar_values := PackedFloat64Array()
	for group_data: Array in groups:
		var subtotal_series: PackedFloat64Array = group_data[1]
		_gather_dollar_values(subtotal_series, dollar_values)
		for leaf_row: Array in group_data[2]:
			var leaf_series: PackedFloat64Array = leaf_row[1]
			_gather_dollar_values(leaf_series, dollar_values)
	if !footer.is_empty():
		var footer_series: PackedFloat64Array = footer[1]
		_gather_dollar_values(footer_series, dollar_values)
	var exponent := clampi(Utils.get_modal_base1000_exponent(dollar_values),
			USD_MIN_EXPONENT, USD_MAX_EXPONENT)
	_display_scale = _usd_inv * pow(1000.0, -float(exponent))
	_display_unit = Utils.get_usd_unit_string(exponent)

	_render_current()


func _render_current() -> void:
	var tab := _display_tab
	var content: VBoxContainer = _content_vboxes[tab]
	var scroll: ScrollContainer = _scrolls[tab]
	var header: BudgetHeaderRow = _headers[tab]
	var footer_group: BudgetGroup = _footers[tab]
	var empty_label: Label = _empty_labels[tab]

	if _display_groups.is_empty() and _display_footer.is_empty():
		header.hide()
		scroll.hide()
		footer_group.hide()
		empty_label.show()
		return
	empty_label.hide()
	scroll.show()
	header.show()

	var total_quarters := _get_total_quarters()
	var max_offset := maxi(0, total_quarters - n_visible_quarters)
	_window_offset = clampi(_window_offset, 0, max_offset)
	header.set_header(_display_unit, _quarter_labels(total_quarters),
			_window_offset > 0, _window_offset < max_offset)

	# reuse-or-create BudgetGroups
	var n_groups := _display_groups.size()
	var n_children := content.get_child_count()
	while n_children < n_groups:
		content.add_child(BudgetGroup.new(_memory, label_width, column_width, arrow_width,
				n_visible_quarters, _fold_icon_substitute))
		n_children += 1
	var i := 0
	while i < n_groups:
		var group_data: Array = _display_groups[i]
		var title: String = group_data[0]
		var subtotal_series: PackedFloat64Array = group_data[1]
		var leaf_rows: Array = group_data[2]
		var formatted_leaves := []
		for leaf_row: Array in leaf_rows:
			var leaf_series: PackedFloat64Array = leaf_row[1]
			formatted_leaves.append([leaf_row[0], _format_cells(leaf_series)])
		var budget_group: BudgetGroup = content.get_child(i)
		budget_group.set_group(tr(title), _format_cells(subtotal_series), formatted_leaves)
		budget_group.show()
		i += 1
	while i < n_children:
		var unused_group: Control = content.get_child(i)
		unused_group.hide()
		i += 1

	if _display_footer.is_empty():
		footer_group.hide()
	else:
		var footer_name: String = _display_footer[0]
		var footer_series: PackedFloat64Array = _display_footer[1]
		footer_group.set_group(tr(footer_name), _format_cells(footer_series), [])
		footer_group.show()


func _shift_window(direction: int) -> void:
	_window_offset += direction
	_render_current()


func _gather_dollar_values(series: PackedFloat64Array, into: PackedFloat64Array) -> void:
	for value in series:
		into.append(value * _usd_inv)


func _get_total_quarters() -> int:
	if !_display_groups.is_empty():
		var group_data: Array = _display_groups[0]
		var series: PackedFloat64Array = group_data[1]
		return series.size()
	if !_display_footer.is_empty():
		var series: PackedFloat64Array = _display_footer[1]
		return series.size()
	return 0


# Maps left-to-right column index to its series index, given the visible window
# (newest at right, scrolled back by _window_offset). Returns -1 for a column
# with no quarter (when fewer quarters exist than columns).
func _column_series_index(column: int, total_quarters: int) -> int:
	var newest_visible := total_quarters - 1 - _window_offset
	var index := newest_visible - (n_visible_quarters - 1 - column)
	return index if index >= 0 and index < total_quarters else -1


func _format_cells(series: PackedFloat64Array) -> PackedStringArray:
	var total_quarters := series.size()
	var cells := PackedStringArray()
	cells.resize(n_visible_quarters)
	for column in n_visible_quarters:
		var index := _column_series_index(column, total_quarters)
		cells[column] = IVQFormat.number(series[index] * _display_scale) if index != -1 else ""
	return cells


func _quarter_labels(total_quarters: int) -> PackedStringArray:
	var labels := PackedStringArray()
	labels.resize(n_visible_quarters)
	for column in n_visible_quarters:
		var index := _column_series_index(column, total_quarters)
		if index == -1:
			labels[column] = ""
			continue
		var ordinal := _display_ordinal_qtr - (total_quarters - 1 - index)
		labels[column] = _format_quarter(ordinal)
	return labels


func _format_quarter(ordinal_qtr: int) -> String:
	# Year shown only on Q1 to keep the header uncluttered (e.g. "2025Q1", "Q2").
	var quarter := ordinal_qtr % 4 + 1
	if quarter == 1:
		@warning_ignore("integer_division")
		var year := ordinal_qtr / 4
		return "%dQ1" % year
	return "Q%d" % quarter


# ****************************** INNER CLASSES ********************************
# Columns are right-anchored. Foldable groups are full width, with the name on
# the native title and only the value cells in a right-aligned title control, so
# column position is independent of the title text. Leaf rows (in the foldable
# body) and the title cells share the in-scroll right edge. The header and footer
# sit outside the scroll, so a trailing scroll_correction spacer pushes their
# columns in to match the content past the vertical scrollbar. (Pattern mirrors
# itab_operations.gd.)

class BudgetHeaderRow extends HBoxContainer:
	# Grid header (outside the scroll): the USD unit label fills the left; the
	# "<" / ">" shift buttons flank the per-quarter labels; a trailing spacer
	# offsets the columns to clear the scrollbar.

	signal shift_requested(direction: int)  # +1 toward newer, -1 toward older

	var _indent_spacer := Control.new()
	var _unit_label := Label.new()
	var _older_button := Button.new()
	var _newer_button := Button.new()
	var _trailing_spacer := Control.new()
	var _cells: Array[Label] = []
	var _label_width: float
	var _column_width: float
	var _arrow_width: float
	var _foldable_indent: float
	var _scroll_correction: float


	func _init(label_width: float, column_width: float, arrow_width: float, foldable_indent: float,
			scroll_correction: float, n_columns: int) -> void:
		_label_width = label_width
		_column_width = column_width
		_arrow_width = arrow_width
		_foldable_indent = foldable_indent
		_scroll_correction = scroll_correction
		size_flags_horizontal = SIZE_FILL
		add_theme_constant_override(&"separation", 0)  # explicit gutters/widths only
		add_child(_indent_spacer)
		_unit_label.clip_text = true
		_unit_label.size_flags_horizontal = SIZE_EXPAND_FILL
		add_child(_unit_label)
		_older_button.text = "<"
		_older_button.pressed.connect(_on_older_pressed)
		add_child(_older_button)
		_cells.resize(n_columns)
		for c in n_columns:
			var cell := Label.new()
			cell.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			cell.clip_text = true
			add_child(cell)
			_cells[c] = cell
		_newer_button.text = ">"
		_newer_button.pressed.connect(_on_newer_pressed)
		add_child(_newer_button)
		add_child(_trailing_spacer)
		var gui_size: int = IVSettingsManager.get_setting(&"gui_size")
		_resize(gui_size)
		IVSettingsManager.changed.connect(_settings_listener)


	func set_header(unit_text: String, quarter_labels: PackedStringArray,
			can_go_newer: bool, can_go_older: bool) -> void:
		_unit_label.text = unit_text
		for c in _cells.size():
			_cells[c].text = quarter_labels[c]
		_newer_button.disabled = !can_go_newer
		_older_button.disabled = !can_go_older


	func _on_older_pressed() -> void:
		shift_requested.emit(1)


	func _on_newer_pressed() -> void:
		shift_requested.emit(-1)


	func _resize(gui_size: int) -> void:
		var multiplier := IVCoreSettings.gui_size_multipliers[gui_size]
		_indent_spacer.custom_minimum_size.x = _foldable_indent * multiplier
		_older_button.custom_minimum_size.x = _arrow_width * multiplier
		_newer_button.custom_minimum_size.x = _arrow_width * multiplier
		_trailing_spacer.custom_minimum_size.x = _scroll_correction * multiplier
		var cell_width := _column_width * multiplier
		for cell in _cells:
			cell.custom_minimum_size.x = cell_width


	func _settings_listener(setting: StringName, value: Variant) -> void:
		if setting == &"gui_size":
			var gui_size: int = value
			_resize(gui_size)


class BudgetGroup extends FoldableContainer:
	# Foldable subtotal group: the native title shows the group name; a right-aligned
	# title control shows the per-quarter subtotal cells; it expands to its per-activity
	# leaf rows. Full width, so the right-aligned cells sit at the content's right edge
	# regardless of title length — keeping columns aligned across groups. A group with
	# no leaves gets a blank fold-icon substitute (preserving the title's left lead) and
	# can't be unfolded.

	var _rows_vbox := VBoxContainer.new()
	var _cells: Array[Label] = []
	var _left_gutter := Control.new()
	var _right_gutter := Control.new()
	var _memory: Dictionary
	var _fold_icon_substitute: Texture2D
	var _label_width: float
	var _column_width: float
	var _arrow_width: float
	var _n_columns: int
	var _memory_key: String
	var _is_singular: bool


	func _init(memory: Dictionary, label_width: float, column_width: float, arrow_width: float,
			n_columns: int, fold_icon_substitute: Texture2D) -> void:
		_memory = memory
		_label_width = label_width
		_column_width = column_width
		_arrow_width = arrow_width
		_n_columns = n_columns
		_fold_icon_substitute = fold_icon_substitute
		size_flags_horizontal = SIZE_FILL  # full width; cells right-align to the content edge
		# Value cells go in a right-aligned title control (FoldableContainer's
		# native arrangement); the name uses the native title (see set_group).
		var block := HBoxContainer.new()
		block.add_theme_constant_override(&"separation", 0)  # explicit gutters/widths only
		block.add_child(_left_gutter)
		_cells.resize(n_columns)
		for c in n_columns:
			var cell := Label.new()
			cell.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			cell.clip_text = true
			block.add_child(cell)
			_cells[c] = cell
		block.add_child(_right_gutter)
		add_title_bar_control(block)
		add_child(_rows_vbox)
		folding_changed.connect(_on_folding_changed)
		var gui_size: int = IVSettingsManager.get_setting(&"gui_size")
		_resize(gui_size)
		IVSettingsManager.changed.connect(_settings_listener)


	func set_group(title_text: String, cells: PackedStringArray, leaf_rows: Array) -> void:
		title = title_text  # native title, left-aligned after the fold-icon
		for c in _cells.size():
			_cells[c].text = cells[c]
		_memory_key = title_text
		if leaf_rows.is_empty():
			add_theme_icon_override(&"folded_arrow", _fold_icon_substitute)
			_is_singular = true
			folded = true
		else:
			remove_theme_icon_override(&"folded_arrow")
			_is_singular = false
			folded = _memory.get(_memory_key, true)  # start closed

		var n_rows := leaf_rows.size()
		var n_children := _rows_vbox.get_child_count()
		while n_children < n_rows:
			_rows_vbox.add_child(BudgetRow.new(_label_width, _column_width, _arrow_width,
					_n_columns, SUBGROUP_INDENT, 0.0))
			n_children += 1
		var i := 0
		while i < n_rows:
			var row_data: Array = leaf_rows[i]
			var row_name: String = row_data[0]
			var row_cells: PackedStringArray = row_data[1]
			var row: BudgetRow = _rows_vbox.get_child(i)
			row.set_row(row_name, row_cells)
			row.show()
			i += 1
		while i < n_children:
			var unused_row: Control = _rows_vbox.get_child(i)
			unused_row.hide()
			i += 1


	func _on_folding_changed(is_folded_: bool) -> void:
		if !_is_singular:
			_memory[_memory_key] = is_folded_
			return
		if !is_folded_:  # a no-leaf group can't be unfolded
			fold()


	func _resize(gui_size: int) -> void:
		var multiplier := IVCoreSettings.gui_size_multipliers[gui_size]
		_left_gutter.custom_minimum_size.x = _arrow_width * multiplier
		_right_gutter.custom_minimum_size.x = _arrow_width * multiplier
		var cell_width := _column_width * multiplier
		for cell in _cells:
			cell.custom_minimum_size.x = cell_width


	func _settings_listener(setting: StringName, value: Variant) -> void:
		if setting == &"gui_size":
			var gui_size: int = value
			_resize(gui_size)


class BudgetRow extends HBoxContainer:
	# One account line (leaf or footer). The name fills the left; the gutter-flanked
	# value cells hug the right so they line up with the foldable's right-aligned
	# subtotal cells. A leaf passes trailing == 0; the out-of-scroll footer passes the
	# scroll correction so its columns clear the scrollbar like the header.

	var _indent_spacer := Control.new()
	var _name_label := Label.new()
	var _left_gutter := Control.new()
	var _right_gutter := Control.new()
	var _trailing_spacer := Control.new()
	var _cells: Array[Label] = []
	var _label_width: float
	var _column_width: float
	var _arrow_width: float
	var _indent: float
	var _trailing: float


	func _init(label_width: float, column_width: float, arrow_width: float, n_columns: int,
			indent: float, trailing: float) -> void:
		_label_width = label_width
		_column_width = column_width
		_arrow_width = arrow_width
		_indent = indent
		_trailing = trailing
		size_flags_horizontal = SIZE_FILL
		add_theme_constant_override(&"separation", 0)  # explicit gutters/widths only
		add_child(_indent_spacer)
		_name_label.clip_text = true
		_name_label.size_flags_horizontal = SIZE_EXPAND_FILL
		add_child(_name_label)
		add_child(_left_gutter)
		_cells.resize(n_columns)
		for c in n_columns:
			var cell := Label.new()
			cell.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			cell.clip_text = true
			add_child(cell)
			_cells[c] = cell
		add_child(_right_gutter)
		add_child(_trailing_spacer)
		var gui_size: int = IVSettingsManager.get_setting(&"gui_size")
		_resize(gui_size)
		IVSettingsManager.changed.connect(_settings_listener)


	func set_row(name_text: String, cells: PackedStringArray) -> void:
		_name_label.text = name_text
		for c in _cells.size():
			_cells[c].text = cells[c]


	func _resize(gui_size: int) -> void:
		var multiplier := IVCoreSettings.gui_size_multipliers[gui_size]
		_indent_spacer.custom_minimum_size.x = _indent * multiplier
		_name_label.custom_minimum_size.x = (_label_width - _indent) * multiplier
		_left_gutter.custom_minimum_size.x = _arrow_width * multiplier
		_right_gutter.custom_minimum_size.x = _arrow_width * multiplier
		_trailing_spacer.custom_minimum_size.x = _trailing * multiplier
		var cell_width := _column_width * multiplier
		for cell in _cells:
			cell.custom_minimum_size.x = cell_width


	func _settings_listener(setting: StringName, value: Variant) -> void:
		if setting == &"gui_size":
			var gui_size: int = value
			_resize(gui_size)
