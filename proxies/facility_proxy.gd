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

## [FacilityProxy] represents a [PlayerProxy]'s development at a [LocusProxy].
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
	## Multiple critical inputs are simultaneously running below their
	## operational reserve targets.
	INPUT_CRISIS = 1 << 2,
	## Mask of all server-published signal bits.
	FROM_SERVER_MASK = (1 << 32) - 1,

	## Crisis posture: operations continue regardless of profitability.
	MODE_EMERGENCY = 1 << 32,
	## Shut down: no operations run; capacity is preserved for later restart (distinct from the
	## capacity a facility lays up, its mothballed units, which it keeps without maintenance).
	MODE_SHUTDOWN = 1 << 33,
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
	## Stock of this resource was below its critical level (see
	## [method get_inventory_critical_level]) as the facility's last interval began, before its
	## flows; the stock and levels published since are the interval's end.
	OPS_RESERVE_BREACHED = 1 << 1,
	## Stock of this resource was below its desired level (see
	## [method get_inventory_desired_level]) as the facility's last interval began, before its
	## flows.
	STRATEGIC_RESERVE_BREACHED = 1 << 2,
	## This resource can be traded: it has a trade class.
	TRADABLE = 1 << 5,
	## A can-have operation at this facility consumes this resource, its residents draw it, or the
	## builds and upkeep of the modules it can have draw it.
	CAN_HAVE_INPUT = 1 << 6,
	## A can-have operation at this facility produces or extracts this resource.
	CAN_HAVE_OUTPUT = 1 << 7,
	## The facility deals in this resource, and a market-making trader makes a market in it
	## where it is also [constant TRADABLE]. For now the server sets it exactly where
	## [constant CAN_HAVE_INPUT] or [constant CAN_HAVE_OUTPUT] is; a market maker is to deal in
	## resources it neither makes nor uses as well.
	IS_MARKET = 1 << 9,
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
	## The operation ran below its intended rate last interval because the room of an output
	## that can't be vented held it: the facility used no more of it, and its storage class
	## could hold no more (see PRODUCTION_MODEL.md, "The output clear").
	WAS_OUTPUT_LIMITED = 1 << 3,
	## Mask of all server-published signal bits.
	FROM_SERVER_MASK = (1 << 32) - 1,

	## When any of the op's outputs is below its critical level, suspend profit-gating so the
	## op can ramp up.
	SHORTAGE_PRIORITY = 1 << 33,
	## Hold the operation at a minimum baseline rate even when other
	## automations would idle it.
	STRATEGIC_FLOOR = 1 << 34,
	## Never make an output past its room for the sake of another: the operation runs only as
	## far as the room of every output that can't be vented allows, rather than making each
	## while it runs for the others.
	CLEARANCE_LIMITED = 1 << 35,
	## Mask of all AI-command bits.
	FROM_PROXY_MASK = ~((1 << 32) - 1),
}


## Field selectors for [method get_inventory_items] (bit flags; OR together).
## All select resource_type-indexed fields, so type is a resource_type. Returned
## values are in ascending bit order.
enum InventoryItems {
	STOCKS = 1,
	CARRIEDS = 1 << 1,
	CRITICAL_LEVELS = 1 << 2,
	DESIRED_LEVELS = 1 << 3,
	EXPECTED_RATES = 1 << 4,
	BUFFEREDS = 1 << 5,
	RATES = 1 << 6,
	FLAGS = 1 << 7,
}


## The lines of a facility's budget in [member budget_lines], each a year (FINANCIAL_MODEL.md,
## "Budgets"): what it has to spend, its income and what its funding lines leave it; what it
## commits, its upkeep, interest and income tax and its replacement, what wears out at its build
## cost; and what its R&D and its expansion may spend of what those leave. Its payouts are what
## remains, except at an agency's facility, which pays nothing out. Apart from them, what its
## expansion borrows past its line from the credit market.
enum BudgetLines {
	BUDGET_INCOME,
	BUDGET_FUNDING,
	BUDGET_UPKEEP,
	BUDGET_INTEREST,
	BUDGET_TAX,
	BUDGET_REPLACEMENT,
	BUDGET_RESEARCH,
	BUDGET_EXPANSION,
	BUDGET_BORROWING,
}


