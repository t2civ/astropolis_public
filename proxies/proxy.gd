# proxy.gd
# This file is part of Astropolis
# https://t2civ.com
# *****************************************************************************
# Copyright 2019-2026 Charlie Whitfield; ALL RIGHTS RESERVED
# Astropolis is a registered trademark of Charlie Whitfield in the US
# *****************************************************************************
@abstract
class_name Proxy
extends RefCounted

## Base class for entity proxies between AI/GUI clients and the game server.
##
## All GUI and in-game AI interaction with game internals goes through a
## [Proxy]. Subclasses ([FacilityProxy], [PlayerProxy], [BodyProxy],
## [JoinProxy], [TraderProxy], [MarketProxy], [BrokerProxy]) declare the
## API. Sync plumbing and concrete instantiation live on server-side entities.
##
## WARNING: Lives on the proxy thread. Containers and many methods are not
## threadsafe; accessing non-container properties is safe.


## Market order status.
enum TradeOrderStatus {
	BOOKED,
	FILLED,
	PARTIALLY_FILLED,
	CANCELLED,
	## Resting order repriced/resized in place. The order keeps its id; the
	## update's quantity field carries a SIGNED unfilled delta (new − old).
	REPLACED,
}

## Indices into the [PackedFloat64Array] rows returned by
## [method get_module_data] and [method get_operation_data]. Rate fields may
## be NAN where not applicable (e.g. fuel rate for a non-generator).
enum OperationDataIndex {
	UTILIZATION,
	ELECTRICITY,
	REVENUE,
	GROSS_MARGIN,
	FUEL_RATE,
	EXTRACTION_RATE,
	MASS_CONVERSION_RATE,
	COMPUTATION,
	N_OPERATION_DATA,
}


const INTERVAL := 7.0 * IVUnits.DAY ## AI tick interval. See [constant BaseAI.INTERVAL].

## ivoyager save/load category. A Proxy is rebuilt blank on load and persists
## NONE of its own state: all "truth" re-flows from the server entity via
## set_network_init() + dirty-sync, and resolve_proxy_refs() side effects (e.g.
## player.add_facility(self), the assert(!joins.has(join))) stay idempotent only
## because the rebuilt proxy is blank. Do NOT add PERSIST_PROPERTIES to a Proxy.
const PERSIST_MODE := IVGlobal.PERSIST_PROCEDURAL


static var proxy_bus: ProxyBus ## Shared [ProxyBus] for proxy-thread signals and data.

@warning_ignore_start("unused_private_class_variable")
static var _times: Array = IVGlobal.times
static var _date: Array = IVGlobal.date
static var _clock: Array = IVGlobal.clock
static var _db_tables := IVTableData.db_tables
static var _table_n_rows: Dictionary = IVTableData.table_n_rows
@warning_ignore_restore("unused_private_class_variable")


var proxy_id := -1  ## Index into [member ProxyBus.proxies].
var entity_type := -1  ## Entity type tag; set by the server-side proxy.
var name := &""  ## Unique, immutable identifier (e.g. [code]&"PLAYER_NASA"[/code]).
var gui_name := ""  ## Display name; mutable. Empty player gui_name hides from GUI.
## Quarterly clock as [code]year * 4 + (quarter - 1)[/code]. Never set for a
## [BodyProxy] without a facility.
var ordinal_qtr := -1


@warning_ignore_start("unused_private_class_variable") # used by subclasses
var _dirty := 0
var _refs_resolved := false
@warning_ignore_restore("unused_private_class_variable")


# ***************************** CREATE & STATIC *******************************

## Returns a [Proxy] by [param proxy_name], or null if doesn't exist. Call on
## proxy thread only!
static func get_proxy_by_name(proxy_name: StringName) -> Proxy:
	return proxy_bus.proxies_by_name.get(proxy_name)



# ************************* VIRTUAL & IMPLEMENTATION **************************

func _init() -> void:
	IVStateManager.about_to_free_procedural_nodes.connect.call_deferred(_clear_for_destruction)


## Runtime mid-game removal entry point. Subclass overrides MUST chain to
## [code]super.remove()[/code] so cycles are broken outside of quit.
func remove() -> void:
	_clear_for_destruction()


## Override to null every outgoing Proxy/Resource ref. Both sides of a
## 2-cycle should clear — redundant on success, robust under refactoring.
func _clear_for_destruction() -> void:
	pass


## Initializes this proxy from a server-supplied init payload. Modders: Don't touch this!
@abstract func set_network_init(data: Array) -> void


## Applies a server-supplied dirty payload. Modders: Don't touch this!
@abstract func _sync_server_dirty(data: Array) -> void


