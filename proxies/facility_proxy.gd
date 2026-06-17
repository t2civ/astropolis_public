# facility_proxy.gd
# This file is part of Astropolis
# https://t2civ.com
# *****************************************************************************
# Copyright 2019-2026 Charlie Whitfield; ALL RIGHTS RESERVED
# Astropolis is a registered trademark of Charlie Whitfield in the US
# *****************************************************************************
@abstract
class_name FacilityProxy
extends Proxy

## [FacilityProxy] represents a [PlayerProxy]'s development at a [BodyProxy].
##
## A facility runs operations enabled by modules (see corresponding data
## tables). Server-side automations translate AI intent set here into per-tick
## operation behavior. AI writes FROM_PROXY_MASK flag bits on [member flags],
## on per-op operations flags, and on per-resource inventory flags; the server
## publishes FROM_SERVER_MASK runtime signals (margin, shortage, surplus) back
## for AI to read.
##
## Indexed methods here are defensive against AI misbehavior: a setter given an
## out-of-range index, NaN, or negative value is a no-op, and a getter given an
## out-of-range index returns a safe default (0.0, 0, NAN, or an empty array).
## This lets a custom AI fail safe. See AI_ARCHITECTURE.md, "Trust the server;
## guard against AI".
##
## To modify AI, see [BaseAI] and the [code]*_base_ai.gd[/code] files.
##
## WARNING: Lives on the proxy thread. Containers and many methods are not
## threadsafe; accessing non-container properties is safe.


## Facility-level bit flags. FROM_SERVER bits (0 - 31) are signals from the
## server; FROM_PROXY bits (32 - 63) are AI commands to the server.
enum FacilityFlags {
	## Many resources at this facility have no established market price, so
	## runtime margin estimates here are unreliable.
	PRICE_UNRELIABLE = 1 << 1,
	## Multiple critical inputs are simultaneously running below their
	## operational reserve targets.
	INPUT_CRISIS = 1 << 2,
	## Mask of all server-published signal bits.
	FROM_SERVER_MASK = (1 << 32) - 1,

	## Crisis posture: operations continue regardless of profitability and
	## storage constraints are relaxed.
	MODE_EMERGENCY = 1 << 32,
	## Laid-up state: no operations run; capacity is preserved for later restart.
	MODE_MOTHBALL = 1 << 33,
	## Inventory drawdown: only operations that net-consume inventory continue
	## (distinct from the DECOMMISSIONING operation, which tears down modules).
	MODE_DRAWDOWN = 1 << 34,
	## Allocate by economic return at both granularities: grow capacity-bound,
	## profitable modules preferentially (vs proportional growth across the existing
	## mix), AND reweight each module's capacity toward its capacity-bound, profitable
	## operations (net-zero, no construction cost). Shortfall-driven bootstrap of a
	## needed module happens either way.
	BUILDOUT_BY_RETURN = 1 << 35,
	## With [constant BUILDOUT_BY_RETURN], also decommission chronically idle or
	## loss-making modules (selective trim). Has no effect on its own.
	BUILDOUT_ALLOW_TRIM = 1 << 36,
	## Mask of all AI-command bits.
	FROM_PROXY_MASK = ~((1 << 32) - 1),
}


## Per-resource inventory bit flags. FROM_SERVER bits (0 - 31) are signals from
## the server; FROM_PROXY bits (32 - 63) are AI commands to the server.
enum InventoryFlags {
	## Stock of this resource is below its operational reserve target.
	OPS_RESERVE_BREACHED = 1 << 1,
	## Stock of this resource is below its AI-set strategic reserve target.
	STRATEGIC_RESERVE_BREACHED = 1 << 2,
	## The storage class holding this resource is at or above the first
	## throttling threshold.
	STORAGE_SURPLUS = 1 << 3,
	## No market price is established for this resource at this location.
	PRICE_UNKNOWN = 1 << 4,
	## This resource is tradable (a commodity assigned to a storage class).
	TRADABLE = 1 << 5,
	## A can-have operation at this facility consumes this resource.
	CAN_HAVE_INPUT = 1 << 6,
	## A can-have operation at this facility produces or extracts this resource.
	CAN_HAVE_OUTPUT = 1 << 7,
	## Mask of all server-published signal bits.
	FROM_SERVER_MASK = (1 << 32) - 1,

