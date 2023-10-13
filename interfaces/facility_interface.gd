# facility_interface.gd
# This file is part of Astropolis
# Copyright 2019-2023 Charlie Whitfield, all rights reserved
# *****************************************************************************
class_name FacilityInterface
extends Interface

# DO NOT MODIFY THIS FILE! To modify AI, see comments in '_base_ai.gd' files.
#
# Warning! This object lives and dies on the AI thread! Containers and many
# methods are not threadsafe. Accessing non-container properties is safe.
#
# Facilities are where most of the important activity happens in Astropolis. 
# A server-side Facility object pushes changes to FacilityInterface and its
# components. FacilityInterface then propagates component changes to
# BodyInterface, PlayerInterface and any ProxyInterfaces held in 'propagations'
# array.
#
# Facility required & optional components:
#   Operations - on init
#   Inventory  - on init
#   Financials - on init
#   Population - when needed
#   Biome      - when needed
#   Metaverse  - when needed

static var facility_interfaces: Array[FacilityInterface] = [] # indexed by facility_id

var facility_id := -1
var facility_class := -1
var public_sector: float # often 0.0 or 1.0, sometimes mixed
var has_economy: bool # ops treated as separate entities for economic measure & tax
var solar_occlusion: float # TODO: calculate from body atmosphere, body shading, etc.
var polity_name: StringName

var body: BodyInterface
var player: PlayerInterface


var propagations := []

var _component_indexes: Array[int] # reused for data propagation
var _int_offsets: Array[int] = [0, 0, 0, 0, 0, 0] # reused for data propagation
var _float_offsets: Array[int] = [0, 0, 0, 0, 0, 0] # reused for data propagation


func _init() -> void:
	super()
	entity_type = ENTITY_FACILITY
	operations = Operations.new(true, true, true)
	inventory = Inventory.new(true)
	financials = Financials.new(true)


#func process_ai_interval(_delta: float) -> void:
#	prints(name, operations.capacities[0])



# *****************************************************************************
# interface API

func remove() -> void:
	body.remove_facility(self)
	player.remove_facility(self)


func set_gui_name(new_gui_name: String) -> void:
	_dirty |= DIRTY_BASE
	gui_name = new_gui_name


func get_body_name() -> StringName:
	return body.name


func get_body_flags() -> int:
	return body.body_flags


func get_player_name() -> StringName:
	return player.name


func get_player_class() -> int:
	return player.player_class


func get_polity_name() -> StringName:
	return polity_name


func add_propagation(interface: Interface) -> void:
	assert(!propagations.has(interface))
	propagations.append(interface)


func remove_propagation(interface: Interface) -> void:
	propagations.erase(interface)


# *****************************************************************************
# sync

func sync_server_init(data: Array) -> void:
	facility_id = data[2]
	name = data[3]
	gui_name = data[4]
	facility_class = data[5]
	public_sector = data[6]
	has_economy = data[7]
	solar_occlusion = data[8]
	polity_name = data[9]
	player = interfaces_by_name[data[10]]
	player.add_facility(self)
	body = interfaces_by_name[data[11]]
	body.add_facility(self)
	_component_indexes = [12, 13, 14, 15, 16, 17, 18]
	var component_data: Array = data[12]
	operations.sync_server_init(component_data)
	component_data = data[13]
	inventory.sync_server_init(component_data)
	component_data = data[14]
	financials.sync_server_init(component_data)
	component_data = data[15]
	if component_data:
		population = Population.new(true, true)
		population.sync_server_init(component_data)
	component_data = data[16]
	if component_data:
		biome = Biome.new(true)
		biome.sync_server_init(component_data)
	component_data = data[17]
	if component_data:
		metaverse = Metaverse.new(true)
		metaverse.sync_server_init(component_data)
	run_qtr = data[18]
	
	# add proxies
	_add_base_propagations() # body, player, part_of_player
	_add_proxies() # off-earth, solar system, etc.
	
	# propagate init data
	var n_propagations := propagations.size()
	var i := 0
	while i < n_propagations:
		var interface: Interface = propagations[i]
		interface.propagate_component_init(data, _component_indexes)
		i += 1


