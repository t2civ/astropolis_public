# facility_interface.gd
# This file is part of Astropolis
# Copyright 2019-2023 Charlie Whitfield, all rights reserved
# *****************************************************************************
class_name FacilityInterface
extends Interface

# DO NOT MODIFY THIS FILE! To modify AI, see comments in '_base_ai.gd' files.
#
# This object lives and dies on the AI thread! Access from other threads is
# possible (e.g., from main thread GUI), but see:
# https://docs.godotengine.org/en/latest/tutorials/performance/thread_safe_apis.html
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

const OBJECT_TYPE := Enums.Objects.FACILITY

var facility_id := -1
var facility_class := -1
var public_sector: float # often 0.0 or 1.0, sometimes mixed
var has_economy: bool # ops treated as separate entities for economic measure & tax
var solar_occlusion: float # TODO: calculate from body atmosphere, body shading, etc.
var polity_name: StringName

var body: BodyInterface
var player: PlayerInterface


var propagations := []

var _component_indexes: Array # reused for data propagation


func _init() -> void:
	operations = Operations.new(true, true, true)
	inventory = Inventory.new(true)
	financials = Financials.new(true)


#func process_ai_interval(_delta: float) -> void:
#	prints(name, operations.capacities[0])



# *****************************************************************************
# interface API

func set_gui_name(new_gui_name: String) -> void:
	_dirty |= DIRTY_BASE
	gui_name = new_gui_name


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
	player = AIGlobal.interfaces_by_name[data[10]]
	body = AIGlobal.interfaces_by_name[data[11]]
	
	_component_indexes = [12, 13, 14, 15, 16, 17, 18]
	operations.sync_server_init(data[12])
	inventory.sync_server_init(data[13])
	financials.sync_server_init(data[14])
	if data[15]:
		population = Population.new(true, true)
		population.sync_server_init(data[15])
	if data[16]:
		biome = Biome.new(true)
		biome.sync_server_init(data[16])
	if data[17]:
		metaverse = Metaverse.new(true)
		metaverse.sync_server_init(data[17])
	yq = data[18]
	
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
	var dirty: int = data[1]
	var k := 2
	if dirty & DIRTY_BASE:
		gui_name = data[k]
		facility_class = data[k + 1]
		public_sector = data[k + 2]
		solar_occlusion = data[k + 3]
		polity_name = data[k + 4]
		k += 5
	if dirty & DIRTY_OPERATIONS:
		_component_indexes[0] = k
		k = operations.sync_server_changes(data, k)
	if dirty & DIRTY_INVENTORY:
		_component_indexes[1] = k
		k = inventory.sync_server_changes(data, k)
	if dirty & DIRTY_FINANCIALS:
		_component_indexes[2] = k
		k = financials.sync_server_changes(data, k)
	if dirty & DIRTY_POPULATION:
		if !population:
			population = Population.new(true, true)
		_component_indexes[3] = k
		k = population.sync_server_changes(data, k)
	if dirty & DIRTY_BIOME:
		if !biome:
			biome = Biome.new(true)
		_component_indexes[4] = k
		k = biome.sync_server_changes(data, k)
	if dirty & DIRTY_METAVERSE:
		if !metaverse:
			metaverse = Metaverse.new(true)
		_component_indexes[5] = k
		k = metaverse.sync_server_changes(data, k)
	
	assert(data[0] >= yq)
	if data[0] > yq:
		if yq == -1:
			yq = data[0]
		else:
			yq = data[0]
			process_ai_new_quarter() # after component histories have updated
	
	# propagate changes
	var n_propagations := propagations.size()
	var i := 0
	while i < n_propagations:
		var interface: Interface = propagations[i]
		interface.propagate_component_changes(data, _component_indexes)
		i += 1


func _sync_ai_changes() -> void:
	# FIXME: update data pattern
	var data := [_dirty]
	if _dirty & DIRTY_BASE:
		data.append(gui_name)
	if _dirty & DIRTY_OPERATIONS:
		data.append(operations.get_interface_dirty())
	_dirty = 0
	AIGlobal.emit_signal("interface_changed", OBJECT_TYPE, facility_id, data)


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
	var proxy_interface: Interface
	
	# off-Earth
	if body.name != "PLANET_EARTH":
		proxy_name = "PROXY_OFF_EARTH"
		proxy_interface = AIGlobal.get_or_make_proxy(proxy_name)
		add_propagation(proxy_interface)
	
	# polity on Earth
	# TODO: generalize to PROXY_HOMEWORLD_<polity_name>, e.g., for new Martian polity
	if body.name == "PLANET_EARTH":
		proxy_name = "PROXY_PLANET_EARTH_" + polity_name
		proxy_gui_name = tr("PLANET_EARTH") + " / " + tr(polity_name)
		proxy_interface = AIGlobal.get_or_make_proxy(proxy_name, proxy_gui_name, true, true, true)
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
		proxy_interface = AIGlobal.get_or_make_proxy(proxy_name)
		add_propagation(proxy_interface)
		proxy_name += "_" + player.name
		proxy_interface = AIGlobal.get_or_make_proxy(proxy_name)
		add_propagation(proxy_interface)
	
	# at moons of planet - all players & player-specific
	if at_moons_of_planet:
		proxy_name = "PROXY_MOONS_OF_" + at_moons_of_planet.name
		proxy_interface = AIGlobal.get_or_make_proxy(proxy_name)
		add_propagation(proxy_interface)
		proxy_name += "_" + player.name
		proxy_interface = AIGlobal.get_or_make_proxy(proxy_name)
		add_propagation(proxy_interface)
	
	# in star system - all facilities!
	proxy_name = "PROXY_SYSTEM_" + in_star_system.name
	proxy_gui_name = tr("SYSTEM_" + in_star_system.name) # for STAR_SUN translates to 'Solar System'
	proxy_interface = AIGlobal.get_or_make_proxy(proxy_name, proxy_gui_name)
	add_propagation(proxy_interface)

