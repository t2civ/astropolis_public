# trader_base_ai.gd
# This file is part of Astropolis
# https://t2civ.com
# *****************************************************************************
# Copyright 2019-2026 Charlie Whitfield; ALL RIGHTS RESERVED
# Astropolis is a registered trademark of Charlie Whitfield in the US
# *****************************************************************************
class_name TraderBaseAI
extends BaseAI

## Default AI for traders the local player owns.
##
## To implement a custom trader AI, extend this class and add
## [code]const OVERRIDE_AI := true[/code].[br][br]
##
## Traders are paired 1-to-1 with facilities. This trader AI trades in the posture
## and resource strategies its facility's AI authors, against the facility's
## inventory (it trusts that these already incorporate player strategies).[br][br]
##
## A facility-paired trader orders delivery/pickup [b]only at its own
## facility's body[/b]: the executors and maintain helpers resolve the delivery
## market to [member TraderProxy.market_id] internally. The front
## (current-quarter) executors trade the facility's [i]stock[/i] imbalance
## against its stock target; the forward executor trades projected [i]flow[/i]
## one-sided on later-quarter instruments (see [method _process_forward_flow]).
## The future transport trader will be this same class running different
## strategies, discriminated by [member TraderProxy.facility_id] == -1 — all
## facility-paired behavior is gated on that pairing.[br][br]
##
## Order memory ([member _asks] / [member _bids]) is [b]optimistic on every
## order[/b]: SET semantics are absolute (a new order replaces the resting one,
## quantity 0 cancels), so writing memory at call time is always safe. The market
## sends no per-order echoes; instead every position notification carries the
## trader's current resting ask/bid, which reconciles memory (see
## [method _on_positions_changed]). Old-quarter orders are purged by the market
## without echoes, so memory self-cleans by the same rule each interval (see
## [method _drop_expired_memory]).[br][br]
##
## TODO: Need API so trader can refresh memory if needed. E.g., for Trader,
## all the trade memory is known by server market. Could be packaged and sent
## back if AI loses memory.


## Trader-posture strategies.
enum TraderStrategies {
	## Init / no-op. Trader should quickly move on to something (usuaally
	## FACILITY_SUPPORT) and start trading.
	INIT,
	## Trade primarily to service the facility's operational needs — replenish
	## inputs, clear outputs. Analog: a procurement / sales desk inside a
	## manufacturing firm.
	FACILITY_SUPPORT,
	## Trade to maximize the trader's own P&L; accept some operational risk
	## to the facility. Analog: a proprietary commodity-trading desk.
	PROFIT_FOCUS,
	## Minimize trading risk; carry ample buffer stock; avoid speculative
	## positions. Analog: utility-style fuel procurement.
	CONSERVATIVE,
	## Pursue spreads and arbitrage aggressively; tolerate inventory
	## volatility. Analog: merchant trader.
	OPPORTUNISTIC,
	## Subordinate trading to the owning player's policy — embargoes, dumping,
	## stockpiling — even at facility cost. Analog: state-owned trading
	## enterprise.
	POLICY_AGENT,
	## Make the facility's body's market: keep a bid and an ask standing on every
	## resource the facility trades, backed by its buffer stock (see TRADE_MODEL.md,
	## "Market makers"). The posture of a market-making facility's trader. Analog: a
	## wholesale merchant; a spaceport's commodity desk.
	MARKET_MAKING,
	N_BASE_TRADER_STRATEGIES,
}

## Per-resource trading strategies.
enum ResourceStrategies {
	## No special stance; replenish operational reserves and clear surplus at
	## prevailing market prices.
	NEUTRAL,
	## Hold minimal inventory; replenish in small, frequent lots. Analog:
	## lean-manufacturing inputs.
	JUST_IN_TIME,
	## Build inventory well beyond operational need; willing to pay
	## above-market to accumulate. Analog: strategic petroleum reserve,
	## semiconductor stockpile.
	STRATEGIC_RESERVE,
	## Wind down holdings aggressively; sell at unfavorable prices if needed.
	## Analog: divestiture from an asset class.
	LIQUIDATE,
	## Withhold supply from market regardless of price. Analog: OPEC
	## production cut, sovereign export ban.
	HOARD,
	## Sell into the market at depressed prices to clear inventory or harm
	## competing suppliers. Analog: predatory dumping, fire sale.
	DUMP,
	## Build inventory in expectation of price rise; accept carrying cost.
	## Analog: contango trade, commodity bull bet.
	SPECULATIVE_LONG,
	## Defer purchases and run down inventory in expectation of price decline.
	## Analog: shorting commodities.
	SPECULATIVE_SHORT,
	## Do not trade this resource externally; rely on the facility's own
	## production / consumption. Analog: import substitution, closed-cycle
	## process.
	AUTARKIC,
	## Facility produces surplus of this resource; push to market aggressively.
	## Analog: export-oriented industry.
	EXPORT_FOCUS,
	## Facility critically needs this resource; pay a premium to secure
	## continuity. Analog: critical-input procurement under shortage.
	IMPORT_PRIORITY,
	## No standing position; act only on price dislocations. Analog: arbitrage
	## / value buying.
	OPPORTUNISTIC,
	## Run holdings down gradually as part of an orderly exit; sell into
	## rallies, do not add to position. Distinct from [code]LIQUIDATE[/code],
	## which accepts unfavorable prices to clear immediately. Analog: a
	## divesting fund quietly reducing a position over months.
	WIND_DOWN,
	N_BASE_RESOURCE_STRATEGIES,
}


