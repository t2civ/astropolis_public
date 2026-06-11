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
## In v1 only the income statement carries line items: revenue and cost-of-goods
## groups (each expandable to its per-activity leaves) plus a derived gross-profit
## line. The other statements light up in later development steps. Hovering a
## dollar value shows its per-quarter history.
##
## Subtab indices follow row enumerations in [code]financial_statements.tsv[/code].

const SCENE := "res://public/ui/itab_budget.tscn"  ## Scene file for instancing.

const SUBGROUP_INDENT := 25


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
var base_column_width := 95.0

# table indexing
var _db_tables := IVTableData.db_tables
var _n_financial_items: int = IVTableData.table_n_rows[&"financial_items"]
var _item_names: Array[StringName] = _db_tables[&"financial_items"][&"name"]
var _item_subtotals: Array[int] = _db_tables[&"financial_items"][&"subtotal_group"]
var _item_statements: Array[int] = _db_tables[&"financial_items"][&"statement"]
var _statement_names: Array[StringName] = IVTableData.get_enumeration_array(&"financial_statements")
var _subtotal_names: Array[StringName] = IVTableData.get_enumeration_array(&"financial_subtotals")
var _subtotal_revenue := IVTableData.get_row(&"FINANCIAL_SUBTOTAL_REVENUE")
var _subtotal_cost_of_goods := IVTableData.get_row(&"FINANCIAL_SUBTOTAL_COST_OF_GOODS")
var _subtotal_gross_profit := IVTableData.get_row(&"FINANCIAL_SUBTOTAL_GROSS_PROFIT")
var _income_statement := IVTableData.get_row(&"FINANCIAL_STATEMENT_INCOME")
var _usd_inv: float = 1.0 / IVUnits.unit_multipliers[&"$"]

# financial_items entity-name keys for leaf rows; rendered via Label
# auto-translation (entities.csv). Cached so proxy-thread reads stay safe.
var _item_keys: Array[String] = []

var _selection_manager: AstroSelectionManager
var _suppress_tab_listener := true

# built in code (see _build_ui)
var _tab_container: TabContainer
var _no_budget_label: Label
var _content_vboxes: Array[VBoxContainer] = []
var _scrolls: Array[ScrollContainer] = []
var _footers: Array[Control] = []
var _empty_labels: Array[Label] = []

@warning_ignore("unsafe_property_access")
@onready var _memory: Dictionary = get_parent().memory # group open states


func _ready() -> void:
	_precompute_display_names()
	IVStateManager.about_to_free_procedural_nodes.connect(_clear_procedural)
	visibility_changed.connect(_update_tab)
	_selection_manager = IVSelectionManager.get_selection_manager(self)
	_selection_manager.selection_changed.connect(_update_tab)
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
	_item_keys.resize(_n_financial_items)
	for item in _n_financial_items:
		_item_keys[item] = String(_item_names[item])


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

	var n_statements := _statement_names.size()
	_content_vboxes.resize(n_statements)
	_scrolls.resize(n_statements)
	_footers.resize(n_statements)
	_empty_labels.resize(n_statements)
	for statement in n_statements:
		var tab := VBoxContainer.new()
		tab.name = String(_statement_names[statement])  # node name auto-translates as tab title
		_tab_container.add_child(tab)

		var scroll := ScrollContainer.new()
		scroll.size_flags_horizontal = SIZE_EXPAND_FILL
		scroll.size_flags_vertical = SIZE_EXPAND_FILL
		tab.add_child(scroll)
		var content := VBoxContainer.new()
		content.size_flags_horizontal = SIZE_EXPAND_FILL
		content.size_flags_vertical = SIZE_EXPAND_FILL
		scroll.add_child(content)

		var footer := BudgetRow.new(base_column_width, false)
		footer.hide()
		tab.add_child(footer)

		var empty_label := Label.new()
		empty_label.text = "No line items."
		empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_label.hide()
		tab.add_child(empty_label)

		_content_vboxes[statement] = content
		_scrolls[statement] = scroll
		_footers[statement] = footer
		_empty_labels[statement] = empty_label

	_tab_container.tab_changed.connect(_select_tab)


func _select_tab(tab: int) -> void:
	if !_suppress_tab_listener:
		_on_ready_tab = tab
	current_tab = tab
	_update_tab()


