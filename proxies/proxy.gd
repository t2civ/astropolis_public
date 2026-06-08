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

## Field selectors for [method get_operations_items] (bit flags; OR together).
## Operation-level bits (0-8) select per-operation fields and treat the type
## argument as an operation_type; module-level bits (9-16) select per-module
## aggregates and treat type as a module_type. Don't mix the two groups in one
## call. Rate fields may be NAN where not applicable; FLAGS returns the
## operation's bidirectional flag int (facility hosts only).
enum OperationsItems {
	UTILIZATION = 1,
	ELECTRICITY = 1 << 1,
	REVENUE = 1 << 2,
	GROSS_MARGIN = 1 << 3,
	FUEL_RATE = 1 << 4,
	EXTRACTION_RATE = 1 << 5,
	MASS_CONVERSION_RATE = 1 << 6,
	COMPUTATION = 1 << 7,
	FLAGS = 1 << 8,
	MODULE_UTILIZATION = 1 << 9,
	MODULE_ELECTRICITY = 1 << 10,
	MODULE_REVENUE = 1 << 11,
	MODULE_GROSS_MARGIN = 1 << 12,
	MODULE_FUEL_RATE = 1 << 13,
	MODULE_EXTRACTION_RATE = 1 << 14,
	MODULE_MASS_CONVERSION_RATE = 1 << 15,
	MODULE_COMPUTATION = 1 << 16,
}


const INTERVAL := 7.0 * IVUnits.DAY ## AI tick interval. See [constant BaseAI.INTERVAL].

## ivoyager save/load category. A Proxy persists NONE of its server data — Net
## components and scalar fields all re-flow from the server entity via
## set_network_init() + dirty-sync. A subclass DOES persist its cross-proxy
## references (and the few relationship scalars a peer sets), so save/load relinks
## the proxy graph directly instead of re-resolving it; list those in the
## subclass's PERSIST_PROPERTIES. Never persist a Net component or entity data.
const PERSIST_MODE := IVGlobal.PERSIST_PROCEDURAL


static var proxy_bus: ProxyBus ## Shared [ProxyBus] for proxy-thread signals and data.

@warning_ignore_start("unused_private_class_variable")
# Add more as convenience values. Include index guards for public use.
static var n_resources: int ## Number of resource types.
static var _base_class_instantiated := false

# FIXME: Change below to public "convenience" values or remove...
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
## True once this proxy's cross-proxy refs are wired and one-time setup has run;
## the server ticks AI only after. Proxy-thread state.
var proxy_ready := false


@warning_ignore_start("unused_private_class_variable") # used by subclasses
var _dirty := 0
# Refs in place (resolved on new game/runtime; pre-set on load — save relinked them).
var _refs_wired := false
@warning_ignore_restore("unused_private_class_variable")


# ***************************** CREATE & STATIC *******************************

## Returns a [Proxy] by [param proxy_name], or null if doesn't exist. Call on
## proxy thread only!
static func get_proxy_by_name(proxy_name: StringName) -> Proxy:
	return proxy_bus.proxies_by_name.get(proxy_name)


## Builds a futures position key [resource_type, ordinal_quarter, delivery_id,
## party_id]. delivery_id == party_id denotes a long (inbound) position; !=
## denotes a short (outbound) position.
static func make_position_key(resource_type: int, ordinal_quarter: int, delivery_id: int,
		party_id: int) -> PackedInt32Array:
	var key := PackedInt32Array()
	key.resize(4)
	key[0] = resource_type
	key[1] = ordinal_quarter
	key[2] = delivery_id
	key[3] = party_id
	return key


static func _on_base_class_instantiated() -> void:
	n_resources = _table_n_rows[&"resources"]



# ************************* VIRTUAL & IMPLEMENTATION **************************

func _init() -> void:
	IVStateManager.about_to_free_procedural_nodes.connect.call_deferred(_clear_for_destruction)
	if !_base_class_instantiated:
		_base_class_instantiated = true
		_on_base_class_instantiated()