## Forward quote offset from the reference price: forward asks are placed this fraction
## below it and forward bids this fraction above, so a producer's ask and a consumer's bid
## cross.
const SPREAD := 0.02
## Minimum order size in trade units; smaller surpluses/deficits are not quoted.
const MIN_LOT := 1
## Market-maker bid ceiling above its stock target, in trade units; the maker buys up
## toward target + this band and sells down to its reserves.
const MM_BAND_LOTS := 2
## A market maker's default quote offsets from its own price: its ask sits this fraction
## above and its bid this fraction below (def keys [code]maker_ask_spread[/code] and
## [code]maker_bid_spread[/code] override per resource strategy).
const MAKER_SPREAD := 0.02
## Fraction by which a market maker leans both quotes at a full gap, up when short and down
## when over (def key [code]maker_lean[/code] overrides per resource strategy).
const MAKER_LEAN := 0.1
## Fractional change per week in a market maker's own price at a full gap -- stock empty or
## double its target, or flows [constant MAKER_FLOW_SATURATION] out of balance -- while the
## price sits at its long-run price (def key [code]maker_drift[/code] overrides per posture).
const MAKER_DRIFT := 0.02
## Turnover time of a resource's storage class, in trader intervals, from which a trader steers
## by stock alone: a market maker's price by its stock gap, and every trader's quote quantities
## by its stock against its levels. Below it the facility's flows weigh in, and steer alone
## where storage carries no flow at all (see [method _get_stock_weight]; def key
## [code]stock_turnover_intervals[/code] overrides, per posture for a maker and per resource
## strategy otherwise).
const STOCK_TURNOVER_INTERVALS := 4.0
## How far ahead, in trader intervals, the quantities a trader quotes from flows look: about as
## long as an order takes to fill, ship and be used (def key [code]flow_lookahead_intervals[/code]
## overrides, like [constant STOCK_TURNOVER_INTERVALS]).
const FLOW_LOOKAHEAD_INTERVALS := 2.0
## Share of a resource's gross flow at a market maker's facility that fills its flow gap: what
## went unmet, less what was held back or vented for want of room (def key
## [code]maker_flow_saturation[/code] overrides per posture).
const MAKER_FLOW_SATURATION := 0.05
## About how far above its long-run price a full lasting gap settles a market maker's price,
## as a fraction of the long-run price; an overstocked maker's settles at the reciprocal
## below it (def key [code]maker_premium_limit[/code] overrides per posture).
const MAKER_PREMIUM_LIMIT := 1.0
## Years over which a market maker's long-run price follows its price (def key
## [code]maker_long_run_years[/code] overrides per posture).
const MAKER_LONG_RUN_YEARS := 7.5
## Re-quote a market maker's standing orders when either side's price drifts beyond this
## fraction (def key [code]maker_price_tol[/code] overrides per posture).
const MAKER_PRICE_TOLERANCE := 0.01
## Ceiling on a market maker's own price, in multiples of the resource's start price: a
## numerical guard for a resource with nothing to bound its price by (see
## [constant MAKER_FORCED_DEMAND_MARKUP]). A price that reaches it marks a broken run.
const MAKER_PRICE_RAIL := 1000.0
## Most a market maker charges over a resource's production break-even when no consuming
## operation at its facility can put a price on it: only forced demand draws it (households,
## upkeep, buildout), or nothing does.
const MAKER_FORCED_DEMAND_MARKUP := 0.5
## Re-quote a standing order when its price drifts beyond this fraction of its price.
const PRICE_TOLERANCE := 0.05
## Re-quote a standing order when its desired quantity drifts beyond this fraction.
const QTY_TOLERANCE := 0.25
## Default fraction of projected per-quarter flow hedged on forward instruments
## (def key [code]forward_hedge[/code] overrides). Sell-side defs stay below
## 1.0: an over-sold forward forces settlement stock-stripping or default,
## while over-bought forwards self-correct by selling surplus at the front.
const FORWARD_HEDGE := 0.75

const NULL_PF64ARRAY: PackedFloat64Array = []


## Trader-posture strategy definitions; index = [enum TraderStrategies] value. The
## [code]two_sided[/code] switch makes markets: the market-making executor quotes every
## resource the facility trades (see [method is_market_resource]), and the facility AI
## warehouses buffer stock for those resources. There the posture's
## [code]maker_drift[/code], [code]maker_premium_limit[/code],
## [code]maker_long_run_years[/code], [code]stock_turnover_intervals[/code],
## [code]maker_flow_saturation[/code] and [code]maker_price_tol[/code] tune the maker's price and
## its [code]min_lot[/code], [code]band_lots[/code], [code]flow_lookahead_intervals[/code] and
## [code]qty_tol[/code] its quotes,
## while the resource's own def in [member resource_strategy_defs] sets their spread and
## lean; the posture's forward keys stand in for the resource's.
static var trader_strategy_defs: Array[Dictionary] = [
	{}, # INIT
	{}, # FACILITY_SUPPORT
	{}, # PROFIT_FOCUS
	{}, # CONSERVATIVE
	{}, # OPPORTUNISTIC
	{}, # POLICY_AGENT
	{&"two_sided": true, &"forward_quarters": 2}, # MARKET_MAKING — front maker + forward flow hedge
]

## Per-resource strategy definitions; index = [enum ResourceStrategies] value.
## Boolean switches select what the facility-support executor does:
## [code]sell_above_reserve[/code], [code]buy_to_reserve[/code]. Tuning keys
## ([code]spread[/code], [code]min_lot[/code], [code]band_lots[/code],
## [code]price_tol[/code], [code]qty_tol[/code]) may override the class-constant
## defaults. An empty entry trades nothing at a facility-support trader. At a market
## maker, which quotes every resource it trades, [code]maker_ask_spread[/code],
## [code]maker_bid_spread[/code] and [code]maker_lean[/code] shape the quotes for
## resources under the strategy (see [constant MAKER_SPREAD] and
## [constant MAKER_LEAN]).[br][br]
##
## [code]forward_quarters[/code] (int) opts a strategy into forward flow-hedging on
## later-quarter instruments and floors the depth — effective depth grows with the
## facility's planning horizon (see [method _process_forward_flow]). Forward is
## always one-sided, driven by the sign of the facility's projected net flow;
## [code]forward_hedge[/code] scales the hedged fraction and the sell/buy switches
## cap the allowed side (a two-sided posture hedges whichever way its flow runs).
## NEUTRAL stays deliberately front-only (no [code]forward_quarters[/code]): with
## both switches set, early forward deliveries could push stock above target and be
## re-sold at a loss (bought at ref×(1+spread), dumped at ref×(1−spread)) — bounded
## churn a single-sided forward hedge can't suffer.
static var resource_strategy_defs: Array[Dictionary] = [
	{&"sell_above_reserve": true, &"buy_to_reserve": true}, # NEUTRAL — maintain at reserve
	{}, # JUST_IN_TIME
	{&"buy_to_reserve": true, &"maker_ask_spread": 0.25}, # STRATEGIC_RESERVE
	{}, # LIQUIDATE
	{}, # HOARD
	{}, # DUMP
	{}, # SPECULATIVE_LONG
	{}, # SPECULATIVE_SHORT
	{}, # AUTARKIC
	{&"sell_above_reserve": true, &"forward_quarters": 2, &"forward_hedge": 0.75}, # EXPORT_FOCUS
	{&"buy_to_reserve": true, &"forward_quarters": 2, &"forward_hedge": 1.0,
			&"maker_ask_spread": 0.05}, # IMPORT_PRIORITY
	{}, # OPPORTUNISTIC
	{&"sell_above_reserve": true, &"maker_ask_spread": 0.0, &"maker_bid_spread": 0.2}, # WIND_DOWN
]


## Member names persisted by save/load (interval timing inherited from BaseAI).
const PERSIST_PROPERTIES: Array[StringName] = [
	&"_last_interval",
	&"_next_interval",
	&"trader_strategy",
	&"resource_strategies",
	&"_asks",
	&"_bids",
	&"_maker_unit_prices",
	&"_maker_long_run_unit_prices",
]


static var _table_n_rows := IVTableData.table_n_rows
static var _trade_unit_multipliers := ThreadsafeGlobal.resource_trade_unit_multipliers
## Per-resource fiat price anchor (USD per trade unit) from resources.tsv start_price,
## used when no live market price exists yet. Built once.
static var _start_unit_prices: PackedInt32Array
## Per-resource 0/1; trade_class == CYBER (orders route to the cyber market). Built once.
static var _is_cyber_resource: PackedByteArray
## Per-resource storage class, -1 for none. Built once.
static var _resource_storage_classes: PackedInt32Array