## A buildout's kind, what its units are for (see [method get_operations_buildouts] and
## PRODUCTION_MODEL.md, "Buildouts").
enum BuildoutKinds {
	## A module's standing buildout, which rebuilds what wears of its plant still needed.
	BUILDOUT_REPLACEMENT,
	## Units of a module past what replacement rebuilds, for an operation's room.
	BUILDOUT_EXPANSION,
}


## Who ordered a buildout (see [method get_operations_buildouts]).
enum BuildoutOrderers {
	ORDERER_PLANNER, ## The server's planner, for a module on auto.
	ORDERER_AI, ## The facility's AI.
	ORDERER_PLAYER, ## Its player, from the Build tab.
}


## A buildout's flags (see [method get_operations_buildouts]).
enum BuildoutFlags {
	BUILDOUT_PAUSED = 1, ## Its owner paused it.
}


## What [method hold_operations_buildout] does to a buildout.
enum BuildoutHolds {
	HOLD_RESUME, ## Resumes a paused buildout.
	HOLD_PAUSE, ## Pauses it: it asks nothing until resumed, and still counts as plant to come.
	HOLD_CANCEL, ## Cancels it: what it built stays in service.
}


## The number of prices a facility's desired flow is given at (see
## [method get_inventory_desired_flow_curve]).
const N_CURVE_POINTS := 3


var facility_id := -1  ## Index into [member ProxyBus.facility_proxies].
## Its name among its player's facilities, as in its owners' budget lines: its locus's name, unless
## the game start names it otherwise.
var short_name := ""
var facility_class := -1  ## [code]facility_classes.tsv[/code] row index.
## Public-sector share of this facility, often 0.0 or 1.0, sometimes mixed.
var public_sector: float
## True if this is a small focused activity (affects stats and tax treatment).
var unitary: bool
## True if this facility makes its locus's market, a port's: it warehouses stock and keeps a
## bid and an ask standing, ready to trade in amounts that matter (see TRADE_MODEL.md, "Market
## makers").
var market_maker: bool
## True if all resource streams flow from/to inventory (no atmosphere/surface
## market).
var closed_cycle_ops: bool
## Per-source corrections multiplying this site's locus-level renewable capacity
## factor (territorial quality vs the locus baseline; 1.0 = locus value).
var solar_correction := 1.0
var wind_correction := 1.0
var geothermal_correction := 1.0
## Time horizon used by AI and automations (inventory reserves, resupply, etc.).
var time_horizon: float
## Region of its locus the facility stands in, or [code]&""[/code] for none; it stands on the
## locus's strata in that region and those that span the locus.
var region: StringName
## Bidirectional bit flags (see [enum FacilityFlags]). FROM_SERVER bits are
## server-authoritative; FROM_PROXY bits are proxy-authoritative. Use
## [method set_flags] to modify the proxy half.
var flags := 0
## Cash the facility keeps: it pays its owners what it holds past it, its debt counted, at the end
## of each interval (FINANCIAL_MODEL.md, "Facilities as subsidiaries"). Its owners' payout policy;
## 0.0 by default. Use [method set_cash_reserve].
var cash_reserve := 0.0
## Its owners' required return: the least interest rate, a year, at which they lend the credit
## market what the facility's build budget leaves unspent; below it they collect what it lent and
## are paid it (FINANCIAL_MODEL.md, "The credit market"). Its owners' payout policy; 0.0 by default.
## Use [method set_required_return].
var required_return := 0.0
## Its available credit: what the facility may spend past what it holds, as of its last interval:
## its cash less what it owes, and what more it could owe before its interest at its own rate
## passed what its income carries, and what is left of each funding line that funds it, as far as
## the treasury's own such room goes (FINANCIAL_MODEL.md, "Saving and borrowing"). Its trader's
## commitments are bound by it.
var credit := 0.0
## Its budget a year as of its last interval, by [enum BudgetLines]; empty before its first.
## Server-authoritative. Use [method get_budget_line].
var budget_lines := PackedFloat64Array()
## The game time of the last interval its ledger is booked through, -INF before its first: what it
## booked this quarter, over the time from the quarter's start to this, is the pace it is on.
var interval_time := -INF

# *****************************************************************************
# persisted

