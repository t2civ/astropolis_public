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
## accounts as one subtab per financial statement (income, cash flow, balance), and
## its budgets in the Funding subtab. A selected body shows links to the facilities
## at it instead.
##
## The income statement is a waterfall: revenue and cost-of-goods groups, a
## derived gross-profit line, an operating-expense group, a derived
## operating-income line, a tax group, and a derived net-income line; each
## group expands to its leaves. The cash-flow statement shows inflow and
## outflow groups (by per-leaf direction) plus a derived net-cash-flow line.
## The balance statement shows asset, liability, and equity groups. Each statement
## shows the facility's own account above its bottom line; a player's treasuries,
## booked at its administrative center, follow it, each as one group of its own
## (FINANCIAL_MODEL.md, "The accounts"). A line item kept per counterparty, such as a treasury's
## funding by facility, is a row for each counterparty, named by both.
##
## Each statement is a grid of recent quarters, newest at right. A header row
## labels the quarters ("2025Q1", ...) and its leftmost cell names the USD
## display unit; the "<" / ">" buttons shift the visible quarter window. Values
## show with SI prefixes ("55.5k").
##
## The Funding subtab shows budgets, each as a bar graph of its lines (FINANCIAL_MODEL.md,
## "Budgets"): its committed lines as shares of what it has to spend a year, and its discretionary
## lines as shares of what they leave, the rest of its budget last. At an administrative center or
## for a player it shows each of its player's treasuries' budgets, and at a facility its own budget,
## below its owners' lines for it where it isn't its player's center. Each bar is filled to what was
## drawn of its line last quarter, and a line that funds all its counterparty lacks spans the width,
## filled to what it drew of the budget. A line its owner sets, a treasury's funding of a facility
## and a facility's R&D and builds, shows the share it is set at.[br][br]
##
## Where this machine's human plays the player ([method PlayerProxy.is_local_human]), each line its
## owner sets has an Auto checkbox, checked while the player's AI sets it; unchecked, the line is
## held and its bar drags, up to what the rest of its budget leaves. With unlimited money
## ([code]ThreadsafeGlobal.sandbox_unlimited_money[/code]) each of its treasuries' budgets has one
## too, and unchecked its total is typed in. The Balance subtab shows such a treasury's cash as
## unbounded.
##
## The Funding subtab comes first, then placeholder grants and R&D subtabs, then the
## statements' subtabs in [code]Enums.StatementTypes[/code] order.

const SCENE := "res://public/ui/itab_budget.tscn"  ## Scene file for instancing.

const SUBGROUP_INDENT := 25

# Subtotal indices into the proxy's dense subtotals array; MUST match the
# SUBTOTAL_* order in the financials components (server/proxy).
const SUBTOTAL_REVENUE := 0
const SUBTOTAL_COST_OF_GOODS := 1
const SUBTOTAL_OPERATING_EXPENSE := 8
const SUBTOTAL_TAX := 10

const NO_VALUE := "—" ## Applies, but has no value now.
const UNBOUNDED := "∞" ## A line that funds all its counterparty lacks, or unlimited money.

const FUNDING_TAB := 0

# What a Funding subtab control sets, its first element; see _collect_funding.
enum Controls {
	CONTROL_BUDGET_SHARE, # a treasury's funding of a facility
	CONTROL_BUDGET_TARGET, # what a treasury spends a year
	CONTROL_BUILDS, # a facility's build share
	CONTROL_RESEARCH, # a facility's research share
}

# Placeholder subtabs after the Funding subtab: [tab title, text].
const PLACEHOLDER_TABS := [
	["Grants", """WIP

You can assist and (to some degree) influence the
R & D of your home nation here. (Mainly for agencies.)"""],
	["R&D", """WIP

Set R & D priorities for your own facilities here.
Pursue specific advancement in three broad categories:
Theory, Technology and Engineering."""],
]

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
var foldable_indent := 20.0  ## Foldable title left-lead (fold-icon + style-box margin); aligns the header's unit label with group titles.
var scroll_correction := 7.0  ## Trailing spacer on the out-of-scroll header; offsets its columns to match the in-scroll content past the vertical scrollbar.
var bar_width := 120.0  ## Min width of the Funding subtab's bars.
var auto_width := 40.0  ## Min width of the Funding subtab's Auto column.

# table indexing
var _db_tables := IVTableData.db_tables
var _n_line_items: int = IVTableData.table_n_rows[&"line_items"]
var _item_names: Array[StringName] = _db_tables[&"line_items"][&"name"]
var _item_statements: Array[int] = _db_tables[&"line_items"][&"statement"]
var _statement_keys := Enums.StatementTypes.keys()
var _account_keys := Enums.Accounts.keys()
var _income_statement := Enums.StatementTypes.STATEMENT_INCOME
var _cash_flow_statement := Enums.StatementTypes.STATEMENT_CASH_FLOW
var _balance_statement := Enums.StatementTypes.STATEMENT_BALANCE
var _first_statement_tab := 1 + PLACEHOLDER_TABS.size()
var _usd_inv: float = 1.0 / IVUnits.unit_multipliers[&"$"]

# line_items entity-name keys for leaf rows, rendered via Label auto-translation
# (entities.csv). _item_subtotals maps each income leaf to its base subtotal index
# (SUBTOTAL_REVENUE, SUBTOTAL_COST_OF_GOODS, SUBTOTAL_OPERATING_EXPENSE, or
# SUBTOTAL_TAX); _item_balance_classes maps each balance leaf to its
# Enums.BalanceClasses; _item_accounts maps each leaf to its Enums.Accounts, -1 for the
# facility's own; _item_keyed_bys maps each to its Enums.Counterparties, -1 for one kept once;
# _item_returns maps each that books a budget line's use to the one that books what came back of
# it, -1 for none. All cached so proxy-thread reads stay safe.
var _item_keys: Array[String] = []
var _item_subtotals := PackedInt32Array()
var _item_balance_classes := PackedInt32Array()
var _item_accounts := PackedInt32Array()
var _item_keyed_bys := PackedInt32Array()
var _item_returns := PackedInt32Array()
var _committed_items := PackedInt32Array() # a treasury's committed lines
var _funding_items := PackedInt32Array() # a treasury's funding of a facility, by Enums.Accounts
var _item_transfers_paid := -1
var _item_dividends_paid := -1
var _item_appropriations_paid := -1
var _item_funding_received := -1
var _item_payouts_paid := -1
var _item_interest_expense := -1
var _item_income_tax := -1
var _item_research_development := -1
var _item_fixed_assets := -1
var _upkeep_items := PackedInt32Array() # a facility's module maintenance, administration, staffing
var _treasury_cash_items := PackedInt32Array() # each treasury's balance, by Enums.Accounts
var _type_buildout := -1 # the operation whose target spending share is the build share
var _research_resources := PackedInt32Array() # those tagged research

var _selection_manager: AstroSelectionManager
var _suppress_tab_listener := true

# Last data pushed to the main thread, retained so window shifts re-render
# without another proxy-thread round trip. Series are per-quarter, oldest first,
# with the current (incomplete) quarter last.
var _display_name := &""
var _display_statement := -1
var _display_ordinal_qtr := -1
var _display_groups: Array = []  # [[title, subtotal_series, [[leaf_key, leaf_series], ...]], ...]
var _display_footer: Array = []  # [name, series] or []
var _display_account_groups: Array = []  # a treasury's leaves per group, as _display_groups
var _window_offset := 0  # quarters scrolled back from newest; 0 shows the current quarter

# Blank icon used as the fold-arrow override for a group with no leaves; keeps
# the title's left lead while hiding the (non-functional) arrow.
var _fold_icon_substitute := MeshTexture.new()