	## Operations must not draw this resource below its strategic reserve.
	PROTECT_STRATEGIC_RESERVE = 1 << 32,
	## No operation may consume this resource (e.g., embargo, phase-out).
	PROHIBIT_CONSUMPTION = 1 << 33,
	## No operation may produce this resource (e.g., divestment, phase-out).
	PROHIBIT_PRODUCTION = 1 << 34,
	## Mask of all AI-command bits.
	FROM_PROXY_MASK = ~((1 << 32) - 1),
}


## Per-operation bit flags. FROM_SERVER bits (0 - 31) are signals from the
## server; FROM_PROXY bits (32 - 63) are AI commands to the server.
enum OperationsFlags {
	## This facility is equipped to run this operation.
	CAN_HAVE = 1,
	## The operation ran at a loss over the last interval at known prices.
	MARGIN_NEGATIVE = 1 << 1,
	## The operation was throttled below its intended rate last interval
	## because an input was in short supply.
	WAS_INPUT_LIMITED = 1 << 2,
	## The operation was throttled below its intended rate last interval
	## because an output's storage was nearly full.
	WAS_STORAGE_LIMITED = 1 << 3,
	## Mask of all server-published signal bits.
	FROM_SERVER_MASK = (1 << 32) - 1,

	## Idle the operation whenever its margin is non-positive and prices are
	## reliable.
	MARGIN_GATED = 1 << 32,
	## When any of the op's outputs is below operational reserve, suspend
	## profit-gating and ease storage throttling so the op can ramp up.
	SHORTAGE_PRIORITY = 1 << 33,
	## Hold the operation at a minimum baseline rate even when other
	## automations would idle it.
	STRATEGIC_FLOOR = 1 << 34,
	## Hard-stop the operation when any of its outputs has insufficient
	## storage headroom (no soft trickle).
	CLEARANCE_LIMITED = 1 << 35,
	## Mask of all AI-command bits.
	FROM_PROXY_MASK = ~((1 << 32) - 1),
}


## Field selectors for [method get_inventory_items] (bit flags; OR together).
## All select resource_type-indexed fields, so type is a resource_type. Returned
## values are in ascending bit order.
enum InventoryItems {
	STOCKS = 1,
	CONTRACTEDS = 1 << 1,
	OPS_RESERVES = 1 << 2,
	STRATEGIC_RESERVES = 1 << 3,
	EXPECTED_RATES = 1 << 4,
	IN_TRANSITS = 1 << 5,
	RATES = 1 << 6,
	FLAGS = 1 << 7,
}


var facility_id := -1  ## Index into [member ProxyBus.facility_proxies].
var facility_class := -1  ## Facility class index. Not implemented yet.
## Public-sector share of this facility, often 0.0 or 1.0, sometimes mixed.
var public_sector: float
## True if this is a small focused activity (affects stats and tax treatment).
var is_unitary: bool
## Large and/or port facilities act as market makers.
var market_maker: bool
## True if all resource streams flow from/to inventory (no atmosphere/surface
## market).
var closed_cycle_ops: bool
## Fraction of solar irradiance occluded at this site (0.0–1.0).
var solar_occlusion: float
## Time horizon used by AI and automations (inventory reserves, resupply, etc.).
var time_horizon: float
## Bidirectional bit flags (see [enum FacilityFlags]). FROM_SERVER bits are
## server-authoritative; FROM_PROXY bits are proxy-authoritative. Use
## [method set_flags] to modify the proxy half.
var flags := 0
## Autonomous growth intensity (proxy-authoritative knob). See
## [method set_buildout_intensity].
var buildout_intensity := 0.3

# *****************************************************************************
# persisted