var player: PlayerProxy  ## Owning [PlayerProxy].
var polity: PlayerProxy  ## The polity of [member player].
var locus: LocusProxy  ## Hosting [LocusProxy].
var trader: TraderProxy  ## Paired [TraderProxy]; set when TraderProxy registers.
var trader_id := -1  ## [member TraderProxy.trader_id] of [member trader].
var joins: Array[JoinProxy] = []  ## [JoinProxy] aggregates this facility belongs to.
var market: MarketProxy  ## Set after init. Lives on markets thread!
## The operations' target spending shares held off auto, by operation type, each at its share (see
## [method hold_operations_target_spending_share]). Resizable container — not threadsafe!
var held_target_spending_shares: Dictionary[int, float] = {}
## The resources' research shares held off auto, by resource type, each at its share (see
## [method hold_inventory_research_share]). Resizable container — not threadsafe!
var held_research_shares: Dictionary[int, float] = {}

# *****************************************************************************


# ************************* VIRTUAL & IMPLEMENTATION **************************

func _clear_for_destruction() -> void:
	locus = null
	player = null
	polity = null
	trader = null
	joins.clear()
	market = null


## Detaches this facility from its locus and player, then breaks its outgoing
## refs via [method super.remove]. Called by the server side at runtime when a
## facility is removed mid-game.
func remove() -> void:
	locus.remove_facility(self)
	player.remove_facility(self)
	super.remove()


# ********************************** STATIC ***********************************

## Returns what a curve of [constant N_CURVE_POINTS] [param values] at [param prices], rising, each
## starting at [param start], gives at [param price]: linear in the log of price between the points,
## and the end point's value past either end.
static func get_curve_value(values: PackedFloat64Array, prices: PackedFloat64Array, price: float,
		start := 0) -> float:
	var last := start + N_CURVE_POINTS - 1
	if !(price > prices[start]):
		return values[start]
	if price >= prices[last]:
		return values[last]
	var k := start + 1
	while prices[k] < price:
		k += 1
	var t := log(price / prices[k - 1]) / log(prices[k] / prices[k - 1])
	return lerpf(values[k - 1], values[k], t)


## Returns the price at which a curve of [constant N_CURVE_POINTS] [param values] at
## [param prices], each starting at [param start], gives [param value]: the inverse of
## [method get_curve_value] for a curve that falls as the price rises, the end price past either
## end.
static func get_curve_price(values: PackedFloat64Array, prices: PackedFloat64Array, value: float,
		start := 0) -> float:
	var last := start + N_CURVE_POINTS - 1
	if !(value < values[start]):
		return prices[start]
	if !(value > values[last]):
		return prices[last]
	var k := start + 1
	while values[k] > value:
		k += 1
	var t := (values[k - 1] - value) / (values[k - 1] - values[k])
	return prices[k - 1] * pow(prices[k] / prices[k - 1], t)


# ***************************** THREAD-SAFE READ ******************************

func has_development() -> bool:
	return true


## Returns the environmental capacity factor for renewable-power operation
## [param operation_type] at this facility (the locus factor scaled by this site's
## per-source correction); NAN if not a locus-modeled renewable or unavailable here.
@abstract func calculate_capacity_factor(operation_type: int) -> float


func has_markets() -> bool:
	return true


func has_inventory() -> bool:
	return true


func get_locus_name() -> StringName:
	return locus.name


func get_body_name() -> StringName:
	return locus.body_name


func get_body_flags() -> int:
	return locus.body_flags


func get_player_name() -> StringName:
	return player.name


func get_player_class() -> int:
	return player.player_class


func get_polity_name() -> StringName:
	return polity.name


# Facility flags and budget

## Returns the full bidirectional flag value (see [enum FacilityFlags]).
func get_flags() -> int:
	return flags


## Returns its budget's line [param line], a [enum BudgetLines], a year (see
## [member budget_lines]), or NAN before its first interval.
func get_budget_line(line: int) -> float:
	if line < 0 or line >= budget_lines.size():
		return NAN
	return budget_lines[line]


# Operations (facility-only). Facility-only reads, plus proxy-authoritative knobs
# (flags and the target_* setters) with reverse data flow proxy -> server. Implemented
# on the server-side facility proxy against its operations component.

## Returns the capacity factor (environmental or historical limit) of operation
## [param operation_type].
@abstract func get_operations_capacity_factor(operation_type: int) -> float


## Returns the per-operation capacity factors array. Return is proxy array
## reference; read only!
@abstract func get_operations_capacity_factors() -> PackedFloat64Array