## Flushes proxy-side dirty state back to the server. Modders: Don't touch this!
@abstract func _sync_ai_changes() -> void



# ***************************** THREAD-SAFE READ ******************************

## Returns true if this proxy contributes development statistics
## (population, economy, power, manufacturing, etc.). Default false.
func has_development() -> bool:
	return false


## Returns true if this proxy participates in markets. Default false.
func has_markets() -> bool:
	return false


## Returns true if this proxy carries inventory state (resource stocks,
## contracts). Default false.
func has_inventory() -> bool:
	return false


# Development totals. Default 0.0; the developed proxies (Facility, Player,
# Body, Join) override with values combined from their components.

## Returns the development "population" total, optionally filtered to a
## specific [param population_type] (-1 for total).
func get_development_population(_population_type := -1) -> float:
	return 0.0


## Returns the development "economy" total (gross output).
func get_development_economy() -> float:
	return 0.0


## Returns the development "power" total (electrical generation).
func get_development_power() -> float:
	return 0.0


## Returns the development "manufacturing" total.
func get_development_manufacturing() -> float:
	return 0.0


## Returns the development "constructions" total (mass constructed).
func get_development_constructions() -> float:
	return 0.0


## Returns the development "computation" total.
func get_development_computation() -> float:
	return 0.0


## Returns the development "information" total.
func get_development_information() -> float:
	return 0.0


## Returns the development "bioproductivity" total.
func get_development_bioproductivity() -> float:
	return 0.0


## Returns the development "biomass" total.
func get_development_biomass() -> float:
	return 0.0


## Returns the development "biodiversity" metric (0.0–1.0).
func get_development_biodiversity() -> float:
	return 0.0


## Returns the [member name] of this proxy's [BodyProxy], or
## [code]&""[/code] if not applicable.
func get_body_name() -> StringName:
	return &""


## Returns body flags for this proxy's [BodyProxy] (see ivoyager
## [code]IVBody.BodyFlags[/code]), or 0 if not applicable.
func get_body_flags() -> int:
	return 0


## Returns the [member name] of this proxy's [PlayerProxy], or
## [code]&""[/code] if not applicable.
func get_player_name() -> StringName:
	return &""


## Returns the player class index for this proxy's [PlayerProxy], or
## -1 if not applicable.
func get_player_class() -> int:
	return -1


## Returns the polity name for this proxy, or [code]&""[/code] if not
## applicable.
func get_polity_name() -> StringName:
	return &""


## Returns this proxy's facilities. proxy thread only! Default empty.
func get_facilities() -> Array[Proxy]:
	return []


## Returns the spot [MarketProxy] for [param _player_id], or null if not
## applicable.
func get_market(_player_id: int) -> MarketProxy:
	return null


# Operations data (read-only). Default empty/false; the developed proxies
# override. [method get_module_data] and [method get_operation_data] return a
# row indexed by [enum OperationDataIndex].

## True if this proxy reports per-operation financial metrics (revenue, margin).
func has_financials() -> bool:
	return false


## True if [param module_type] (and any of its operations) has nonzero
## capacity or interest at this proxy.
func is_operations_of_interest_module(_module_type: int) -> bool:
	return false


## Returns a display row for [param module_type] indexed by
## [enum OperationDataIndex], or an empty array if this proxy has no operations.
func get_module_data(_module_type: int) -> PackedFloat64Array:
	return PackedFloat64Array()


## Returns a display row for operation [param operation_type] indexed by
## [enum OperationDataIndex], or an empty array if this proxy has no operations.
func get_operation_data(_operation_type: int) -> PackedFloat64Array:
	return PackedFloat64Array()


# Per-operation scalars (read-only). Default 0.0/false; developed proxies
# override. Rate fields may be NAN where not applicable.

## Returns the capacity (maximum run rate) of operation [param operation_type].
## The key capability signal: nonzero capacity means the proxy can run it.
func get_operations_capacity(_operation_type: int) -> float:
	return 0.0


## Returns the current run rate of operation [param operation_type].
func get_operations_run_rate(_operation_type: int) -> float:
	return 0.0


## Returns the effective rate of operation [param operation_type] (output actually
## realized; may be below the run rate).
func get_operations_effective_rate(_operation_type: int) -> float:
	return 0.0


## Returns utilization (run rate / capacity) of operation [param operation_type].
func get_operations_utilization(_operation_type: int) -> float:
	return 0.0


## Returns the AI-set target utilization of operation [param operation_type]
## (facility proxies only).
func get_operations_target_utilization(_operation_type: int) -> float:
	return 0.0


