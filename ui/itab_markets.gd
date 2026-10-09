# itab_markets.gd
# This file is part of Astropolis
# https://t2civ.com
# *****************************************************************************
# Copyright 2019-2026 Charlie Whitfield; ALL RIGHTS RESERVED
# Astropolis is a registered trademark of Charlie Whitfield in the US
# *****************************************************************************
class_name ITabMarkets
extends MarginContainer

## "Markets" tab subpanel for [InfoPanel]. Shows the selection's prices and market flows for
## the resources of one resource class at a time, in two views.
##
## [b]Flows[/b]: for a facility, its local price, its net trade, its internal volume where it
## is non-unitary, and the trade it wants and must have; for a body, join or player, the market
## price and spread (at a join or player, of cyber resources only) and its facilities' net
## trade, purchases and internal volume. [b]Cover[/b], for a facility only: its stock and stock
## levels as a percent of one time horizon's outflow, and the share of the horizon's wanted trade
## it has contracted. A body with one facility shows as that facility. A facility lists the
## resources it deals in or holds; an aggregate, those any of its facilities deal in. Unfolding a
## resource lists its quarters: forward prices and what is contracted for each. Header tooltips
## define the columns.[br][br]
##
## The desired and critical rates, and so the hedged share, read "—" until the facility
## publishes them (PRODUCTION_MODEL.md, "A facility's flows with the market").[br][br]
##
## Tab indices follow row enumerations in [code]resource_classes.tsv[/code], with a
## placeholder transport tab after them.

const SCENE := "res://public/ui/itab_markets.tscn"  ## Scene file for instancing.

enum {
	TAB_ENERGY,
	TAB_ORES,
	TAB_VOLATILES,
	TAB_MATERIALS,
	TAB_MANUFACTURED,
	TAB_BIOLOGICALS,
	TAB_SERVICES,
	TAB_TRANSPORT,
}

## The views; Cover is for a facility only.
enum {
	VIEW_FLOWS,
	VIEW_COVER,
}

# What is shown, which decides the columns.
enum {
	KIND_FACILITY,
	KIND_UNITARY,
	KIND_AGGREGATE,
}

# The columns a layout picks from; COLUMN_NONE leaves a cell empty.
enum {
	COLUMN_LOCAL,
	COLUMN_PRICE,
	COLUMN_SPREAD,
	COLUMN_TRADE,
	COLUMN_MARKET,
	COLUMN_INTERNAL,
	COLUMN_DESIRED_RATE,
	COLUMN_CRITICAL_RATE,
	COLUMN_STOCK,
	COLUMN_CRITICAL_LEVEL,
	COLUMN_DESIRED_LEVEL,
	COLUMN_HEDGED,
	COLUMN_NONE,
}

enum {
	TONE_NORMAL,
	TONE_WARNING,
	TONE_ALERT,
}

const N_CELLS := 5
const SUBGROUP_INDENT := 25

const FACILITY_FLOWS: Array[int] = [COLUMN_LOCAL, COLUMN_TRADE, COLUMN_INTERNAL,
		COLUMN_DESIRED_RATE, COLUMN_CRITICAL_RATE]
const UNITARY_FLOWS: Array[int] = [COLUMN_LOCAL, COLUMN_TRADE, COLUMN_DESIRED_RATE,
		COLUMN_CRITICAL_RATE, COLUMN_NONE]
const FACILITY_COVER: Array[int] = [COLUMN_LOCAL, COLUMN_STOCK, COLUMN_CRITICAL_LEVEL,
		COLUMN_DESIRED_LEVEL, COLUMN_HEDGED]
const AGGREGATE_FLOWS: Array[int] = [COLUMN_PRICE, COLUMN_SPREAD, COLUMN_TRADE, COLUMN_MARKET,
		COLUMN_INTERNAL]

const COLUMN_HEADERS: Array[String] = [ # by COLUMN_
	"Local\n($)",
	"Price\n($)",
	"Spread\n(%)",
	"Trade\n(net/d)",
	"Market\n(/d)",
	"Internal\n(/d)",
	"Desired\n(/d)",
	"Critical\n(/d)",
	"Stock\n(%H)",
	"Critical\n(%H)",
	"Desired\n(%H)",
	"Hedged\n(%)",
	"",
]
const COLUMN_TOOLTIPS: Array[String] = [ # by COLUMN_
	("The facility's local price, $ per row unit: the price at its own market, which its"
			+ "\noperations plan against."),
	("The body market's price, $ per row unit. A join or player has one only for cyber"
			+ "\nresources, at the system-wide cyber market."),
	("The gap between the best ask and the best bid, as a percent of their midpoint."
			+ "\nHover a cell for both."),
	("Net trade, row units per day: what was bought (+) less what was sold (-)."
			+ "\nAt a body or join, what its facilities trade among themselves cancels."),
	"What the facilities here bought, row units per day.",
	("What the non-unitary facilities here pass from their own producers and stock to"
			+ "\ntheir users, row units per day."),
	("The trade the facility wants, row units per day: + to take, - to give."
			+ "\nNot yet published."),
	("The trade the facility must have (+), or the most it can spare (-), row units per"
			+ "\nday. Not yet published."),
	("Stock as a percent of one horizon's outflow: what the facility uses and sells"
			+ "\nover its time horizon (H)."),
	("The critical level, the stock its operations and its residents' existence need,"
			+ "\nas a percent of one horizon's outflow."),
	("The desired level, the stock the facility aims at, as a percent of one horizon's"
			+ "\noutflow."),
	("What is contracted for delivery within the horizon, as a percent of the trade the"
			+ "\nfacility wants over it. Not yet published: it waits on the desired rate."),
	"",
]

