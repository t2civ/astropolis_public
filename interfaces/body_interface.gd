# body_interface.gd
# This file is part of Astropolis
# Copyright 2019-2023 Charlie Whitfield, all rights reserved
# *****************************************************************************
class_name BodyInterface
extends Interface

# DO NOT MODIFY THIS FILE! To modify AI, see comments in '_base_ai.gd' files.
#
# Warning! This object lives and dies on the AI Server thread! Some access from
# other threads is possible (e.g., from main thread GUI), but see:
# https://docs.godotengine.org/en/latest/tutorials/performance/thread_safe_apis.html
#
# To get the SceenTree "body" node (class IVBody) use IVGlobal.bodies[body_name].
# Be aware that SceenTree works on the Main thread!
#
# Body optional components:
#   Operations   - when needed
#   Population   - when needed
#   Biome        - when needed
#   Metaverse    - when needed
#   Compositions - when needed (BodyInterface only!)

const OBJECT_TYPE = Enums.Objects.BODY

var body_id := -1
var body_flags := 0
var solar_occlusion: float # atmosphere & rotation/orbit shading
var parent: Interface # null for top body
var satellites := [] # Interfaces; resizable container - not threadsafe!
var compositions := [] # resizable container - not threadsafe!



func _init() -> void:
	IVGlobal.about_to_free_procedural_nodes.connect(_clear)
	IVGlobal.about_to_quit.connect(_clear)


func _clear() -> void:
	# clear circular references
	parent = null
	satellites.clear()


# *****************************************************************************
# interface API


# *****************************************************************************
# sync - DON'T MODIFY!

func sync_server_init(data: Array) -> void:
	body_id = data[2]
	name = data[3]
	gui_name = data[4]
	body_flags = data[5]
	solar_occlusion = data[6]
	var parent_name: String = data[7]
	if parent_name:
		parent = AIGlobal.get_interface_by_name(parent_name)
		@warning_ignore("unsafe_method_access")
		parent.add_satellite(self)
	if data[8]:
		var compositions_data: Array = data[8]
		var n_compositions := compositions_data.size()
		compositions.resize(n_compositions)
		var i := 0
		while i < n_compositions:
			var composition_data: Array = compositions_data[i]
			var composition := Composition.new(true)
			composition.sync_server_init(composition_data)
			compositions[i] = composition
			i += 1


func propagate_component_init(data: Array, indexes: Array) -> void:
	if data[indexes[0]]:
		if !operations:
			operations = Operations.new(true)
		operations.propagate_component_init(data[indexes[0]])
	# skip inventory, financials
	if data[indexes[3]]:
		if !population:
			population = Population.new(true)
		population.propagate_component_init(data[indexes[3]])
	if data[indexes[4]]:
		if !biome:
			biome = Biome.new(true)
		biome.propagate_component_init(data[indexes[4]])
	if data[indexes[5]]:
		if !metaverse:
			metaverse = Metaverse.new(true)
		metaverse.propagate_component_init(data[indexes[5]])
	assert(data[indexes[6]] >= yq)
	yq = data[indexes[6]]


func sync_server_dirty(data: Array) -> void:
	var dirty: int = data[0]
	var k := 1
	if dirty & DIRTY_BASE:
		gui_name = data[k]
		solar_occlusion = data[k + 1]
		k += 2
	if dirty & DIRTY_COMPOSITIONS:
		var n_compositions: int = data[k]
		k += 1
		while n_compositions > compositions.size(): # server added a Composition
			var composition := Composition.new(true)
			compositions.append(composition)
		var i := 0
		while i < n_compositions:
			var composition: Composition = compositions[i]
			k = composition.sync_server_dirty(data, k)
			i += 1


func propagate_component_changes(data: Array, indexes: Array) -> void:
	var dirty: int = data[1]
	if dirty & DIRTY_OPERATIONS:
		if !operations:
			operations = Operations.new(true)
		operations.sync_server_changes(data, indexes[0])
	# no inventory or financials
	if dirty & DIRTY_POPULATION:
		if !population:
			population = Population.new(true)
		population.sync_server_changes(data, indexes[3])
	if dirty & DIRTY_BIOME:
		if !biome:
			biome = Biome.new(true)
		biome.sync_server_changes(data, indexes[4])
	if dirty & DIRTY_METAVERSE:
		if !metaverse:
			metaverse = Metaverse.new(true)
		metaverse.sync_server_changes(data, indexes[5])
	
	assert(data[0] >= yq)
	if data[0] > yq:
		if yq == -1:
			yq = data[0]
		else:
			yq = data[0]
			process_ai_new_quarter() # after component histories have updated


func add_satellite(satellite: Interface) -> void:
	assert(!satellites.has(satellite))
	satellites.append(satellite)


func remove_satellite(satellite: Interface) -> void:
	satellites.erase(satellite)

