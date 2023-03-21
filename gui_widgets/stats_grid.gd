# stats_grid.gd
# This file is part of Astropolis
# Copyright 2019-2023 Charlie Whitfield, all rights reserved
# *****************************************************************************
extends MarginContainer

signal has_stats_changed(has_stats)

const ivutils := preload("res://ivoyager/static/utils.gd")

const NUMBER := IVQuantityFormatter.NUMBER
const NAMED_NUMBER := IVQuantityFormatter.NAMED_NUMBER
const PREFIXED_UNIT := IVQuantityFormatter.PREFIXED_UNIT

# GUI values - parent should set only once at init
#var update_interval := 1.0 # seconds
var zero_value := "-" # set "" to print zeros w/ units
var show_missing_interface := true
var force_rows := true # if false, skip rows missing in all interfaces
var min_columns := 3 # inclues row labels
var required_component := "operations"

var content := [
	# label_txt, target_path
	["LABEL_POPULATION", "get_population_and_crew_total", [NAMED_NUMBER]],
	["LABEL_ENERGY", "operations/get_power_total", [PREFIXED_UNIT, "W"]],
	["LABEL_ECONOMY", "operations/lfq_gross_output", [NUMBER, "$B"]],
	["LABEL_MANUFACTURING", "operations/get_manufacturing_mass_flow_total", [PREFIXED_UNIT, "t/d"]],
	["LABEL_CONSTRUCTIONS", "operations/constructions", [PREFIXED_UNIT, "t"]],
	["LABEL_COMPUTATIONS", "metaverse/computations", [PREFIXED_UNIT, "flops"]],
	["LABEL_INFORMATION", "metaverse/get_information", [PREFIXED_UNIT, "bits"]],
	["LABEL_BIOPRODUCTIVITY", "biome/bioproductivity", [PREFIXED_UNIT, "t/d"]],
	["LABEL_BIOMASS", "biome/biomass", [PREFIXED_UNIT, "t"]],
	["LABEL_BIODIVERSITY", "biome/get_biodiversity", [NUMBER, "species"]],
]

var targets := ["PLANET_EARTH", "PROXY_OFF_EARTH"]
var replacement_names := [] # use instead of Interface name
var fallback_names := ["", ""] # if "" will uses targets string

var _state: Dictionary = IVGlobal.state
var _is_running := false
var _network_targets: Array
var _network_fallback_names: Array
var _network_replacement_names: Array

onready var _quantity_formatter: IVQuantityFormatter = IVGlobal.program.QuantityFormatter
onready var _tree: SceneTree = get_tree()
onready var _grid: GridContainer = $Grid


func update_targets(targets_: Array, replacement_names_ := [], fallback_names_ := []) -> void:
	targets = targets_
	replacement_names = replacement_names_
	fallback_names = fallback_names_
	update()


func update() -> void:
	MainThreadGlobal.call_on_ai_thread(self, "_set_network_data")


# *****************************************************************************
# AI thread !!!!

func _set_network_data(data: Array) -> void:
	assert(!data) # empty now but we will fill it
	_network_targets = targets # for thread safety
	_network_replacement_names = replacement_names
	_network_fallback_names = fallback_names
	
	# get Interfaces and check required components
	var interfaces := []
	var has_data := false
	for target in _network_targets:
		var interface = AIGlobal.interfaces_by_name.get(target)
		if interface:
			if !interface.get(required_component):
				interface = null
		if interface:
			if interface.has_method("calculate_proxy_data"): # ProxyInterface
				interface.calculate_proxy_data()
			has_data = true
		if interface or show_missing_interface:
			interfaces.append(interface) # may be null
	if !has_data:
		call_deferred("_no_data")
		return

	# do counts
	var n_interfaces := interfaces.size()
	var n_spacers := 0
	if n_interfaces < min_columns - 1:
		n_spacers = min_columns - n_interfaces - 1
	
	# start building data
	data.append(n_interfaces + 1 + n_spacers) # n_columns
	
	# headers
	var i := 0
	while i < n_interfaces:
		var interface: Interface = interfaces[i]
		var gui_name := ""
		if _network_replacement_names:
			gui_name = _network_replacement_names[i]
		elif interface:
			gui_name = interface.gui_name
		elif _network_fallback_names[i]:
			gui_name = _network_fallback_names[i]
		else:
			gui_name = _network_targets[i]
		data.append(gui_name) # header
		i += 1
	i = 0
	while i < n_spacers:
		data.append("")
		i += 1

	# data rows
	var row := 1
	for line_array in content:
		var path: String = line_array[1]
		var values := []
		var is_data := false
		for interface in interfaces:
			var value = 0.0
			if interface:
				value = ivutils.get_path_result(interface, path)
				if value != null:
					is_data = true
			values.append(value)
		
		if !force_rows and !is_data:
			continue # don't add row
			
		# add row label
		var row_text: String = line_array[0] # row label
		data.append(row_text)
		
		# get args for QuantityFormatter
		var args: Array = line_array[2]
		var n_args: int = args.size()
		var option_type: int = args[0]
		var unit: String = args[1] if n_args > 1 else ""
		var precision: int = args[2] if n_args > 2 else 3
		var num_type: int = args[3] if n_args > 3 else IVQuantityFormatter.NUM_DYNAMIC
		var long_form: bool = args[4] if n_args > 4 else false
		var case_type: int = args[5] if n_args > 5 else IVQuantityFormatter.CASE_MIXED
		
		# add values
		for value in values:
			var value_text := zero_value
			if value != null and (value or !zero_value):
				value_text = _quantity_formatter.number_option(value, option_type, unit,
						precision, num_type, long_form, case_type)
			data.append(value_text)
		i = 0
		while i < n_spacers:
			data.append("")
			i += 1
		
		# next row
		row += 1

	# add n_rows and finish
	data.append(row)
	call_deferred("_build_grid", data)


# *****************************************************************************
# Main thread !!!!

func _no_data() -> void:
	_grid.hide()
	emit_signal("has_stats_changed", false)


func _build_grid(data: Array) -> void:
	var n_columns: int = data[0] # includes labels
	_grid.columns = n_columns
	var n_rows: int = data[-1] # includes headers
	var n_cells_needed := n_rows * n_columns
	var n_cells := _grid.get_child_count()
	while n_cells < n_cells_needed:
		var label := Label.new()
		label.align = Label.ALIGN_CENTER
		label.size_flags_horizontal = SIZE_EXPAND_FILL
		_grid.add_child(label)
		n_cells += 1
		
	# headers
	var column := 1
	while column < n_columns:
		var header_label: Label = _grid.get_child(column)
		var header_text: String = data[column]
		header_label.text = header_text
		header_label.align = Label.ALIGN_CENTER
		header_label.show()
		column += 1
		
	# data rows
	var row := 1
	while row < n_rows:
		var row_label: Label = _grid.get_child(row * n_columns)
		var row_text: String = data[row * n_columns]
		row_label.text = row_text
		row_label.align = Label.ALIGN_LEFT
		row_label.show()
		
		# values
		column = 1
		while column < n_columns:
			var value_label: Label = _grid.get_child(row * n_columns + column)
			var value_text: String = data[row * n_columns + column]
			value_label.text = value_text
			value_label.show()
			column += 1
		row += 1
	
	# hide unsused cells
	while n_cells > n_cells_needed:
		n_cells -= 1
		var label: Label = _grid.get_child(n_cells)
		label.hide()
	
	emit_signal("has_stats_changed", true)
	_grid.show()
	