const TRADE_CLASS_TEXTS: Array[String] = [ # by TradeClasses
	"",
	"",
	"ice, ",
	"liq, ",
	"cryo, ",
	"",
	"",
]
const TAB_NAMES: Array[StringName] = [ # by TAB_; node names auto-translate as tab titles
	&"TAB_MKS_ENERGY",
	&"TAB_MKS_ORES",
	&"TAB_MKS_VOLATILES",
	&"TAB_MKS_MATERIALS",
	&"TAB_MKS_MANUFACTURED",
	&"TAB_MKS_BIOLOGICALS",
	&"TAB_MKS_SERVICES",
]
const TRANSPORT_TEXT := """WIP

Will have info on transport tonnage to and from this facilty:
* Price for transport (per tonne) from various locations/spaceports.
* Current transport tonnage en route.
* Bids/Asks for transport tonnage."""

const NO_VALUE := "—" ## Applies, but has no value now.
const NOT_APPLICABLE := "·" ## Doesn't apply to this resource.
const UNBOUNDED := "∞" ## Stock that nothing draws on.
const WARNING_COLOR := Color(1.0, 0.75, 0.3)
const ALERT_COLOR := Color(1.0, 0.4, 0.4)

const PERSIST_MODE := IVGlobal.PERSIST_PROCEDURAL  ## Save/load mode (procedural node).
## Member names persisted by save/load.
const PERSIST_PROPERTIES: Array[StringName] = [
	&"view",
	&"current_tab",
	&"_on_ready_tab",
]

# persisted
var view: int = VIEW_FLOWS ## The view chosen, shown wherever it applies.
var current_tab: int = TAB_ENERGY
var _on_ready_tab: int = TAB_ENERGY

# not persisted
## Min width of each value column.
var column_width := 58.0
## Min width of the gutter right of the value columns.
var cell_gutter := 8.0
## Foldable title left-lead (fold-icon + style-box margin); aligns the header with group
## titles.
var foldable_indent := 20.0
## Trailing spacer on the out-of-scroll header; offsets its columns to match the in-scroll
## content past the vertical scrollbar.
var scroll_correction := 7.0

var _selection_manager: AstroSelectionManager
var _suppress_tab_listener := true

# table indexing
var _db_tables := IVTableData.db_tables
var _resource_names: Array[StringName] = _db_tables[&"resources"][&"name"]
var _trade_classes: Array[int] = _db_tables[&"resources"][&"trade_class"]
var _trade_units: Array[StringName] = _db_tables[&"resources"][&"trade_unit"]
var _resource_resource_classes: Array[int] = _db_tables[&"resources"][&"resource_class"]
var _resource_classes_resources: Array[PackedInt32Array] = (
		Utils.invert_many_to_one_indexing_to_packed(_resource_resource_classes,
		IVTableData.table_n_rows[&"resource_classes"]))
var _trade_unit_multipliers := ThreadsafeGlobal.resource_trade_unit_multipliers
var _times: Array = IVGlobal.times

# Blank icon used as the fold-arrow override for a resource with no quarters; keeps the
# title's left lead while hiding the (non-functional) arrow.
var _fold_icon_substitute := MeshTexture.new()

# built in code (see _build_ui)
var _tab_container: TabContainer
var _no_markets_label: Label
var _headers: Array[MarketsHeaderRow] = []
var _content_vboxes: Array[VBoxContainer] = []
var _empty_labels: Array[Label] = []

@warning_ignore("unsafe_property_access")
@onready var _memory: Dictionary = get_parent().memory # resource open states



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
		label.text = cells[i]
		label.tooltip_text = tooltips[i]
		match tones[i]:
			TONE_WARNING:
				label.add_theme_color_override(&"font_color", WARNING_COLOR)
			TONE_ALERT:
				label.add_theme_color_override(&"font_color", ALERT_COLOR)
			_:
				label.remove_theme_color_override(&"font_color")


# ************************* VIRTUAL & IMPLEMENTATION **************************

func _ready() -> void:
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


## Refreshes the active markets tab. Wired to [InfoTabContainer]'s shared 1 s
## timer.
func timer_update() -> void:
	_update_tab()


func _build_ui() -> void:
	_tab_container = TabContainer.new()
	_tab_container.size_flags_horizontal = SIZE_EXPAND_FILL
	_tab_container.size_flags_vertical = SIZE_EXPAND_FILL
	add_child(_tab_container)

	_no_markets_label = Label.new()
	_no_markets_label.text = "LABEL_NO_MARKETS"
	_no_markets_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_no_markets_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_no_markets_label.hide()
	add_child(_no_markets_label)

	var n_class_tabs := TAB_NAMES.size()
	_headers.resize(n_class_tabs)
	_content_vboxes.resize(n_class_tabs)
	_empty_labels.resize(n_class_tabs)
	for tab in n_class_tabs:
		var tab_vbox := VBoxContainer.new()
		tab_vbox.name = TAB_NAMES[tab]
		_tab_container.add_child(tab_vbox)

		var header := MarketsHeaderRow.new(column_width, cell_gutter, foldable_indent,
				scroll_correction)
		header.view_selected.connect(_select_view)
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

		var empty_label := Label.new()
		empty_label.text = "No resources dealt in here."
		empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_label.hide()
		tab_vbox.add_child(empty_label)

		_headers[tab] = header
		_content_vboxes[tab] = content
		_empty_labels[tab] = empty_label

	var transport_label := Label.new()
	transport_label.name = &"Transp"
	transport_label.text = TRANSPORT_TEXT
	transport_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	transport_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_tab_container.add_child(transport_label)

	_tab_container.tab_changed.connect(_select_tab)