var proxy: TraderProxy


# *****************************************************************************
# persisted

## Trader-posture strategy. See [enum TraderStrategies].
var trader_strategy := 0
## Per-resource strategies. See [enum ResourceStrategies].
var resource_strategies: PackedInt32Array


## Memory of open asks, keyed at this trader's order-key width (see [member _key_width]):
## the 2-element instrument [resource_type, ordinal_quarter] for a facility trader (one
## market per resource makes the body redundant), or 3-element [resource_type,
## ordinal_quarter, body_id] for a transport trader (which trades a resource at many
## bodies). Values are [unit_quantity, unit_price] in trade units; unique per key. Mirrors
## the market's resting ask, refreshed via position notifications.
var _asks: Dictionary[PackedInt32Array, PackedInt64Array] = {}

## Memory of open bids, keyed like [member _asks] with values [unit_quantity, unit_price]
## in trade units.
var _bids: Dictionary[PackedInt32Array, PackedInt64Array] = {}

## Per-resource market-maker price in trade units, fractional so a slow drift
## accumulates; 0 until the maker first prices the resource (see
## [method _process_market_making]).
var _maker_unit_prices: PackedFloat64Array

## Per-resource market-maker long-run price in trade units, the slow average of
## [member _maker_unit_prices] its price moves against; 0 until the maker first prices the
## resource.
var _maker_long_run_unit_prices: PackedFloat64Array

# *****************************************************************************

var _facility_ai: FacilityBaseAI
var _facility: FacilityProxy  # paired facility proxy

# Facility-trader auxiliary: this trader's positions keyed by the 2-element instrument
# [resource_type, ordinal_quarter], body projected out (unique per instrument because a
# facility trades each resource in exactly one market — home or cyber). Maintained in
# _on_positions_changed, seeded in ai_init. Stays empty for a transport trader, which is
# inherently multi-body and works off proxy.positions directly.
var _positions_by_instrument: Dictionary[PackedInt32Array, PackedFloat64Array] = {}
# This trader's cyber market id, resolved once in ai_init; the routing target for cyber
# resources (see _delivery_market_id). -1 for a transport trader.
var _cyber_market_id := -1
# Width of this trader's order keys (_asks / _bids / _on_positions_changed): 2 for a
# facility trader ([resource, quarter]), 3 for a transport trader ([resource, quarter,
# body_id]). Set in ai_init.
var _key_width := 2

# Per-resource open-position sums in trade units (quarters up to and including the
# current one), rebuilt each interval by _tally_net_positions().
var _net_long_units: PackedInt64Array
var _net_short_units: PackedInt64Array
# Front-quarter instrument scratch [resource_type, ordinal_qtr]; safe for lookups
# and outgoing calls (downstream duplicates), never stored as a key.
var _instrument_scratch: PackedInt32Array
# Collect-then-act key scratch for _drop_expired_memory() and _clear_resource_orders().
var _expired_keys: Array[PackedInt32Array] = []
# Per-resource quarter-offset of the farthest forward order in memory (0 = none);
# rebuilt by _drop_expired_memory() each interval. Lets the forward pass keep
# maintaining — and so want-0-clearing — orders beyond the def's current horizon
# (strategy change, def shrink, lost reference price).
var _forward_mem_horizons: PackedInt32Array
# Forward instrument scratch [resource_type, ordinal_quarter]; safe for lookups, the aux
# position lookup, and outgoing calls (downstream duplicates), never stored as a key.
var _forward_instrument_scratch: PackedInt32Array
# Per-resource front executor at the last interval: 0 not yet run, 1 facility support, 2
# market making. A switch clears the resource's orders first (see _clear_resource_orders)
# and its maker price.
var _executor_branches: PackedByteArray


# ********************************** STATIC ***********************************

## True if inventory [param flags] mark a resource a market-making posture makes a
## market in: tradable, and produced or consumed by the facility.
static func is_market_resource(flags: int) -> bool:
	const TRADABLE := FacilityProxy.InventoryFlags.TRADABLE
	const CAN_HAVE_INPUT := FacilityProxy.InventoryFlags.CAN_HAVE_INPUT
	const CAN_HAVE_OUTPUT := FacilityProxy.InventoryFlags.CAN_HAVE_OUTPUT
	return (flags & TRADABLE) != 0 and (flags & (CAN_HAVE_INPUT | CAN_HAVE_OUTPUT)) != 0


# ************************* VIRTUAL & IMPLEMENTATION **************************

func _init() -> void:
	super()
	var n_resources: int = _table_n_rows[&"resources"]
	resource_strategies.resize(n_resources)
	_net_long_units.resize(n_resources)
	_net_short_units.resize(n_resources)
	_instrument_scratch.resize(2)
	_forward_mem_horizons.resize(n_resources)
	_forward_instrument_scratch.resize(2)
	_executor_branches.resize(n_resources)
	_maker_unit_prices.resize(n_resources)
	_maker_long_run_unit_prices.resize(n_resources)
	if _start_unit_prices.is_empty():
		const TRADE_CLASS_CYBER := Enums.TradeClasses.TRADE_CLASS_CYBER
		var resources_table: Dictionary[StringName, Array] = IVTableData.db_tables[&"resources"]
		_start_unit_prices = PackedInt32Array(resources_table[&"start_price"])
		_resource_storage_classes = PackedInt32Array(resources_table[&"storage_class"])
		var trade_classes := PackedInt32Array(resources_table[&"trade_class"])
		_is_cyber_resource.resize(trade_classes.size())
		for resource_type in trade_classes.size():
			_is_cyber_resource[resource_type] = 1 if trade_classes[resource_type] == TRADE_CLASS_CYBER else 0


func _clear_for_destruction() -> void:
	proxy = null
	_facility_ai = null
	_facility = null


func bind_proxy(proxy_: Proxy) -> void:
	proxy = proxy_ as TraderProxy


func ai_init() -> void:
	proxy.positions_changed.connect(_on_positions_changed)
	if proxy.facility_id == -1:
		_key_width = 3 # transport: order keys carry the delivery body (see _key_width)
		return # transport trader: not facility-paired; transport strategies TBD
	_facility = proxy.facility
	_cyber_market_id = proxy.market.cyber_market_id
	# Seed the instrument-keyed view from any positions predating this connection (e.g.
	# on load); _on_positions_changed keeps it current thereafter.
	for position_key in proxy.positions:
		_positions_by_instrument[position_key.slice(0, 2)] = proxy.positions[position_key]
	_facility_ai = Proxy.proxy_bus.facility_ais[proxy.facility_id]
	assert(_facility_ai, "TraderBaseAI expects facility's AI to be FacilityBaseAI")
	_facility_ai.trader_strategy_changed.connect(_on_facility_trader_strategy_changed)
	_facility_ai.facility_resource_strategy_changed.connect(_on_facility_resource_strategy_changed)
	# The facility may have authored its strategies before we connected (init order
	# across entity types is not guaranteed), so re-sync them now.
	trader_strategy = _facility_ai.trader_strategy
	for resource_type in resource_strategies.size():
		var facility_strategy := _facility_ai.facility_resource_strategies[resource_type]
		resource_strategies[resource_type] = _trader_strategy_for_facility(facility_strategy)


