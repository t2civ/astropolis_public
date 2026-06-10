# body_proxy.gd
# This file is part of Astropolis
# https://t2civ.com
# *****************************************************************************
# Copyright 2019-2026 Charlie Whitfield; ALL RIGHTS RESERVED
# Astropolis is a registered trademark of Charlie Whitfield in the US
# *****************************************************************************
@abstract
class_name BodyProxy
extends Proxy

## [BodyProxy] corresponds to an [IVBody] in the simulation, hosting
## facilities and aggregating their stats.
##
## Server-side Body aggregates component data from its facilities and exposes
## stratum composition (atmosphere, surface, subsurface). It gains a spot
## [MarketProxy] when it has a facility.
##
## Indexed getters here (notably the per-stratum [code]get_stratum_*[/code]
## reads) are defensive: an out-of-range index returns a safe default. See
## AI_ARCHITECTURE.md, "Trust the server; guard against AI".
##
## To get the corresponding scene-tree [code]IVBody[/code] node use
## [code]IVBody.bodies[body_name][/code]. Be aware that the SceneTree runs
## on the main thread!
##
## To modify AI, see [BaseAI] and the [code]*_base_ai.gd[/code] files.
##
## WARNING: Lives on the proxy thread. Containers and many methods are not
## threadsafe; accessing non-container properties is safe.


## Emitted when a futures position at this body changes. [param position_key] is the
## 3-element key [resource_type, ordinal_quarter, trader_id]. [param value] is the
## resulting position [signed_unit_quantity, unit_price] in trade units (empty if the
## position cleared); the quantity sign gives the side (+ long, − short). [param ask]
## and [param bid] are the trader's outstanding ask and bid [unit_quantity, unit_price]
## in trade units for this instrument; an empty array is a cleared ask or bid.
signal futures_positions_changed(position_key: PackedInt32Array, value: PackedFloat64Array,
		ask: PackedInt32Array, bid: PackedInt32Array)


var body_id := -1  ## Index into [member ProxyBus.body_proxies].
var body_flags := 0  ## Body flags from [enum IVBody.BodyFlags].
var solar_occlusion: float  ## Average solar irradiance occlusion at this body.

# *****************************************************************************
# persisted

var is_satellites := false  ## True while this body has at least one satellite.
var is_facilities := false  ## True while this body hosts at least one facility.
## Parent body, or null for the top body only.
var parent: BodyProxy
## Direct satellite bodies, keyed by name. Resizable container — not threadsafe!
var satellites: Dictionary[StringName, BodyProxy]
## Facilities at this body. Resizable container — not threadsafe!
var facilities: Array[Proxy] = []
## The spot market at this body, or null if it has no facility yet.
var market: MarketProxy

# *****************************************************************************

## Futures positions at this body, keyed by the 3-element position key
## [resource_type, ordinal_quarter, trader_id] (the delivery body is this body).
## Values are [signed_unit_quantity, unit_price] in trade units; the quantity sign
## gives the side (+ long, − short). Server-maintained; read-only here.
var futures_positions: Dictionary[PackedInt32Array, PackedFloat64Array] = {}


# ************************* VIRTUAL & IMPLEMENTATION **************************

func _clear_for_destruction() -> void:
	parent = null
	satellites.clear()
	facilities.clear()
	market = null


# ********************************* PROXY API *********************************

func has_development() -> bool:
	return is_facilities


func get_body_name() -> StringName:
	return name


func get_body_flags() -> int:
	return body_flags


## Returns this body's [member facilities]. proxy thread only!
func get_facilities() -> Array[Proxy]:
	return facilities


func get_market() -> MarketProxy:
	return market


# Strata. The composition layers live on the server.

## Returns true if this body has any stratum composition layers.
@abstract func has_strata() -> bool


## Returns the number of stratum composition layers on this body.
@abstract func get_n_strata() -> int


## Returns the name of the stratum at [param index].
@abstract func get_stratum_name(index: int) -> StringName


## Returns the polity name of the stratum at [param index] ([code]&""[/code]
## for commons strata).
@abstract func get_stratum_polity(index: int) -> StringName


## Returns the density of the stratum at [param index].
@abstract func get_stratum_density(index: int) -> float