func _select_tab(tab: int) -> void:
	if !_suppress_tab_listener:
		_on_ready_tab = tab
	current_tab = tab
	_update_tab()


func _select_view(new_view: int) -> void:
	view = new_view
	_update_tab()


func _update_tab(_dummy := false) -> void:
	if !visible or !IVStateManager.is_threads_allowed():
		return
	if current_tab == TAB_TRANSPORT:
		_no_markets_label.hide()
		_tab_container.show()
		return
	var target_name := _selection_manager.get_name()
	if !MainThreadGlobal.has_development(target_name):
		_update_no_markets()
		return
	MainThreadGlobal.call_proxy_thread(_get_proxy_data.bind(target_name))


func _update_no_markets() -> void:
	_tab_container.hide()
	_no_markets_label.show()


# ******************************* PROXY THREAD ********************************

func _get_proxy_data(target_name: StringName) -> void:
	var proxy := Proxy.get_proxy_by_name(target_name)
	if proxy:
		var body := proxy as BodyProxy
		if body and body.facilities.size() == 1:
			proxy = body.facilities[0]
	if !proxy or !proxy.has_development():
		_update_no_markets.call_deferred()
		return
	var tab := current_tab
	if tab == TAB_TRANSPORT:
		return
	var time: float = _times[0]
	var resource_types: PackedInt32Array = _resource_classes_resources[tab]
	var rows: Array[RowData] = []
	var facility := proxy as FacilityProxy
	if facility:
		_get_facility_rows(facility, resource_types, time, rows)
		var kind := KIND_UNITARY if facility.is_unitary else KIND_FACILITY
		_update_tab_display.call_deferred(tab, kind, facility.time_horizon, rows)
		return
	_get_aggregate_rows(proxy, resource_types, time, rows)
	_update_tab_display.call_deferred(tab, KIND_AGGREGATE, 0.0, rows)


func _get_facility_rows(facility: FacilityProxy, resource_types: PackedInt32Array, time: float,
		rows: Array[RowData]) -> void:
	const IS_MARKET := FacilityProxy.InventoryFlags.IS_MARKET
	const TRADABLE := FacilityProxy.InventoryFlags.TRADABLE
	var market := facility.get_market()
	var trader_positions := _get_trader_positions(facility.trader)
	for resource_type in resource_types:
		var flags := facility.get_inventory_flags(resource_type)
		var stock := facility.get_inventory_stock(resource_type)
		var resource_positions: Dictionary = trader_positions.get(resource_type, {})
		if !(flags & IS_MARKET) and !stock and resource_positions.is_empty():
			continue
		var row := RowData.new()
		row.resource_type = resource_type
		row.is_tradable = bool(flags & TRADABLE)
		row.has_market_price = row.is_tradable and market != null
		row.local_price = facility.get_inventory_local_price(resource_type)
		if row.has_market_price:
			row.unit_price = market.get_unit_price(resource_type)
			row.bid_unit_price = market.get_bid_unit_price(resource_type)
			row.ask_unit_price = market.get_ask_unit_price(resource_type)
		row.bought_rate = facility.get_operations_bought_rate(resource_type)
		row.sold_rate = facility.get_operations_sold_rate(resource_type)
		row.internal_volume = facility.get_operations_internal_volume(resource_type)
		row.use = facility.get_inventory_use(resource_type)
		row.stock = stock
		row.in_transit = facility.get_inventory_in_transit(resource_type)
		row.outbound = facility.get_inventory_outbound(resource_type)
		row.buffer_stock = facility.get_inventory_buffer_stock(resource_type)
		row.critical_level = facility.get_inventory_critical_level(resource_type)
		row.desired_level = facility.get_inventory_desired_level(resource_type)
		row.unmet_rate = facility.get_inventory_unmet_rate(resource_type)
		row.curtailed_rate = facility.get_inventory_curtailed_rate(resource_type)
		row.disposal_rate = facility.get_inventory_disposal_rate(resource_type)
		if row.has_market_price and facility.ordinal_qtr >= 0:
			_add_facility_quarters(row, market, resource_positions, facility.ordinal_qtr, time,
					time + facility.time_horizon)
		rows.append(row)


# The trader's positions summed by resource type, then by ordinal quarter, in trade units
# (+ long, - short).
func _get_trader_positions(trader: TraderProxy) -> Dictionary[int, Dictionary]:
	var trader_positions: Dictionary[int, Dictionary] = {}
	if !trader:
		return trader_positions
	for key: PackedInt32Array in trader.positions:
		var quantity := trader.positions[key][0]
		if !quantity:
			continue
		var resource_positions: Dictionary = trader_positions.get_or_add(key[0], {})
		var summed: float = resource_positions.get(key[1], 0.0)
		resource_positions[key[1]] = summed + quantity
	return trader_positions