## Acts on live market and inventory state using the posture and the sticky
## per-resource strategies (authored by the facility, translated and stored on
## change). Trades only the resources the facility flags
## [constant FacilityProxy.InventoryFlags.TRADABLE]: a two-sided posture makes markets in
## those the facility produces or consumes (see [method is_market_resource]), priced as its
## def and theirs direct, and every other one gets the facility-support executor per its
## strategy's def. Both SET orders on the front (current-quarter) instrument at the
## trader's local market, and def-gated strategies also maintain forward-flow orders on
## later quarters (see [method _process_forward_flow]).
func process_ai_interval(delta: float) -> void:
	const TRADABLE := FacilityProxy.InventoryFlags.TRADABLE
	var market := proxy.market
	if !market or !_facility:
		return # no market yet, or transport trader (transport strategies TBD)
	_drop_expired_memory()
	_tally_net_positions()
	_instrument_scratch[1] = proxy.ordinal_qtr
	var posture_def := trader_strategy_defs[trader_strategy]
	var makes_markets: bool = posture_def.get(&"two_sided", false)
	for resource_type in resource_strategies.size():
		if _stop:
			return # cooperative bail; remaining resources re-quote next interval (idempotent)
		# A resource with no trade class can't be traded (resources.schema.md).
		# Tradability is fixed per resource, so none loses it with orders resting.
		var flags := _facility.get_inventory_flags(resource_type)
		if !(flags & TRADABLE):
			continue
		_instrument_scratch[0] = resource_type
		var def := resource_strategy_defs[resource_strategies[resource_type]]
		var is_made := makes_markets and is_market_resource(flags)
		var branch := 2 if is_made else 1
		if _executor_branches[resource_type] != branch:
			if _executor_branches[resource_type]:
				_clear_resource_orders(resource_type)
				_maker_unit_prices[resource_type] = 0.0 # stale by the time it is made again
				_maker_long_run_unit_prices[resource_type] = 0.0
			_executor_branches[resource_type] = branch
		if is_made:
			_process_market_making(resource_type, market, _instrument_scratch, posture_def, def,
					delta)
			def = posture_def
		else:
			_process_facility_support(resource_type, market, _instrument_scratch, def)
		_process_forward_flow(resource_type, market, def)


## Trades one resource to service facility operations: clears stock above its stock
## target (the two effective reserves and any effective buffer stock; see
## [method FacilityProxy.get_inventory_effective_ops_reserve]) and/or replenishes up toward
## it, per the def switches. With both enabled it self-balances around the target — stock
## can't be both over and under, so at most one side quotes. Where the resource's storage
## can't carry a few intervals of its flows, what the flows call for weighs in (see
## [method _get_stock_weight]). It takes the book, selling
## into the best bid and buying at the best ask, and quotes the reference price where
## the other side is empty (see TRADE_MODEL.md, "Price discovery"). A still-valid
## resting order is left untouched; we re-quote only on material divergence. Open
## positions count against the want quantities: a filled order is committed in/outflow
## until the short side physically settles it (up to ~a trader interval), so quoting
## without netting would re-order already-filled demand every interval. A bid never
## exceeds what the operations consuming the resource can pay (see
## [method _cap_bid_price]).
func _process_facility_support(resource_type: int, market: MarketProxy,
		instrument: PackedInt32Array, def: Dictionary) -> void:
	var sell: bool = def.get(&"sell_above_reserve", false)
	var buy: bool = def.get(&"buy_to_reserve", false)
	var reference_price := market.get_unit_price(resource_type)
	if reference_price <= 0 or (not sell and not buy):
		# Not trading this resource now: drop any resting orders (placeholder
		# price 1 — the proxy rejects price <= 0 even for a cancel).
		_maintain_ask(instrument, 0, 1, MIN_LOT, 0.0, 0.0)
		_maintain_bid(instrument, 0, 1, MIN_LOT, 0.0, 0.0)
		return
	var min_lot: int = def.get(&"min_lot", MIN_LOT)
	var price_tol: float = def.get(&"price_tol", PRICE_TOLERANCE)
	var qty_tol: float = def.get(&"qty_tol", QTY_TOLERANCE)
	var turnover_intervals: float = def.get(&"stock_turnover_intervals", STOCK_TURNOVER_INTERVALS)
	var lookahead: float = def.get(&"flow_lookahead_intervals", FLOW_LOOKAHEAD_INTERVALS) * INTERVAL
	var multiplier := _trade_unit_multipliers[resource_type]
	var stock_weight := _get_stock_weight(resource_type, turnover_intervals)
	var target := (_facility.get_inventory_effective_ops_reserve(resource_type)
			+ _facility.get_inventory_effective_strategic_reserve(resource_type)
			+ _facility.get_inventory_effective_buffer_stock(resource_type))
	var stock := _facility.get_inventory_stock(resource_type)
	var outbound := _facility.get_inventory_outbound(resource_type)
	var ask_units := 0
	if sell: # open shorts are committed stock, some of it set aside already
		ask_units = (int((stock + outbound - target) / multiplier)
				- _net_short_units[resource_type])
		if stock_weight < 1.0:
			ask_units = roundi(lerpf(_get_flow_ask_units(resource_type, lookahead), ask_units,
					stock_weight))
	# Quoting off the reference instead, a taker would set the price its next quote reads,
	# a ratchet wherever its quote is the only one standing.
	var best_bid := market.get_bid_unit_price(resource_type)
	var ask_price := best_bid if best_bid > 0 else reference_price
	_maintain_ask(instrument, ask_units, ask_price, min_lot, price_tol, qty_tol)
	var bid_units := 0
	if buy: # open longs are committed inbound goods, like in-transit stock
		bid_units = (int((target - stock - outbound
				- _facility.get_inventory_in_transit(resource_type)) / multiplier)
				- _net_long_units[resource_type])
		if stock_weight < 1.0:
			bid_units = roundi(lerpf(_get_flow_bid_units(resource_type, lookahead), bid_units,
					stock_weight))
	var best_ask := market.get_ask_unit_price(resource_type)
	var bid_price := _cap_bid_price(resource_type, best_ask if best_ask > 0 else reference_price)
	if bid_price < 1: # the facility's operations can pay nothing for it
		bid_units = 0
		bid_price = 1 # placeholder: the proxy rejects price <= 0 even for a cancel
	_maintain_bid(instrument, bid_units, bid_price, min_lot, price_tol, qty_tol)