## Returns the revenue rate of operation [param operation_type], or NAN if this
## proxy reports no financials.
func get_operations_revenue_rate(_operation_type: int) -> float:
	return 0.0


## Returns the cost-of-goods-sold rate of operation [param operation_type], or NAN
## if this proxy reports no financials.
func get_operations_cogs_rate(_operation_type: int) -> float:
	return 0.0


## Returns the gross margin of operation [param operation_type], or NAN if
## undefined (no financials, or a non-facility with zero revenue).
func get_operations_gross_margin(_operation_type: int) -> float:
	return 0.0


## Returns the capacity factor (environmental/historical limit) of operation
## [param operation_type] (facility proxies only).
func get_operations_capacity_factor(_operation_type: int) -> float:
	return 0.0


## Returns the electricity rate of operation [param operation_type] (negative =
## consumer). If [param positive_only], consumers are clamped to 0.0.
func get_operations_electricity_rate(_operation_type: int, _positive_only := false) -> float:
	return 0.0


## Returns the extraction rate of operation [param operation_type].
func get_operations_extraction_rate(_operation_type: int) -> float:
	return 0.0


## Returns the mass-conversion rate of operation [param operation_type].
func get_operations_mass_conversion_rate(_operation_type: int) -> float:
	return 0.0


## Returns the fuel rate of operation [param operation_type].
func get_operations_fuel_rate(_operation_type: int) -> float:
	return 0.0


## Returns the manufacturing rate of operation [param operation_type]. If
## [param positive_only], consumers are clamped to 0.0.
func get_operations_manufacturing(_operation_type: int, _positive_only := false) -> float:
	return 0.0


## Returns the computation rate of operation [param operation_type]. If
## [param positive_only], consumers are clamped to 0.0.
func get_operations_computation(_operation_type: int, _positive_only := false) -> float:
	return 0.0


## True if operation [param operation_type] can be run at this proxy (facility
## capability; always false for non-facility proxies).
func is_operations_can_have(_operation_type: int) -> bool:
	return false


## True if operation [param operation_type] is of interest here (runnable at a
## facility, or nonzero capacity at an aggregate).
func is_operations_of_interest(_operation_type: int) -> bool:
	return false


# Per-module scalars (read-only). Default 0.0/0/false; developed proxies override.

## Returns the module count of [param module_type] (sum of its operations' capacities).
func get_operations_module_number(_module_type: int) -> float:
	return 0.0


## Returns the number of operations belonging to [param module_type].
func get_operations_n_operations_in_module(_module_type: int) -> int:
	return 0


## Returns the capacity-weighted utilization of [param module_type].
func get_operations_module_utilization(_module_type: int) -> float:
	return 0.0


## Returns the total electricity rate of [param module_type].
func get_operations_module_electricity(_module_type: int) -> float:
	return 0.0


## Returns the total revenue rate of [param module_type], or NAN if no financials.
func get_operations_module_revenue(_module_type: int) -> float:
	return 0.0


## Returns the total cost-of-goods-sold rate of [param module_type], or NAN if no
## financials.
func get_operations_module_cogs_rate(_module_type: int) -> float:
	return 0.0


## Returns the gross margin of [param module_type], or NAN if undefined.
func get_operations_module_gross_margin(_module_type: int) -> float:
	return 0.0


## Returns the total extraction rate of [param module_type].
func get_operations_module_extraction_rate(_module_type: int) -> float:
	return 0.0


## Returns the total mass-conversion rate of [param module_type].
func get_operations_module_mass_conversion_rate(_module_type: int) -> float:
	return 0.0


## Returns the total fuel rate of [param module_type].
func get_operations_module_fuel_rate(_module_type: int) -> float:
	return 0.0


## Returns the total computation rate of [param module_type].
func get_operations_module_computation(_module_type: int) -> float:
	return 0.0


## True if [param module_type] can be run at this proxy (facility capability;
## always false for non-facility proxies).
func is_operations_can_have_module(_module_type: int) -> bool:
	return false


# Inventory data (read-only). Default 0.0; FacilityProxy overrides.

func get_inventory_stock(_resource_type: int) -> float:
	return 0.0


func get_inventory_contracted(_resource_type: int) -> float:
	return 0.0


## Returns the operational reserve target for [param resource_type] — the stock
## level the facility aims to keep on hand to sustain its operations. Default 0.0.
func get_inventory_ops_reserve(_resource_type: int) -> float:
	return 0.0


## Returns the strategic reserve target for [param resource_type] — an AI-set
## buffer held beyond operational need. Default 0.0.
func get_inventory_strategic_reserve(_resource_type: int) -> float:
	return 0.0


