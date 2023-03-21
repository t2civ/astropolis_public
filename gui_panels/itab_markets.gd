# itab_markets.gd
# This file is part of Astropolis
# Copyright 2019-2023 Charlie Whitfield, all rights reserved
# *****************************************************************************
class_name ITabMarkets
extends MarginContainer
const SCENE := "res://astropolis_public/gui_panels/itab_markets.tscn"

# Tabs follow row enumerations in resource_classes.tsv.
# TODO: complete localizations


signal header_changed(new_header)

const units := preload("res://ivoyager/static/units.gd")
const MULTIPLIERS := Units.MULTIPLIERS

const N_COLUMNS := 6

const TRADE_CLASS_TEXTS := [ # correspond to TradeClasses
	"",
	"",
	"ice, ",
	"liq, ",
	"cryo, ",
	"",
	"",
]

const PERSIST_MODE := IVEnums.PERSIST_PROCEDURAL
const PERSIST_PROPERTIES := [
	"current_tab",
	"_on_ready_tab",
]

# persisted
var current_tab := 0
var _on_ready_tab := 0

# not persisted

var _header_suffix := "  -  " + tr("LABEL_MARKETS")
var _subheader_suffixes := [
	" / " + tr("LABEL_ENERGY"),
	" / " + tr("LABEL_ORES"),
	" / " + tr("LABEL_VOLATILES"),
	" / " + tr("LABEL_MATERIALS"),
	" / " + tr("LABEL_MANUFACTURED"),
	" / " + tr("LABEL_BIOLOGICALS"),
	" / " + tr("LABEL_CYBER"),
]
var _show_subheader := true
var _state: Dictionary = IVGlobal.state
var _selection_manager: SelectionManager
var _suppress_tab_listener := true

var _name_column_width := 250.0 # TODO: resize on GUI resize (also in RowItem)

# table indexing
var _tables: Dictionary = IVGlobal.tables
var _n_resources: int = _tables.n_resources
var _resource_names: Array = _tables.resources.name
var _trade_classes: Array = _tables.resources.trade_class
var _trade_units: Array = _tables.resources.trade_unit
var _resource_classes_resources: Array = _tables.resource_classes_resources # array of arrays
var _qf: IVQuantityFormatter = IVGlobal.program.QuantityFormatter

onready var _no_markets_label: Label = $NoMarkets
onready var _tab_container: TabContainer = $TabContainer
onready var _vboxes := [
	$"%EnergyVBox",
	$"%OresVBox",
	$"%VolatilesVBox",
	$"%MaterialsVBox",
	$"%ManufacturedVBox",
	$"%BiologicalsVBox",
	$"%CyberVBox",
]
onready var _col0_spacers := [
	$TabContainer/Energy/Hdrs/Spacer,
	$TabContainer/Ores/Hdrs/Spacer,
	$TabContainer/Volatiles/Hdrs/Spacer,
	$TabContainer/Materials/Hdrs/Spacer,
	$TabContainer/Manufactured/Hdrs/Spacer,
	$TabContainer/Biologicals/Hdrs/Spacer,
	$TabContainer/Cyber/Hdrs/Spacer,
]


func _ready() -> void:
	IVGlobal.connect("about_to_free_procedural_nodes", self, "_clear")
	connect("visibility_changed", self, "_update_tab")
	_selection_manager = IVWidgets.get_selection_manager(self)
	_selection_manager.connect("selection_changed", self, "_update_tab")
	_tab_container.connect("tab_changed", self, "_select_tab")
	# rename tabs for abreviated localization
	$TabContainer/Energy.name = "TAB_MKS_ENERGY"
	$TabContainer/Ores.name = "TAB_MKS_ORES"
	$TabContainer/Volatiles.name = "TAB_MKS_VOLATILES"
	$TabContainer/Materials.name = "TAB_MKS_MATERIALS"
	$TabContainer/Manufactured.name = "TAB_MKS_MANUFACTURED"
	$TabContainer/Biologicals.name = "TAB_MKS_BIOLOGICALS"
	$TabContainer/Cyber.name = "TAB_MKS_CYBER"
	for col0_spacer in _col0_spacers:
		col0_spacer.rect_min_size.x = _name_column_width - 10.0
	_tab_container.set_current_tab(_on_ready_tab)
	_suppress_tab_listener = false
	_update_tab()


func _clear() -> void:
	if _selection_manager:
		_selection_manager.disconnect("selection_changed", self, "_update_tab")
		_selection_manager = null
	disconnect("visibility_changed", self, "_update_tab")
	_tab_container.disconnect("tab_changed", self, "_select_tab")


func timer_update() -> void:
	_update_tab()


