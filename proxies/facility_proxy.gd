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

	## Crisis posture: operations continue regardless of profitability.
	MODE_EMERGENCY = 1 << 32,
	## Laid-up state: no operations run; capacity is preserved for later restart.
	MODE_MOTHBALL = 1 << 33,
	## Inventory drawdown: no stock may rise, so each operation runs only as far as the
	## facility itself uses what it makes (distinct from the DECOMMISSIONING operation, which
	## tears down modules).
	MODE_DRAWDOWN = 1 << 34,
	## Mask of all AI-command bits.
	FROM_PROXY_MASK = ~((1 << 32) - 1),
}


## Per-resource inventory bit flags. FROM_SERVER bits (0 - 31) are signals from
## the server; FROM_PROXY bits (32 - 63) are AI commands to the server.
enum InventoryFlags {
	## Stock of this resource is below its critical level (see
	## [method get_inventory_critical_level]).
	OPS_RESERVE_BREACHED = 1 << 1,
	## Stock of this resource is below its desired level (see
	## [method get_inventory_desired_level]).
	STRATEGIC_RESERVE_BREACHED = 1 << 2,
	## No market price is established for this resource at this location.
	PRICE_UNKNOWN = 1 << 4,
	## This resource can be traded: it has a trade class.
	TRADABLE = 1 << 5,
	## A can-have operation at this facility consumes this resource.
	CAN_HAVE_INPUT = 1 << 6,
	## A can-have operation at this facility produces or extracts this resource.
	CAN_HAVE_OUTPUT = 1 << 7,
	## Not set since the holding rent replaced disposal for want of room (PRODUCTION_MODEL.md,
	## "A storage class: the holding rent"). The trader reads it until its rebuild.
	DUMPING = 1 << 8,
	## Mask of all server-published signal bits.
	FROM_SERVER_MASK = (1 << 32) - 1,

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
	## The operation ran below its intended rate last interval because its outputs' budgets
	## called for less: the facility used no more of them, and their stocks were at their
	## levels (see PRODUCTION_MODEL.md, "A facility's stock of a resource").
	WAS_OUTPUT_LIMITED = 1 << 3,
	## The operation made up a short input from others in its substitution group
	## last interval.
	WAS_SUBSTITUTING = 1 << 4,
	## Mask of all server-published signal bits.
	FROM_SERVER_MASK = (1 << 32) - 1,

	## When any of the op's outputs is below its critical level, suspend profit-gating so the
	## op can ramp up.
	SHORTAGE_PRIORITY = 1 << 33,
	## Hold the operation at a minimum baseline rate even when other
	## automations would idle it.
	STRATEGIC_FLOOR = 1 << 34,
	## Never run past an output's budget: the operation runs only as far as every output is
	## called for, rather than as far as any one of them is and making the others with it.
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
	CRITICAL_LEVELS = 1 << 2,
	DESIRED_LEVELS = 1 << 3,
	EXPECTED_RATES = 1 << 4,
	IN_TRANSITS = 1 << 5,
	RATES = 1 << 6,
	FLAGS = 1 << 7,
	BUFFER_STOCKS = 1 << 8,
}


var facility_id := -1  ## Index into [member ProxyBus.facility_proxies].
var facility_class := -1  ## Facility class index. Not implemented yet.
## Public-sector share of this facility, often 0.0 or 1.0, sometimes mixed.
var public_sector: float
## True if this is a small focused activity (affects stats and tax treatment).
var is_unitary: bool
## True if this facility makes its body's market, warehousing stock and keeping a bid
## and an ask standing (see TRADE_MODEL.md, "Market makers").
var market_maker: bool
## True if all resource streams flow from/to inventory (no atmosphere/surface
## market).
var closed_cycle_ops: bool
## Per-source corrections multiplying this site's body-level renewable capacity
## factor (territorial quality vs the body baseline; 1.0 = body value).
var solar_correction := 1.0
var wind_correction := 1.0
var geothermal_correction := 1.0
## Time horizon used by AI and automations (inventory reserves, resupply, etc.).
var time_horizon: float
## Bidirectional bit flags (see [enum FacilityFlags]). FROM_SERVER bits are
## server-authoritative; FROM_PROXY bits are proxy-authoritative. Use
## [method set_flags] to modify the proxy half.
var flags := 0

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