# Lists the quarters that overlap the facility's horizon, then any later one it holds a position
# in, and sums what it has contracted within the horizon, a quarter counting by its overlap.
func _add_facility_quarters(row: RowData, market: MarketProxy, resource_positions: Dictionary,
		current_qtr: int, time: float, horizon_end: float) -> void:
	const MAX_FORWARD_QUARTERS := TraderProxy.MAX_FORWARD_QUARTERS
	var ordinal_qtr := current_qtr
	while ordinal_qtr < current_qtr + MAX_FORWARD_QUARTERS:
		var start := Utils.get_time_at_ordinal_quarter(ordinal_qtr)
		if ordinal_qtr > current_qtr and start >= horizon_end:
			break
		var end := Utils.get_time_at_ordinal_quarter(ordinal_qtr + 1)
		var from := maxf(start, time)
		var quarter := _make_quarter(market, row.resource_type, ordinal_qtr, current_qtr, from, end)
		var contracted: float = resource_positions.get(ordinal_qtr, 0.0)
		quarter.position = contracted
		quarter.has_positions = true
		row.quarters.append(quarter)
		var span := end - from
		var window_share := 0.0
		if span > 0.0:
			window_share = clampf((minf(end, horizon_end) - from) / span, 0.0, 1.0)
		if contracted > 0.0:
			row.window_long += contracted * window_share
		else:
			row.window_short -= contracted * window_share
		ordinal_qtr += 1
	var later_qtrs: Array = resource_positions.keys()
	later_qtrs.sort()
	for later_qtr: int in later_qtrs:
		if later_qtr < ordinal_qtr:
			continue
		var quarter := _make_quarter(market, row.resource_type, later_qtr, current_qtr,
				Utils.get_time_at_ordinal_quarter(later_qtr),
				Utils.get_time_at_ordinal_quarter(later_qtr + 1))
		var contracted: float = resource_positions[later_qtr]
		quarter.position = contracted
		quarter.has_positions = true
		quarter.is_beyond_horizon = true
		row.quarters.append(quarter)


func _get_aggregate_rows(proxy: Proxy, resource_types: PackedInt32Array, time: float,
		rows: Array[RowData]) -> void:
	const TRADE_CLASS_CYBER := Enums.TradeClasses.TRADE_CLASS_CYBER
	var body := proxy as BodyProxy
	var market := proxy.get_market()
	var cyber_market := _get_cyber_market()
	for resource_type in resource_types:
		var market_count := proxy.get_operations_market_count(resource_type)
		var bought_rate := proxy.get_operations_bought_rate(resource_type)
		var sold_rate := proxy.get_operations_sold_rate(resource_type)
		var internal_volume := proxy.get_operations_internal_volume(resource_type)
		if !market_count and !bought_rate and !sold_rate and !internal_volume:
			continue
		var row := RowData.new()
		row.resource_type = resource_type
		row.is_tradable = _trade_classes[resource_type] != -1
		var is_cyber := _trade_classes[resource_type] == TRADE_CLASS_CYBER
		var row_market := cyber_market if is_cyber else market
		row.has_market_price = row.is_tradable and row_market != null
		if row.has_market_price:
			row.unit_price = row_market.get_unit_price(resource_type)
			row.bid_unit_price = row_market.get_bid_unit_price(resource_type)
			row.ask_unit_price = row_market.get_ask_unit_price(resource_type)
		row.bought_rate = bought_rate
		row.sold_rate = sold_rate
		row.internal_volume = internal_volume
		row.market_count = market_count
		if row.has_market_price and row_market.ordinal_qtr >= 0:
			_add_aggregate_quarters(row, row_market, null if is_cyber else body, time)
		rows.append(row)


# Lists the current quarter and every later one with a book at [param market] or open interest at
# [param body], with what the body's own facilities have contracted in each, net.
func _add_aggregate_quarters(row: RowData, market: MarketProxy, body: BodyProxy, time: float
		) -> void:
	var resource_type := row.resource_type
	var current_qtr := market.ordinal_qtr
	var ordinal_qtrs := PackedInt32Array([current_qtr])
	for key: PackedInt32Array in market.instruments:
		if key[0] == resource_type and key[1] >= current_qtr and !ordinal_qtrs.has(key[1]):
			ordinal_qtrs.append(key[1])
	var open_interests: Dictionary[int, float] = {}
	var facility_positions: Dictionary[int, float] = {}
	if body:
		var trader_proxies := Proxy.proxy_bus.trader_proxies
		for key: PackedInt32Array in body.positions:
			if key[0] != resource_type or key[1] < current_qtr:
				continue
			var ordinal_qtr := key[1]
			var quantity := body.positions[key][0]
			if quantity > 0.0:
				open_interests[ordinal_qtr] = open_interests.get(ordinal_qtr, 0.0) + quantity
			var trader: TraderProxy = (trader_proxies[key[2]] if key[2] < trader_proxies.size()
					else null)
			if trader and trader.facility and trader.facility.body == body:
				facility_positions[ordinal_qtr] = (facility_positions.get(ordinal_qtr, 0.0)
						+ quantity)
			if !ordinal_qtrs.has(ordinal_qtr):
				ordinal_qtrs.append(ordinal_qtr)
	ordinal_qtrs.sort()
	for ordinal_qtr in ordinal_qtrs:
		var from := maxf(Utils.get_time_at_ordinal_quarter(ordinal_qtr), time)
		var end := Utils.get_time_at_ordinal_quarter(ordinal_qtr + 1)
		var quarter := _make_quarter(market, resource_type, ordinal_qtr, current_qtr, from, end)
		if body:
			quarter.has_positions = true
			quarter.position = facility_positions.get(ordinal_qtr, 0.0)
			quarter.open_interest = open_interests.get(ordinal_qtr, 0.0)
		row.quarters.append(quarter)


# A quarter's book and price at [param market], and its days from [param from] to its end:
# the current quarter's published price, or a later quarter's book midpoint.
func _make_quarter(market: MarketProxy, resource_type: int, ordinal_qtr: int, current_qtr: int,
		from: float, end: float) -> QuarterData:
	var quarter := QuarterData.new()
	quarter.ordinal_qtr = ordinal_qtr
	quarter.days = (end - from) / IVUnits.DAY
	if ordinal_qtr == current_qtr:
		quarter.bid_unit_price = market.get_bid_unit_price(resource_type)
		quarter.ask_unit_price = market.get_ask_unit_price(resource_type)
		var unit_price := market.get_unit_price(resource_type)
		quarter.unit_price = float(unit_price) if unit_price else NAN
		return quarter
	var bid_unit_price := market.get_instrument_bid_unit_price(resource_type, ordinal_qtr)
	var ask_unit_price := market.get_instrument_ask_unit_price(resource_type, ordinal_qtr)
	quarter.bid_unit_price = bid_unit_price
	quarter.ask_unit_price = ask_unit_price
	if bid_unit_price and ask_unit_price:
		quarter.unit_price = (bid_unit_price + ask_unit_price) / 2.0
	elif bid_unit_price or ask_unit_price:
		quarter.unit_price = bid_unit_price + ask_unit_price
	else:
		quarter.unit_price = NAN
	return quarter