## Makes the market in one resource the facility trades (see TRADE_MODEL.md, "Market
## makers"). The maker keeps its own price for the resource, raising it while the resource is
## short and lowering it while it is over, at a rate tied to the gap and toward a premium or
## discount on its own long-run price, headed only between what the facility's cheapest
## producing operation needs and what its most tolerant consuming operation can pay, and
## quotes both sides around that price leaned by the same gap. The gap is its stock against
## target where the resource's storage class carries a few intervals of flow (see
## [constant STOCK_TURNOVER_INTERVALS]). Where it carries less, what the facility went without
## and held back weighs in (see [method _get_flow_gap]), the price heads no lower than
## what the costliest unit still making the resource there needs (see
## [method FacilityProxy.get_inventory_marginal_production_breakeven]), and what the flows call
## for weighs in on the quantities as it does at facility support.
## [param posture_def] sets how fast the price moves and [param resource_def], the resource
## strategy's def, sets the spread and lean. It steers by the facility's effective stock
## levels, which fit what its storage can hold (see
## [method FacilityProxy.get_inventory_storage_level_scale]): it sells only stock above both
## effective reserves and buys up to its effective target plus a band, netting open positions
## like facility support, and never bids for a resource full storage is disposing of. A
## maker's first price for a resource is the market's, or the resource's start_price when the
## market has none.
func _process_market_making(resource_type: int, market: MarketProxy,
		instrument: PackedInt32Array, posture_def: Dictionary, resource_def: Dictionary,
		delta: float) -> void:
	const DUMPING := FacilityProxy.InventoryFlags.DUMPING
	var min_lot: int = posture_def.get(&"min_lot", MIN_LOT)
	var band_lots: int = posture_def.get(&"band_lots", MM_BAND_LOTS)
	var drift: float = posture_def.get(&"maker_drift", MAKER_DRIFT)
	var turnover_intervals: float = posture_def.get(&"stock_turnover_intervals",
			STOCK_TURNOVER_INTERVALS)
	var lookahead: float = (posture_def.get(&"flow_lookahead_intervals",
			FLOW_LOOKAHEAD_INTERVALS) * INTERVAL)
	var flow_saturation: float = posture_def.get(&"maker_flow_saturation", MAKER_FLOW_SATURATION)
	var premium_limit: float = posture_def.get(&"maker_premium_limit", MAKER_PREMIUM_LIMIT)
	var long_run_years: float = posture_def.get(&"maker_long_run_years", MAKER_LONG_RUN_YEARS)
	var price_tol: float = posture_def.get(&"maker_price_tol", MAKER_PRICE_TOLERANCE)
	var qty_tol: float = posture_def.get(&"qty_tol", QTY_TOLERANCE)
	var ask_spread: float = resource_def.get(&"maker_ask_spread", MAKER_SPREAD)
	var bid_spread: float = resource_def.get(&"maker_bid_spread", MAKER_SPREAD)
	var lean: float = resource_def.get(&"maker_lean", MAKER_LEAN)
	var multiplier := _trade_unit_multipliers[resource_type]
	var price := _maker_unit_prices[resource_type]
	var long_run_price := _maker_long_run_unit_prices[resource_type]
	if price <= 0.0:
		price = market.get_unit_price(resource_type)
		if price <= 0.0:
			price = _start_unit_prices[resource_type]
		if price <= 0.0: # nothing to price it from
			_maintain_ask(instrument, 0, 1, min_lot, 0.0, 0.0)
			_maintain_bid(instrument, 0, 1, min_lot, 0.0, 0.0)
			return
	if long_run_price <= 0.0: # first priced here, or a save from before long-run prices
		long_run_price = price
	var reserves := (_facility.get_inventory_effective_ops_reserve(resource_type)
			+ _facility.get_inventory_effective_strategic_reserve(resource_type))
	var target := reserves + _facility.get_inventory_effective_buffer_stock(resource_type)
	var stock := _facility.get_inventory_stock(resource_type)
	var in_transit := _facility.get_inventory_in_transit(resource_type)
	var outbound := _facility.get_inventory_outbound(resource_type)
	# A sale commits stock the moment it fills, though the maker delivers it later; pricing
	# before delivery would keep selling cheap into its own shortage. A purchase counts
	# only once it ships: its seller may be short too, and delivery can wait a quarter.
	var committed_stock := (stock + in_transit + outbound
			- multiplier * _net_short_units[resource_type])
	var gap := clampf((target - committed_stock) / maxf(target, multiplier), -1.0, 1.0)
	# A price no operation here can pay prices out every consumer, and one below what every
	# producer needs idles all production: past either, a gap nothing answers never closes.
	var floor_price := _facility.get_inventory_production_breakeven(resource_type)
	var ceiling_price := _facility.get_inventory_consumption_breakeven(resource_type)
	# Stock that can't carry a few intervals of its flows says little about the next one. The
	# flows say what is short instead, and with no stock to cover a shortfall, a price below
	# what the costliest unit still running needs would idle output the facility still uses.
	var stock_weight := _get_stock_weight(resource_type, turnover_intervals)
	if stock_weight < 1.0:
		gap = (stock_weight * gap
				+ (1.0 - stock_weight) * _get_flow_gap(resource_type, flow_saturation))
		var marginal_price := _facility.get_inventory_marginal_production_breakeven(resource_type)
		if !is_inf(marginal_price): # INF: no producer here whose run its margin floor sets
			floor_price = lerpf(marginal_price, floor_price, stock_weight)
	if is_inf(ceiling_price):
		ceiling_price = floor_price * (1.0 + MAKER_FORCED_DEMAND_MARKUP) # INF: no producer either
	if is_inf(floor_price):
		floor_price = 0.0
	var rail := MAKER_PRICE_RAIL * maxi(_start_unit_prices[resource_type], 1)
	var upper := clampf(maxf(floor_price, ceiling_price) * multiplier, 1.0, rail)
	var lower := clampf(minf(floor_price, ceiling_price) * multiplier, 1.0, upper)
	# Unanchored, a gap nothing answers compounds the price for as long as it lasts, so the
	# gap heads the price only a premium away from its long-run price, which follows slowly.
	# The band bounds where the price is headed rather than the price itself: break-evens
	# jump as operations cross their floors, and a price snapped to one jumps with them.
	var weeks := delta / (7.0 * IVUnits.DAY)
	var drift_rate := log(1.0 + drift)
	var follow_rate := 7.0 / (long_run_years * 365.25)
	var decay_rate := drift_rate / log(1.0 + premium_limit) + follow_rate
	var headed_premium := clampf(drift_rate * gap / decay_rate, log(lower / long_run_price),
			log(upper / long_run_price))
	var premium := headed_premium + ((log(price / long_run_price) - headed_premium)
			* exp(-decay_rate * weeks))
	long_run_price *= exp(premium * follow_rate * weeks)
	price = clampf(long_run_price * exp(premium), 1.0, rail)
	_maker_unit_prices[resource_type] = price
	_maker_long_run_unit_prices[resource_type] = long_run_price
	var center := price * (1.0 + lean * gap)
	var bid_price := maxi(1, floori(center * (1.0 - bid_spread)))
	var ask_price := maxi(bid_price + 1, ceili(center * (1.0 + ask_spread)))
	var ask_units := int((stock + outbound - reserves) / multiplier) - _net_short_units[resource_type]
	var bid_units := 0
	if !(_facility.get_inventory_flags(resource_type) & DUMPING): # storage throws it away
		bid_units = (int((target + band_lots * multiplier - stock - outbound - in_transit)
				/ multiplier) - _net_long_units[resource_type])
		if stock_weight < 1.0:
			bid_units = roundi(lerpf(_get_flow_bid_units(resource_type, lookahead), bid_units,
					stock_weight))
	if stock_weight < 1.0:
		ask_units = roundi(lerpf(_get_flow_ask_units(resource_type, lookahead), ask_units,
				stock_weight))
	# The market drops a trader's crossed ask and bid as a wash, without an echo, so the
	# two quotes re-quote together: one side moved against the other's stale price could
	# cross it.
	if (_is_quote_stale(_asks, instrument, ask_units, ask_price, min_lot, price_tol, qty_tol)
			or _is_quote_stale(_bids, instrument, bid_units, bid_price, min_lot, price_tol,
			qty_tol)):
		_maintain_ask(instrument, ask_units, ask_price, min_lot, 0.0, 0.0)
		_maintain_bid(instrument, bid_units, bid_price, min_lot, 0.0, 0.0)


