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
	## Stock of this resource, with what is on its way here, is below its effective
	## operational reserve (see [method get_inventory_effective_ops_reserve]).
	OPS_RESERVE_BREACHED = 1 << 1,
	## Stock of this resource, with what is on its way here, is below its effective
	## strategic reserve (see [method get_inventory_effective_strategic_reserve]).
	STRATEGIC_RESERVE_BREACHED = 1 << 2,
	## No market price is established for this resource at this location.
	PRICE_UNKNOWN = 1 << 4,
	## This resource can be traded: it has a trade class.
	TRADABLE = 1 << 5,
	## A can-have operation at this facility consumes this resource.
	CAN_HAVE_INPUT = 1 << 6,
	## A can-have operation at this facility produces or extracts this resource.
	CAN_HAVE_OUTPUT = 1 << 7,
	## Nobody here uses or bids for this resource, and it is being disposed of or vented
	## for want of storage room; operations here value it at zero, as both input and
	## output, until its stock falls to its reserves or someone uses it or bids for it.
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
	## The operation ran below its intended rate last interval because an output
	## had no storage room.
	WAS_STORAGE_LIMITED = 1 << 3,
	## The operation made up a short input from others in its substitution group
	## last interval.
	WAS_SUBSTITUTING = 1 << 4,
	## Mask of all server-published signal bits.
	FROM_SERVER_MASK = (1 << 32) - 1,

	## When any of the op's outputs is below operational reserve, suspend
	## profit-gating so the op can ramp up.
	SHORTAGE_PRIORITY = 1 << 33,
	## Hold the operation at a minimum baseline rate even when other
	## automations would idle it.
	STRATEGIC_FLOOR = 1 << 34,
	## Never vent the operation's outputs: it runs only as far as every output has
	## storage room, rather than venting a co-product it has no room for.
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
# (flags, strategic reserve, buffer stock) with reverse data flow proxy -> server. Implemented
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
## level the facility aims to keep on hand to sustain its operations. This is the desired
## level; what the facility acts on is [method get_inventory_effective_ops_reserve].
@abstract func get_inventory_ops_reserve(resource_type: int) -> float


## Returns the per-resource ops reserves array. Return is proxy array reference;
## read only!
@abstract func get_inventory_ops_reserves() -> PackedFloat64Array


## Returns the operational reserve the facility acts on for [param resource_type]:
## [method get_inventory_ops_reserve] times its storage class's
## [method get_inventory_storage_level_scale], so that every stock level fits the storage
## the facility has. The reserve breach flags, disposal, settlement and a trader's quotes all
## read the effective levels.
@abstract func get_inventory_effective_ops_reserve(resource_type: int) -> float


## Returns the strategic reserve for [param resource_type]: stock the AI keeps beyond
## the operational reserve so operations run through a supply interruption. Operations
## draw it; trade never sells it (see AI_ARCHITECTURE.md, "Stock levels"). This is the
## desired level; what the facility acts on is
## [method get_inventory_effective_strategic_reserve].
@abstract func get_inventory_strategic_reserve(resource_type: int) -> float


## Returns the per-resource strategic reserves array. Return is proxy array
## reference; read only!
@abstract func get_inventory_strategic_reserves() -> PackedFloat64Array


## Returns the strategic reserve the facility acts on for [param resource_type] (see
## [method get_inventory_effective_ops_reserve]).
@abstract func get_inventory_effective_strategic_reserve(resource_type: int) -> float


## Returns the buffer stock for [param resource_type]: stock the AI holds for the
## market beyond both reserves, such as a market maker's warehouse. Operations draw it
## and trade sells it (see AI_ARCHITECTURE.md, "Stock levels"). This is the desired level;
## what the facility acts on is [method get_inventory_effective_buffer_stock].
@abstract func get_inventory_buffer_stock(resource_type: int) -> float


## Returns the per-resource buffer stocks array. Return is proxy array
## reference; read only!
@abstract func get_inventory_buffer_stocks() -> PackedFloat64Array


## Returns the buffer stock the facility acts on for [param resource_type] (see
## [method get_inventory_effective_ops_reserve]).
@abstract func get_inventory_effective_buffer_stock(resource_type: int) -> float


## Returns the expected net flow rate for [param resource_type] (positive =
## net production, negative = net consumption), projected from operating
## intent — consumption at process utilization × capacity, production at
## capacity factor × capacity (a time-horizon moving average of realized
## utilization, which smooths the production side). Not degraded by transient
## input shortages.
@abstract func get_inventory_expected_rate(resource_type: int) -> float


## Returns the per-resource expected rates array. Return is proxy array
## reference; read only!
@abstract func get_inventory_expected_rates() -> PackedFloat64Array


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
## interval because nothing here used it and its storage class had no room for it (>= 0.0),
## counted only where this resource was the output that held its operation back. What an
## operation made anyway, running for another output, is vented instead and shows in
## [method get_inventory_disposal_rate].
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


## Returns the stock storage class [param storage_type] would hold with every resource in
## it at its desired stock levels: the operations and strategic reserves and buffer stock.
## Where the class can't hold that, the facility acts on levels scaled down to fit (see
## [method get_inventory_storage_level_scale]), and what they give up is the facility's
## storage shortfall, the signal storage buildout acts on (see TRADE_MODEL.md, "Market
## makers").
@abstract func get_inventory_storage_demand(storage_type: int) -> float


## Returns what a unit of space in storage class [param storage_type] was worth
## at the last interval, in price per sim unit of stock: 0.0 when the class
## needed no disposal (or only worthless surplus was disposed of), the value of
## the last resource disposed of otherwise, and INF when the class stayed full
## with nothing left it could dispose of.
@abstract func get_inventory_storage_value(storage_type: int) -> float


## Returns the per-storage-class space values array. Return is proxy array
## reference; read only!
@abstract func get_inventory_storage_values() -> PackedFloat64Array


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


## Returns the share of storage class [param storage_type]'s desired stock levels the
## facility acts on (0.0 - 1.0): 1.0 where the class holds every member's operations and
## strategic reserves and buffer stock with room to spare, and the share of them it can hold
## otherwise. Every effective level in the class, such as
## [method get_inventory_effective_ops_reserve], is its desired level times this. Set at the
## start of each interval, and 1.0 before the first (see PRODUCTION_MODEL.md, "Stock levels
## fit storage").
@abstract func get_inventory_storage_level_scale(storage_type: int) -> float


## Returns the per-storage-class level scales array. Return is proxy array
## reference; read only!
@abstract func get_inventory_storage_level_scales() -> PackedFloat64Array


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


## Returns the smoothed share of life-support needs met for the population housed in
## [param carrying_capacity_group] (1.0 = fully met); a shortfall shrinks the group's
## effective carrying capacity. Safe default on an out-of-range index.
@abstract func get_population_life_support_satisfaction(carrying_capacity_group: int) -> float


## Returns the smoothed share of the rest of that population's consumption met (1.0 =
## fully met); recorded only. Safe default on an out-of-range index.
@abstract func get_population_consumption_satisfaction(carrying_capacity_group: int) -> float


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


## Sets the strategic reserve for [param type]. Proxy-authoritative:
## this change flows proxy -> server. No-op on an out-of-range index or invalid
## value.
@abstract func set_inventory_strategic_reserve(type: int, value: float) -> void


## Sets the buffer stock for [param type]. Proxy-authoritative: this change
## flows proxy -> server. No-op on an out-of-range index or invalid value.
@abstract func set_inventory_buffer_stock(type: int, value: float) -> void