func _get_cyber_market() -> MarketProxy:
	for market in Proxy.proxy_bus.market_proxies:
		if market:
			return market.cyber_market
	return null


# ******************************** MAIN THREAD ********************************

func _update_tab_display(tab: int, kind: int, horizon: float, rows: Array[RowData]) -> void:
	_no_markets_label.hide()
	_tab_container.show()
	var is_facility := kind != KIND_AGGREGATE
	var shown_view := view if is_facility else VIEW_FLOWS
	var columns := _get_columns(kind, shown_view)
	var horizon_text := _format_horizon(horizon) if is_facility else ""
	_headers[tab].set_header(shown_view, is_facility, horizon_text, columns)

	var content := _content_vboxes[tab]
	var n_rows := rows.size()
	var n_children := content.get_child_count()
	while n_children < n_rows:
		content.add_child(MarketsGroup.new(_memory, column_width, cell_gutter,
				_fold_icon_substitute))
		n_children += 1
	for i in n_rows:
		var group: MarketsGroup = content.get_child(i)
		_set_group(group, rows[i], columns, horizon)
		group.show()
	for i in range(n_rows, n_children):
		var unused_group: Control = content.get_child(i)
		unused_group.hide()
	_empty_labels[tab].visible = rows.is_empty()


func _get_columns(kind: int, shown_view: int) -> Array[int]:
	if kind == KIND_AGGREGATE:
		return AGGREGATE_FLOWS
	if shown_view == VIEW_COVER:
		return FACILITY_COVER
	return UNITARY_FLOWS if kind == KIND_UNITARY else FACILITY_FLOWS


func _set_group(group: MarketsGroup, row: RowData, columns: Array[int], horizon: float) -> void:
	var cells := PackedStringArray()
	var tooltips := PackedStringArray()
	var tones := PackedByteArray()
	for column in columns:
		var cell := _get_row_cell(column, row, horizon)
		var text: String = cell[0]
		var tooltip: String = cell[1]
		var tone: int = cell[2]
		cells.append(text)
		tooltips.append(tooltip)
		tones.append(tone)
	var quarter_rows := []
	for quarter in row.quarters:
		var quarter_cells := PackedStringArray()
		var quarter_tooltips := PackedStringArray()
		var quarter_tones := PackedByteArray()
		for column in columns:
			var cell := _get_quarter_cell(column, row, quarter)
			var text: String = cell[0]
			var tooltip: String = cell[1]
			quarter_cells.append(text)
			quarter_tooltips.append(tooltip)
			quarter_tones.append(TONE_NORMAL)
		var label := _format_quarter(quarter.ordinal_qtr)
		if quarter.is_beyond_horizon:
			label += "  ›H"
		quarter_rows.append([label, quarter_cells, quarter_tooltips, quarter_tones])
	var memory_key := "MKT_" + _resource_names[row.resource_type]
	group.set_group(memory_key, _get_row_title(row.resource_type), cells, tooltips, tones,
			quarter_rows)


# A resource row's cell in [param column], as [text, tooltip, tone].
func _get_row_cell(column: int, row: RowData, horizon: float) -> Array:
	var resource_type := row.resource_type
	var multiplier := _trade_unit_multipliers[resource_type]
	var unit := _get_unit_text(resource_type)
	var horizon_need := (row.use + row.sold_rate) * horizon
	match column:
		COLUMN_LOCAL:
			return [_format_price(row.local_price * multiplier), _get_local_tooltip(row, unit),
					TONE_NORMAL]
		COLUMN_PRICE:
			if !row.is_tradable:
				return [NOT_APPLICABLE, "Not traded: it can't be carried.", TONE_NORMAL]
			var count_text := _get_market_count_text(row.market_count)
			if !row.has_market_price:
				return [NO_VALUE, "No market here: only cyber resources have a price at a join\n"
						+ "or player.\n" + count_text, TONE_NORMAL]
			return [_format_price(row.unit_price),
					_format_book(row.bid_unit_price, row.ask_unit_price) + "\n" + count_text,
					TONE_NORMAL]
		COLUMN_SPREAD:
			if !row.is_tradable:
				return [NOT_APPLICABLE, "", TONE_NORMAL]
			if !row.has_market_price:
				return ["", "", TONE_NORMAL]
			return [_format_spread(row.bid_unit_price, row.ask_unit_price),
					_format_book(row.bid_unit_price, row.ask_unit_price), TONE_NORMAL]
		COLUMN_TRADE:
			if !row.is_tradable:
				return [NOT_APPLICABLE, "", TONE_NORMAL]
			return [_format_rate(row.bought_rate - row.sold_rate, multiplier, true),
					"Bought %s/d, sold %s/d" % [_format_rate(row.bought_rate, multiplier) + unit,
					_format_rate(row.sold_rate, multiplier) + unit], TONE_NORMAL]
		COLUMN_MARKET:
			if !row.is_tradable:
				return [NOT_APPLICABLE, "", TONE_NORMAL]
			return [_format_rate(row.bought_rate, multiplier), "", TONE_NORMAL]
		COLUMN_INTERNAL:
			return [_format_rate(row.internal_volume, multiplier), "", TONE_NORMAL]
		COLUMN_DESIRED_RATE, COLUMN_CRITICAL_RATE:
			return [NO_VALUE if row.is_tradable else NOT_APPLICABLE, "", TONE_NORMAL]
		COLUMN_STOCK:
			# The inventory's breach flags date from the start of the last interval, the stock and
			# levels from its end, so the tone compares what the row shows.
			var tone := TONE_NORMAL
			if row.stock < row.critical_level:
				tone = TONE_ALERT
			elif row.stock < row.desired_level:
				tone = TONE_WARNING
			return [_format_percent(_get_cover_share(row.stock, horizon_need)),
					_get_stock_tooltip(row, multiplier, unit), tone]
		COLUMN_CRITICAL_LEVEL:
			return [_format_percent(_get_cover_share(row.critical_level, horizon_need)),
					"Critical level " + _format_quantity(row.critical_level, multiplier, unit),
					TONE_NORMAL]
		COLUMN_DESIRED_LEVEL:
			return [_format_percent(_get_cover_share(row.desired_level, horizon_need)),
					"Desired level " + _format_quantity(row.desired_level, multiplier, unit),
					TONE_NORMAL]
		COLUMN_HEDGED:
			if !row.is_tradable:
				return [NOT_APPLICABLE, "", TONE_NORMAL]
			return [NO_VALUE, "Contracted within the horizon: %s to take, %s to give." % [
					_format_amount(row.window_long, unit), _format_amount(row.window_short, unit)],
					TONE_NORMAL]
	return ["", "", TONE_NORMAL]