## Maintains one-sided forward orders on later-quarter instruments at the local
## market, hedging the facility's projected per-quarter flow (expected rate ×
## quarter duration) on the side its net flow runs — a net producer sells, a net
## consumer buys — capped by the def's sell/buy switches and netted against each
## instrument's open position. The front executors trade [i]stock[/i] imbalance;
## this trades [i]flow[/i] — no double-commitment, because filled forwards roll
## into the front position sums at quarter rollover and net out of front wants
## there. The def's [code]forward_quarters[/code] gates participation and floors
## the depth; the facility's [member FacilityProxy.time_horizon] deepens it, so a
## remote facility planning years ahead quotes proportionally farther out. Runs
## for every tradable resource (even front-only defs) and maintains out to the farthest
## remembered forward order past the def horizon, so a strategy change, def
## shrink, or lost reference price want-0-clears stale orders. Bids are capped like
## the front's (see [method _cap_bid_price]).
func _process_forward_flow(resource_type: int, market: MarketProxy, def: Dictionary) -> void:
	var def_forward_quarters: int = def.get(&"forward_quarters", 0)
	var forward_quarters := 0
	if def_forward_quarters > 0: # def gates forward participation
		var horizon_quarters := ceili(_facility.time_horizon / (IVUnits.YEAR / 4.0))
		forward_quarters = mini(maxi(def_forward_quarters, horizon_quarters),
				TraderProxy.MAX_FORWARD_QUARTERS - 1)
	var n_quarters := maxi(forward_quarters, _forward_mem_horizons[resource_type])
	if n_quarters == 0:
		return # nothing wanted, nothing resting (the common case)
	var reference_price := market.get_unit_price(resource_type)
	var expected_rate := _facility.get_inventory_expected_rate(resource_type)
	# Forward is a one-sided flow hedge driven by the facility's projected net flow:
	# a net producer (rate > 0) sells its surplus forward, a net consumer (rate < 0)
	# buys its deficit. The def's sell/buy switches cap the allowed side (EXPORT_FOCUS
	# sells only, IMPORT_PRIORITY buys only); a two-sided maker hedges whichever way
	# its flow runs. Volume is bounded to resources the facility actually has flow in
	# — never the whole tradable set — which is what keeps order traffic sane.
	var allow_ask: bool = def.get(&"sell_above_reserve", false) or def.get(&"two_sided", false)
	var allow_bid: bool = def.get(&"buy_to_reserve", false) or def.get(&"two_sided", false)
	var want_ask := allow_ask and expected_rate > 0.0 and reference_price > 0
	var want_bid := allow_bid and expected_rate < 0.0 and reference_price > 0
	if !want_ask and !want_bid and _forward_mem_horizons[resource_type] == 0:
		return # no flow to hedge and nothing resting forward
	var spread: float = def.get(&"spread", SPREAD)
	var min_lot: int = def.get(&"min_lot", MIN_LOT)
	var price_tol: float = def.get(&"price_tol", PRICE_TOLERANCE)
	var qty_tol: float = def.get(&"qty_tol", QTY_TOLERANCE)
	var forward_hedge: float = def.get(&"forward_hedge", FORWARD_HEDGE)
	var multiplier := _trade_unit_multipliers[resource_type]
	# Crossing-friendly like facility support: a producer's ask sits below the
	# reference, a consumer's bid above, so a net producer and net consumer of the
	# same resource cross. Placeholder 1 on cancel-only paths — the proxy rejects
	# price <= 0 even for a cancel.
	var ask_price := maxi(1, floori(reference_price * (1.0 - spread)))
	var bid_price := _cap_bid_price(resource_type,
			maxi(1, ceili(reference_price * (1.0 + spread))))
	if bid_price < 1: # the facility's operations can pay nothing for it
		want_bid = false
		bid_price = 1
	var current_qtr := proxy.ordinal_qtr
	for k in range(1, n_quarters + 1):
		var ordinal_quarter := current_qtr + k
		_forward_instrument_scratch[0] = resource_type
		_forward_instrument_scratch[1] = ordinal_quarter
		# An open position on this instrument is already-committed flow, netted
		# out of the want like the front executors net the front position sums.
		var position: PackedFloat64Array = _positions_by_instrument.get(
				_forward_instrument_scratch, NULL_PF64ARRAY)
		var net_units := int(position[0]) if position else 0
		var ask_units := 0
		var bid_units := 0
		if k <= forward_quarters and (want_ask or want_bid):
			var flow_units := int(forward_hedge * absf(expected_rate)
					* Utils.get_ordinal_quarter_duration(ordinal_quarter) / multiplier)
			if want_ask:
				ask_units = flow_units - maxi(0, -net_units)
			else:
				bid_units = flow_units - maxi(0, net_units)
		# A single interval's ask and bid flush to the market together and apply
		# before any match (see _ProxyServer/_MarketsServer run loops), so the call
		# order here is immaterial: at most one side is wanted, the other 0-clears
		# any stale resting order via SET.
		_maintain_ask(_forward_instrument_scratch, ask_units, ask_price,
				min_lot, price_tol, qty_tol)
		_maintain_bid(_forward_instrument_scratch, bid_units, bid_price,
				min_lot, price_tol, qty_tol)


# ******************************* AI / PROXY API ******************************
# Call on proxy thread.

## Adds, replaces, or cancels a sell (ask) order. See [method
## TraderProxy.set_ask] for instrument composition and params, including
## [param market_id] (the market at the delivery body). This method
## updates AI ask memory on the outgoing call. Rejects if specified
## ordinal_quarter < proxy.ordinal_qtr (proxy would reject if it went through
## here).
func _set_ask(instrument: PackedInt32Array, unit_quantity: int,
		unit_price: int, delivery_market_id: int) -> void:
	if instrument[1] < proxy.ordinal_qtr:
		return
	var mem_key := instrument.duplicate() # facility: 2-element [resource, quarter]
	if _key_width == 3: # transport: append the delivery body (see _key_width)
		mem_key.append(_market_body_id(delivery_market_id))
	if unit_quantity:
		var ask: PackedInt64Array
		if _asks.has(mem_key):
			ask = _asks[mem_key]
		else:
			ask.resize(2)
			_asks[mem_key] = ask
		ask[0] = unit_quantity
		ask[1] = unit_price
	else:
		_asks.erase(mem_key)
	proxy.set_ask(instrument, unit_quantity, unit_price, delivery_market_id)