var player: PlayerProxy  ## Owning [PlayerProxy].
var polity: PlayerProxy  ## The polity of [member player].
var body: BodyProxy  ## Hosting [BodyProxy].
var trader: TraderProxy  ## Paired [TraderProxy]; set when TraderProxy registers.
var trader_id := -1  ## [member TraderProxy.trader_id] of [member trader].
var joins: Array[JoinProxy] = []  ## [JoinProxy] aggregates this facility belongs to.
var market: MarketProxy  ## Set after init. Lives on markets thread!

# *****************************************************************************

## Body texture cached for [code]IVSelectionManager[/code] (currently the
## hosting body's [code]IVBody.texture_2d[/code]).
var texture_2d: Texture2D


# ************************* VIRTUAL & IMPLEMENTATION **************************

func _clear_for_destruction() -> void:
	body = null
	player = null
	polity = null
	trader = null
	joins.clear()
	market = null
	texture_2d = null


## Detaches this facility from its body and player, then breaks its outgoing
## refs via [method super.remove]. Called by the server side at runtime when a
## facility is removed mid-game.
func remove() -> void:
	body.remove_facility(self)
	player.remove_facility(self)
	super.remove()


# ***************************** THREAD-SAFE READ ******************************

func has_development() -> bool:
	return true


func has_markets() -> bool:
	return true


func has_inventory() -> bool:
	return true


func get_body_name() -> StringName:
	return body.name


func get_body_flags() -> int:
	return body.body_flags


func get_player_name() -> StringName:
	return player.name


func get_player_class() -> int:
	return player.player_class


func get_polity_name() -> StringName:
	return polity.name


# Facility flags

## Returns the full bidirectional flag value (see [enum FacilityFlags]).
func get_flags() -> int:
	return flags


## Returns the facility's autonomous growth intensity; see
## [method set_buildout_intensity].
func get_buildout_intensity() -> float:
	return buildout_intensity


# Operations (facility-only). Facility-only reads, plus proxy-authoritative knobs
# (flags, target utilization) with reverse data flow proxy -> server. Implemented
# on the server-side facility proxy against its operations component.

## Returns the capacity factor (environmental or historical limit) of operation
## [param operation_type].
@abstract func get_operations_capacity_factor(operation_type: int) -> float


## Returns the per-operation capacity factors array. Return is proxy array
## reference; read only!
@abstract func get_operations_capacity_factors() -> PackedFloat64Array


## Returns the Tier-3 target utilization of operation [param operation_type] (the
## server/controller's run-rate target; for display).
@abstract func get_operations_target_utilization(operation_type: int) -> float


## Returns the per-operation target utilizations array. Return is proxy array
## reference; read only!
@abstract func get_operations_target_utilizations() -> PackedFloat64Array


## Returns the AI/player-set target margin floor of operation [param operation_type].
@abstract func get_operations_target_margin(operation_type: int) -> float


## Returns the AI/player-set target spending share of operation [param operation_type]
## (NAN = not in effect).
@abstract func get_operations_target_spending_share(operation_type: int) -> float


## Returns the AI/player-set target run rate of operation [param operation_type]
## (NAN = not in effect).
@abstract func get_operations_target_run_rate(operation_type: int) -> float


## Returns the build/decommission lever for [param module_type]; see
## [method set_operations_module_buildout] for what the value means.
@abstract func get_operations_module_buildout(module_type: int) -> float


## Returns the capitalized book value (historical cost) of [param module_type].
@abstract func get_operations_module_book_value(module_type: int) -> float


## Returns the full bidirectional flag value for operation [param operation_type].
@abstract func get_operations_flags(operation_type: int) -> int


## Returns the per-operation flags array. Return is proxy array reference;
## read only!
@abstract func get_operations_flags_array() -> PackedInt64Array


# Inventory (facility-only). Facility-only reads, plus proxy-authoritative knobs
# (flags, strategic reserve) with reverse data flow proxy -> server. Implemented
# on the server-side facility proxy against its inventory component.

## Returns the [enum InventoryItems] fields selected by [param items_mask] for
## [param resource_type], as an untyped Array in ascending bit order.
@abstract func get_inventory_items(resource_type: int, items_mask: int) -> Array


## Returns the stock (current quantity on hand) of [param resource_type].
@abstract func get_inventory_stock(resource_type: int) -> float