## Returns the availability of operation [param operation_type]: the share of its capacity it can
## run at, seeded or, for a renewable its locus models, its capacity factor.
@abstract func get_operations_availability(operation_type: int) -> float


## Returns the per-operation availabilities array. Return is proxy array
## reference; read only!
@abstract func get_operations_availabilities() -> PackedFloat64Array


## Returns the AI/player-set target margin floor of operation [param operation_type].
@abstract func get_operations_target_margin(operation_type: int) -> float


## Returns the AI/player-set target spending share of operation [param operation_type]
## (NAN = not in effect).
@abstract func get_operations_target_spending_share(operation_type: int) -> float


## Returns true if operation [param operation_type]'s target spending share is held off auto (see
## [method hold_operations_target_spending_share]). proxy thread only!
func is_operations_target_spending_share_held(operation_type: int) -> bool:
	return held_target_spending_shares.has(operation_type)


## Returns the build/decommission lever for [param module_type]; see
## [method set_operations_module_buildout] for what the value means.
@abstract func get_operations_module_buildout(module_type: int) -> float


## Returns whether the server's planner plans [param module_type]'s buildouts (see
## [method set_operations_module_auto]); false for an index out of range.
@abstract func is_operations_module_auto(module_type: int) -> bool


## Returns the facility's buildouts, its capital projects (PRODUCTION_MODEL.md, "Buildouts"), as
## of its last interval and in the order they were opened: each a dictionary of its "id", unique
## in the game; "module" (a [code]modules[/code] row) and "operation", the operation its units go
## to, -1 for a replacement, whose units go back to the operations of its module that lost them;
## "kind" ([enum BuildoutKinds]) and "orderer" ([enum BuildoutOrderers]); "units" planned, 0.0 for
## a replacement, which stands, "built" and "left"; "rate", its schedule in units a second,
## "start", the game time it was opened, and "pace", the share of its schedule it built over about
## a quarter; "binding", the resource of which least could be had for its schedule, -1 for none;
## "spent" and "borrowed", in dollars; "return", what its units would return a year at capital's
## prices, and "unit_cost", what a unit costs at them; and "paused". A new array each call; empty
## but at a facility. Proxy thread only!
@abstract func get_operations_buildouts() -> Array[Dictionary]


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


## Returns what this facility's transit buffer will still hold of [param resource_type], of what
## is to come into its stock, when the current quarter ends (always >= 0.0): the interval of what is
## contracted to come in that it holds back to take up uneven deliveries, and what its pacing leaves
## of the rest; once its facility has no step left in the quarter, all it holds and all still to
## arrive before the quarter ends. Its trader counts what its buffer holds against the current
## quarter less this, and this against the next (PRODUCTION_MODEL.md, "The local price: two flows
## and a stock").
@abstract func get_inventory_carried(resource_type: int) -> float


## Returns the per-resource carried array (see [method get_inventory_carried]). Return is proxy
## array reference; read only!
@abstract func get_inventory_carrieds() -> PackedFloat64Array


## Returns what this facility's transit buffer holds of [param resource_type] (always >= 0.0): what
## is delivered to it, less what it gave the stock or delivered, and with what it took from the
## stock for what is owed. It uses no storage. The trade flow its local price reads comes from it,
## and its trader contracts net of it (PRODUCTION_MODEL.md, "The local price: two flows and a
## stock").
@abstract func get_inventory_buffered(resource_type: int) -> float


## Returns the per-resource buffered array (see [method get_inventory_buffered]). Return is proxy
## array reference; read only!
@abstract func get_inventory_buffereds() -> PackedFloat64Array


## Returns the rate at which this facility's transit buffer gave [param resource_type] to its stock
## over its last interval: what the step took of its offer at the market's ask, and what filled the
## stock to its desired level; the trade flow in.
@abstract func get_inventory_trade_in_rate(resource_type: int) -> float


## Returns the rate at which this facility's stock gave [param resource_type] to its transit
## buffer over its last interval: what the step drew for what is owed at the market's bid, and the
## surplus taken off for what is contracted to go out; the trade flow out.
@abstract func get_inventory_trade_out_rate(resource_type: int) -> float