# built in code (see _build_ui)
var _tab_container: TabContainer
var _no_budget_label: Label
var _local_selections: LocalSelections
var _content_vboxes: Array[VBoxContainer] = []
var _account_vboxes: Array[VBoxContainer] = []
var _scrolls: Array[ScrollContainer] = []
var _headers: Array[BudgetHeaderRow] = []
var _footers: Array[BudgetGroup] = []  # net-income / net-cash-flow line, a leafless foldable
var _empty_labels: Array[Label] = []
var _funding_header: FundingHeaderRow
var _funding_scroll: ScrollContainer
var _funding_rows: VBoxContainer
var _funding_empty_label: Label

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
	var item_is_tax: Array[bool] = _db_tables[&"line_items"][&"tax"]
	var item_balance_classes: Array[int] = _db_tables[&"line_items"][&"balance_class"]
	_item_keys.resize(_n_line_items)
	_item_subtotals.resize(_n_line_items)
	_item_balance_classes.resize(_n_line_items)
	var item_accounts: Array[int] = _db_tables[&"line_items"][&"account"]
	_item_accounts = PackedInt32Array(item_accounts)
	var item_keyed_bys: Array[int] = _db_tables[&"line_items"][&"keyed_by"]
	_item_keyed_bys = PackedInt32Array(item_keyed_bys)
	for item in _n_line_items:
		_item_keys[item] = String(_item_names[item])
		if item_is_tax[item]:
			_item_subtotals[item] = SUBTOTAL_TAX
		elif item_operating_expense[item]:
			_item_subtotals[item] = SUBTOTAL_OPERATING_EXPENSE
		else:
			_item_subtotals[item] = SUBTOTAL_REVENUE if item_revenue[item] else SUBTOTAL_COST_OF_GOODS
		_item_balance_classes[item] = item_balance_classes[item]
	_item_returns.resize(_n_line_items)
	_item_returns.fill(-1)
	var funding_paid := _find_item(Enums.UniqueLineItems.GOVERNMENT_FUNDING_PAID)
	var corporate_funding_paid := _find_item(Enums.UniqueLineItems.CORPORATE_FUNDING_PAID)
	_item_appropriations_paid = _find_item(Enums.UniqueLineItems.APPROPRIATIONS_PAID)
	_item_returns[funding_paid] = _find_item(Enums.UniqueLineItems.GOVERNMENT_PAYOUTS_RECEIVED)
	_item_returns[corporate_funding_paid] = _find_item(
			Enums.UniqueLineItems.CORPORATE_PAYOUTS_RECEIVED)
	_item_returns[_item_appropriations_paid] = _find_item(
			Enums.UniqueLineItems.APPROPRIATIONS_RECEIVED)
	_funding_items = PackedInt32Array([funding_paid, corporate_funding_paid])
	_committed_items = PackedInt32Array([
		_find_item(Enums.UniqueLineItems.GOVERNMENT_INTEREST_PAID),
		_find_item(Enums.UniqueLineItems.CORPORATE_INTEREST_PAID),
	])
	_item_transfers_paid = _find_item(Enums.UniqueLineItems.TRANSFERS_PAID)
	_item_dividends_paid = _find_item(Enums.UniqueLineItems.DIVIDENDS_PAID)
	_item_funding_received = _find_item(Enums.UniqueLineItems.FUNDING_RECEIVED)
	_item_payouts_paid = _find_item(Enums.UniqueLineItems.PAYOUTS_PAID)
	_item_interest_expense = _find_item(Enums.UniqueLineItems.INTEREST_EXPENSE)
	_item_income_tax = _find_item(Enums.UniqueLineItems.INCOME_TAX)
	_item_research_development = _find_item(Enums.UniqueLineItems.RESEARCH_DEVELOPMENT)
	_item_fixed_assets = _find_item(Enums.UniqueLineItems.FIXED_ASSETS)
	_upkeep_items = PackedInt32Array([
		_find_item(Enums.UniqueLineItems.MODULE_MAINTENANCE),
		_find_item(Enums.UniqueLineItems.ADMINISTRATION),
		_find_item(Enums.UniqueLineItems.STAFFING),
	])
	_treasury_cash_items = PackedInt32Array([
		_find_item(Enums.UniqueLineItems.GOVERNMENT_CASH),
		_find_item(Enums.UniqueLineItems.CORPORATE_CASH),
	])
	_type_buildout = IVTableData.db_find(&"operations", &"operation_group",
			Enums.OperationGroup.OPERATION_GROUP_BUILDOUT)
	var resource_tags: Array[Array] = _db_tables[&"resources"][&"ai_tags"]
	for resource_type in resource_tags.size():
		if resource_tags[resource_type].has(&"research"):
			_research_resources.append(resource_type)


func _find_item(unique_type: int) -> int:
	return IVTableData.db_find(&"line_items", &"unique_type", unique_type)


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

	var local_selections_scene: PackedScene = load(LocalSelections.SCENE)
	_local_selections = local_selections_scene.instantiate()
	_local_selections.local_only = true
	_local_selections.header_text = "LABEL_FACILITIES_AT_BODY"
	_local_selections.centered = true
	_local_selections.hide()
	add_child(_local_selections)

	var funding_tab := VBoxContainer.new()
	funding_tab.name = "TAB_FUNDING"  # node name auto-translates as tab title (gui.csv)
	_tab_container.add_child(funding_tab)
	_funding_header = FundingHeaderRow.new(column_width, bar_width, auto_width,
			scroll_correction)
	_funding_header.hide()
	funding_tab.add_child(_funding_header)
	_funding_scroll = ScrollContainer.new()
	_funding_scroll.size_flags_horizontal = SIZE_EXPAND_FILL
	_funding_scroll.size_flags_vertical = SIZE_EXPAND_FILL
	_funding_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	funding_tab.add_child(_funding_scroll)
	_funding_rows = VBoxContainer.new()
	_funding_rows.size_flags_horizontal = SIZE_EXPAND_FILL
	_funding_scroll.add_child(_funding_rows)
	_funding_empty_label = Label.new()
	_funding_empty_label.text = "No funding lines for this selection."
	_funding_empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_funding_empty_label.hide()
	funding_tab.add_child(_funding_empty_label)

	for placeholder: Array in PLACEHOLDER_TABS:
		var placeholder_label := Label.new()
		placeholder_label.name = placeholder[0]
		placeholder_label.text = placeholder[1]
		placeholder_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		placeholder_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_tab_container.add_child(placeholder_label)

	var n_statements := _statement_keys.size()
	_content_vboxes.resize(n_statements)
	_account_vboxes.resize(n_statements)
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

		# Groups and the bottom-line footer live inside the scroll — the whole
		# statement is one scrollable unit; only the header stays pinned outside.
		# The footer is itself a leafless foldable so it shares the groups' styling.
		var groups_vbox := VBoxContainer.new()
		groups_vbox.size_flags_horizontal = SIZE_EXPAND_FILL
		content.add_child(groups_vbox)

		var footer := BudgetGroup.new(_memory, label_width, column_width, arrow_width,
				n_visible_quarters, _fold_icon_substitute)
		footer.hide()
		content.add_child(footer)

		var accounts_vbox := VBoxContainer.new()
		accounts_vbox.size_flags_horizontal = SIZE_EXPAND_FILL
		content.add_child(accounts_vbox)

		var empty_label := Label.new()
		empty_label.text = "No line items."
		empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_label.hide()
		tab.add_child(empty_label)

		_content_vboxes[statement] = groups_vbox
		_account_vboxes[statement] = accounts_vbox
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
	if target_name and target_name == _selection_manager.get_body_name():
		_show_only(_local_selections)
	elif MainThreadGlobal.has_development(target_name):
		MainThreadGlobal.call_proxy_thread(_get_proxy_data.bind(target_name))
	else:
		_update_no_budget()


func _update_no_budget() -> void:
	_show_only(_no_budget_label)


func _show_only(view: Control) -> void:
	for control: Control in [_tab_container, _no_budget_label, _local_selections]:
		control.visible = control == view


# ******************************* PROXY THREAD ********************************