## Returns the per-resource stocks array. Return is proxy array reference;
## read only!
@abstract func get_inventory_stocks() -> PackedFloat64Array


## Returns the contracted quantity of [param resource_type] (committed but not
## yet delivered).
@abstract func get_inventory_contracted(resource_type: int) -> float


## Returns the per-resource contracted array. Return is proxy array reference;
## read only!
@abstract func get_inventory_contracteds() -> PackedFloat64Array


## Returns the operational reserve target for [param resource_type] — the stock
## level the facility aims to keep on hand to sustain its operations.
@abstract func get_inventory_ops_reserve(resource_type: int) -> float


## Returns the per-resource ops reserves array. Return is proxy array reference;
## read only!
@abstract func get_inventory_ops_reserves() -> PackedFloat64Array


## Returns the strategic reserve target for [param resource_type] — an AI-set
## buffer held beyond operational need.
@abstract func get_inventory_strategic_reserve(resource_type: int) -> float


## Returns the per-resource strategic reserves array. Return is proxy array
## reference; read only!
@abstract func get_inventory_strategic_reserves() -> PackedFloat64Array


## Returns the expected net flow rate for [param resource_type] (positive =
## net production, negative = net consumption), projected from operating
## intent — consumption at target utilization × capacity, production at
## capacity factor × capacity (a time-horizon moving average of realized
## utilization, which smooths the production side). Not degraded by transient
## input shortages.
@abstract func get_inventory_expected_rate(resource_type: int) -> float


## Returns the per-resource expected rates array. Return is proxy array
## reference; read only!
@abstract func get_inventory_expected_rates() -> PackedFloat64Array


## Returns the in-transit quantity for [param resource_type] (en route to this
## facility; always >= 0.0).
@abstract func get_inventory_in_transit(resource_type: int) -> float


## Returns the per-resource in-transit array. Return is proxy array reference;
## read only!
@abstract func get_inventory_in_transits() -> PackedFloat64Array


## Returns the most recent measured net rate for [param resource_type] (positive
## = production, negative = consumption).
@abstract func get_inventory_rate(resource_type: int) -> float


## Returns the per-resource rates array. Return is proxy array reference;
## read only!
@abstract func get_inventory_rates() -> PackedFloat64Array


## Returns the storage capacity of storage class [param storage_type].
@abstract func get_inventory_storage(storage_type: int) -> float


## Returns the per-storage-class capacities array. Return is proxy array
## reference; read only!
@abstract func get_inventory_storages() -> PackedFloat64Array


## Returns the amount of storage class [param storage_type] currently in use
## (local stocks plus remote stores).
@abstract func get_inventory_storage_used(storage_type: int) -> float


## Returns the quantity of [param resource_type] this facility owns stored
## remotely at the given facility.
@abstract func get_inventory_remote_store(facility_id_: int, resource_type: int) -> float


## Returns the full bidirectional flag value for resource [param resource_type].
@abstract func get_inventory_flags(resource_type: int) -> int


## Returns the per-resource flags array. Return is proxy array reference;
## read only!
@abstract func get_inventory_flags_array() -> PackedInt64Array


# Population (facility-only). Facility-only reads. Implemented on the server-side
# facility proxy against its population component.

## Returns the intrinsic growth rate for [param population_type]. Safe default
## on an out-of-range index.
@abstract func get_population_intrinsic_growth(population_type: int) -> float


## Returns the carrying capacity for [param carrying_capacity_group]. Safe
## default on an out-of-range index.
@abstract func get_population_carrying_capacity(carrying_capacity_group: int) -> float


## Returns the summed carrying capacity across the groups [param population_type]
## can occupy. Safe default on an out-of-range index.
@abstract func get_population_carrying_capacity_for_population(population_type: int) -> float


## Returns the total population sharing [param carrying_capacity_group].
@abstract func get_population_number_for_carrying_capacity_group(carrying_capacity_group: int) -> float


## Returns migration pressure for [param population_type] (positive = net
## immigration, negative = net emigration). Safe default on an out-of-range index.
@abstract func get_population_migration_pressure(population_type: int) -> float