# A quarter row's cell in [param column], as [text, tooltip]. Quantities from positions are in
# trade units already.
func _get_quarter_cell(column: int, row: RowData, quarter: QuarterData) -> Array:
	var unit := _get_unit_text(row.resource_type)
	match column:
		COLUMN_LOCAL, COLUMN_PRICE:
			return [_format_price(quarter.unit_price),
					_format_book(quarter.bid_unit_price, quarter.ask_unit_price)]
		COLUMN_SPREAD:
			return [_format_spread(quarter.bid_unit_price, quarter.ask_unit_price),
					_format_book(quarter.bid_unit_price, quarter.ask_unit_price)]
		COLUMN_TRADE:
			if !quarter.has_positions or !(quarter.days > 0.0):
				return ["", ""]
			return [_format_per_day(quarter.position / quarter.days, true),
					"Contracted " + _format_amount(quarter.position, unit)]
		COLUMN_MARKET:
			if !quarter.has_positions or !(quarter.days > 0.0):
				return ["", ""]
			return [_format_per_day(quarter.open_interest / quarter.days),
					"Open interest " + _format_amount(quarter.open_interest, unit)]
		COLUMN_HEDGED:
			return [NO_VALUE, ""]
	return ["", ""]


func _get_local_tooltip(row: RowData, unit: String) -> String:
	var multiplier := _trade_unit_multipliers[row.resource_type]
	var lines := PackedStringArray()
	if !row.is_tradable:
		lines.append("Not traded: it can't be carried.")
	elif !row.has_market_price:
		lines.append("No market price.")
	else:
		lines.append("Market price %s (%s)" % [_format_price(row.unit_price),
				_format_book(row.bid_unit_price, row.ask_unit_price).to_lower()])
	if row.unmet_rate:
		lines.append("Unmet %s/d" % (_format_rate(row.unmet_rate, multiplier) + unit))
	if row.curtailed_rate:
		lines.append("Curtailed %s/d" % (_format_rate(row.curtailed_rate, multiplier) + unit))
	if row.disposal_rate:
		lines.append("Disposed of %s/d" % (_format_rate(row.disposal_rate, multiplier) + unit))
	return "\n".join(lines)


func _get_stock_tooltip(row: RowData, multiplier: float, unit: String) -> String:
	var outflow := row.use + row.sold_rate
	var cover_text := UNBOUNDED if !outflow else IVQFormat.number(
			row.stock / outflow / IVUnits.DAY, 2)
	return "Stock %s\nIn transit %s, outbound %s\nBuffer stock %s\nCover %s d" % [
			_format_quantity(row.stock, multiplier, unit),
			_format_quantity(row.in_transit, multiplier, unit),
			_format_quantity(row.outbound, multiplier, unit),
			_format_quantity(row.buffer_stock, multiplier, unit),
			cover_text]


func _get_market_count_text(market_count: float) -> String:
	var n_facilities := roundi(market_count)
	if n_facilities == 1:
		return "1 facility deals in it."
	return "%d facilities deal in it." % n_facilities


func _get_row_title(resource_type: int) -> String:
	var title := tr(_resource_names[resource_type])
	var trade_unit := _trade_units[resource_type]
	if trade_unit == &"1":
		return title
	var trade_class := _trade_classes[resource_type]
	var class_text := TRADE_CLASS_TEXTS[trade_class] if trade_class != -1 else ""
	return "%s (%s%s)" % [title, class_text, trade_unit]


func _get_unit_text(resource_type: int) -> String:
	var trade_unit := _trade_units[resource_type]
	return "" if trade_unit == &"1" else " " + trade_unit


# Stock or a level as a share of one horizon's outflow: INF where nothing flows out of a stock
# held, NAN where nothing is held or flows.
func _get_cover_share(quantity: float, horizon_need: float) -> float:
	if horizon_need > 0.0:
		return quantity / horizon_need
	return INF if quantity > 0.0 else NAN


func _format_price(unit_price: float) -> String:
	if !(unit_price > 0.0):
		return NO_VALUE
	return IVQFormat.number(unit_price, 3)


# Formats [param rate], in sim units per second, as trade units per day.
func _format_rate(rate: float, multiplier: float, is_signed := false) -> String:
	return _format_per_day(rate * IVUnits.DAY / multiplier, is_signed)