## Returns the critical level of [param resource_type]: the stock the facility's operations
## and its residents' existence needs draw until resupply could land, their use over its time
## horizon. Its producers rebuild it as fast as their capacity allows. Fitted to what storage
## holds, with every critical level in a class held before any desired level (see
## PRODUCTION_MODEL.md, "A facility's stock of a resource").
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


## Returns the share of what its budget's committed lines leave that the facility spends on
## [param resource_type] as research and development (see [method set_inventory_research_share]).
@abstract func get_inventory_research_share(resource_type: int) -> float


## Returns true if [param resource_type]'s research share is held off auto (see
## [method hold_inventory_research_share]). proxy thread only!
func is_inventory_research_share_held(resource_type: int) -> bool:
	return held_research_shares.has(resource_type)


## Returns the net flow rate of [param resource_type] averaged over the time horizon (positive
## = the facility made more than it used, negative = it used more than it made).
@abstract func get_inventory_expected_rate(resource_type: int) -> float


## Returns the per-resource expected rates array. Return is proxy array
## reference; read only!
@abstract func get_inventory_expected_rates() -> PackedFloat64Array


## Returns the critical rate of [param resource_type], smoothed over the time horizon: the trade
## the facility must have (positive), what its operations and its residents' existence use past
## all its producers could make, or the most it can spare (negative), read where its trader could
## trade now as the desired rate is (see [method get_inventory_desired_rate]). A trader secures at
## least this where it is positive, and never commits to give more than it allows. 0.0 for a
## resource that can't be traded. See PRODUCTION_MODEL.md, "A facility's flows with the market".
@abstract func get_inventory_critical_rate(resource_type: int) -> float


## Returns the per-resource critical rates array. Return is proxy array reference; read only!
@abstract func get_inventory_critical_rates() -> PackedFloat64Array


## Returns the desired rate of [param resource_type], smoothed over the time horizon: the trade
## the facility wants, positive to take and negative to give, where its whole use and the step
## toward its desired level would meet what its producers make, read where its trader could trade
## now: at the ask its trader expects where the facility would take there, at the bid where it
## would give there, and nothing between; where its trader expects no quote, at the market's last
## sale, and where the market has none, at the facility's own price. NAN where it has no price at
## all; 0.0 for a resource that can't be traded. See PRODUCTION_MODEL.md, "A facility's flows with
## the market".
@abstract func get_inventory_desired_rate(resource_type: int) -> float


## Returns the per-resource desired rates array. Return is proxy array reference; read only!
@abstract func get_inventory_desired_rates() -> PackedFloat64Array


## Returns the flow in the critical rate of [param resource_type], read as the rate is: the rate
## without its step to the critical level (see [method get_inventory_critical_step]), so what the
## facility must have over a span longer than its horizon is this flow over the span plus that
## step, once. Smoothed over the time horizon as the rate is.
@abstract func get_inventory_critical_flow(resource_type: int) -> float


## Returns the step in the critical rate of [param resource_type], read as the rate is: what the
## facility's stock must gain to reach its critical level, a quantity, negative for what it holds
## past it. Smoothed over the time horizon as the rate is.
@abstract func get_inventory_critical_step(resource_type: int) -> float


## Returns the step in the desired rate of [param resource_type], read as the rate is: what the
## facility's holder would add to its stock, a quantity, negative for what it would give. Smoothed
## over the time horizon as the rate is. NAN where the facility has no price at all.
@abstract func get_inventory_desired_step(resource_type: int) -> float


## Returns the flow in the desired rate of [param resource_type], the rate without its step toward
## the desired levels (see [method get_inventory_desired_step]), as a curve over price: at each of
## the prices [method get_inventory_curve_prices] gives, smoothed over the time horizon. What the
## facility wants over a span longer than its horizon is this flow over the span plus that step,
## once; a trader reads it at the price its order would trade at (see [method get_curve_value]).
## NANs where the facility has no price at all; empty for an index out of range.
@abstract func get_inventory_desired_flow_curve(resource_type: int) -> PackedFloat64Array


## Returns the prices, rising and in [method MarketProxy.get_price] units, that the desired flow's
## curve of [param resource_type] is given at (see [method get_inventory_desired_flow_curve]): the
## facility's own price between the lowest and the highest of half and twice it, the market's last
## sale and the quotes its trader expects. NANs where the facility has no price at all; empty for an
## index out of range.
@abstract func get_inventory_curve_prices(resource_type: int) -> PackedFloat64Array


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