func _get_proxy_data(target_name: StringName) -> void:
	var proxy := Proxy.get_proxy_by_name(target_name)
	if !proxy or !proxy.has_financials():
		_update_no_budget.call_deferred()
		return

	var tab := current_tab
	if tab == FUNDING_TAB:
		_update_funding_display.call_deferred(_collect_funding(proxy))
		return
	if tab < _first_statement_tab:
		_show_placeholder.call_deferred()
		return
	var statement := tab - _first_statement_tab
	var ordinal_qtr := proxy.ordinal_qtr
	var groups := []
	var footer := []
	var accountings := proxy.get_financials_accountings().duplicate()

	if statement == _income_statement:
		# Income waterfall: gross profit and operating income render as leafless
		# subtotal lines; the opex group (a gain subtracting) and the tax group (signed
		# like SUBTOTAL_TAX) sit above and below operating income, and net income is the
		# bottom-line footer. The opex and tax groups are summed from their leaves (no
		# tracked-subtotal history getter).
		var subtotals := proxy.get_financials_subtotals()
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
		var opex_group := _collect_signed_group(proxy, accountings, SUBTOTAL_OPERATING_EXPENSE,
				"SUBTOTAL_OPERATING_EXPENSE", false)
		groups.append(opex_group)
		var opex_series: PackedFloat64Array = opex_group[1]
		var operating_income_series := _subtract_series(gross_profit_series, opex_series)
		groups.append(["SUBTOTAL_OPERATING_INCOME", operating_income_series, []])
		var tax_group := _collect_signed_group(proxy, accountings, SUBTOTAL_TAX, "SUBTOTAL_TAX",
				true)
		groups.append(tax_group)
		var tax_series: PackedFloat64Array = tax_group[1]
		var net_income_series := operating_income_series.duplicate()
		_add_series(net_income_series, tax_series)
		footer = ["SUBTOTAL_NET_INCOME", net_income_series]
	elif statement == _cash_flow_statement:
		# Inflow/outflow group series are summed from their leaf series (cash-flow
		# direction is per-leaf; only the net is a tracked subtotal).
		var inflow_group := _collect_summed_group(proxy, accountings, _cash_flow_statement,
				_item_subtotals, SUBTOTAL_REVENUE, "CASH_INFLOWS")
		var outflow_group := _collect_summed_group(proxy, accountings, _cash_flow_statement,
				_item_subtotals, SUBTOTAL_COST_OF_GOODS, "CASH_OUTFLOWS")
		groups.append(inflow_group)
		groups.append(outflow_group)
		var inflow_series: PackedFloat64Array = inflow_group[1]
		var outflow_series: PackedFloat64Array = outflow_group[1]
		footer = ["SUBTOTAL_NET_CASH_FLOW", _subtract_series(inflow_series, outflow_series)]
	elif statement == _balance_statement:
		# Asset / liability / equity groups (by per-leaf balance_class); a group with
		# no nonzero leaf is dropped so unused sections stay hidden. No footer (the
		# balancing identity is a later step).
		_append_balance_group(groups, proxy, accountings,
				Enums.BalanceClasses.BALANCE_CLASS_ASSET, "SUBTOTAL_ASSETS")
		_append_balance_group(groups, proxy, accountings,
				Enums.BalanceClasses.BALANCE_CLASS_LIABILITY, "SUBTOTAL_LIABILITIES")
		_append_balance_group(groups, proxy, accountings,
				Enums.BalanceClasses.BALANCE_CLASS_EQUITY, "SUBTOTAL_EQUITY")

	var account_groups := _collect_account_groups(proxy, accountings, statement)
	_update_tab_display.call_deferred(target_name, statement, ordinal_qtr, groups, footer,
			account_groups)


func _collect_group(proxy: Proxy, accountings: Dictionary[int, float], subtotal: int, title: String,
		subtotal_value: float, subtotal_history: PackedFloat64Array) -> Array:
	# Leaves in table order, matching this group, with any nonzero quarter (the
	# current value drops to 0 right after rollover, so history must count too).
	var rows := []
	for item in _n_line_items:
		if _item_statements[item] != _income_statement or _item_accounts[item] != -1:
			continue
		if _item_subtotals[item] != subtotal:
			continue
		for leaf: Array in _get_leaves(proxy, accountings, item):
			var leaf_series: PackedFloat64Array = leaf[1]
			if _has_nonzero(leaf_series):
				rows.append(leaf)
	return [title, _make_series(subtotal_history, subtotal_value), rows]


func _collect_summed_group(proxy: Proxy, accountings: Dictionary[int, float], statement: int,
		classifier: PackedInt32Array, class_value: int, title: String) -> Array:
	# Like _collect_group, but the group series is summed from its leaf series
	# rather than read from a tracked subtotal. Used for cash-flow direction groups
	# (classifier _item_subtotals, where only the net is a tracked subtotal) and balance-sheet
	# groups (classifier _item_balance_classes). Leaves in table order, matching this
	# statement and classifier value, with any nonzero quarter.
	var rows := []
	var group_series := PackedFloat64Array()
	for item in _n_line_items:
		if _item_statements[item] != statement or _item_accounts[item] != -1:
			continue
		if classifier[item] != class_value:
			continue
		for leaf: Array in _get_leaves(proxy, accountings, item):
			var leaf_series: PackedFloat64Array = leaf[1]
			_add_series(group_series, leaf_series)
			if _has_nonzero(leaf_series):
				rows.append(leaf)
	return [title, group_series, rows]


func _collect_signed_group(proxy: Proxy, accountings: Dictionary[int, float], subtotal: int,
		title: String, revenue_adds: bool) -> Array:
	# Like _collect_summed_group over the income leaves of one subtotal, but signs each
	# leaf into the group the way the subtotal does: a revenue leaf adds where
	# revenue_adds and a cost subtracts (the tax group, TAX_REVENUE less
	# INCOME_TAX, the net tax effect on net income), or the reverse (the opex group, its
	# costs less its gains). Each displayed leaf keeps its raw magnitude.
	var item_revenue: Array[bool] = _db_tables[&"line_items"][&"revenue"]
	var rows := []
	var group_series := PackedFloat64Array()
	for item in _n_line_items:
		if (_item_statements[item] != _income_statement or _item_accounts[item] != -1
				or _item_subtotals[item] != subtotal):
			continue
		for leaf: Array in _get_leaves(proxy, accountings, item):
			var leaf_series: PackedFloat64Array = leaf[1]
			if item_revenue[item] == revenue_adds:
				_add_series(group_series, leaf_series)
			else:
				_subtract_into_series(group_series, leaf_series)
			if _has_nonzero(leaf_series):
				rows.append(leaf)
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


func _collect_account_groups(proxy: Proxy, accountings: Dictionary[int, float],
		statement: int) -> Array:
	# One group per treasury with any nonzero leaf in this statement, its series the net of its
	# leaves: revenue, inflows and assets add, and the rest subtracts.
	# A treasury with unlimited money is never short, so its cash shows as unbounded.
	var item_revenue: Array[bool] = _db_tables[&"line_items"][&"revenue"]
	var is_unbounded := statement == _balance_statement and _has_unlimited_money(proxy)
	var groups := []
	for account in _account_keys.size():
		var rows := []
		var group_series := PackedFloat64Array()
		for item in _n_line_items:
			if _item_statements[item] != statement or _item_accounts[item] != account:
				continue
			var adds := (_item_balance_classes[item] == Enums.BalanceClasses.BALANCE_CLASS_ASSET
					if statement == _balance_statement else item_revenue[item])
			for leaf: Array in _get_leaves(proxy, accountings, item):
				var leaf_series: PackedFloat64Array = leaf[1]
				if is_unbounded and _treasury_cash_items.has(item):
					leaf_series.fill(INF)
					leaf[1] = leaf_series
				if adds:
					_add_series(group_series, leaf_series)
				else:
					_subtract_into_series(group_series, leaf_series)
				if _has_nonzero(leaf_series):
					rows.append(leaf)
		if !rows.is_empty():
			groups.append([_account_keys[account], group_series, rows])
	return groups


func _get_leaves(proxy: Proxy, accountings: Dictionary[int, float], item: int) -> Array:
	# [[name, series], ...] for line item [param item]: one leaf where it is kept once, its name a
	# translation key, and one per counterparty where it is kept per counterparty, its name a pair
	# of the item's key and the counterparty's name, translated on the main thread.
	if _item_keyed_bys[item] == -1:
		var current_value: float = accountings.get(item, 0.0)
		return [[_item_keys[item], _make_series(proxy.get_financials_accounting_history(item),
				current_value)]]
	var leaves := []
	for key in proxy.get_financials_counterparty_keys(item):
		var key_value: float = accountings.get(key, 0.0)
		leaves.append([_get_line_name(item, key),
				_make_series(proxy.get_financials_accounting_history(key), key_value)])
	return leaves


func _add_series(into: PackedFloat64Array, add: PackedFloat64Array) -> void:
	if into.size() < add.size():
		into.resize(add.size())
	for q in add.size():
		into[q] += add[q]