## Adds, replaces, or cancels a buy (bid) order. See [method
## TraderProxy.set_bid] for instrument composition and params, including
## [param market_id] (the market at the delivery body). This method
## updates AI bid memory on the outgoing call. Rejects if specified
## ordinal_quarter < proxy.ordinal_qtr (proxy would reject if it went through
## here).
func _set_bid(instrument: PackedInt32Array, unit_quantity: int,
		unit_price: int, delivery_market_id: int) -> void:
	if instrument[1] < proxy.ordinal_qtr:
		return
	var mem_key := instrument.duplicate() # facility: 2-element [resource, quarter]
	if _key_width == 3: # transport: append the delivery body (see _key_width)
		mem_key.append(_market_body_id(delivery_market_id))
	if unit_quantity:
		var bid: PackedInt64Array
		if _bids.has(mem_key):
			bid = _bids[mem_key]
		else:
			bid.resize(2)
			_bids[mem_key] = bid
		bid[0] = unit_quantity
		bid[1] = unit_price
	else:
		_bids.erase(mem_key)
	proxy.set_bid(instrument, unit_quantity, unit_price, delivery_market_id)


# ****************************** INTERNAL LOGIC *******************************

## Brings our resting ask for [param instrument] in line with the desired quantity
## and price under SET semantics: a want below [param min_lot] clears any resting
## ask (the 0-set is sent only when memory holds one); otherwise posts if absent,
## or re-quotes on material divergence (see [method _is_quote_stale]). The delivery
## market is resolved per resource (see [method _delivery_market_id]).
func _maintain_ask(instrument: PackedInt32Array,
		want_quantity: int, want_price: int, min_lot: int, price_tol: float, qty_tol: float
		) -> void:
	if !_is_quote_stale(_asks, instrument, want_quantity, want_price, min_lot, price_tol,
			qty_tol):
		return
	_set_ask(instrument, want_quantity if want_quantity >= min_lot else 0, want_price,
			_delivery_market_id(instrument[0]))


## Bid counterpart of [method _maintain_ask].
func _maintain_bid(instrument: PackedInt32Array,
		want_quantity: int, want_price: int, min_lot: int, price_tol: float, qty_tol: float
		) -> void:
	if !_is_quote_stale(_bids, instrument, want_quantity, want_price, min_lot, price_tol,
			qty_tol):
		return
	_set_bid(instrument, want_quantity if want_quantity >= min_lot else 0, want_price,
			_delivery_market_id(instrument[0]))


## True when our resting order in [param orders] ([member _asks] or [member _bids]) for
## [param instrument] is out of line with the desired quantity and price: one rests
## against a want below [param min_lot], none rests for a real want, or the resting
## order has drifted past the tolerances (see [method _needs_requote]).
func _is_quote_stale(orders: Dictionary[PackedInt32Array, PackedInt64Array],
		instrument: PackedInt32Array, want_quantity: int, want_price: int, min_lot: int,
		price_tol: float, qty_tol: float) -> bool:
	if want_quantity < min_lot:
		return orders.has(instrument)
	if !orders.has(instrument):
		return true
	var have := orders[instrument]
	return _needs_requote(have[0], have[1], want_quantity, want_price, price_tol, qty_tol)


## Returns [param bid_price] (trade units) capped at the facility's reservation price
## for [param resource_type] (see [method FacilityProxy.get_inventory_reservation_price]).
## Returns 0 when its operations can pay nothing for the resource.
func _cap_bid_price(resource_type: int, bid_price: int) -> int:
	var cap := (_facility.get_inventory_reservation_price(resource_type)
			* _trade_unit_multipliers[resource_type])
	if cap >= bid_price: # INF too: nothing here with revenue consumes it
		return bid_price
	return floori(cap)


## Returns how far [param resource_type]'s stock steers this trader, from 1.0 where its storage
## class carries [param turnover_intervals] trader intervals of the facility's flows or more, to
## 0.0 where it carries none; the facility's flows steer the rest. Stock that can't carry a few
## intervals of its flows swings from empty to full between them and says little about the
## next one. 1.0 for a resource with no storage class, whose stock is unbounded.
func _get_stock_weight(resource_type: int, turnover_intervals: float) -> float:
	var storage_class := _resource_storage_classes[resource_type]
	if storage_class == -1:
		return 1.0
	return clampf(_facility.get_inventory_storage_turnover_time(storage_class)
			/ (turnover_intervals * INTERVAL), 0.0, 1.0)


## Returns what [param resource_type]'s flows call for this trader to offer over
## [param lookahead], in trade units: what the facility expects to make beyond its own use and
## what it held back for want of room, less what it has sold already.
func _get_flow_ask_units(resource_type: int, lookahead: float) -> int:
	var rate := (_facility.get_inventory_expected_rate(resource_type)
			+ _facility.get_inventory_curtailed_rate(resource_type))
	return (int(maxf(rate, 0.0) * lookahead / _trade_unit_multipliers[resource_type])
			- _net_short_units[resource_type])


## Returns what [param resource_type]'s flows call for this trader to buy over
## [param lookahead], in trade units: what the facility expects to use beyond what it makes,
## less what has arrived and what it has bought already.
func _get_flow_bid_units(resource_type: int, lookahead: float) -> int:
	var need := (maxf(-_facility.get_inventory_expected_rate(resource_type), 0.0) * lookahead
			- _facility.get_inventory_in_transit(resource_type))
	return int(need / _trade_unit_multipliers[resource_type]) - _net_long_units[resource_type]


## Returns a market maker's flow gap for [param resource_type], -1.0 to 1.0, positive when
## short: what the facility went without over the last interval, less what it held back or
## vented for want of room, as a share of the resource's gross flow there, full at
## [param saturation] (see [constant MAKER_FLOW_SATURATION]).
func _get_flow_gap(resource_type: int, saturation: float) -> float:
	var unmet := _facility.get_inventory_unmet_rate(resource_type)
	var curtailed := _facility.get_inventory_curtailed_rate(resource_type)
	var surplus := curtailed + _facility.get_inventory_disposal_rate(resource_type)
	var gross_flow := maxf(_facility.get_inventory_production_rate(resource_type) + curtailed,
			_facility.get_inventory_consumption_rate(resource_type) + unmet)
	gross_flow = maxf(gross_flow, surplus) # a delivered glut of what nothing here makes or uses
	if gross_flow <= 0.0:
		return 0.0
	return clampf((unmet - surplus) / (saturation * gross_flow), -1.0, 1.0)


# Resolves which market an order for [param resource_type] routes to: the cyber market
# for a cyber resource, else this facility trader's home body market.
func _delivery_market_id(resource_type: int) -> int:
	return _cyber_market_id if _is_cyber_resource[resource_type] else proxy.market_id