## Returns the stratum-group index of the stratum at [param index].
@abstract func get_stratum_stratum_type(index: int) -> int


## Returns the thickness of the stratum at [param index].
@abstract func get_stratum_thickness(index: int) -> float


## Returns the volume of the stratum at [param index].
@abstract func get_stratum_volume(index: int) -> float


## Returns the total mass of the stratum at [param index].
@abstract func get_stratum_total_mass(index: int) -> float


## Returns the body radius cached on the stratum at [param index].
@abstract func get_stratum_body_radius(index: int) -> float


## Returns the per-resource mass array for the stratum at [param index].
@abstract func get_stratum_masses(index: int) -> PackedFloat64Array


## Returns the per-resource dispersion array for the stratum at [param index].
@abstract func get_stratum_dispersions(index: int) -> PackedFloat64Array


## Returns the survey-type index for the stratum at [param index].
@abstract func get_stratum_survey_type(index: int) -> int


## Returns survey/discovery data for [param resource_type] in the stratum at
## [param index].
@abstract func get_stratum_resource_data(index: int, resource_type: int) -> PackedFloat64Array


## Returns the estimated mass of [param resource_type] in the stratum at
## [param index] (extraction-subset resources only).
@abstract func get_stratum_mass(index: int, resource_type: int) -> float


## Returns the estimated mass fraction of [param resource_type] in the stratum
## at [param index].
@abstract func get_stratum_mass_fraction(index: int, resource_type: int) -> float


## Returns the spatial dispersion (log10 units) of [param resource_type] in the
## stratum at [param index].
@abstract func get_stratum_dispersion(index: int, resource_type: int) -> float


## Returns the coefficient of variation of the estimated mass of
## [param resource_type] in the stratum at [param index].
@abstract func get_stratum_mass_cv(index: int, resource_type: int) -> float


## Returns the coefficient of variation of the dispersion of
## [param resource_type] in the stratum at [param index].
@abstract func get_stratum_dispersion_cv(index: int, resource_type: int) -> float


## Returns the base deposit fraction (before survey adjustment) of
## [param resource_type] in the stratum at [param index].
@abstract func get_stratum_base_deposit(index: int, resource_type: int) -> float


## Returns the discovery fraction of [param resource_type] in the stratum at
## [param index].
@abstract func get_stratum_discovered(index: int, resource_type: int) -> float


## Returns the maximum discovery fraction across [param resource_types] in the
## stratum at [param index] (best extraction target).
@abstract func get_stratum_max_discovered(index: int, resource_types: PackedInt32Array) -> float


## Returns the per-resource coefficient-of-variation array for masses in the
## stratum at [param index].
@abstract func get_stratum_masses_cv(index: int) -> PackedFloat64Array


## Returns the per-resource coefficient-of-variation array for dispersions in
## the stratum at [param index].
@abstract func get_stratum_dispersions_cv(index: int) -> PackedFloat64Array


## Returns the per-resource discovery-fraction array for the stratum at
## [param index].
@abstract func get_stratum_discoveries(index: int) -> PackedFloat64Array


## Returns the current survey level of the stratum at [param index].
@abstract func get_stratum_survey_level(index: int) -> float


## Returns the inner radius of the stratum at [param index] (0.0 for an
## undifferentiated body).
@abstract func get_stratum_inner_radius(index: int) -> float


## Returns the spherical fraction (of a theoretical whole-sphere stratum) of the
## stratum at [param index].
@abstract func get_stratum_spherical_fraction(index: int) -> float


## Returns true if the stratum at [param index] is the body's atmosphere.
@abstract func get_stratum_is_atmosphere(index: int) -> bool


## Registers [param satellite] under this body. Updates [member is_satellites].
@abstract func add_satellite(satellite: BodyProxy) -> void


## Removes [param satellite] from this body. Updates [member is_satellites].
@abstract func remove_satellite(satellite: BodyProxy) -> void


## Registers [param facility] at this body. Updates [member is_facilities].
@abstract func add_facility(facility: Proxy) -> void


## Removes [param facility] from this body. Updates [member is_facilities].
@abstract func remove_facility(facility: Proxy) -> void