## Returns the rate at which surplus [param resource_type] was disposed of over the last interval,
## where keeping it would have cost more than it is worth (>= 0.0). Disposal is not counted in
## [method get_inventory_rate].
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
## [method get_inventory_disposal_rate] if keeping it would cost more than it is worth.
@abstract func get_inventory_curtailed_rate(resource_type: int) -> float


## Returns the per-resource curtailed rates array. Return is proxy array reference;
## read only!
@abstract func get_inventory_curtailed_rates() -> PackedFloat64Array


## Returns the most this facility's most tolerant consuming operation could pay per unit
## of [param resource_type], in [method MarketProxy.get_price] units, and still clear its
## margin floor, counting operations already priced below their floor. INF when nothing here
## with revenue consumes it.
@abstract func get_inventory_consumption_breakeven(resource_type: int) -> float


## Returns the per-resource consumption break-evens array. Return is proxy array
## reference; read only!
@abstract func get_inventory_consumption_breakevens() -> PackedFloat64Array


## Returns what a unit of [param resource_type] must fetch, in
## [method MarketProxy.get_price] units, for the costliest unit of production still making
## it here to clear its margin floor, as of the last interval: its merit-order price. Where
## nothing here made it, the price at which the cheapest unit would start. Only operations whose
## margin floors set their runs count (see
## PRODUCTION_MODEL.md, "What the facility publishes"). 0.0 when that unit clears its floor
## giving it away; INF when no such operation here produces it at known prices.
@abstract func get_inventory_marginal_cost(resource_type: int) -> float


## Returns the per-resource marginal costs array. Return is proxy array
## reference; read only!
@abstract func get_inventory_marginal_costs() -> PackedFloat64Array


## Returns what a unit of [param resource_type] must fetch, in [method MarketProxy.get_price]
## units, for a new unit of the cheapest route the facility would build for it to pay, at the
## prices its capital weighs, as of the last interval: where a shortage, or a need left unmet,
## should grow its makers (see PRODUCTION_MODEL.md, "What the facility publishes"). It holds no
## margin floor. NAN where no route here would be built for it.
@abstract func get_inventory_long_run_marginal_cost(resource_type: int) -> float


## Returns the per-resource long-run marginal costs array. Return is proxy array reference; read
## only!
@abstract func get_inventory_long_run_marginal_costs() -> PackedFloat64Array


## Returns the amount of storage class [param storage_type] currently in use
## (local stocks plus remote stores).
@abstract func get_inventory_storage_used(storage_type: int) -> float


## Returns the price of storage class [param storage_type]'s space at this facility, what keeping a
## unit of its capacity for a second costs: no more than its stores' running cost while what the
## class holds is well within what they make, more as it nears that and past it, where the class's
## overflow improvises space (storage_classes.schema.md). NAN for a class with no space of its own.
## A level is held as far as its space pays for it, and what can't be vented pays its holding cost
## in its makers' margins (see PRODUCTION_MODEL.md, "A storage class: its storage rent").
@abstract func get_inventory_storage_rent(storage_type: int) -> float


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


## Sets [member cash_reserve] (>= 0.0), in money. Proxy-authoritative: this change flows
## proxy -> server. No-op on a negative value or NAN.
@abstract func set_cash_reserve(value: float) -> void


## Sets [member required_return] (>= 0.0), a year. Proxy-authoritative: this change flows
## proxy -> server. No-op on a negative value or NAN.
@abstract func set_required_return(value: float) -> void


## Sets the [code]FROM_PROXY_MASK[/code] bits of operations flags for
## [param operation_type] to [param value]. Proxy-authoritative: this
## change flows proxy -> server. No-op on an out-of-range index.
@abstract func set_operations_flags(operation_type: int, value: int) -> void


## Sets the target margin floor for operation [param type] (run while gross margin
## >= value). Proxy-authoritative: this change flows proxy -> server. No-op on an
## out-of-range index or NAN.
@abstract func set_operations_target_margin(type: int, value: float) -> void


## Sets the target spending share for operation [param type] (fraction of what the facility's
## budget leaves past its committed lines, what wears out among them, or NAN = not in effect; see
## [member budget_lines]). Proxy-authoritative; flows proxy -> server. No-op where the share is
## held (see [method hold_operations_target_spending_share]).
@abstract func set_operations_target_spending_share(type: int, value: float) -> void