## Returns the environmental capacity factor for renewable-power operation
## [param operation_type] at this facility (the body factor scaled by this site's
## per-source correction); NAN if not a body-modeled renewable or unavailable here.
@abstract func calculate_capacity_factor(operation_type: int) -> float


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


# Operations (facility-only). Facility-only reads, plus proxy-authoritative knobs
# (flags and the target_* setters) with reverse data flow proxy -> server. Implemented
# on the server-side facility proxy against its operations component.

## Returns the capacity factor (environmental or historical limit) of operation
## [param operation_type].
@abstract func get_operations_capacity_factor(operation_type: int) -> float


## Returns the per-operation capacity factors array. Return is proxy array
## reference; read only!
@abstract func get_operations_capacity_factors() -> PackedFloat64Array


## Returns the Tier-3 process utilization of operation [param operation_type] (the
## server/controller's run-rate target; for display).
@abstract func get_operations_process_utilization(operation_type: int) -> float


## Returns the per-operation process utilizations array. Return is proxy array
## reference; read only!
@abstract func get_operations_process_utilizations() -> PackedFloat64Array


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
# (flags, level lever, buffer stock) with reverse data flow proxy -> server. Implemented
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


## Returns the critical level of [param resource_type]: the stock the facility's survival
## draws and operations need until resupply could land, their use over its time horizon. Its
## producers rebuild it as fast as their capacity allows. Fitted to what storage holds, with
## every critical level in a class held before any desired level (see PRODUCTION_MODEL.md, "A
## facility's stock of a resource").
@abstract func get_inventory_critical_level(resource_type: int) -> float


## Returns the per-resource critical levels array. Return is proxy array reference;
## read only!
@abstract func get_inventory_critical_levels() -> PackedFloat64Array


## Returns the desired level of [param resource_type], never below its critical level: the
## stock the facility's production aims at, the critical level and what the AI's lever asks for
## beyond it (see [method set_inventory_level_lever]), fitted to what storage holds. Production
## closes the gap to it over a few intervals.
@abstract func get_inventory_desired_level(resource_type: int) -> float


## Returns the per-resource desired levels array. Return is proxy array reference;
## read only!
@abstract func get_inventory_desired_levels() -> PackedFloat64Array


## Returns the AI's lever on the desired level of [param resource_type] (see
## [method set_inventory_level_lever]).
@abstract func get_inventory_level_lever(resource_type: int) -> float


## Returns the per-resource level levers array. Return is proxy array reference;
## read only!
@abstract func get_inventory_level_levers() -> PackedFloat64Array


## Returns the buffer stock for [param resource_type]: stock the AI would hold for the market,
## such as a market maker's warehouse. The facility ignores it until trade is rebuilt
## (PRODUCTION_MODEL.md, "Build order" of the feedback plan, step 8).
@abstract func get_inventory_buffer_stock(resource_type: int) -> float


## Returns the per-resource buffer stocks array. Return is proxy array
## reference; read only!
@abstract func get_inventory_buffer_stocks() -> PackedFloat64Array


## Returns the net flow rate of [param resource_type] averaged over the time horizon (positive
## = the facility made more than it used, negative = it used more than it made).
@abstract func get_inventory_expected_rate(resource_type: int) -> float


## Returns the per-resource expected rates array. Return is proxy array
## reference; read only!
@abstract func get_inventory_expected_rates() -> PackedFloat64Array


## Returns what the facility used of [param resource_type] per unit time, averaged over its
## time horizon: the internal volume of its own market, and what its desired level is sized
## from (see PRODUCTION_MODEL.md, "Local prices").
@abstract func get_inventory_use(resource_type: int) -> float