func _subtract_into_series(into: PackedFloat64Array, sub: PackedFloat64Array) -> void:
	if into.size() < sub.size():
		into.resize(sub.size())
	for q in sub.size():
		into[q] -= sub[q]


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


func _collect_funding(proxy: Proxy) -> Array:
	# [[title, total, committed_rows, discretionary_rows, control], ...], each row [name, share,
	# line, drawn, fill, control]: at an administrative center or for a player, each of the player's
	# treasuries that has a budget or a line; at a facility its own budget, after its owners' lines
	# for it where it isn't its player's center. A control is empty where this machine's human can't
	# set the line or budget, and else [Controls, proxy name, index, is held, limit], its index a
	# budget line's key, a treasury's account or the build share's operation, and its limit the most
	# a line's share may be set at or a budget's total now.
	var player: PlayerProxy
	var facility: FacilityProxy
	if proxy is PlayerProxy:
		player = proxy
	elif proxy is FacilityProxy:
		facility = proxy
		player = facility.player
	if !player:
		return []
	var center := player.administrative_center
	var is_local := player.is_local_human()
	var panels := []
	if center and (!facility or facility == center):
		var keys: Array[int] = []
		keys.assign(player.budget_lines.keys())
		keys.sort_custom(_is_key_before)
		for account in player.budgets.size():
			var panel := _collect_treasury(player, center, account, keys, is_local)
			if !panel.is_empty():
				panels.append(panel)
	if !facility:
		return panels
	if center and facility != center:
		panels.append_array(_collect_owner_lines(facility, player, center, is_local))
	var budget_panel := _collect_facility_budget(facility, is_local)
	if !budget_panel.is_empty():
		panels.append(budget_panel)
	return panels


func _collect_facility_budget(facility: FacilityProxy, is_local: bool) -> Array:
	# The facility's budget, or empty before its first interval: its committed lines, its
	# operations' loss among them where its income is below nothing, as shares of what it has to
	# spend, and its R&D and builds at the shares they are set at of what those leave, its payouts
	# the rest. What its builds drew is what its fixed assets gained, net of what came down. Its
	# R&D and builds are controls where [param is_local].
	const BUDGET_INCOME := FacilityProxy.BudgetLines.BUDGET_INCOME
	const BUDGET_FUNDING := FacilityProxy.BudgetLines.BUDGET_FUNDING
	const BUDGET_UPKEEP := FacilityProxy.BudgetLines.BUDGET_UPKEEP
	const BUDGET_INTEREST := FacilityProxy.BudgetLines.BUDGET_INTEREST
	const BUDGET_TAX := FacilityProxy.BudgetLines.BUDGET_TAX
	const BUDGET_WEAR := FacilityProxy.BudgetLines.BUDGET_WEAR
	const BUDGET_RESEARCH := FacilityProxy.BudgetLines.BUDGET_RESEARCH
	const BUDGET_BUILDS := FacilityProxy.BudgetLines.BUDGET_BUILDS
	var lines := facility.budget_lines
	if lines.size() != FacilityProxy.BudgetLines.size():
		return []
	var income := lines[BUDGET_INCOME]
	var total := maxf(income, 0.0) + lines[BUDGET_FUNDING]
	# A unitary facility books only what it buys and sells, never what its upkeep or R&D draws.
	var upkeep_drawn := NAN
	var research_drawn := NAN
	if !facility.unitary:
		upkeep_drawn = 0.0
		for item in _upkeep_items:
			upkeep_drawn += _get_drawn(facility, item, false)
		research_drawn = _get_drawn(facility, _item_research_development, false)
	var committed_rows := []
	var committed := 0.0
	for row: Array in [
		["LABEL_UPKEEP", lines[BUDGET_UPKEEP], upkeep_drawn],
		[_item_keys[_item_interest_expense], lines[BUDGET_INTEREST],
				_get_drawn(facility, _item_interest_expense, false)],
		[_item_keys[_item_income_tax], lines[BUDGET_TAX],
				_get_drawn(facility, _item_income_tax, false)],
		["LABEL_WEAR", lines[BUDGET_WEAR], NAN],
		["LABEL_OPERATIONS_LOSS", maxf(-income, 0.0), NAN],
	]:
		var line: float = row[1]
		if !(line > 0.0):
			continue
		var drawn: float = row[2]
		committed += line
		committed_rows.append([row[0], line / total if total > 0.0 else NAN, line, drawn,
				_get_fill(drawn, line), []])
	var left := maxf(total - committed, 0.0)
	var research := lines[BUDGET_RESEARCH]
	var builds := lines[BUDGET_BUILDS]
	var research_share := _get_research_share(facility)
	var builds_share := _get_builds_share(facility)
	var research_control := []
	var builds_control := []
	if is_local:
		research_control = [Controls.CONTROL_RESEARCH, facility.name, -1,
				_is_research_held(facility), maxf(1.0 - builds_share, 0.0)]
		if _type_buildout != -1:
			builds_control = [Controls.CONTROL_BUILDS, facility.name, _type_buildout,
					facility.is_operations_target_spending_share_held(_type_buildout),
					maxf(1.0 - research_share, 0.0)]
	# Where it houses its residents its income counts their pay, so the rest reaches them as wages
	# as well as payouts, and the ledger doesn't tell which wages its upkeep's staffing took.
	var rest_name: String = _item_keys[_item_payouts_paid]
	var rest_drawn := _get_drawn(facility, _item_payouts_paid, false)
	if facility.get_population_number() > 0.0:
		rest_name = "LABEL_PAY_AND_PAYOUTS"
		rest_drawn = NAN
	var discretionary_rows := []
	for row: Array in [
		[_item_keys[_item_research_development], research_share, research, research_drawn,
				research_control],
		["LABEL_BUILDS", builds_share, builds, _get_balance_change(facility, _item_fixed_assets),
				builds_control],
		[rest_name, maxf(1.0 - research_share - builds_share, 0.0),
				maxf(left - research - builds, 0.0), rest_drawn, []],
	]:
		var line: float = row[2]
		var drawn: float = row[3]
		discretionary_rows.append([row[0], row[1], line, drawn, _get_fill(drawn, line), row[4]])
	return [facility.gui_name, total, committed_rows, discretionary_rows, []]


func _collect_treasury(player: PlayerProxy, center: FacilityProxy, account: int,
		keys: Array[int], is_local: bool) -> Array:
	# A treasury's budget, or empty where it has neither a budget nor a line. Its committed lines'
	# shares are of what it has to spend, and its discretionary lines' of what they leave, its
	# funding lines' those they are set at, which its rest, transfers or dividends, or at an agency
	# what goes back to its polity, takes last. Its funding lines are controls where
	# [param is_local], and its budget too with unlimited money.
	var budget := player.budgets[account]
	var funding_room := maxf(1.0 - _get_funding_share_sum(player, account), 0.0)
	var committed_rows := []
	var discretionary_rows := []
	var committed := 0.0
	var share_sum := 0.0
	for key in keys:
		var item := Utils.get_line_item_type(key)
		if _item_accounts[item] != account:
			continue
		var line: float = player.budget_lines[key]
		var drawn := _get_drawn(center, key, true)
		if _committed_items.has(item):
			committed += line
			committed_rows.append([_get_line_name(item, key), NAN, line, drawn,
					_get_fill(drawn, line), []])
			continue
		var share := line / budget if budget > 0.0 else NAN
		var control := []
		if item == _funding_items[account]:
			share = player.get_budget_share(key)
			if is_local and is_finite(share):
				control = [Controls.CONTROL_BUDGET_SHARE, player.name, key,
						player.is_budget_share_held(key), share + funding_room]
		if is_finite(share):
			share_sum += share
		var fill := _get_fill(drawn, line if is_finite(line) else budget)
		discretionary_rows.append([_get_line_name(item, key), share, line, drawn, fill, control])
	if !(budget > 0.0) and committed_rows.is_empty() and discretionary_rows.is_empty():
		return []
	var total := budget + committed
	for row: Array in committed_rows:
		var line: float = row[2]
		row[1] = line / total if total > 0.0 else NAN
	var rest_key := _item_dividends_paid
	if account == Enums.Accounts.ACCOUNT_GOVERNMENT:
		rest_key = _item_transfers_paid
		if player.player_class == Enums.PlayerClasses.PLAYER_CLASS_AGENCY:
			rest_key = Utils.get_line_item_key(_item_appropriations_paid, player.polity.player_id)
	var rest_share := maxf(1.0 - share_sum, 0.0) if budget > 0.0 else NAN
	var rest := rest_share * budget
	var rest_drawn := _get_drawn(center, rest_key, false)
	discretionary_rows.append([_get_line_name(Utils.get_line_item_type(rest_key), rest_key),
			rest_share, rest, rest_drawn, _get_fill(rest_drawn, rest), []])
	var budget_control := []
	if is_local and ThreadsafeGlobal.sandbox_unlimited_money:
		var target := player.get_budget_target(account)
		budget_control = [Controls.CONTROL_BUDGET_TARGET, player.name, account,
				player.is_budget_target_held(account), target if target >= 0.0 else total]
	return [_account_keys[account], total, committed_rows, discretionary_rows, budget_control]