func _format_per_day(per_day: float, is_signed := false) -> String:
	if !per_day:
		return "0"
	var text := IVQFormat.number(per_day, 2)
	return "+" + text if is_signed and per_day > 0.0 else text


# Formats [param quantity], in sim units, in trade units.
func _format_quantity(quantity: float, multiplier: float, unit: String) -> String:
	return _format_amount(quantity / multiplier, unit)


func _format_amount(trade_quantity: float, unit: String) -> String:
	return ("0" if !trade_quantity else IVQFormat.number(trade_quantity, 3)) + unit


func _format_percent(share: float) -> String:
	if is_nan(share):
		return NO_VALUE
	if is_inf(share):
		return UNBOUNDED
	return "%.f" % (share * 100.0)


func _format_spread(bid_unit_price: int, ask_unit_price: int) -> String:
	if !bid_unit_price or !ask_unit_price:
		return NO_VALUE
	return IVQFormat.number(200.0 * (ask_unit_price - bid_unit_price)
			/ (ask_unit_price + bid_unit_price), 2)


func _format_book(bid_unit_price: int, ask_unit_price: int) -> String:
	return "Bid %s / ask %s" % [str(bid_unit_price) if bid_unit_price else NO_VALUE,
			str(ask_unit_price) if ask_unit_price else NO_VALUE]


func _format_horizon(horizon: float) -> String:
	var days := horizon / IVUnits.DAY
	if days >= 730.0:
		return "H %s y" % IVQFormat.number(days / 365.25, 2)
	return "H %s d" % IVQFormat.number(days, 2)


func _format_quarter(ordinal_qtr: int) -> String:
	@warning_ignore("integer_division")
	var year := ordinal_qtr / 4
	return "%dQ%d" % [year, ordinal_qtr % 4 + 1]


# ****************************** INNER CLASSES ********************************
# Columns are right-anchored, as in itab_budget.gd: a resource is a full-width foldable whose
# name is the native title and whose value cells are a right-aligned title control; its quarter
# rows and the out-of-scroll header end at the same right edge, the header past the vertical
# scrollbar by a trailing spacer.

class RowData extends RefCounted:
	# One resource's values, gathered on the proxy thread. Rates are sim units per second,
	# quantities sim units, local price sim units, unit prices $ per trade unit, and the window
	# sums trade units.
	var resource_type: int
	var is_tradable: bool
	var has_market_price: bool
	var local_price: float
	var unit_price: int
	var bid_unit_price: int
	var ask_unit_price: int
	var bought_rate: float
	var sold_rate: float
	var internal_volume: float
	var market_count: float
	var use: float
	var stock: float
	var in_transit: float
	var outbound: float
	var buffer_stock: float
	var critical_level: float
	var desired_level: float
	var unmet_rate: float
	var curtailed_rate: float
	var disposal_rate: float
	var window_long: float
	var window_short: float
	var quarters: Array[QuarterData] = []


class QuarterData extends RefCounted:
	# One quarter of a resource's forward market; positions are in trade units (+ long).
	var ordinal_qtr: int
	var is_beyond_horizon := false
	var has_positions := false
	var days: float
	var unit_price: float # NAN without a price
	var bid_unit_price: int
	var ask_unit_price: int
	var position: float
	var open_interest: float


class MarketsHeaderRow extends HBoxContainer:
	# The view buttons and the facility's horizon fill the left; the column headers sit over
	# the value cells.

	signal view_selected(view: int)

	var _indent_spacer := Control.new()
	var _flows_button := Button.new()
	var _cover_button := Button.new()
	var _horizon_label := Label.new()
	var _cells: Array[Label] = []
	var _trailing_spacer := Control.new()
	var _column_width: float
	var _cell_gutter: float
	var _foldable_indent: float
	var _scroll_correction: float


	func _init(column_width: float, cell_gutter: float, foldable_indent: float,
			scroll_correction: float) -> void:
		_column_width = column_width
		_cell_gutter = cell_gutter
		_foldable_indent = foldable_indent
		_scroll_correction = scroll_correction
		size_flags_horizontal = SIZE_FILL
		add_theme_constant_override(&"separation", 0)  # explicit gutters/widths only
		add_child(_indent_spacer)
		var button_group := ButtonGroup.new()
		_flows_button.text = "Flows"
		_flows_button.tooltip_text = "Prices and flows"
		_cover_button.text = "Cover"
		_cover_button.tooltip_text = ("A facility's stock, stock levels and contracts, against its"
				+ "\ntime horizon (H)")
		for button: Button in [_flows_button, _cover_button]:
			button.toggle_mode = true
			button.button_group = button_group
			button.size_flags_vertical = SIZE_SHRINK_CENTER
			add_child(button)
		_flows_button.pressed.connect(view_selected.emit.bind(VIEW_FLOWS))
		_cover_button.pressed.connect(view_selected.emit.bind(VIEW_COVER))
		_horizon_label.size_flags_horizontal = SIZE_EXPAND_FILL
		_horizon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_horizon_label.mouse_filter = MOUSE_FILTER_PASS
		_horizon_label.tooltip_text = "The facility's time horizon"
		add_child(_horizon_label)
		_cells.resize(N_CELLS)
		for i in N_CELLS:
			var cell := ITabMarkets._make_cell_label()
			add_child(cell)
			_cells[i] = cell
		add_child(_trailing_spacer)
		var gui_size: int = IVSettingsManager.get_setting(&"gui_size")
		_resize(gui_size)
		IVSettingsManager.changed.connect(_settings_listener)


	func set_header(shown_view: int, is_cover_enabled: bool, horizon_text: String,
			columns: Array[int]) -> void:
		_flows_button.set_pressed_no_signal(shown_view == VIEW_FLOWS)
		_cover_button.set_pressed_no_signal(shown_view == VIEW_COVER)
		_cover_button.disabled = !is_cover_enabled
		_horizon_label.text = horizon_text
		for i in N_CELLS:
			_cells[i].text = COLUMN_HEADERS[columns[i]]
			_cells[i].tooltip_text = COLUMN_TOOLTIPS[columns[i]]


	func _resize(gui_size: int) -> void:
		var multiplier := IVCoreSettings.gui_size_multipliers[gui_size]
		_indent_spacer.custom_minimum_size.x = _foldable_indent * multiplier
		_trailing_spacer.custom_minimum_size.x = (_cell_gutter + _scroll_correction) * multiplier
		var cell_width := _column_width * multiplier
		for cell in _cells:
			cell.custom_minimum_size.x = cell_width


	func _settings_listener(setting: StringName, value: Variant) -> void:
		if setting == &"gui_size":
			var gui_size: int = value
			_resize(gui_size)