# Resolves the delivery body of [param market_id], for a transport trader's 3-element
# order key (see _key_width). Not called on the facility path (_key_width == 2).
func _market_body_id(market_id: int) -> int:
	var market_proxy: MarketProxy = Proxy.proxy_bus.market_proxies[market_id]
	assert(market_proxy and market_proxy.body, "delivery market/body not resolved")
	return market_proxy.body.body_id


# The market purges old-quarter resting orders at rollover without echoes; drop
# matching memory by the same rule so stale entries can't satisfy _maintain_*
# lookups (which would suppress fresh front-quarter quotes). Piggybacks the same
# iteration to rebuild _forward_mem_horizons (the farthest forward order per resource).
func _drop_expired_memory() -> void:
	var current_qtr := proxy.ordinal_qtr
	_forward_mem_horizons.fill(0)
	for key in _asks:
		if key[1] < current_qtr:
			_expired_keys.append(key)
		elif key[1] > current_qtr and _forward_mem_horizons[key[0]] < key[1] - current_qtr:
			_forward_mem_horizons[key[0]] = key[1] - current_qtr
	for key in _bids:
		if key[1] < current_qtr:
			_expired_keys.append(key)
		elif key[1] > current_qtr and _forward_mem_horizons[key[0]] < key[1] - current_qtr:
			_forward_mem_horizons[key[0]] = key[1] - current_qtr
	for key in _expired_keys: # duplicates fine; erase is idempotent
		_asks.erase(key)
		_bids.erase(key)
	_expired_keys.clear()


# Sums open long / short position units per resource, quarters up to and including the
# current one. Physical settlement lags fills by up to ~a trader interval, so executors
# net these out of want quantities (else they re-order already-filled demand every
# interval). Reads the instrument-keyed aux view; the delivery body is irrelevant to a
# facility trader (each resource trades in exactly one market). Proxy-thread-owned, safe.
func _tally_net_positions() -> void:
	_net_long_units.fill(0)
	_net_short_units.fill(0)
	var current_qtr := proxy.ordinal_qtr
	for key in _positions_by_instrument:
		if key[1] > current_qtr:
			continue
		var signed_qty := _positions_by_instrument[key][0]
		if signed_qty > 0.0:
			_net_long_units[key[0]] += int(signed_qty)
		else:
			_net_short_units[key[0]] += int(-signed_qty)


## True when a standing order's price or quantity has drifted from the desired
## values by more than [constant PRICE_TOLERANCE] / [constant QTY_TOLERANCE].
func _needs_requote(have_quantity: int, have_price: int, want_quantity: int, want_price: int,
		price_tol: float, qty_tol: float) -> bool:
	if have_price <= 0 or have_quantity <= 0:
		return true
	if absf(float(want_price - have_price) / have_price) > price_tol:
		return true
	if absf(float(want_quantity - have_quantity) / have_quantity) > qty_tol:
		return true
	return false


# Cancels this trader's resting ask and bid (if any) on every quarter's instrument
# for [param resource_type]. Called on an executor-branch change: an order the old branch
# left resting can sit within the new branch's tolerances, so it would not be re-quoted,
# and cross the new branch's opposite quote (a self-trade) — on the front or any forward
# quarter both branches quote.
func _clear_resource_orders(resource_type: int) -> void:
	if !proxy.market:
		return
	var market_id := _delivery_market_id(resource_type)
	for key in _asks: # collect-then-act; _set_* mutates the dicts
		if key[0] == resource_type:
			_expired_keys.append(key)
	for key in _bids:
		if key[0] == resource_type:
			_expired_keys.append(key)
	for key in _expired_keys: # duplicates fine; the has() checks make this idempotent
		if _asks.has(key):
			_set_ask(key, 0, 1, market_id)
		if _bids.has(key):
			_set_bid(key, 0, 1, market_id)
	_expired_keys.clear()


# ********************************* LISTENERS *********************************

## Translates a facility resource strategy into this trader's per-resource strategy.
## The trader consumes facility intent here (and in the init re-sync) and nowhere
## else — never facility identity such as market_maker.
func _trader_strategy_for_facility(facility_strategy: int) -> int:
	const PRIMARY_PRODUCT := FacilityBaseAI.FacilityResourceStrategies.PRIMARY_PRODUCT
	const SECONDARY_PRODUCT := FacilityBaseAI.FacilityResourceStrategies.SECONDARY_PRODUCT
	const COPRODUCT := FacilityBaseAI.FacilityResourceStrategies.COPRODUCT
	const BYPRODUCT := FacilityBaseAI.FacilityResourceStrategies.BYPRODUCT
	const CRITICAL_INPUT := FacilityBaseAI.FacilityResourceStrategies.CRITICAL_INPUT
	const ROUTINE_INPUT := FacilityBaseAI.FacilityResourceStrategies.ROUTINE_INPUT
	const CONSUMABLE := FacilityBaseAI.FacilityResourceStrategies.CONSUMABLE
	const CLOSED_LOOP_INTERMEDIATE := FacilityBaseAI.FacilityResourceStrategies.CLOSED_LOOP_INTERMEDIATE
	const STRATEGIC_RESERVE := FacilityBaseAI.FacilityResourceStrategies.STRATEGIC_RESERVE
	const PHASE_OUT := FacilityBaseAI.FacilityResourceStrategies.PHASE_OUT
	match facility_strategy:
		PRIMARY_PRODUCT, SECONDARY_PRODUCT, COPRODUCT, BYPRODUCT:
			return ResourceStrategies.EXPORT_FOCUS
		CRITICAL_INPUT, ROUTINE_INPUT, CONSUMABLE:
			return ResourceStrategies.IMPORT_PRIORITY
		STRATEGIC_RESERVE:
			return ResourceStrategies.STRATEGIC_RESERVE
		PHASE_OUT:
			return ResourceStrategies.WIND_DOWN
		CLOSED_LOOP_INTERMEDIATE:
			return ResourceStrategies.AUTARKIC
	return ResourceStrategies.NEUTRAL


func _on_facility_trader_strategy_changed(strategy_id: int) -> void:
	trader_strategy = strategy_id


func _on_facility_resource_strategy_changed(resource_type: int, strategy_id: int) -> void:
	resource_strategies[resource_type] = _trader_strategy_for_facility(strategy_id)


# Mirrors the trader's resting ask/bid (carried in every notification) into order memory,
# keyed at this trader's width (2-element instrument for a facility, 3-element with the
# delivery body for a transport — see _key_width). The body-less position view
# (_positions_by_instrument) is a facility convenience; a transport reads proxy.positions
# directly, so it is maintained only when _facility is set.
func _on_positions_changed(position_key: PackedInt32Array, value: PackedFloat64Array,
		ask: PackedInt64Array, bid: PackedInt64Array) -> void:
	var order_key := position_key.slice(0, _key_width)
	if _facility:
		if value:
			_positions_by_instrument[order_key] = value
		else:
			_positions_by_instrument.erase(order_key)
	if ask:
		_asks[order_key] = ask
	else:
		_asks.erase(order_key)
	if bid:
		_bids[order_key] = bid
	else:
		_bids.erase(order_key)