func _collect_owner_lines(facility: FacilityProxy, player: PlayerProxy,
		center: FacilityProxy, is_local: bool) -> Array:
	# The lines of [param facility]'s owners' treasuries that fund it, as one panel, each at the
	# share it is set at, and controls where [param is_local].
	var rows := []
	for account in player.budgets.size():
		var key := Utils.get_line_item_key(_funding_items[account], facility.facility_id)
		var line := player.get_budget_line(key)
		if is_nan(line):
			continue
		var budget := player.budgets[account]
		var share := player.get_budget_share(key)
		var control := []
		if is_local and is_finite(share):
			control = [Controls.CONTROL_BUDGET_SHARE, player.name, key,
					player.is_budget_share_held(key),
					share + maxf(1.0 - _get_funding_share_sum(player, account), 0.0)]
		var drawn := _get_drawn(center, key, true)
		var fill := _get_fill(drawn, line if is_finite(line) else budget)
		rows.append([[_account_keys[account], player.gui_name], share, line, drawn, fill, control])
	if rows.is_empty():
		return []
	return [[_item_keys[_item_funding_received], NAN, [], rows, []]]


# What was drawn last quarter of the line kept under [param key] at [param center], net of what came
# back of it where [param is_net], as a rate a year; NAN before a quarter has ended.
func _get_drawn(center: FacilityProxy, key: int, is_net: bool) -> float:
	var history := center.get_financials_accounting_history(key)
	if history.is_empty():
		return NAN
	var drawn := history[-1]
	var returned_item := _item_returns[Utils.get_line_item_type(key)]
	if is_net and returned_item != -1:
		var returned_key := Utils.get_line_item_key(returned_item,
				Utils.get_line_item_counterparty(key))
		drawn -= center.get_financials_accounting_history(returned_key)[-1]
	return drawn * IVUnits.YEAR / Utils.get_ordinal_quarter_duration(center.ordinal_qtr - 1)


# What [param facility]'s balance [param item] gained last quarter, as a rate a year; NAN before
# two quarters have ended.
func _get_balance_change(facility: FacilityProxy, item: int) -> float:
	var history := facility.get_financials_accounting_history(item)
	if history.size() < 2:
		return NAN
	return ((history[-1] - history[-2]) * IVUnits.YEAR
			/ Utils.get_ordinal_quarter_duration(facility.ordinal_qtr - 1))


# What of [param line] [param drawn] is, or NAN where either has no value.
func _get_fill(drawn: float, line: float) -> float:
	if !is_finite(drawn) or !(line > 0.0) or is_inf(line):
		return NAN
	return drawn / line


# The share of the treasury [param account]'s budget its funding lines are set at, together.
func _get_funding_share_sum(player: PlayerProxy, account: int) -> float:
	var sum := 0.0
	for key in player.budget_shares:
		if Utils.get_line_item_type(key) == _funding_items[account]:
			sum += player.budget_shares[key]
	return sum


# The share of what [param facility]'s committed lines leave that its R&D is set at.
func _get_research_share(facility: FacilityProxy) -> float:
	var share := 0.0
	for resource_type in _research_resources:
		share += maxf(facility.get_inventory_research_share(resource_type), 0.0)
	return minf(share, 1.0)


# The share of what [param facility]'s committed lines leave that its builds are set at, nothing
# where it builds nothing.
func _get_builds_share(facility: FacilityProxy) -> float:
	if _type_buildout == -1:
		return 0.0
	return maxf(facility.get_operations_target_spending_share(_type_buildout), 0.0)


func _is_research_held(facility: FacilityProxy) -> bool:
	for resource_type in _research_resources:
		if facility.is_inventory_research_share_held(resource_type):
			return true
	return false


func _has_unlimited_money(proxy: Proxy) -> bool:
	if !ThreadsafeGlobal.sandbox_unlimited_money:
		return false
	var player := proxy as PlayerProxy
	if proxy is FacilityProxy:
		player = (proxy as FacilityProxy).player
	return player != null and player.human


# Holds what [param control] sets (see _collect_funding) at [param value], and refreshes the tab.
func _hold_control(control: Array, value: float) -> void:
	var proxy_name: StringName = control[1]
	var proxy := Proxy.get_proxy_by_name(proxy_name)
	if !proxy:
		return
	var index: int = control[2]
	match control[0]:
		Controls.CONTROL_BUDGET_SHARE:
			(proxy as PlayerProxy).hold_budget_share(index, value)
		Controls.CONTROL_BUDGET_TARGET:
			(proxy as PlayerProxy).hold_budget_target(index, value)
		Controls.CONTROL_BUILDS:
			(proxy as FacilityProxy).hold_operations_target_spending_share(index, value)
		Controls.CONTROL_RESEARCH:
			_hold_research_share(proxy as FacilityProxy, value)
	_update_tab.call_deferred()


# Returns what [param control] sets to its AI where [param auto], or holds it at what it is set at,
# and refreshes the tab.
func _set_control_auto(control: Array, auto: bool) -> void:
	var proxy_name: StringName = control[1]
	var proxy := Proxy.get_proxy_by_name(proxy_name)
	if !proxy:
		return
	var index: int = control[2]
	match control[0]:
		Controls.CONTROL_BUDGET_SHARE:
			var player := proxy as PlayerProxy
			if auto:
				player.release_budget_share(index)
			else:
				player.hold_budget_share(index, player.get_budget_share(index))
		Controls.CONTROL_BUDGET_TARGET:
			var player := proxy as PlayerProxy
			if auto:
				player.release_budget_target(index)
			else:
				var budget := player.get_budget(index)
				player.hold_budget_target(index, budget if budget >= 0.0 else 0.0)
		Controls.CONTROL_BUILDS:
			var facility := proxy as FacilityProxy
			if auto:
				facility.release_operations_target_spending_share(index)
			else:
				facility.hold_operations_target_spending_share(index, _get_builds_share(facility))
		Controls.CONTROL_RESEARCH:
			var facility := proxy as FacilityProxy
			for resource_type in _research_resources:
				if auto:
					facility.release_inventory_research_share(resource_type)
				else:
					facility.hold_inventory_research_share(resource_type,
							clampf(facility.get_inventory_research_share(resource_type), 0.0, 1.0))
	_update_tab.call_deferred()


# Holds [param facility]'s research shares so that together they are [param share]: each in
# proportion to what it is set at now, or alike where none is set.
func _hold_research_share(facility: FacilityProxy, share: float) -> void:
	var sum := 0.0
	for resource_type in _research_resources:
		sum += maxf(facility.get_inventory_research_share(resource_type), 0.0)
	for resource_type in _research_resources:
		var resource_share := share / _research_resources.size()
		if sum > 0.0:
			resource_share = (share * maxf(facility.get_inventory_research_share(resource_type), 0.0)
					/ sum)
		facility.hold_inventory_research_share(resource_type, clampf(resource_share, 0.0, 1.0))


