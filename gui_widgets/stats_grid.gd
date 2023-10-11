# stats_grid.gd
# This file is part of Astropolis
# Copyright 2019-2023 Charlie Whitfield, all rights reserved
# *****************************************************************************
extends MarginContainer

# IDEA: Click on value to cycle representation. E.g., for population:
#     1.23 Quadrillion
#     1.23 x 10^15
#     1,234,567,890,123,456

signal has_stats_changed(has_stats)

const ivutils := preload("res://addons/ivoyager_core/static/utils.gd")


# GUI values - parent should set only once at init
#var update_interval := 1.0 # seconds
var zero_value := "-" # set "" to print zeros w/ units
var show_missing_interface := true
var force_rows := true # if false, skip rows missing in all interfaces
var min_columns := 3 # inclues row labels
var required_component := "operations"


var content := [
	# label_txt, target_path
	[&"LABEL_POPULATION", "get_population_and_crew_total", IVQFormat.named_number],
	[&"LABEL_ECONOMY", "operations/lfq_gross_output", IVQFormat.prefixed_named_number.bind("$")],
	[&"LABEL_ENERGY", "operations/get_power_total", IVQFormat.prefixed_unit.bind("W")],
	[&"LABEL_MANUFACTURING", "operations/get_manufacturing_mass_flow_total",
			IVQFormat.prefixed_unit.bind("t/d")],
	[&"LABEL_CONSTRUCTIONS", "operations/constructions", IVQFormat.prefixed_unit.bind("t")],
	[&"LABEL_COMPUTATIONS", "metaverse/computations", IVQFormat.prefixed_unit.bind("flops")],
	[&"LABEL_INFORMATION", "metaverse/get_information", IVQFormat.prefixed_unit.bind("bits")],
	[&"LABEL_BIOPRODUCTIVITY", "biome/bioproductivity", IVQFormat.prefixed_unit.bind("t/d")],
	[&"LABEL_BIOMASS", "biome/biomass", IVQFormat.prefixed_unit.bind("t")],
	[&"LABEL_BIODIVERSITY", "biome/get_biodiversity", IVQFormat.fixed_unit.bind("species")],
]

var targets := ["PLANET_EARTH", "PROXY_OFF_EARTH"]
var replacement_names := [] # use instead of Interface name
var fallback_names := ["", ""] # if "" will uses targets string

#var _state: Dictionary = IVGlobal.state
#var _is_running := false
var _network_targets: Array
var _network_fallback_names: Array
var _network_replacement_names: Array

#@onready var _tree: SceneTree = get_tree()
@onready var _grid: GridContainer = $Grid


func update_targets(targets_: Array, replacement_names_ := [], fallback_names_ := []) -> void:
	targets = targets_
	replacement_names = replacement_names_
	fallback_names = fallback_names_
	update()


func update() -> void:
	MainThreadGlobal.call_ai_thread(_set_network_data)


# *****************************************************************************
# AI thread !!!!

func _set_network_data() -> void:
	var data := []
	_network_targets = targets # for thread safety
	_network_replacement_names = replacement_names
	_network_fallback_names = fallback_names
	
	# get Interfaces and check required components
	var interfaces := []
	var has_data := false
	for target in _network_targets:
		var interface := Interface.get_interface_by_name(target)
		if interface:
			if !interface.get(required_component):
				interface = null
		if interface:
			if interface.has_method(&"calculate_proxy_data"): # ProxyInterface
				@warning_ignore("unsafe_method_access")
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
		
		var format_callable: Callable = line_array[2]
		
		# add values
		for value in values:
			var value_text: String
			if value != null and (value or !zero_value):
				value_text = format_callable.call(value)
			else:
				value_text = zero_value
			data.append(value_text)
		i = 0
		while i < n_spacers:
			data.append("")
			i += 1
		
		# next row
		row += 1

	# add n_rows and finish
	data.append(row)
	_build_grid.call_deferred(data)


# *****************************************************************************
# Main thread !!!!

func _no_data() -> void:
	_grid.hide()
	has_stats_changed.emit(false)


func _build_grid(data: Array) -> void:
	var n_columns: int = data[0] # includes labels
	_grid.columns = n_columns
	var n_rows: int = data[-1] # includes headers
	var n_cells_needed := n_rows * n_columns
	var n_cells := _grid.get_child_count()
	while n_cells < n_cells_needed:
		var label := Label.new()
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.size_flags_horizontal = SIZE_EXPAND_FILL
		_grid.add_child(label)
		n_cells += 1
		
	# headers
	var column := 1
	while column < n_columns:
		var header_label: Label = _grid.get_child(column)
		var header_text: String = data[column]
		header_label.text = header_text
		header_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		header_label.show()
		column += 1
		
	# data rows
	var row := 1
	while row < n_rows:
		var row_label: Label = _grid.get_child(row * n_columns)
		var row_text: String = data[row * n_columns]
		row_label.text = row_text
		row_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
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
	
	has_stats_changed.emit(true)
	_grid.show()