## Returns this facility's [MarketProxy], or null if not yet set.
func get_market() -> MarketProxy:
	return market


# ******************************** AI METHODS *********************************

## Sets [member gui_name] and marks the proxy dirty. Reverse-flow:
## proxy -> server.
@abstract func set_gui_name(new_gui_name: String) -> void


## Sets the [code]FROM_PROXY_MASK[/code] bits of [member flags] to
## [param value], preserving the server-authoritative
## [code]FROM_SERVER_MASK[/code] bits. Proxy-authoritative: this change
## flows proxy -> server.
@abstract func set_flags(value: int) -> void


## Sets the facility's autonomous growth intensity — how aggressively the server
## grows (or, when negative, winds down) module capacity each interval, scaling
## its per-module allocation. Proxy-authoritative: this change flows
## proxy -> server. No-op on a NaN value.[br]
## - > 0.0: grow at this aggressiveness (~0.3 is steady; ~1.0 compounds fast).[br]
## - 0.0: hold — run no buildout or decommission.[br]
## - < 0.0: wind down — decommission capacity proportionally at this magnitude.
@abstract func set_buildout_intensity(value: float) -> void


## Sets the [code]FROM_PROXY_MASK[/code] bits of operations flags for
## [param operation_type] to [param value]. Proxy-authoritative: this
## change flows proxy -> server. No-op on an out-of-range index.
@abstract func set_operations_flags(operation_type: int, value: int) -> void


## Sets the target margin floor for operation [param type] (run while gross margin
## >= value). Proxy-authoritative: this change flows proxy -> server. No-op on an
## out-of-range index or NAN.
@abstract func set_operations_target_margin(type: int, value: float) -> void


## Sets the target spending share for operation [param type] (fraction of facility
## income, or NAN = not in effect). Proxy-authoritative; flows proxy -> server.
@abstract func set_operations_target_spending_share(type: int, value: float) -> void


## Sets the target run rate for operation [param type] (absolute rate, or NAN = not
## in effect). Proxy-authoritative; flows proxy -> server.
@abstract func set_operations_target_run_rate(type: int, value: float) -> void


## Overrides the server's autonomous build/decommission decision for
## [param module_type]. Pass [code]NAN[/code] (the default) to leave the module
## on auto — the facility allocates its build/decommission from demand and
## economics (see [method set_buildout_intensity]). Pass a number to override
## just this module; it is read relative to the other modules' effective levers,
## rate-limited by the facility's construction yards:[br]
## - NAN (default): auto — let the server decide this module.[br]
## - 1.0: expand in proportion to the module's current size; an all-1.0 fill
##   grows the whole facility while preserving its mix.[br]
## - 0.0: leave this module alone — its share of construction goes to others.[br]
## - 0.0 to 1.0 (exclusive): expand at reduced emphasis, letting the mix drift
##   away from current.[br]
## - >1.0: prioritize this module — grow faster than proportional. *This is the
##   only way to bootstrap build a module that has 0.0 current quantity.*[br]
## - <0.0 (<-1.0 to prioritize): decommission instead, reclaiming materials.
@abstract func set_operations_module_buildout(module_type: int, value: float) -> void


## Fills the entire per-module build/decommission override array with
## [param value] — the array-wide form of [method set_operations_module_buildout].
## Pass [code]NAN[/code] to return every module to auto (server-decided)
## allocation, or e.g. 1.0 to override all modules to proportional growth.
## Proxy-authoritative: this change flows proxy -> server.
@abstract func set_operations_module_buildouts_fill(value: float) -> void


## Sets the [code]FROM_PROXY_MASK[/code] bits of inventory flags for
## [param resource_type] to [param value]. Proxy-authoritative: this
## change flows proxy -> server. No-op on an out-of-range index.
@abstract func set_inventory_flags(resource_type: int, value: int) -> void


## Sets the strategic reserve for [param type]. Proxy-authoritative:
## this change flows proxy -> server. No-op on an out-of-range index or invalid
## value.
@abstract func set_inventory_strategic_reserve(type: int, value: float) -> void