# A line's name, as _get_leaf_name takes it: [param item]'s translation key where it is kept once,
# or that and its counterparty's name where it is kept per counterparty.
func _get_line_name(item: int, key: int) -> Variant:
	var keyed_by := _item_keyed_bys[item]
	if keyed_by == -1:
		return _item_keys[item]
	var counterparties: Array = Proxy.proxy_bus.facility_proxies
	if keyed_by == Enums.Counterparties.COUNTERPARTY_PLAYER:
		counterparties = Proxy.proxy_bus.player_proxies
	var counterparty_id := Utils.get_line_item_counterparty(key)
	var counterparty_name := str(counterparty_id)
	if counterparty_id < counterparties.size():
		var counterparty: Proxy = counterparties[counterparty_id]
		if counterparty:
			counterparty_name = counterparty.gui_name if counterparty.gui_name else String(
					counterparty.name)
	return [_item_keys[item], counterparty_name]


func _is_key_before(a: int, b: int) -> bool:
	var type_a := Utils.get_line_item_type(a)
	var type_b := Utils.get_line_item_type(b)
	return type_a < type_b or (type_a == type_b and a < b)


# ******************************** MAIN THREAD ********************************

func _show_placeholder() -> void:
	_show_only(_tab_container)


func _update_tab_display(target_name: StringName, statement: int, ordinal_qtr: int,
		groups: Array, footer: Array, account_groups: Array) -> void:
	_show_only(_tab_container)

	if target_name != _display_name or statement != _display_statement:
		_window_offset = 0
	_display_name = target_name
	_display_statement = statement
	_display_ordinal_qtr = ordinal_qtr
	_display_groups = groups
	_display_footer = footer
	_display_account_groups = account_groups

	_render_current()


func _render_current() -> void:
	var statement := _display_statement
	var scroll: ScrollContainer = _scrolls[statement]
	var header: BudgetHeaderRow = _headers[statement]
	var footer_group: BudgetGroup = _footers[statement]
	var empty_label: Label = _empty_labels[statement]

	if (_display_groups.is_empty() and _display_footer.is_empty()
			and _display_account_groups.is_empty()):
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
	header.set_header(tr(&"LABEL_USD"), _quarter_labels(total_quarters),
			_window_offset > 0, _window_offset < max_offset)

	_render_groups(_content_vboxes[statement], _display_groups)
	if _display_footer.is_empty():
		footer_group.hide()
	else:
		var footer_name: String = _display_footer[0]
		var footer_series: PackedFloat64Array = _display_footer[1]
		footer_group.set_group(tr(footer_name), _format_cells(footer_series), [])
		footer_group.show()
	_render_groups(_account_vboxes[statement], _display_account_groups)


# Shows [param groups] in [param content]'s BudgetGroups, reusing them or creating more, and
# hides those left over.
func _render_groups(content: VBoxContainer, groups: Array) -> void:
	var n_groups := groups.size()
	var n_children := content.get_child_count()
	while n_children < n_groups:
		content.add_child(BudgetGroup.new(_memory, label_width, column_width, arrow_width,
				n_visible_quarters, _fold_icon_substitute))
		n_children += 1
	var i := 0
	while i < n_groups:
		var group_data: Array = groups[i]
		var title: String = group_data[0]
		var subtotal_series: PackedFloat64Array = group_data[1]
		var leaf_rows: Array = group_data[2]
		var formatted_leaves := []
		for leaf_row: Array in leaf_rows:
			var leaf_series: PackedFloat64Array = leaf_row[1]
			formatted_leaves.append([_get_leaf_name(leaf_row[0]), _format_cells(leaf_series)])
		var budget_group: BudgetGroup = content.get_child(i)
		budget_group.set_group(tr(title), _format_cells(subtotal_series), formatted_leaves)
		budget_group.show()
		i += 1
	while i < n_children:
		var unused_group: Control = content.get_child(i)
		unused_group.hide()
		i += 1


# A leaf's name: [param leaf_name] where a translation key, which its Label translates, or the
# item and its counterparty where a pair of them.
func _get_leaf_name(leaf_name: Variant) -> String:
	if leaf_name is String:
		var translation_key: String = leaf_name
		return translation_key
	var pair: Array = leaf_name
	var item_key: String = pair[0]
	var counterparty_name: String = pair[1]
	return "%s: %s" % [tr(item_key), tr(counterparty_name)]


func _shift_window(direction: int) -> void:
	_window_offset += direction
	_render_current()


func _get_total_quarters() -> int:
	if !_display_groups.is_empty():
		var group_data: Array = _display_groups[0]
		var series: PackedFloat64Array = group_data[1]
		return series.size()
	if !_display_footer.is_empty():
		var series: PackedFloat64Array = _display_footer[1]
		return series.size()
	if !_display_account_groups.is_empty():
		var group_data: Array = _display_account_groups[0]
		var series: PackedFloat64Array = group_data[1]
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
		cells[column] = _format_money(series[index]) if index != -1 else ""
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


func _update_funding_display(panels: Array) -> void:
	_show_only(_tab_container)
	if panels.is_empty():
		_funding_header.hide()
		_funding_scroll.hide()
		_funding_empty_label.show()
		return
	_funding_empty_label.hide()
	_funding_scroll.show()
	_funding_header.show()

	_funding_header.set_unit("%s %s" % [tr(&"LABEL_USD"), tr(&"LABEL_A_YEAR")])
	var has_controls := false
	for panel: Array in panels:
		var panel_control: Array = panel[4]
		var panel_rows: Array = panel[3]
		has_controls = has_controls or !panel_control.is_empty()
		for row: Array in panel_rows:
			var row_control: Array = row[5]
			has_controls = has_controls or !row_control.is_empty()
	_funding_header.set_auto_column(has_controls)

	var n_rows := 0
	for panel: Array in panels:
		var total: float = panel[1]
		var committed_rows: Array = panel[2]
		var discretionary_rows: Array = panel[3]
		var panel_control: Array = panel[4]
		var is_budget := !is_nan(total)
		var title_row := _get_funding_row(n_rows, has_controls)
		title_row.set_title(_get_leaf_name(panel[0]), _format_money(total) if is_budget else "",
				panel_control)
		if !panel_control.is_empty():
			var budget_total: float = panel_control[4]
			title_row.set_total_edit(_format_money(budget_total))
		n_rows += 1
		if !committed_rows.is_empty():
			_get_funding_row(n_rows, has_controls).set_section(tr(&"LABEL_COMMITTED"))
			n_rows += 1
			for row: Array in committed_rows:
				_set_funding_line(_get_funding_row(n_rows, has_controls), row)
				n_rows += 1
		if is_budget:
			_get_funding_row(n_rows, has_controls).set_section(tr(&"LABEL_DISCRETIONARY"))
			n_rows += 1
		for row: Array in discretionary_rows:
			_set_funding_line(_get_funding_row(n_rows, has_controls), row)
			n_rows += 1
	for i in range(n_rows, _funding_rows.get_child_count()):
		var unused_row: Control = _funding_rows.get_child(i)
		unused_row.hide()


# The Funding subtab's row [param index], made where there are fewer, and shown, with the Auto
# column where [param has_controls].
func _get_funding_row(index: int, has_controls: bool) -> FundingRow:
	while _funding_rows.get_child_count() <= index:
		var new_row := FundingRow.new(label_width, column_width, bar_width, auto_width,
				SUBGROUP_INDENT)
		new_row.control_held.connect(_on_control_held)
		new_row.control_auto_set.connect(_on_control_auto_set)
		new_row.total_submitted.connect(_on_total_submitted)
		_funding_rows.add_child(new_row)
	var row: FundingRow = _funding_rows.get_child(index)
	row.set_auto_column(has_controls)
	row.show()
	return row


func _set_funding_line(row: FundingRow, data: Array) -> void:
	var share: float = data[1]
	var line: float = data[2]
	var drawn: float = data[3]
	var fill: float = data[4]
	var share_text := NO_VALUE
	if is_inf(share):
		share_text = UNBOUNDED
	elif !is_nan(share):
		share_text = "%.f%%" % (share * 100.0)
	var control: Array = data[5]
	row.set_line(_get_leaf_name(data[0]), share, fill, share_text, _format_money(line),
			_format_money(drawn), control)


func _format_money(value: float) -> String:
	if is_nan(value):
		return NO_VALUE
	if is_inf(value):
		return UNBOUNDED
	return IVQFormat.metric_number(value * _usd_inv)