func _select_tab(tab: int) -> void:
	if !_suppress_tab_listener:
		_on_ready_tab = tab
	current_tab = tab
	_update_tab()


func _update_tab(_suppress_camera_move := false) -> void:
	if !visible or !_state.is_running:
		return
	var selection_data := _selection_manager.get_info_panel_data()
	if !selection_data:
		return
	var target_name: String = selection_data[0]
	var header_text: String = selection_data[1] + _header_suffix
	var is_developed: bool = selection_data[2]
	var has_market := is_developed and (target_name.begins_with("FACILITY_") \
			or target_name.begins_with("PROXY_"))
	if has_market:
		MainThreadGlobal.call_on_ai_thread(self, "_get_ai_data", [target_name])
		header_text += _subheader_suffixes[current_tab]
	else:
		_update_no_markets(is_developed)
	emit_signal("header_changed", header_text)


func _update_no_markets(is_developed := false) -> void:
	_tab_container.hide()
	_no_markets_label.text = "LABEL_NO_MARKETS_SELECT_ENTITY" if is_developed \
			else "LABEL_NO_MARKETS"
	_no_markets_label.show()


# *****************************************************************************
# AI thread !!!!

func _get_ai_data(data: Array) -> void:
	var target_name: String = data.pop_back()
	assert(!data)
	var interface: Interface = AIGlobal.get_interface_by_name(target_name)
	if !interface:
		call_deferred("_update_no_markets")
		return
	var inventory := interface.inventory
	if !inventory:
		call_deferred("_update_no_markets")
		return
	var tab := current_tab
	var resource_class_resources: Array = _resource_classes_resources[tab]
	var n_resources := resource_class_resources.size()
	var i := 0
	while i < n_resources:
		var resource_type: int = resource_class_resources[i]
		data.append(resource_type)
		data.append(inventory.prices[resource_type])
		data.append(inventory.bids[resource_type])
		data.append(inventory.asks[resource_type])
		data.append(inventory.get_in_stock(resource_type))
		data.append(inventory.contracteds[resource_type])
		i += 1
	
	data.append(n_resources)
	data.append(tab)
#	data.append(target_name)
	call_deferred("_update_tab_display", data)
	

# *****************************************************************************
# Main thread !!!!

func _update_tab_display(data: Array) -> void:
#	var target_name: String = data.pop_back()
	var tab: int = data.pop_back()
	var n_resources: int = data.pop_back()

	# make rows as needed
	var vbox: VBoxContainer = _vboxes[tab]
	var n_children := vbox.get_child_count()
	while n_children < n_resources:
		var hbox := HBoxContainer.new()
		hbox.size_flags_horizontal = SIZE_FILL
		var column := 0
		while column < N_COLUMNS:
			var label := Label.new()
			label.size_flags_horizontal = SIZE_EXPAND_FILL
			if column == 0: # resource name
				label.rect_min_size.x = _name_column_width
			else: # value
				label.align = Label.ALIGN_CENTER
			hbox.add_child(label)
			column += 1
		vbox.add_child(hbox)
		n_children += 1
	
	var i := 0
	while i < n_resources:
		var resource_type: int = data[i * N_COLUMNS]
		var price: float = data[i * N_COLUMNS + 1]
		var bid: float = data[i * N_COLUMNS + 2]
		var ask: float = data[i * N_COLUMNS + 3]
		var in_stock: float = data[i * N_COLUMNS + 4]
		var contracted: float = data[i * N_COLUMNS + 5]
		
		var trade_class: int = _trade_classes[resource_type]
		var trade_unit: String = _trade_units[resource_type]
		
		in_stock /= MULTIPLIERS[trade_unit]
		contracted /= MULTIPLIERS[trade_unit]
		
		var resource_text: String = (
			tr(_resource_names[resource_type])
			+ " (" + TRADE_CLASS_TEXTS[trade_class]
			+ trade_unit + ")"
		)
		var price_text := "" if is_nan(price) else _qf.number(price, 3)
		var bid_text := "" if is_nan(bid) else _qf.number(bid, 3)
		var ask_text := "" if is_nan(ask) else _qf.number(ask, 3)
		var in_stock_text := _qf.number(in_stock, 2) # FIXME: trade unit
		var contracted_text := _qf.number(contracted, 2) # FIXME: trade unit
		
		var hbox: HBoxContainer = vbox.get_child(i)
		hbox.get_child(0).text = resource_text
		hbox.get_child(1).text = price_text
		hbox.get_child(2).text = bid_text
		hbox.get_child(3).text = ask_text
		hbox.get_child(4).text = in_stock_text
		hbox.get_child(5).text = contracted_text
		i += 1
	
	# no show/hide needed if we always show all resources

	_no_markets_label.hide()
	_tab_container.show()



