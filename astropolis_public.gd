# astropolis_public.gd
# This file is part of Astropolis
# Copyright 2019-2023 Charlie Whitfield, all rights reserved
# *****************************************************************************

const EXTENSION_NAME := "Astropolis Public"
const EXTENSION_VERSION := "0.0.2"
const EXTENSION_BUILD := "" # hotfix or debug build
const EXTENSION_STATE := "prototype" # 'dev', 'alpha', 'beta', 'rc', ''
const EXTENSION_YMD := 20230725

const AI_VERBOSE := false
const AI_VERBOSE2 := false
const IVOYAGER_VERBOSE := false
const USE_THREADS := false


func _extension_init():
	print("%s %s%s-%s %s" % [EXTENSION_NAME, EXTENSION_VERSION, EXTENSION_BUILD, EXTENSION_STATE,
			str(EXTENSION_YMD)])
	IVGlobal.connect("project_objects_instantiated", Callable(self, "_on_project_objects_instantiated"))
	IVGlobal.connect("project_nodes_added", Callable(self, "_on_project_nodes_added"))

	# properties
	AIGlobal.verbose = AI_VERBOSE
	AIGlobal.verbose2 = AI_VERBOSE2
	IVGlobal.verbose = IVOYAGER_VERBOSE
	IVGlobal.use_threads = USE_THREADS
	IVGlobal.save_file_extension = "AstropolisSave"
	IVGlobal.save_file_extension_name = "Astropolis Save"
	IVGlobal.start_time = 10.0 * IVUnits.YEAR
	IVGlobal.colors.great = Color.BLUE
	
	# translations
	var path_format := "res://astropolis_public/data/text/%s.position"
	IVGlobal.translations.append(path_format % "entities.en")
	IVGlobal.translations.append(path_format % "gui.en")
	IVGlobal.translations.append(path_format % "hints.en")
	
	# tables
	path_format = "res://astropolis_public/data/tables/%s.tsv"
	var postprocess_tables_append := [
		# primary tables
		path_format % "carrying_capacity_groups",
		path_format % "compositions",
		path_format % "facilities",
		path_format % "major_strata",
		path_format % "mod_classes",
		path_format % "modules",
		path_format % "op_classes",
		path_format % "op_groups",
		path_format % "operations",
		path_format % "players",
		path_format % "populations",
		path_format % "resource_classes",
		path_format % "resources",
		path_format % "spacecrafts", # replacement!
		path_format % "strata",
		path_format % "surveys",
		# primary table mods
		path_format % "asset_adjustments_mod",
		path_format % "planets_mod",
		path_format % "moons_mod",
		# enum x enum tables
		path_format % "compositions_resources_heterogeneities",
		path_format % "compositions_resources_percents",
		path_format % "facilities_operations_capacities",
		path_format % "facilities_operations_utilizations",
		path_format % "facilities_populations",
		path_format % "facilities_resources",
	]
	IVGlobal.postprocess_tables.append_array(postprocess_tables_append)
	
	# added/replaced classes
	IVProjectBuilder.prog_refs._InfoCloner_ = InfoCloner
	IVProjectBuilder.gui_nodes._AstroGUI_ = AstroGUI
	
	# extended
	IVProjectBuilder.procedural_classes._SelectionManager_ = SelectionManager
	
	# removed
	IVProjectBuilder.prog_refs.erase("_CompositionBuilder_")
	IVProjectBuilder.gui_nodes.erase("_CreditsPopup_")
	IVProjectBuilder.procedural_classes.erase("_Composition_") # using total replacement
	
	# add game units
	var multipliers := IVUnits.multipliers
	multipliers.flops = 1.0 / IVUnits.SECOND # base unit for computation
	multipliers.puhr = 1e16 * 3600.0 # 'processor unit hour'; 1e16 flops/s * hr


func _on_project_objects_instantiated() -> void:
	# program object changes
	
	var timekeeper: IVTimekeeper = IVGlobal.program.Timekeeper
	timekeeper.date_format = timekeeper.DATE_FORMAT_Y_M_D_Q_YQ_YM
	timekeeper.start_speed = 0
	
	var qty_txt_converter: IVQuantityFormatter = IVGlobal.program.QuantityFormatter
	qty_txt_converter.exp_str = "e"
	# https://sites.google.com/site/largenumbers/home/2-2/2-2-3-non-canonical-si-prefixes
#	qty_txt_converter.prefix_names.append("Bronto") # fictional e27
#	qty_txt_converter.prefix_names.append("Giop") # fictional e30
#	qty_txt_converter.prefix_symbols.append("B")
#	qty_txt_converter.prefix_symbols.append("Gp")
	
	var settings_manager: IVSettingsManager = IVGlobal.program.SettingsManager
	var defaults: Dictionary = settings_manager.defaults
	defaults.save_base_name = "Astropolis"
	
#	var model_builder: IVModelBuilder = IVGlobal.program.ModelBuilder
#	model_builder.model_tables.append("spacecrafts")
	
	
	# table additions (subtables, re-indexings, or other useful table items)
	var tables: Dictionary = IVTableData.tables
	# unique items
	tables.resource_type_electricity = tables.resources.unique_type.find("electricity")
	assert(tables.resource_type_electricity != -1)
	# table row subsets (arrays of row_types)
	tables.extraction_resources = IVTableData.get_db_true_rows("resources", "is_extraction")
	tables.maybe_free_resources = IVTableData.get_db_true_rows("resources", "maybe_free")
	tables.is_manufacturing_operations = IVTableData.get_db_true_rows("operations", "is_manufacturing")
	tables.extraction_operations = IVTableData.get_db_matching_rows("operations", "op_process_group",
			Enums.OpProcessGroup.OP_PROCESS_GROUP_EXTRACTION)
	# inverted table row subsets (array of indexes in the subset, where non-subset = -1)
	tables.resource_extractions = Utils.invert_subset_indexing(tables.extraction_resources,
			tables.n_resources)
	tables.operation_extractions = Utils.invert_subset_indexing(tables.extraction_operations,
			tables.n_operations)
	# one-to-many indexing (arrays of arrays)
	tables.op_classes_op_groups = Utils.invert_many_to_one_indexing(tables.op_groups.op_class,
			tables.n_op_classes) # an array of op_groups for each op_class
	tables.op_groups_operations = Utils.invert_many_to_one_indexing(tables.operations.op_group,
			tables.n_op_groups) # an array of operations for each op_group
	tables.resource_classes_resources = Utils.invert_many_to_one_indexing(tables.resources.resource_class,
			tables.n_resource_classes) # an array of resources for each resource_class
	
	# tests
	for i in tables.operations.input_resources:
		assert(tables.operations.input_resources.size() == tables.operations.input_quantities.size())
	for i in tables.operations.output_resources:
		assert(tables.operations.output_resources.size() == tables.operations.output_quantities.size())


func _on_project_nodes_added() -> void:
	IVProjectBuilder.move_top_gui_child_to_sibling("AstroGUI", "SplashScreen", true)