## Runtime mid-game removal entry point. Subclass overrides MUST chain to
## [code]super.remove()[/code] so cycles are broken outside of quit.
func remove() -> void:
	_clear_for_destruction()


## Override to null every outgoing Proxy/Resource ref. Both sides of a
## 2-cycle should clear — redundant on success, robust under refactoring.
func _clear_for_destruction() -> void:
	pass


## Called once by ProxyServer when this proxy becomes ready (cross-proxy refs
## wired). Override to derive non-ref state from those refs (e.g. a cached
## texture from the hosting body). Runs again on the fresh post-load instance;
## idempotent overrides required.
func _on_ready() -> void:
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
# override. [method get_operations_items] returns the selected fields indexed by
# [enum OperationsItems].

## True if this proxy reports per-operation financial metrics (revenue, margin).
func has_financials() -> bool:
	return false


## True if [param module_type] (and any of its operations) has nonzero
## capacity or interest at this proxy.
func is_operations_of_interest_module(_module_type: int) -> bool:
	return false


## Returns the [enum OperationsItems] fields selected by [param _items_mask] for
## [param _type], as an untyped Array in ascending bit order — or an empty array
## if this proxy has no operations. See [enum OperationsItems] for the type/mask
## contract.
func get_operations_items(_type: int, _items_mask: int) -> Array:
	return []


# Per-operation scalars (read-only). Default 0.0/false; developed proxies
# override. Rate fields may be NAN where not applicable.

## Returns the capacity (maximum run rate) of operation [param operation_type].
## The key capability signal: nonzero capacity means the proxy can run it.
func get_operations_capacity(_operation_type: int) -> float:
	return 0.0


## Returns the per-operation capacities array, or empty if this proxy has no
## operations. Read-only reference; do not mutate.
func get_operations_capacities() -> PackedFloat64Array:
	return PackedFloat64Array()


## Returns the current run rate of operation [param operation_type].
func get_operations_run_rate(_operation_type: int) -> float:
	return 0.0


## Returns the per-operation run rates array, or empty if this proxy has no
## operations. Read-only reference; do not mutate.
func get_operations_run_rates() -> PackedFloat64Array:
	return PackedFloat64Array()


## Returns the effective rate of operation [param operation_type] (output actually
## realized; may be below the run rate).
func get_operations_effective_rate(_operation_type: int) -> float:
	return 0.0


## Returns the per-operation effective rates array, or empty if this proxy has no
## operations. Read-only reference; do not mutate.
func get_operations_effective_rates() -> PackedFloat64Array:
	return PackedFloat64Array()


## Returns utilization (run rate / capacity) of operation [param operation_type].
func get_operations_utilization(_operation_type: int) -> float:
	return 0.0


## Returns the revenue rate of operation [param operation_type], or NAN if this
## proxy reports no financials.
func get_operations_revenue_rate(_operation_type: int) -> float:
	return 0.0


## Returns the per-operation revenue rates array, or empty if this proxy has no
## operations or no financials. Read-only reference; do not mutate.
func get_operations_revenue_rates() -> PackedFloat64Array:
	return PackedFloat64Array()


## Returns the cost-of-goods-sold rate of operation [param operation_type], or NAN
## if this proxy reports no financials.
func get_operations_cogs_rate(_operation_type: int) -> float:
	return 0.0


## Returns the per-operation cost-of-goods-sold rates array, or empty if this
## proxy has no operations or no financials. Read-only reference; do not mutate.
func get_operations_cogs_rates() -> PackedFloat64Array:
	return PackedFloat64Array()


## Returns the gross margin of operation [param operation_type], or NAN if
## undefined (no financials, or a non-facility with zero revenue).
func get_operations_gross_margin(_operation_type: int) -> float:
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

## Returns the population count for [param population_type], or the total across
## all types if -1. Safe default on an out-of-range index.
func get_population_number(_population_type := -1) -> float:
	return 0.0


## Returns the per-quarter population-number history (oldest first) for
## [param population_type], or an empty array. Safe default on an out-of-range
## index.
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