# The money [param text] gives in the form _format_money writes, or NAN where it gives none.
func _parse_money(text: String) -> float:
	var number := text.strip_edges()
	var exponent := 0
	if !number.is_empty():
		var prefix_index := IVQFormat.prefix_symbols.find(number.right(1))
		if prefix_index != -1:
			exponent = 3 * (prefix_index - IVQFormat.prefix_symbols.find(""))
			number = number.left(-1).strip_edges()
	if !number.is_valid_float():
		return NAN
	return number.to_float() * 10.0 ** exponent / _usd_inv


func _on_control_held(control: Array, value: float) -> void:
	if !IVStateManager.is_threads_allowed():
		return
	MainThreadGlobal.call_proxy_thread(_hold_control.bind(control, value))


func _on_control_auto_set(control: Array, auto: bool) -> void:
	if !IVStateManager.is_threads_allowed():
		return
	MainThreadGlobal.call_proxy_thread(_set_control_auto.bind(control, auto))


func _on_total_submitted(control: Array, text: String) -> void:
	var value := _parse_money(text)
	if value >= 0.0:
		_on_control_held(control, value)


# ****************************** INNER CLASSES ********************************
# Columns are right-anchored. Foldable groups are full width, with the name on
# the native title and only the value cells in a right-aligned title control, so
# column position is independent of the title text. Leaf rows (in the foldable
# body) and the title cells share the in-scroll right edge. The header sits
# outside the scroll, so a trailing scroll_correction spacer pushes its columns
# in to match the content past the vertical scrollbar. (Pattern mirrors
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
	# title control shows the per-quarter subtotal cells; it expands to its
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
	var _singular: bool


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
			_singular = true
			folded = true
		else:
			remove_theme_icon_override(&"folded_arrow")
			_singular = false
			folded = _memory.get(_memory_key, true)  # start closed

		var n_rows := leaf_rows.size()
		var n_children := _rows_vbox.get_child_count()
		while n_children < n_rows:
			_rows_vbox.add_child(BudgetRow.new(_label_width, _column_width, _arrow_width,
					_n_columns, SUBGROUP_INDENT))
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
		if !_singular:
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
	# One leaf account line. The name fills the left; the gutter-flanked value cells
	# hug the right so they line up with the foldable's right-aligned subtotal cells.

	var _indent_spacer := Control.new()
	var _name_label := Label.new()
	var _left_gutter := Control.new()
	var _right_gutter := Control.new()
	var _cells: Array[Label] = []
	var _label_width: float
	var _column_width: float
	var _arrow_width: float
	var _indent: float


	func _init(label_width: float, column_width: float, arrow_width: float, n_columns: int,
			indent: float) -> void:
		_label_width = label_width
		_column_width = column_width
		_arrow_width = arrow_width
		_indent = indent
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
		var cell_width := _column_width * multiplier
		for cell in _cells:
			cell.custom_minimum_size.x = cell_width


	func _settings_listener(setting: StringName, value: Variant) -> void:
		if setting == &"gui_size":
			var gui_size: int = value
			_resize(gui_size)


class FundingHeaderRow extends HBoxContainer:
	# The Funding subtab's header (outside the scroll): the USD unit label fills the left, above
	# the bars; the column titles sit over the Auto checkboxes, where any, and the cells, and a
	# trailing spacer offsets them to clear the scrollbar.

	var _unit_label := Label.new()
	var _auto_label := Label.new()
	var _bar_spacer := Control.new()
	var _trailing_spacer := Control.new()
	var _cells: Array[Label] = []
	var _column_width: float
	var _bar_width: float
	var _auto_width: float
	var _scroll_correction: float


	func _init(column_width: float, bar_width: float, auto_width: float,
			scroll_correction: float) -> void:
		_column_width = column_width
		_bar_width = bar_width
		_auto_width = auto_width
		_scroll_correction = scroll_correction
		size_flags_horizontal = SIZE_FILL
		add_theme_constant_override(&"separation", 0)  # explicit gutters/widths only
		_unit_label.clip_text = true
		_unit_label.size_flags_horizontal = SIZE_EXPAND_FILL
		add_child(_unit_label)
		_auto_label.text = &"LABEL_AUTO"
		_auto_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_auto_label.clip_text = true
		_auto_label.hide()
		add_child(_auto_label)
		add_child(_bar_spacer)
		for title: StringName in [&"LABEL_SHARE", &"LABEL_LINE", &"LABEL_DRAWN"]:
			var cell := Label.new()
			cell.text = title
			cell.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			cell.clip_text = true
			add_child(cell)
			_cells.append(cell)
		add_child(_trailing_spacer)
		var gui_size: int = IVSettingsManager.get_setting(&"gui_size")
		_resize(gui_size)
		IVSettingsManager.changed.connect(_settings_listener)


	func set_unit(unit_text: String) -> void:
		_unit_label.text = unit_text


	func set_auto_column(shown: bool) -> void:
		_auto_label.visible = shown


	func _resize(gui_size: int) -> void:
		var multiplier := IVCoreSettings.gui_size_multipliers[gui_size]
		_auto_label.custom_minimum_size.x = _auto_width * multiplier
		_bar_spacer.custom_minimum_size.x = _bar_width * multiplier
		_trailing_spacer.custom_minimum_size.x = _scroll_correction * multiplier
		for cell in _cells:
			cell.custom_minimum_size.x = _column_width * multiplier


	func _settings_listener(setting: StringName, value: Variant) -> void:
		if setting == &"gui_size":
			var gui_size: int = value
			_resize(gui_size)


class FundingRow extends HBoxContainer:
	# One row of the Funding subtab: a budget's title and what it has to spend, a section's name,
	# or a line with its bar, share, line and what was drawn of it. The name fills the left and the
	# cells hug the right, under the header's. A line or a budget its human can set has an Auto
	# checkbox; unchecked, the line's bar drags, and the budget's total is typed in.

	signal control_held(control: Array, value: float)
	signal control_auto_set(control: Array, auto: bool)
	signal total_submitted(control: Array, text: String)

	var _indent_spacer := Control.new()
	var _name_label := Label.new()
	var _auto_cell := CenterContainer.new()
	var _auto_box := CheckBox.new()
	var _bar: FundingBar
	var _cells: Array[Label] = []
	var _total_edit := LineEdit.new()
	var _control: Array = []
	var _label_width: float
	var _column_width: float
	var _auto_width: float
	var _indent: float
	var _row_indent := 0.0


	func _init(label_width: float, column_width: float, bar_width: float, auto_width: float,
			indent: float) -> void:
		_label_width = label_width
		_column_width = column_width
		_auto_width = auto_width
		_indent = indent
		size_flags_horizontal = SIZE_FILL
		add_theme_constant_override(&"separation", 0)  # explicit gutters/widths only
		add_child(_indent_spacer)
		_name_label.clip_text = true
		_name_label.size_flags_horizontal = SIZE_EXPAND_FILL
		add_child(_name_label)
		_auto_box.tooltip_text = &"HINT_AUTO"
		_auto_box.toggled.connect(_on_auto_toggled)
		_auto_cell.add_child(_auto_box)
		_auto_cell.hide()
		add_child(_auto_cell)
		_bar = FundingBar.new(bar_width)
		_bar.share_dragged.connect(_on_share_dragged)
		_bar.share_set.connect(_on_share_set)
		add_child(_bar)
		for i in 3:
			var cell := Label.new()
			cell.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			cell.clip_text = true
			add_child(cell)
			_cells.append(cell)
		# The total's cell, typed in where its budget is held.
		_total_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
		_total_edit.text_submitted.connect(_on_total_submitted)
		_total_edit.hide()
		add_child(_total_edit)
		move_child(_total_edit, _cells[1].get_index())
		var gui_size: int = IVSettingsManager.get_setting(&"gui_size")
		_resize(gui_size)
		IVSettingsManager.changed.connect(_settings_listener)


	func set_auto_column(shown: bool) -> void:
		_auto_cell.visible = shown


	func set_title(title_text: String, total_text: String, control: Array) -> void:
		_set_texts(0.0, title_text, ["", total_text, ""])
		_set_control(control)
		_bar.hide()
		var is_held: bool = !control.is_empty() and control[3]
		_cells[1].visible = !is_held
		_total_edit.visible = is_held


	# Sets the text of the total's cell where its budget is held, unless it is being typed in.
	func set_total_edit(total_text: String) -> void:
		if !_total_edit.has_focus():
			_total_edit.text = total_text


	func set_section(section_text: String) -> void:
		_set_texts(_indent, section_text, ["", "", ""])
		_set_control([])
		_bar.hide()
		_cells[1].show()
		_total_edit.hide()


	func set_line(name_text: String, share: float, fill: float, share_text: String,
			line_text: String, drawn_text: String, control: Array) -> void:
		_set_texts(2.0 * _indent, name_text, [share_text, line_text, drawn_text])
		_set_control(control)
		var is_held: bool = !control.is_empty() and control[3]
		var cap: float = control[4] if is_held else NAN
		_bar.set_draggable(is_held, cap)
		_bar.set_bar(share, fill)
		_bar.show()
		_cells[1].show()
		_total_edit.hide()


	func _set_control(control: Array) -> void:
		_control = control
		_auto_box.visible = !control.is_empty()
		if !control.is_empty():
			var is_held: bool = control[3]
			_auto_box.set_pressed_no_signal(!is_held)


	func _set_texts(row_indent: float, name_text: String, cell_texts: Array[String]) -> void:
		_name_label.text = name_text
		for i in _cells.size():
			_cells[i].text = cell_texts[i]
		if row_indent != _row_indent:
			_row_indent = row_indent
			var gui_size: int = IVSettingsManager.get_setting(&"gui_size")
			_resize(gui_size)


	func _on_auto_toggled(toggled_on: bool) -> void:
		if !_control.is_empty():
			control_auto_set.emit(_control, toggled_on)


	func _on_share_dragged(share: float) -> void:
		_cells[0].text = "%.f%%" % (share * 100.0)


	func _on_share_set(share: float) -> void:
		if !_control.is_empty():
			control_held.emit(_control, share)


	func _on_total_submitted(text: String) -> void:
		_total_edit.release_focus()
		if !_control.is_empty():
			total_submitted.emit(_control, text)


	func _resize(gui_size: int) -> void:
		var multiplier := IVCoreSettings.gui_size_multipliers[gui_size]
		_indent_spacer.custom_minimum_size.x = _row_indent * multiplier
		_name_label.custom_minimum_size.x = (_label_width - _row_indent) * multiplier
		_auto_cell.custom_minimum_size.x = _auto_width * multiplier
		_total_edit.custom_minimum_size.x = _column_width * multiplier
		for cell in _cells:
			cell.custom_minimum_size.x = _column_width * multiplier


	func _settings_listener(setting: StringName, value: Variant) -> void:
		if setting == &"gui_size":
			var gui_size: int = value
			_resize(gui_size)