## Holds the target spending share of operation [param type] off auto at [param value], as
## [method set_operations_target_spending_share] takes it, until
## [method release_operations_target_spending_share]. No-op on an out-of-range index.
@abstract func hold_operations_target_spending_share(type: int, value: float) -> void


## Returns the target spending share of operation [param type] to auto, where
## [method set_operations_target_spending_share] sets it again. It keeps its share until then.
func release_operations_target_spending_share(type: int) -> void:
	held_target_spending_shares.erase(type)


## Tears [param module_type] down where [param value] is below 0.0, reclaiming materials, its
## laid-up units first, with a flat slice of the construction yards, its size over the sum of every
## module's (1.0 for a module with none); NAN (the default) or 0.0 or more tears nothing down.
## Its buildouts build a module ([method set_operations_module_auto]). Planned to go once
## teardowns are built, the owner's buildouts that take units down (PRODUCTION_MODEL.md,
## "Buildouts").
@abstract func set_operations_module_buildout(module_type: int, value: float) -> void


## Orders a buildout of [param units] units of [param module_type], to go to its operation
## [param operation_type], over [param build_time] seconds, or where that is nothing or less over
## the module's build time ([code]build_time[/code] in [code]modules.tsv[/code]), past what the
## server's planner opens (PRODUCTION_MODEL.md, "Buildouts", the planner and the AI). The server opens
## it at the facility's next interval and funds and prices it as any buildout: it runs only as far as
## its funding carries it and the step's prices ration what it draws. [param orderer] is who ordered
## it, [constant ORDERER_AI] or [constant ORDERER_PLAYER]. A bad order is dropped: an index out of
## range, an operation not of the module, or units not above nothing. Proxy-authoritative: this
## order flows proxy -> server.
@abstract func order_operations_buildout(module_type: int, operation_type: int, units: float,
		build_time := 0.0, orderer := BuildoutOrderers.ORDERER_AI) -> void


## Pauses, resumes or cancels buildout [param id] (see [method get_operations_buildouts]) at the
## facility's next interval, as [param hold] says ([enum BuildoutHolds]). Only its owner pauses or
## cancels a buildout, as only an owner scraps. An id the facility has none of is dropped.
## Proxy-authoritative: this flows proxy -> server.
@abstract func hold_operations_buildout(id: int, hold: int) -> void


## Sets whether the server's planner plans [param module_type]'s buildouts, true by default. On
## auto, it reviews the facility's buildouts once a quarter: it sets each module's replacement to
## what wears of the plant still needed, and opens an expansion for each operation whose room past
## what is in flight is more than what its units wear in a quarter, where its return beats the cost
## of capital (PRODUCTION_MODEL.md, "Buildouts", the planner and the AI). Off auto, it opens
## nothing for the module. Proxy-authoritative: this change flows proxy -> server. No-op on an
## out-of-range index.
@abstract func set_operations_module_auto(module_type: int, is_auto: bool) -> void


## Fills the entire per-module build/decommission override array with
## [param value] — the array-wide form of [method set_operations_module_buildout].
## Pass [code]NAN[/code] to return every module to auto (server-decided)
## allocation, or e.g. 0.0 to stop all building.
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


## Sets the share of what its budget leaves past its committed lines (see [member budget_lines])
## that the facility spends on [param type] each interval as research and development, an operating
## expense, before its builds take their share of the same: 0.0 spends none. It buys only what the
## facility can trade or make. What it buys raises nothing yet: a patch until the
## technology model, in which research raises what operations make (ROADMAP.md, "Technology").
## Proxy-authoritative: this change flows proxy -> server. No-op on an out-of-range index or a value
## outside [0.0, 1.0], or where the share is held (see [method hold_inventory_research_share]).
@abstract func set_inventory_research_share(type: int, value: float) -> void


## Holds the research share of [param type] off auto at [param value], as
## [method set_inventory_research_share] takes it, until [method release_inventory_research_share].
## No-op on an out-of-range index or a value outside [0.0, 1.0].
@abstract func hold_inventory_research_share(type: int, value: float) -> void


## Returns the research share of [param type] to auto, where [method set_inventory_research_share]
## sets it again. It keeps its share until then.
func release_inventory_research_share(type: int) -> void:
	held_research_shares.erase(type)