## Returns the per-resource uses array. Return is proxy array reference; read only!
@abstract func get_inventory_uses() -> PackedFloat64Array


## Returns the facility's local price of [param resource_type]: the price at its own market,
## which its operations plan against, its storage values and its books count, in
## [method MarketProxy.get_price] units. It moves each interval toward the price at which the
## facility's own producers and users would have balanced (PRODUCTION_MODEL.md, "Local
## prices"). 0.0 for a resource that nobody here uses, and for one with no price at all.
@abstract func get_inventory_local_price(resource_type: int) -> float


## Returns the per-resource local prices array. Return is proxy array reference; read only!
@abstract func get_inventory_local_prices() -> PackedFloat64Array


## Returns the quantity of [param resource_type] delivered to this facility and not yet taken
## into stock (always >= 0.0). It uses no storage. The facility's next interval draws it before
## anything else and stores what is left, and what its storage can't hold then is disposed of.
@abstract func get_inventory_in_transit(resource_type: int) -> float


## Returns the per-resource in-transit array. Return is proxy array reference;
## read only!
@abstract func get_inventory_in_transits() -> PackedFloat64Array


## Returns the quantity of [param resource_type] this facility has set aside for deliveries it
## owes (always >= 0.0). It uses no storage, and settlement delivers it before any stock; what
## the facility no longer owes returns in transit.
@abstract func get_inventory_outbound(resource_type: int) -> float


## Returns the per-resource outbound array. Return is proxy array reference; read only!
@abstract func get_inventory_outbounds() -> PackedFloat64Array


## Returns the most recent measured net rate for [param resource_type] (positive
## = production, negative = consumption).
@abstract func get_inventory_rate(resource_type: int) -> float


## Returns the per-resource rates array. Return is proxy array reference;
## read only!
@abstract func get_inventory_rates() -> PackedFloat64Array


## Returns the most recent measured gross production rate for [param resource_type]
## (>= 0.0): the production half of [method get_inventory_rate].
@abstract func get_inventory_production_rate(resource_type: int) -> float


## Returns the most recent measured gross consumption rate for [param resource_type]
## (>= 0.0), counting operation input, maintenance and buildout draws: the consumption
## half of [method get_inventory_rate].
@abstract func get_inventory_consumption_rate(resource_type: int) -> float


## Returns the rate at which surplus [param resource_type] was disposed of over
## the last interval to relieve a full storage class (>= 0.0). Disposal is not
## counted in [method get_inventory_rate]. See [constant InventoryFlags.DUMPING].
@abstract func get_inventory_disposal_rate(resource_type: int) -> float


## Returns the per-resource disposal rates array. Return is proxy array
## reference; read only!
@abstract func get_inventory_disposal_rates() -> PackedFloat64Array


## Returns the rate at which demand for [param resource_type] went unserved over the last
## interval (>= 0.0), counted only where this resource was what held its consumer back: an
## operation short of electricity draws less of its other inputs too, and only the
## electricity counts. Residents, buildout and maintenance count what they went without, but
## not a backlog carried from earlier intervals, such as deferred maintenance (see
## PRODUCTION_MODEL.md, "What the facility publishes").
@abstract func get_inventory_unmet_rate(resource_type: int) -> float


## Returns the per-resource unmet rates array. Return is proxy array reference;
## read only!
@abstract func get_inventory_unmet_rates() -> PackedFloat64Array


## Returns the rate at which production of [param resource_type] was held back over the last
## interval because the facility used no more of it and its stock was at its levels (>= 0.0),
## counted only where this resource was the output that held its operation back. What an
## operation made anyway, running for another output, goes to stock instead, and leaves it by
## [method get_inventory_disposal_rate] if its class's rent says so.
@abstract func get_inventory_curtailed_rate(resource_type: int) -> float


## Returns the per-resource curtailed rates array. Return is proxy array reference;
## read only!
@abstract func get_inventory_curtailed_rates() -> PackedFloat64Array