## Returns the smoothed expected net rate for [param resource_type] (positive =
## net production, negative = net consumption). Default 0.0.
func get_inventory_expected_rate(_resource_type: int) -> float:
	return 0.0


## Returns the in-transit quantity for [param resource_type] (en route to this
## facility; always >= 0.0). Default 0.0.
func get_inventory_in_transit(_resource_type: int) -> float:
	return 0.0


## Returns the most recent measured net rate for [param resource_type] (positive
## = production, negative = consumption). Default 0.0.
func get_inventory_rate(_resource_type: int) -> float:
	return 0.0


## Returns the storage capacity of storage class [param storage_type]. Default 0.0.
func get_inventory_storage(_storage_type: int) -> float:
	return 0.0


## Returns the amount of storage class [param storage_type] currently in use
## (local stocks plus remote stores). Default 0.0.
func get_inventory_storage_used(_storage_type: int) -> float:
	return 0.0


## Returns the quantity of [param resource_type] this facility owns stored
## remotely at facility [param facility_id]. Default 0.0.
func get_inventory_remote_store(_facility_id: int, _resource_type: int) -> float:
	return 0.0


# Financials data (read-only). Default 0.0/empty; Facility, Player, and
# player-specific Join proxies override. "lfq" = last four quarters.

## Returns revenue summed over the last four quarters.
func get_financials_revenue_lfq() -> float:
	return 0.0


## Returns gross output (producer revenue) summed over the last four quarters.
func get_financials_gross_output_lfq() -> float:
	return 0.0


## Returns cost of goods sold summed over the last four quarters.
func get_financials_cost_of_goods_sold_lfq() -> float:
	return 0.0


## Returns revenue accumulated so far in the current (incomplete) quarter.
func get_financials_revenue() -> float:
	return 0.0


## Returns gross output accumulated so far in the current (incomplete) quarter.
func get_financials_gross_output() -> float:
	return 0.0


## Returns cost of goods sold accumulated so far in the current (incomplete) quarter.
func get_financials_cost_of_goods_sold() -> float:
	return 0.0


## Returns the per-quarter revenue history (oldest first), or an empty array.
func get_financials_revenue_history() -> PackedFloat64Array:
	return PackedFloat64Array()


## Returns the per-quarter gross-output history (oldest first), or an empty array.
func get_financials_gross_output_history() -> PackedFloat64Array:
	return PackedFloat64Array()


## Returns the per-quarter cost-of-goods-sold history (oldest first), or empty.
func get_financials_cost_of_goods_sold_history() -> PackedFloat64Array:
	return PackedFloat64Array()


# Population data (read-only). Default 0.0/empty; developed proxies override.
# Intrinsic growth, carrying capacity, and migration pressure are facility-only.

## Returns the population count for [param population_type], or the total across
## all types if -1.
func get_population_number(_population_type := -1) -> float:
	return 0.0


## Returns the intrinsic growth rate for [param population_type] (facility proxies only).
func get_population_intrinsic_growth(_population_type: int) -> float:
	return 0.0


## Returns the carrying capacity for [param carrying_capacity_group]
## (facility proxies only).
func get_population_carrying_capacity(_carrying_capacity_group: int) -> float:
	return 0.0


## Returns the summed carrying capacity across the groups [param population_type]
## can occupy (facility proxies only).
func get_population_carrying_capacity_for_population(_population_type: int) -> float:
	return 0.0


## Returns the total population sharing [param carrying_capacity_group]
## (facility proxies only).
func get_population_number_for_carrying_capacity_group(_carrying_capacity_group: int) -> float:
	return 0.0


## Returns migration pressure for [param population_type] (positive = net
## immigration, negative = net emigration; facility proxies only).
func get_population_migration_pressure(_population_type: int) -> float:
	return 0.0


## Returns the per-quarter population-number history (oldest first) for
## [param population_type], or an empty array.
func get_population_number_history(_population_type: int) -> PackedFloat64Array:
	return PackedFloat64Array()


# Biome data (read-only). Default 0.0; developed proxies override.

## Returns current bioproductivity.
func get_biome_bioproductivity() -> float:
	return 0.0


## Returns current biomass.
func get_biome_biomass() -> float:
	return 0.0


## Returns current biodiversity (minimum 1.0 where a biome is present).
func get_biome_biodiversity() -> float:
	return 0.0


# Cyberspace data (read-only). Default 0.0; developed proxies override.

## Returns the current computation rate.
func get_cyberspace_computation_rate() -> float:
	return 0.0


## Returns current information (minimum 1.0 where cyberspace is present).
func get_cyberspace_information() -> float:
	return 0.0
