# astropolis_public.gd
# This file is part of Astropolis
# Copyright 2019-2023 Charlie Whitfield, all rights reserved
# *****************************************************************************

const EXTENSION_NAME := "Astropolis Public"
const EXTENSION_VERSION := "0.0.1"
const EXTENSION_BUILD := "" # hotfix or debug build
const EXTENSION_STATE := "dev" # 'dev', 'alpha', 'beta', 'rc', ''
const EXTENSION_YMD := 20230321

const AI_VERBOSE := false
const AI_VERBOSE2 := false
const IVOYAGER_VERBOSE := false
const USE_THREADS := false


func _extension_init():
	print("%s %s%s-%s %s" % [EXTENSION_NAME, EXTENSION_VERSION, EXTENSION_BUILD, EXTENSION_STATE,
			str(EXTENSION_YMD)])
	IVGlobal.connect("project_objects_instantiated", self, "_on_project_objects_instantiated")
	IVGlobal.connect("project_nodes_added", self, "_on_project_nodes_added")

	# properties
	AIGlobal.verbose = AI_VERBOSE
	AIGlobal.verbose2 = AI_VERBOSE2
	IVGlobal.verbose = IVOYAGER_VERBOSE
	IVGlobal.use_threads = USE_THREADS
	IVGlobal.save_file_extension = "AstropolisSave"
	IVGlobal.save_file_extension_name = "Astropolis Save"
	IVGlobal.start_time = 10.0 * Units.YEAR
	IVGlobal.colors.great = Color.blue
#	IVGlobal.body_tables.append("spacecrafts")
	IVGlobal.unit_multipliers = Units.MULTIPLIERS
	IVGlobal.unit_functions = Units.FUNCTIONS
#	var globe_mesh: SphereMesh = IVGlobal.shared_resources.globe_mesh
#	globe_mesh.set_radial_segments(128) # default 64
#	globe_mesh.set_rings(64) # default 32
	
	# translations
	var path_format := "res://astropolis_public/data/text/%s.translation"
	IVGlobal.translations.append(path_format % "entities.en")
	IVGlobal.translations.append(path_format % "gui.en")
	IVGlobal.translations.append(path_format % "hints.en")
	
	# primary tables
	path_format = "res://astropolis_public/data/tables/%s.tsv"
	IVGlobal.table_import.carrying_capacity_groups = path_format % "carrying_capacity_groups"
	IVGlobal.table_import.compositions = path_format % "compositions"
	IVGlobal.table_import.facilities = path_format % "facilities"
	IVGlobal.table_import.major_strata = path_format % "major_strata"
	IVGlobal.table_import.mod_classes = path_format % "mod_classes"
	IVGlobal.table_import.modules = path_format % "modules"
	IVGlobal.table_import.op_classes = path_format % "op_classes"
	IVGlobal.table_import.op_groups = path_format % "op_groups"
	IVGlobal.table_import.operations = path_format % "operations"
	IVGlobal.table_import.players = path_format % "players"
	IVGlobal.table_import.populations = path_format % "populations"
	IVGlobal.table_import.resource_classes = path_format % "resource_classes"
	IVGlobal.table_import.resources = path_format % "resources"
	IVGlobal.table_import.spacecrafts = path_format % "spacecrafts" # replacement!
	IVGlobal.table_import.strata = path_format % "strata"
	IVGlobal.table_import.surveys = path_format % "surveys"
	
	# primary table mods
	IVGlobal.table_import_mods.asset_adjustments = path_format % "asset_adjustments_mod"
	IVGlobal.table_import_mods.planets = path_format % "planets_mod"
	IVGlobal.table_import_mods.moons = path_format % "moons_mod"
	
	# type x type tables
	IVGlobal.project.type_by_type_tables = [
		[path_format, "compositions_resources_heterogeneities", "compositions", "resources"],
		[path_format, "compositions_resources_percents", "compositions", "resources"],
		[path_format, "facilities_operations_capacities", "operations", "facilities"], # transposed
		[path_format, "facilities_operations_utilizations", "operations", "facilities"], # transposed
		[path_format, "facilities_populations", "facilities", "populations"],
		[path_format, "facilities_resources", "facilities", "resources"],
	]
	
	# added/replaced classes
	IVProjectBuilder.prog_refs._InfoCloner_ = InfoCloner
	IVProjectBuilder.gui_nodes._AstroGUI_ = AstroGUI
	
	# extended
	IVProjectBuilder.prog_refs._TableReader_ = TableReader
	IVProjectBuilder.procedural_classes._SelectionManager_ = SelectionManager
	
	# removed
	IVProjectBuilder.prog_refs.erase("_CompositionBuilder_")
	IVProjectBuilder.gui_nodes.erase("_CreditsPopup_")
	IVProjectBuilder.procedural_classes.erase("_Composition_") # using total replacement
	


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
	var tables: Dictionary = IVGlobal.tables
	var table_reader: TableReader = IVGlobal.program.TableReader
	# unique items
	tables.resource_type_electricity = tables.resources.unique_type.find("electricity")
	assert(tables.resource_type_electricity != -1)
	# table row subsets (arrays of row_types)
	tables.extraction_resources = table_reader.get_true_rows("resources", "is_extraction")
	tables.maybe_free_resources = table_reader.get_true_rows("resources", "maybe_free")
	tables.is_manufacturing_operations = table_reader.get_true_rows("operations", "is_manufacturing")
	tables.extraction_operations = table_reader.get_matching_rows("operations", "op_process_group",
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

	
	# DEPRECIATE
	tables.operations_inputs = [
		tables.operations.input_1,
		tables.operations.input_2,
		tables.operations.input_3,
		tables.operations.input_4,
	]
	tables.operations_input_qtys = [
		tables.operations.input_1_qty,
		tables.operations.input_2_qty,
		tables.operations.input_3_qty,
		tables.operations.input_4_qty,
	]
	tables.operations_outputs = [
		tables.operations.output_1,
		tables.operations.output_2,
		tables.operations.output_3,
		tables.operations.output_4,
	]
	tables.operations_output_qtys = [
		tables.operations.output_1_qty,
		tables.operations.output_2_qty,
		tables.operations.output_3_qty,
		tables.operations.output_4_qty,
	]


func _on_project_nodes_added() -> void:
	IVProjectBuilder.move_top_gui_child_to_sibling("AstroGUI", "SplashScreen", true)