## Returns the most this facility's traders will pay per unit of [param resource_type],
## in [method MarketProxy.get_price] units: what the operations consuming it could pay
## and still clear their margin floors, set by the marginal one (see TRADE_MODEL.md,
## "Price discovery"). INF when nothing here with revenue consumes it.
@abstract func get_inventory_reservation_price(resource_type: int) -> float


## Returns the per-resource reservation prices array. Return is proxy array
## reference; read only!
@abstract func get_inventory_reservation_prices() -> PackedFloat64Array


## Returns the least a unit of [param resource_type] must fetch, in
## [method MarketProxy.get_price] units, for this facility's cheapest producing operation
## to clear its margin floor: the floor of a market maker's price where storage carries the
## flows (see TRADE_MODEL.md, "Market makers"). 0.0 when an operation here clears its floor
## even giving it away; INF when nothing here produces it at known prices.
@abstract func get_inventory_production_breakeven(resource_type: int) -> float


## Returns the per-resource production break-evens array. Return is proxy array
## reference; read only!
@abstract func get_inventory_production_breakevens() -> PackedFloat64Array


## Returns the most this facility's most tolerant consuming operation could pay per unit
## of [param resource_type], in [method MarketProxy.get_price] units, and still clear its
## margin floor: the ceiling of a market maker's price (see TRADE_MODEL.md, "Market
## makers"). Unlike [method get_inventory_reservation_price], it counts operations
## already priced below their floor. INF when nothing here with revenue consumes it.
@abstract func get_inventory_consumption_breakeven(resource_type: int) -> float


## Returns the per-resource consumption break-evens array. Return is proxy array
## reference; read only!
@abstract func get_inventory_consumption_breakevens() -> PackedFloat64Array


## Returns what a unit of [param resource_type] must fetch, in
## [method MarketProxy.get_price] units, for the costliest unit of production still making
## it here to clear its margin floor, as of the last interval: the price the merit order
## sets, and the floor of a market maker's price where storage can't carry the flows (see
## TRADE_MODEL.md, "Market makers"). Where nothing here made it, the price at which the
## cheapest unit would start. Only operations whose margin floors set their runs count (see
## PRODUCTION_MODEL.md, "What the facility publishes"). 0.0 when that unit clears its floor
## giving it away; INF when no such operation here produces it at known prices.
@abstract func get_inventory_marginal_production_breakeven(resource_type: int) -> float


## Returns the per-resource marginal production break-evens array. Return is proxy array
## reference; read only!
@abstract func get_inventory_marginal_production_breakevens() -> PackedFloat64Array


## Returns the storage capacity of storage class [param storage_type].
@abstract func get_inventory_storage(storage_type: int) -> float


## Returns the per-storage-class capacities array. Return is proxy array
## reference; read only!
@abstract func get_inventory_storages() -> PackedFloat64Array


## Returns the amount of storage class [param storage_type] currently in use
## (local stocks plus remote stores).
@abstract func get_inventory_storage_used(storage_type: int) -> float


## Returns the rent storage class [param storage_type] charges per interval, as a share of the
## value of what it holds: 0.0 at or below its capacity, rising past it with the square of the
## overfill over the class's give (storage_classes.schema.md), and INF where the class can hold
## nothing more. Surplus worth less than the rent is disposed of, and what can't be disposed of
## pays it in its makers' margins (see PRODUCTION_MODEL.md, "A storage class: the holding
## rent").
@abstract func get_inventory_storage_rent(storage_type: int) -> float


## Returns the per-storage-class rents array. Return is proxy array reference; read only!
@abstract func get_inventory_storage_rents() -> PackedFloat64Array