class FundingBar extends Control:
	# A line as a horizontal bar: its share, from empty to the full width at 1.0, filled to what
	# was drawn of it; a share past 1.0, or a fill past the line, is marked at the right end. A line
	# that funds all its counterparty lacks is an outline across the width, filled to what it drew
	# of its budget. A draggable bar's share follows the mouse, up to its cap, while a button is
	# held, and is set on release. Its tooltip is a legend of its colors.

	signal share_dragged(share: float)
	signal share_set(share: float)

	const TRACK_COLOR := Color(1.0, 1.0, 1.0, 0.08)
	const LINE_COLOR := Color(0.62, 0.62, 0.62, 0.4)
	const FILL_COLOR := Color(0.62, 0.62, 0.62)
	const PAST_COLOR := Color(1.0, 0.4, 0.4)
	const DRAGGABLE_COLOR := Color(0.53, 0.81, 0.98, 0.6)
	# The legend's rows: [color, is filled, text key].
	const LEGEND := [
		[TRACK_COLOR, true, &"HINT_BAR_BUDGET"],
		[LINE_COLOR, true, &"HINT_BAR_LINE"],
		[FILL_COLOR, true, &"HINT_BAR_DRAWN"],
		[FILL_COLOR, false, &"HINT_BAR_UNBOUNDED"],
		[PAST_COLOR, true, &"HINT_BAR_PAST"],
		[DRAGGABLE_COLOR, false, &"HINT_BAR_HELD"],
	]

	var _share := NAN
	var _fill := NAN
	var _bar_width: float
	var _cap := NAN
	var _is_dragging := false


	func _init(bar_width: float) -> void:
		_bar_width = bar_width
		mouse_filter = MOUSE_FILTER_PASS
		tooltip_text = " " # shows the legend, which replaces it
		var gui_size: int = IVSettingsManager.get_setting(&"gui_size")
		_resize(gui_size)
		IVSettingsManager.changed.connect(_settings_listener)


	func set_bar(share: float, fill: float) -> void:
		if _is_dragging or (is_same(share, _share) and is_same(fill, _fill)):
			return
		_share = share
		_fill = fill
		queue_redraw()


	# Lets the bar drag up to [param cap] where [param draggable].
	func set_draggable(draggable: bool, cap: float) -> void:
		var is_draggable := mouse_filter == MOUSE_FILTER_STOP
		if draggable == is_draggable and is_same(cap, _cap):
			return
		_cap = cap
		mouse_filter = MOUSE_FILTER_STOP if draggable else MOUSE_FILTER_PASS
		mouse_default_cursor_shape = CURSOR_HSIZE if draggable else CURSOR_ARROW
		if !draggable:
			_is_dragging = false
		queue_redraw()


	func _make_custom_tooltip(_for_text: String) -> Object:
		var legend := VBoxContainer.new()
		for item: Array in LEGEND:
			var style := StyleBoxFlat.new()
			var color: Color = item[0]
			var is_filled: bool = item[1]
			if is_filled:
				style.bg_color = color
			else:
				style.draw_center = false
				style.border_color = color
				style.set_border_width_all(1)
			var swatch := Panel.new()
			swatch.custom_minimum_size = Vector2(24.0, 10.0)
			swatch.size_flags_vertical = SIZE_SHRINK_CENTER
			swatch.add_theme_stylebox_override(&"panel", style)
			var label := Label.new()
			var text_key: StringName = item[2]
			label.text = tr(text_key)
			var row := HBoxContainer.new()
			row.add_child(swatch)
			row.add_child(label)
			legend.add_child(row)
		return legend


	func _gui_input(event: InputEvent) -> void:
		if mouse_filter != MOUSE_FILTER_STOP:
			return
		var button_event := event as InputEventMouseButton
		if button_event and button_event.button_index == MOUSE_BUTTON_LEFT:
			if button_event.pressed:
				_is_dragging = true
				_drag_to(button_event.position.x)
			elif _is_dragging:
				_is_dragging = false
				share_set.emit(_share)
			accept_event()
			return
		var motion_event := event as InputEventMouseMotion
		if motion_event and _is_dragging:
			_drag_to(motion_event.position.x)
			accept_event()


	func _drag_to(x: float) -> void:
		var share := clampf((x - size.x * 0.05) / (size.x * 0.9), 0.0, 1.0)
		if share > _cap:
			share = _cap
		_share = share
		queue_redraw()
		share_dragged.emit(share)


	func _draw() -> void:
		var left := size.x * 0.05
		var span := size.x * 0.9
		var height := size.y * 0.5
		var top := (size.y - height) * 0.5
		draw_rect(Rect2(left, top, span, height), TRACK_COLOR)
		if mouse_filter == MOUSE_FILTER_STOP:
			draw_rect(Rect2(left, top, span, height), DRAGGABLE_COLOR, false, 1.0)
		if is_nan(_share):
			return
		var width := span * clampf(_share, 0.0, 1.0)
		if is_inf(_share):
			draw_rect(Rect2(left, top, width, height), FILL_COLOR, false, 1.0)
		else:
			draw_rect(Rect2(left, top, width, height), LINE_COLOR)
		if !is_nan(_fill):
			draw_rect(Rect2(left, top, width * clampf(_fill, 0.0, 1.0), height), FILL_COLOR)
		if _share > 1.0 or _fill > 1.0:
			draw_rect(Rect2(left + width - 2.0, top, 2.0, height), PAST_COLOR)


	func _resize(gui_size: int) -> void:
		var multiplier := IVCoreSettings.gui_size_multipliers[gui_size]
		custom_minimum_size.x = _bar_width * multiplier


	func _settings_listener(setting: StringName, value: Variant) -> void:
		if setting == &"gui_size":
			var gui_size: int = value
			_resize(gui_size)