func _update_tab(_dummy := false) -> void:
	if !visible or !IVStateManager.running:
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
	var groups := []
	var footer := []

	# v1: only the income statement is populated.
	if tab == _income_statement:
		var subtotals := proxy.get_financials_subtotals()
		var accountings := proxy.get_financials_accountings().duplicate()
		var revenue_history := proxy.get_financials_revenue_history()
		var cogs_history := proxy.get_financials_cost_of_goods_sold_history()
		groups.append(_collect_group(proxy, accountings, _subtotal_revenue,
				String(_subtotal_names[_subtotal_revenue]), subtotals[_subtotal_revenue],
				revenue_history))
		groups.append(_collect_group(proxy, accountings, _subtotal_cost_of_goods,
				String(_subtotal_names[_subtotal_cost_of_goods]), subtotals[_subtotal_cost_of_goods],
				cogs_history))
		var gross_profit: float = subtotals[_subtotal_revenue] - subtotals[_subtotal_cost_of_goods]
		var gross_profit_history := _subtract_histories(revenue_history, cogs_history)
		footer = [String(_subtotal_names[_subtotal_gross_profit]), gross_profit, gross_profit_history]

	_update_tab_display.call_deferred(target_name, tab, groups, footer)


func _collect_group(proxy: Proxy, accountings: Dictionary[int, float], subtotal: int, title: String,
		subtotal_value: float, subtotal_history: PackedFloat64Array) -> Array:
	# Leaves in table order, only those present (sparse) and matching this group.
	var rows := []
	for item in _n_financial_items:
		if _item_statements[item] != _income_statement:
			continue
		if _item_subtotals[item] != subtotal:
			continue
		if !accountings.has(item):
			continue
		var value: float = accountings[item]
		var history := proxy.get_financials_accounting_history(item)
		rows.append([_item_keys[item], value, history])
	return [title, subtotal_value, subtotal_history, rows]


func _subtract_histories(a: PackedFloat64Array, b: PackedFloat64Array) -> PackedFloat64Array:
	var n := maxi(a.size(), b.size())
	var result := PackedFloat64Array()
	result.resize(n)
	for q in n:
		var av := a[q] if q < a.size() else 0.0
		var bv := b[q] if q < b.size() else 0.0
		result[q] = av - bv
	return result


# ******************************** MAIN THREAD ********************************

func _update_tab_display(_target_name: StringName, tab: int, groups: Array, footer: Array) -> void:
	_no_budget_label.hide()
	_tab_container.show()

	var content: VBoxContainer = _content_vboxes[tab]
	var scroll: ScrollContainer = _scrolls[tab]
	var footer_row: BudgetRow = _footers[tab]
	var empty_label: Label = _empty_labels[tab]

	if groups.is_empty() and footer.is_empty():
		scroll.hide()
		footer_row.hide()
		empty_label.show()
		return
	empty_label.hide()
	scroll.show()

	# reuse-or-create BudgetGroups
	var n_groups := groups.size()
	var n_children := content.get_child_count()
	while n_children < n_groups:
		content.add_child(BudgetGroup.new(_memory, base_column_width))
		n_children += 1
	var i := 0
	while i < n_groups:
		var group_data: Array = groups[i]
		var title: String = group_data[0]
		var subtotal_value: float = group_data[1]
		var subtotal_history: PackedFloat64Array = group_data[2]
		var leaf_rows: Array = group_data[3]
		var budget_group: BudgetGroup = content.get_child(i)
		budget_group.set_group(tr(title), _format_money(subtotal_value),
				_history_tooltip(subtotal_history), _format_rows(leaf_rows))
		budget_group.show()
		i += 1
	while i < n_children:
		var unused_group: Control = content.get_child(i)
		unused_group.hide()
		i += 1

	if footer.is_empty():
		footer_row.hide()
	else:
		var footer_name: String = footer[0]
		var footer_value: float = footer[1]
		var footer_history: PackedFloat64Array = footer[2]
		footer_row.set_row(footer_name, _format_money(footer_value), _history_tooltip(footer_history))
		footer_row.show()


func _format_rows(rows_data: Array) -> Array:
	var formatted := []
	for row_data: Array in rows_data:
		var value: float = row_data[1]
		var history: PackedFloat64Array = row_data[2]
		formatted.append([row_data[0], _format_money(value), _history_tooltip(history)])
	return formatted