class MarketsGroup extends FoldableContainer:
	# One resource: the native title shows its name, a right-aligned title control its cells,
	# and it unfolds to its quarter rows. One with no quarters gets a blank fold-icon substitute
	# and can't be unfolded.

	var _rows_vbox := VBoxContainer.new()
	var _cells: Array[Label] = []
	var _gutter := Control.new()
	var _memory: Dictionary
	var _fold_icon_substitute: Texture2D
	var _column_width: float
	var _cell_gutter: float
	var _memory_key: String
	var _is_singular: bool


	func _init(memory: Dictionary, column_width: float, cell_gutter: float,
			fold_icon_substitute: Texture2D) -> void:
		_memory = memory
		_column_width = column_width
		_cell_gutter = cell_gutter
		_fold_icon_substitute = fold_icon_substitute
		size_flags_horizontal = SIZE_FILL  # full width; cells right-align to the content edge
		var block := HBoxContainer.new()
		block.add_theme_constant_override(&"separation", 0)  # explicit gutters/widths only
		_cells.resize(N_CELLS)
		for i in N_CELLS:
			var cell := ITabMarkets._make_cell_label()
			block.add_child(cell)
			_cells[i] = cell
		block.add_child(_gutter)
		add_title_bar_control(block)
		add_child(_rows_vbox)
		folding_changed.connect(_on_folding_changed)
		var gui_size: int = IVSettingsManager.get_setting(&"gui_size")
		_resize(gui_size)
		IVSettingsManager.changed.connect(_settings_listener)


	func set_group(memory_key: String, title_text: String, cells: PackedStringArray,
			tooltips: PackedStringArray, tones: PackedByteArray, quarter_rows: Array) -> void:
		title = title_text
		ITabMarkets._apply_cells(_cells, cells, tooltips, tones)
		_memory_key = memory_key
		if quarter_rows.is_empty():
			add_theme_icon_override(&"folded_arrow", _fold_icon_substitute)
			_is_singular = true
			folded = true
		else:
			remove_theme_icon_override(&"folded_arrow")
			_is_singular = false
			folded = _memory.get(_memory_key, true)  # start closed

		var n_rows := quarter_rows.size()
		var n_children := _rows_vbox.get_child_count()
		while n_children < n_rows:
			_rows_vbox.add_child(MarketsRow.new(_column_width, _cell_gutter, SUBGROUP_INDENT))
			n_children += 1
		for i in n_rows:
			var row_data: Array = quarter_rows[i]
			var name_text: String = row_data[0]
			var row_cells: PackedStringArray = row_data[1]
			var row_tooltips: PackedStringArray = row_data[2]
			var row_tones: PackedByteArray = row_data[3]
			var row: MarketsRow = _rows_vbox.get_child(i)
			row.set_row(name_text, row_cells, row_tooltips, row_tones)
			row.show()
		for i in range(n_rows, n_children):
			var unused_row: Control = _rows_vbox.get_child(i)
			unused_row.hide()


	func _on_folding_changed(is_folded_: bool) -> void:
		if !_is_singular:
			_memory[_memory_key] = is_folded_
			return
		if !is_folded_:  # a resource with no quarters can't be unfolded
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


class MarketsRow extends HBoxContainer:
	# One quarter of a resource. The name fills the left; the value cells hug the right so they
	# line up with the foldable's right-aligned cells.

	var _indent_spacer := Control.new()
	var _name_label := Label.new()
	var _cells: Array[Label] = []
	var _gutter := Control.new()
	var _column_width: float
	var _cell_gutter: float
	var _indent: float


	func _init(column_width: float, cell_gutter: float, indent: float) -> void:
		_column_width = column_width
		_cell_gutter = cell_gutter
		_indent = indent
		size_flags_horizontal = SIZE_FILL
		add_theme_constant_override(&"separation", 0)  # explicit gutters/widths only
		add_child(_indent_spacer)
		_name_label.clip_text = true
		_name_label.size_flags_horizontal = SIZE_EXPAND_FILL
		add_child(_name_label)
		_cells.resize(N_CELLS)
		for i in N_CELLS:
			var cell := ITabMarkets._make_cell_label()
			add_child(cell)
			_cells[i] = cell
		add_child(_gutter)
		var gui_size: int = IVSettingsManager.get_setting(&"gui_size")
		_resize(gui_size)
		IVSettingsManager.changed.connect(_settings_listener)


	func set_row(name_text: String, cells: PackedStringArray, tooltips: PackedStringArray,
			tones: PackedByteArray) -> void:
		_name_label.text = name_text
		ITabMarkets._apply_cells(_cells, cells, tooltips, tones)


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