## Returns how long storage class [param storage_type] could carry the last interval's flows
## through it, in sim time: its capacity over its members' gross throughput, each member at
## the larger of what the facility made and what it used of it. INF when nothing flowed, and
## before the first interval. Much less than an interval means the class's stock says little
## about the next one (see PRODUCTION_MODEL.md, "Level plus rates times the period"). A
## resource with no storage class holds unbounded stock, as though its turnover were INF.
@abstract func get_inventory_storage_turnover_time(storage_type: int) -> float


## Returns the per-storage-class turnover times array. Return is proxy array
## reference; read only!
@abstract func get_inventory_storage_turnover_times() -> PackedFloat64Array


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

## Returns how many of [param population_type] are in its age [param bucket], one of the
## type's eight (see POPULATION_MODEL.md, "Demographics"). Safe default on an out-of-range
## index.
@abstract func get_population_bucket_number(population_type: int, bucket: int) -> float


## Returns how many of [param population_type] are in life [param stage], an
## [enum Enums.LifeStages]. Safe default on an out-of-range index.
@abstract func get_population_stage_number(population_type: int, stage: int) -> float


## Returns the births per second of [param population_type], smoothed over about a
## quarter. Safe default on an out-of-range index.
@abstract func get_population_birth_rate(population_type: int) -> float


## Returns the deaths per second of [param population_type], starvation included, smoothed
## over about a quarter. Safe default on an out-of-range index.
@abstract func get_population_death_rate(population_type: int) -> float


## Returns the starvation deaths per second of [param population_type], smoothed over about
## a quarter: the people who die for want of life support. Safe default on an out-of-range
## index.
@abstract func get_population_starvation_rate(population_type: int) -> float


## Returns the life expectancy at birth of [param population_type] at its present death
## rates, in seconds. Safe default on an out-of-range index.
@abstract func get_population_life_expectancy(population_type: int) -> float


## Returns migration pressure for [param population_type] (positive = net
## immigration, negative = net emigration). Safe default on an out-of-range index.
@abstract func get_population_migration_pressure(population_type: int) -> float


## Returns the share of [param population_type]'s want for [param need], a
## [code]needs.tsv[/code] row, that it got (1.0 = fully met), smoothed over about a month for
## an existence need and a quarter for the others. Below its type's threshold in any existence
## need, people starve. 1.0 for a need the type has no want for. Safe default on an
## out-of-range index.
@abstract func get_population_satisfaction(population_type: int, need: int) -> float


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
## economics. Pass a number to override
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


## Sets how much stock of [param type] the facility holds beyond its critical level, against an
## interruption or as a stockpile, in time horizons of its use: 0.0 holds none. The server sizes
## the desired level from it, caps it and fits it to storage (see
## [method get_inventory_desired_level]). Proxy-authoritative: this change flows proxy ->
## server. No-op on an out-of-range index or invalid value.
@abstract func set_inventory_level_lever(type: int, value: float) -> void


## Sets the buffer stock for [param type], which the facility ignores until trade is rebuilt.
## Proxy-authoritative: this change flows proxy -> server. No-op on an out-of-range index or
## invalid value.
@abstract func set_inventory_buffer_stock(type: int, value: float) -> void


## @deprecated: Read by the trader until its rebuild (PRODUCTION_MODEL.md, "Build order" of the
## feedback plan, step 8). Returns [method get_inventory_critical_level].
func get_inventory_effective_ops_reserve(resource_type: int) -> float:
	return get_inventory_critical_level(resource_type)


## @deprecated: Read by the trader until its rebuild. Returns the desired level less the
## critical level.
func get_inventory_effective_strategic_reserve(resource_type: int) -> float:
	return get_inventory_desired_level(resource_type) - get_inventory_critical_level(resource_type)


## @deprecated: Read by the trader until its rebuild. Returns
## [method get_inventory_buffer_stock].
func get_inventory_effective_buffer_stock(resource_type: int) -> float:
	return get_inventory_buffer_stock(resource_type)


## @deprecated: Read by the trader until its rebuild. Returns 1.0: levels are fitted to storage
## before they are published.
func get_inventory_storage_level_scale(_storage_type: int) -> float:
	return 1.0