func _format_money(value: float) -> String:
	return IVQFormat.modified_named_number(value, 3, IVQFormat.TextFormat.SHORT_MIXED_CASE,
			false, 999999.5, "$", "", _usd_inv)


func _history_tooltip(history: PackedFloat64Array) -> String:
	var n := history.size()
	if n == 0:
		return "No completed quarters yet."
	var lines := PackedStringArray()
	var start := maxi(0, n - 8)
	for q in range(start, n):
		lines.append(_format_money(history[q]))
	return "Completed quarters (oldest → newest):\n" + "\n".join(lines)


# ****************************** INNER CLASSES ********************************

class BudgetGroup extends FoldableContainer:
	# Foldable subtotal group: title bar shows the subtotal value; expands to its
	# per-activity leaf rows.

	var _rows_vbox := VBoxContainer.new()
	var _value_label := Label.new()
	var _memory: Dictionary
	var _base_column_width: float
	var _memory_key: String


	func _init(memory: Dictionary, base_column_width: float) -> void:
		_memory = memory
		_base_column_width = base_column_width
		size_flags_horizontal = SIZE_FILL
		_value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_value_label.size_flags_horizontal = SIZE_EXPAND_FILL
		add_title_bar_control(_value_label)
		add_child(_rows_vbox)
		folding_changed.connect(_on_folding_changed)
		var gui_size: int = IVSettingsManager.get_setting(&"gui_size")
		_resize(gui_size)
		IVSettingsManager.changed.connect(_settings_listener)


	func set_group(title_text: String, value_text: String, tooltip: String, rows: Array) -> void:
		title = title_text
		_value_label.text = value_text
		_value_label.tooltip_text = tooltip
		_memory_key = title_text
		folded = _memory.get(_memory_key, false)

		var n_rows := rows.size()
		var n_children := _rows_vbox.get_child_count()
		while n_children < n_rows:
			_rows_vbox.add_child(BudgetRow.new(_base_column_width, true))
			n_children += 1
		var i := 0
		while i < n_rows:
			var row_data: Array = rows[i]
			var row_name: String = row_data[0]
			var row_value: String = row_data[1]
			var row_tooltip: String = row_data[2]
			var row: BudgetRow = _rows_vbox.get_child(i)
			row.set_row(row_name, row_value, row_tooltip)
			row.show()
			i += 1
		while i < n_children:
			var unused_row: Control = _rows_vbox.get_child(i)
			unused_row.hide()
			i += 1


	func _on_folding_changed(is_folded_: bool) -> void:
		_memory[_memory_key] = is_folded_


	func _resize(gui_size: int) -> void:
		var column_width := _base_column_width * IVCoreSettings.gui_size_multipliers[gui_size]
		_value_label.custom_minimum_size.x = column_width


	func _settings_listener(setting: StringName, value: Variant) -> void:
		if setting == &"gui_size":
			var gui_size: int = value
			_resize(gui_size)


class BudgetRow extends HBoxContainer:
	# One account line: name (indented for leaves) + right-aligned dollar value.
	# History tooltip lives on the value label.

	var _name_label := Label.new()
	var _value_label := Label.new()
	var _base_column_width: float


	func _init(base_column_width: float, indented: bool) -> void:
		_base_column_width = base_column_width
		size_flags_horizontal = SIZE_FILL
		if indented:
			var spacer := Control.new()
			spacer.size_flags_horizontal = SIZE_SHRINK_BEGIN
			spacer.custom_minimum_size.x = SUBGROUP_INDENT
			add_child(spacer)
		_name_label.size_flags_horizontal = SIZE_EXPAND_FILL
		add_child(_name_label)
		_value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		add_child(_value_label)
		var gui_size: int = IVSettingsManager.get_setting(&"gui_size")
		_resize(gui_size)
		IVSettingsManager.changed.connect(_settings_listener)


	func set_row(name_text: String, value_text: String, tooltip: String) -> void:
		_name_label.text = name_text
		_value_label.text = value_text
		_value_label.tooltip_text = tooltip


	func _resize(gui_size: int) -> void:
		var column_width := _base_column_width * IVCoreSettings.gui_size_multipliers[gui_size]
		_value_label.custom_minimum_size.x = column_width


	func _settings_listener(setting: StringName, value: Variant) -> void:
		if setting == &"gui_size":
			var gui_size: int = value
			_resize(gui_size)