func sync_server_dirty(data: Array) -> void:
	
	var int_data: Array[int] = data[0]
	var float_data: Array[float] = data[1]
	var string_data: Array[String] = data[2]
	
	var dirty: int = int_data[1]

	var int_offset := 2
	var float_offset := 0
	
	if dirty & DIRTY_BASE:
		facility_class = data[int_offset]
		int_offset += 1
		public_sector = float_data[float_offset]
		solar_occlusion = float_data[float_offset + 1]
		float_offset += 2
		gui_name = string_data[0]
		polity_name = string_data[1]
	
	data.append(float_offset)
	data.append(int_offset)
	
	if dirty & DIRTY_OPERATIONS:
		_int_offsets[0] = int_offset
		_float_offsets[0] = float_offset
		operations.add_server_delta(data)
	if dirty & DIRTY_INVENTORY:
		_int_offsets[1] = data[-1]
		_float_offsets[1] = data[-2]
		inventory.add_server_delta(data)
	if dirty & DIRTY_FINANCIALS:
		_int_offsets[2] = data[-1]
		_float_offsets[2] = data[-2]
		financials.add_server_delta(data)
	if dirty & DIRTY_POPULATION:
		if !population:
			population = Population.new(true, true)
		_int_offsets[3] = data[-1]
		_float_offsets[3] = data[-2]
		population.add_server_delta(data)
	if dirty & DIRTY_BIOME:
		if !biome:
			biome = Biome.new(true)
		_int_offsets[4] = data[-1]
		_float_offsets[4] = data[-2]
		biome.add_server_delta(data)
	if dirty & DIRTY_METAVERSE:
		if !metaverse:
			metaverse = Metaverse.new(true)
		_int_offsets[5] = data[-1]
		_float_offsets[5] = data[-2]
		metaverse.add_server_delta(data)
	
	assert(int_data[0] >= run_qtr)
	if int_data[0] > run_qtr:
		if run_qtr == -1:
			run_qtr = int_data[0]
		else:
			run_qtr = int_data[0]
			process_ai_new_quarter() # after component histories have updated
	
	# propagate changes
	var n_propagations := propagations.size()
	var i := 0
	while i < n_propagations:
		var interface: Interface = propagations[i]
		interface.propagate_component_changes(data, _int_offsets, _float_offsets)
		i += 1


func _sync_ai_changes() -> void:
	# FIXME: update data pattern
	var data := [_dirty]
	if _dirty & DIRTY_BASE:
		data.append(gui_name)
	if _dirty & DIRTY_OPERATIONS:
		data.append(operations.get_interface_dirty())
	_dirty = 0
	AIGlobal.emit_signal("interface_changed", entity_type, facility_id, data)


func _add_base_propagations() -> void:
	add_propagation(body)
	add_propagation(player)
	if player.part_of:
		add_propagation(player.part_of)


func _add_proxies() -> void:
	# Currently we add:
	#
	#  PROXY_OFF_EARTH                          - all facilities not on Earth
	#  PROXY_PLANET_EARTH_<polity_name>         - facilities of polity on Earth
	#  PROXY_ORBIT_<body_name>                  - all facilities in orbit of planet or moon
	#  PROXY_ORBIT_<body_name>_<player_name>    - as above for player facilities
	#  PROXY_MOONS_OF_<body_name>               - all facilities at or orbiting a planet's moons
	#  PROXY_MOONS_OF_<body_name>_<player_name> - as above for player facilities
	#  PROXY_SYSTEM_<star_name>                 - all facilities under star
	
	var proxy_name: StringName
	var proxy_gui_name: String
	var proxy_interface: ProxyInterface
	
	# off-Earth
	if body.name != "PLANET_EARTH":
		proxy_name = "PROXY_OFF_EARTH"
		proxy_interface = ProxyInterface.get_or_make_proxy(proxy_name)
		add_propagation(proxy_interface)
	
	# polity on Earth
	# TODO: generalize to PROXY_HOMEWORLD_<polity_name>, e.g., for new Martian polity
	if body.name == "PLANET_EARTH":
		proxy_name = "PROXY_PLANET_EARTH_" + polity_name
		proxy_gui_name = tr("PLANET_EARTH") + " / " + tr(polity_name)
		proxy_interface = ProxyInterface.get_or_make_proxy(proxy_name, proxy_gui_name, true, true, true)
		add_propagation(proxy_interface)
	
	# search up body tree for others...
	var BodyFlags: Dictionary = IVEnums.BodyFlags
	var in_orbit_of_planet_or_moon: Interface
	var at_moons_of_planet: Interface
	var in_star_system: Interface
	var up_body := body.parent
	if up_body.body_flags & BodyFlags.IS_PLANET_OR_MOON:
		in_orbit_of_planet_or_moon = up_body
	while true:
		if up_body.body_flags & BodyFlags.IS_STAR:
			in_star_system = up_body
			break
		if up_body.body_flags & BodyFlags.IS_PLANET:
			if up_body != in_orbit_of_planet_or_moon:
				at_moons_of_planet = up_body
		up_body = up_body.parent
	
	# in orbit of planet or moon - all players & player-specific
	if in_orbit_of_planet_or_moon:
		proxy_name = "PROXY_ORBIT_" + in_orbit_of_planet_or_moon.name
		proxy_interface = ProxyInterface.get_or_make_proxy(proxy_name)
		add_propagation(proxy_interface)
		proxy_name += "_" + player.name
		proxy_interface = ProxyInterface.get_or_make_proxy(proxy_name)
		add_propagation(proxy_interface)
	
	# at moons of planet - all players & player-specific
	if at_moons_of_planet:
		proxy_name = "PROXY_MOONS_OF_" + at_moons_of_planet.name
		proxy_interface = ProxyInterface.get_or_make_proxy(proxy_name)
		add_propagation(proxy_interface)
		proxy_name += "_" + player.name
		proxy_interface = ProxyInterface.get_or_make_proxy(proxy_name)
		add_propagation(proxy_interface)
	
	# in star system - all facilities!
	proxy_name = "PROXY_SYSTEM_" + in_star_system.name
	proxy_gui_name = tr("SYSTEM_" + in_star_system.name) # for STAR_SUN translates to 'Solar System'
	proxy_interface = ProxyInterface.get_or_make_proxy(proxy_name, proxy_gui_name)
	add_propagation(proxy_interface)

