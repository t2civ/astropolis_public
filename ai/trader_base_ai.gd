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
## Traders are paired 1-to-1 with facilities. This trader AI has awareness of
## its facility's resource strategies and inventory (it trusts that this
## already incorporates player resource strategies).[br][br]
##
## A facility-paired trader orders delivery/pickup [b]only at its own
## facility's body[/b]: the executors and maintain helpers resolve the delivery
## market to [member TraderProxy.market_id] internally. The front
## (current-quarter) executors trade the facility's [i]stock[/i] imbalance
## against its reserve target; the forward executor trades projected [i]flow[/i]
## on later-quarter instruments (see [method _process_forward_flow]). The future
## transport trader will be this same class running different strategies,
## discriminated by [member TraderProxy.facility_id] == -1 — all facility-paired
## behavior is gated on that pairing.[br][br]
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
	## Quote both bid and ask; profit on the spread; provide liquidity.
	## Analog: market-maker / specialist desks.
	MARKET_MAKING,
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


## Quote offset from the reference price: asks are placed this fraction below it
## and bids this fraction above, so a producer's ask and a consumer's bid cross.
const SPREAD := 0.02
## Minimum order size in trade units; smaller surpluses/deficits are not quoted.
const MIN_LOT := 1
## Market-maker bid ceiling above the trade-reserve target, in trade units; the maker
## buys up toward target + this band and sells down to its operational reserve.
const MM_BAND_LOTS := 2
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


## Trader-posture strategy definitions; index = [enum TraderStrategies] value.
static var trader_strategy_defs: Array[Dictionary] = [
	{}, # INIT
	{}, # FACILITY_SUPPORT
	{}, # PROFIT_FOCUS
	{}, # CONSERVATIVE
	{}, # OPPORTUNISTIC
	{}, # POLICY_AGENT
]

## Per-resource strategy definitions; index = [enum ResourceStrategies] value.
## Boolean switches select the executor branch: [code]two_sided[/code] (maker
## quotes both sides), [code]sell_above_reserve[/code], [code]buy_to_reserve[/code].
## Tuning keys ([code]spread[/code], [code]min_lot[/code], [code]band_lots[/code],
## [code]price_tol[/code], [code]qty_tol[/code]) may override the class-constant
## defaults. An empty entry trades nothing.[br][br]
##
## [code]forward_quarters[/code] (int) gates and floors forward-flow trading on
## later-quarter instruments — effective depth grows with the facility's
## planning horizon (see [method _process_forward_flow]) — and
## [code]forward_hedge[/code] scales the hedged fraction of projected flow. The
## forward branch reuses the sell/buy switches as side gates. NEUTRAL stays
## deliberately front-only: with both switches set, early forward deliveries
## can push stock above target and be re-sold at a loss (bought at
## ref×(1+spread), dumped at ref×(1−spread)) — bounded churn that one-sided
## strategies can't suffer.
static var resource_strategy_defs: Array[Dictionary] = [
	{&"sell_above_reserve": true, &"buy_to_reserve": true}, # NEUTRAL — maintain at reserve
	{}, # JUST_IN_TIME
	{&"buy_to_reserve": true}, # STRATEGIC_RESERVE
	{}, # LIQUIDATE
	{}, # HOARD
	{}, # DUMP
	{&"two_sided": true}, # MARKET_MAKING
	{}, # SPECULATIVE_LONG
	{}, # SPECULATIVE_SHORT
	{}, # AUTARKIC
	{&"sell_above_reserve": true, &"forward_quarters": 2, &"forward_hedge": 0.75}, # EXPORT_FOCUS
	{&"buy_to_reserve": true, &"forward_quarters": 2, &"forward_hedge": 1.0}, # IMPORT_PRIORITY
	{}, # OPPORTUNISTIC
	{&"sell_above_reserve": true}, # WIND_DOWN
]


## Member names persisted by save/load (interval timing inherited from BaseAI).
const PERSIST_PROPERTIES: Array[StringName] = [
	&"_last_interval",
	&"_next_interval",
	&"trader_strategy",
	&"resource_strategies",
	&"_asks",
	&"_bids",
]


static var _table_n_rows := IVTableData.table_n_rows
static var _trade_unit_multipliers := ThreadsafeGlobal.resource_trade_unit_multipliers
## Per-resource fiat price anchor (USD per trade unit) from resources.tsv start_price,
## used when no live market price exists yet. Built once.
static var _start_unit_prices: PackedInt32Array


var proxy: TraderProxy


# *****************************************************************************
# persisted

## Trader-posture strategy. See [enum TraderStrategies].
var trader_strategy := 0
## Per-resource strategies. See [enum ResourceStrategies].
var resource_strategies: PackedInt32Array


## Memory of open asks. Indexed by 3-element key [resource_type,
## ordinal_quarter, body_id] (the delivery body) with values [unit_quantity,
## unit_price] in trade units. Mirrors the market's per-instrument ask, refreshed
## via position notifications.
var _asks: Dictionary[PackedInt32Array, PackedInt32Array] = {}

## Memory of open bids. Indexed by 3-element key [resource_type,
## ordinal_quarter, body_id] (the delivery body) with values [unit_quantity,
## unit_price] in trade units. Mirrors the market's per-instrument bid, refreshed
## via position notifications.
var _bids: Dictionary[PackedInt32Array, PackedInt32Array] = {}

# *****************************************************************************

var _facility_ai: FacilityBaseAI
var _facility: FacilityProxy  # paired facility proxy

# Per-resource open-position sums at the local body in trade units (quarters up
# to and including the current one), rebuilt each interval by _tally_net_positions().
var _net_long_units: PackedInt64Array
var _net_short_units: PackedInt64Array
# Front-quarter instrument scratch [resource_type, ordinal_qtr]; safe for lookups
# and outgoing calls (downstream duplicates), never stored as a key.
var _instrument_scratch: PackedInt32Array
# Collect-then-erase scratch for _drop_expired_memory().
var _expired_keys: Array[PackedInt32Array] = []
# Per-resource quarter-offset of the farthest forward order in memory at the
# local body (0 = none); rebuilt by _drop_expired_memory() each interval. Lets
# the forward pass keep maintaining — and so want-0-clearing — orders beyond
# the def's current horizon (strategy change, def shrink, lost reference price).
var _forward_mem_horizons: PackedInt32Array
# Forward instrument scratch [resource_type, ordinal_quarter]; safe for lookups
# and outgoing calls (downstream duplicates), never stored as a key.
var _forward_instrument_scratch: PackedInt32Array
# Position-lookup scratch [resource_type, ordinal_quarter, body_id]; never stored.
var _position_scratch: PackedInt32Array


# ************************* VIRTUAL & IMPLEMENTATION **************************

func _init() -> void:
	var n_resources: int = _table_n_rows[&"resources"]
	resource_strategies.resize(n_resources)
	_net_long_units.resize(n_resources)
	_net_short_units.resize(n_resources)
	_instrument_scratch.resize(2)
	_forward_mem_horizons.resize(n_resources)
	_forward_instrument_scratch.resize(2)
	_position_scratch.resize(3)
	if _start_unit_prices.is_empty():
		var resources_table: Dictionary[StringName, Array] = IVTableData.db_tables[&"resources"]
		_start_unit_prices = PackedInt32Array(resources_table[&"start_price"])


func _clear_for_destruction() -> void:
	proxy = null
	_facility_ai = null
	_facility = null


func bind_proxy(proxy_: Proxy) -> void:
	proxy = proxy_ as TraderProxy


func ai_init() -> void:
	proxy.positions_changed.connect(_on_positions_changed)
	if proxy.facility_id == -1:
		return # transport trader: not facility-paired; transport strategies TBD
	_facility = proxy.facility
	_facility_ai = Proxy.proxy_bus.facility_ais[proxy.facility_id]
	assert(_facility_ai, "TraderBaseAI expects facility's AI to be FacilityBaseAI")
	_facility_ai.facility_resource_strategy_changed.connect(_on_facility_resource_strategy_changed)
	# The facility may have authored its strategies before we connected (init order
	# across entity types is not guaranteed), so re-sync the full array now.
	for resource_type in resource_strategies.size():
		var facility_strategy := _facility_ai.facility_resource_strategies[resource_type]
		resource_strategies[resource_type] = _trader_strategy_for_facility(facility_strategy)


## Acts on live market and inventory state using the sticky per-resource strategy
## (authored by the facility, translated and stored on change). The strategy's def
## selects the front executor branch: two-sided maker vs. one-sided facility
## support, both SET orders on the front (current-quarter) instrument at the
## trader's local market. Def-gated strategies also maintain forward-flow orders
## on later quarters (see [method _process_forward_flow]).
func process_ai_interval(_delta: float) -> void:
	var market := proxy.market
	if !market or !_facility:
		return # no market yet, or transport trader (transport strategies TBD)
	_drop_expired_memory()
	_tally_net_positions()
	_instrument_scratch[1] = proxy.ordinal_qtr
	for resource_type in resource_strategies.size():
		_instrument_scratch[0] = resource_type
		var def := resource_strategy_defs[resource_strategies[resource_type]]
		if def.get(&"two_sided", false):
			_process_market_making(resource_type, market, _instrument_scratch, def)
		else:
			_process_facility_support(resource_type, market, _instrument_scratch, def)
		_process_forward_flow(resource_type, market, def)


## Trades one resource to service facility operations: clears stock above the reserve
## target (sell) and/or replenishes up toward it (buy), per the def switches. With both
## enabled it self-balances around the reserve — stock can't be both over and under, so
## at most one side quotes. A still-valid resting order is left untouched; we re-quote
## only on material divergence. Open positions count against the want quantities: a
## filled order is committed in/outflow until the short side physically settles it
## (up to ~a trader interval), so quoting without netting would re-order
## already-filled demand every interval.
func _process_facility_support(resource_type: int, market: MarketProxy,
		instrument: PackedInt32Array, def: Dictionary) -> void:
	var sell: bool = def.get(&"sell_above_reserve", false)
	var buy: bool = def.get(&"buy_to_reserve", false)
	var mem_key := _order_memory_key(instrument, proxy.market_id)
	var reference_price := market.get_unit_price(resource_type)
	if reference_price <= 0 or (not sell and not buy):
		# Not trading this resource now: drop any resting orders (placeholder
		# price 1 — the proxy rejects price <= 0 even for a cancel).
		_maintain_ask(instrument, mem_key, 0, 1, MIN_LOT, 0.0, 0.0)
		_maintain_bid(instrument, mem_key, 0, 1, MIN_LOT, 0.0, 0.0)
		return
	var spread: float = def.get(&"spread", SPREAD)
	var min_lot: int = def.get(&"min_lot", MIN_LOT)
	var price_tol: float = def.get(&"price_tol", PRICE_TOLERANCE)
	var qty_tol: float = def.get(&"qty_tol", QTY_TOLERANCE)
	var multiplier := _trade_unit_multipliers[resource_type]
	var target := (_facility.get_inventory_ops_reserve(resource_type)
			+ _facility.get_inventory_strategic_reserve(resource_type))
	var stock := _facility.get_inventory_stock(resource_type)
	var ask_units := 0
	if sell: # open shorts are committed outbound stock
		ask_units = int((stock - target) / multiplier) - _net_short_units[resource_type]
	var ask_price := maxi(1, floori(reference_price * (1.0 - spread)))
	var bid_units := 0
	if buy: # open longs are committed inbound goods, like in-transit stock
		bid_units = (int((target - stock - _facility.get_inventory_in_transit(resource_type))
				/ multiplier) - _net_long_units[resource_type])
	var bid_price := maxi(1, ceili(reference_price * (1.0 + spread)))
	# Cancel side first (see _process_forward_flow): at most one side wants — post
	# it only after the opposite side's clear is queued, so a stale opposite-side
	# order can't cross the fresh post if the markets thread drains mid-pass.
	if ask_units >= min_lot:
		_maintain_bid(instrument, mem_key, bid_units, bid_price, min_lot, price_tol, qty_tol)
		_maintain_ask(instrument, mem_key, ask_units, ask_price, min_lot, price_tol, qty_tol)
	else:
		_maintain_ask(instrument, mem_key, ask_units, ask_price, min_lot, price_tol, qty_tol)
		_maintain_bid(instrument, mem_key, bid_units, bid_price, min_lot, price_tol, qty_tol)


## Quotes both sides for a market-relevant resource: bid below the reference price, ask
## above it, so the maker earns the spread and provides liquidity (the inverse of
## facility-support, which crosses to transact). Quantities self-balance inventory toward
## the trade-reserve target as fills occur, netting open positions like facility-support.
## Falls back to the resource's start_price when no live market price exists.
func _process_market_making(resource_type: int, market: MarketProxy,
		instrument: PackedInt32Array, def: Dictionary) -> void:
	var spread: float = def.get(&"spread", SPREAD)
	var min_lot: int = def.get(&"min_lot", MIN_LOT)
	var band_lots: int = def.get(&"band_lots", MM_BAND_LOTS)
	var price_tol: float = def.get(&"price_tol", PRICE_TOLERANCE)
	var qty_tol: float = def.get(&"qty_tol", QTY_TOLERANCE)
	var mem_key := _order_memory_key(instrument, proxy.market_id)
	var multiplier := _trade_unit_multipliers[resource_type]
	var reference_price := market.get_unit_price(resource_type)
	if reference_price <= 0:
		reference_price = _start_unit_prices[resource_type]
	if reference_price <= 0:
		_maintain_ask(instrument, mem_key, 0, 1, min_lot, 0.0, 0.0)
		_maintain_bid(instrument, mem_key, 0, 1, min_lot, 0.0, 0.0)
		return
	var ask_price := maxi(1, ceili(reference_price * (1.0 + spread)))
	var bid_price := maxi(1, floori(reference_price * (1.0 - spread)))
	var ops_reserve := _facility.get_inventory_ops_reserve(resource_type)
	var target := ops_reserve + _facility.get_inventory_strategic_reserve(resource_type)
	var ceiling := target + band_lots * multiplier
	var stock := _facility.get_inventory_stock(resource_type)
	var ask_units := int((stock - ops_reserve) / multiplier) - _net_short_units[resource_type]
	var bid_units := (int((ceiling - stock - _facility.get_inventory_in_transit(resource_type))
			/ multiplier) - _net_long_units[resource_type])
	_maintain_ask(instrument, mem_key, maxi(0, ask_units), ask_price, min_lot,
			price_tol, qty_tol)
	_maintain_bid(instrument, mem_key, maxi(0, bid_units), bid_price, min_lot,
			price_tol, qty_tol)


## Maintains forward-flow orders on later-quarter instruments at the local
## market: hedges the facility's projected per-quarter flow (expected rate ×
## quarter duration), netting each instrument's open position. The front
## executors trade [i]stock[/i] imbalance; this one trades [i]flow[/i] — no
## double-commitment, because filled forwards roll into the front position sums
## at quarter rollover and net out of front wants there. The def's
## [code]forward_quarters[/code] gates participation and floors the depth; the
## facility's [member FacilityProxy.time_horizon] deepens it, so a remote
## facility planning years ahead quotes proportionally farther out. Runs for
## every resource (even maker/front-only defs) and maintains out to the
## farthest remembered forward order past the def horizon, so a strategy
## change, def shrink, or lost reference price want-0-clears stale orders.
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
	var sell: bool = def.get(&"sell_above_reserve", false)
	var buy: bool = def.get(&"buy_to_reserve", false)
	var want_ask := sell and expected_rate > 0.0 and reference_price > 0
	var want_bid := buy and expected_rate < 0.0 and reference_price > 0
	if !want_ask and !want_bid and _forward_mem_horizons[resource_type] == 0:
		return # no flow to hedge and nothing resting forward
	var spread: float = def.get(&"spread", SPREAD)
	var min_lot: int = def.get(&"min_lot", MIN_LOT)
	var price_tol: float = def.get(&"price_tol", PRICE_TOLERANCE)
	var qty_tol: float = def.get(&"qty_tol", QTY_TOLERANCE)
	var forward_hedge: float = def.get(&"forward_hedge", FORWARD_HEDGE)
	var multiplier := _trade_unit_multipliers[resource_type]
	var local_body_id := market.body_id
	# Crossing-friendly prices like facility support: ask below the reference,
	# bid above, so producer and consumer forwards cross (placeholder 1 on
	# cancel-only paths — the proxy rejects price <= 0 even for a cancel).
	var ask_price := maxi(1, floori(reference_price * (1.0 - spread)))
	var bid_price := maxi(1, ceili(reference_price * (1.0 + spread)))
	var current_qtr := proxy.ordinal_qtr
	for k in range(1, n_quarters + 1):
		var ordinal_quarter := current_qtr + k
		_forward_instrument_scratch[0] = resource_type
		_forward_instrument_scratch[1] = ordinal_quarter
		var mem_key := _order_memory_key(_forward_instrument_scratch, proxy.market_id)
		var flow_units := 0
		if k <= forward_quarters and (want_ask or want_bid):
			flow_units = int(forward_hedge * absf(expected_rate)
					* Utils.get_ordinal_quarter_duration(ordinal_quarter) / multiplier)
		# An open position on this instrument is already-committed flow, netted
		# out of the want like the front executors net the front position sums.
		_position_scratch[0] = resource_type
		_position_scratch[1] = ordinal_quarter
		_position_scratch[2] = local_body_id
		var position: PackedFloat64Array = proxy.positions.get(_position_scratch, NULL_PF64ARRAY)
		var net_units := int(position[0]) if position else 0
		var ask_units := (flow_units - maxi(0, -net_units)) if want_ask else 0
		var bid_units := (flow_units - maxi(0, net_units)) if want_bid else 0
		# Cancel side first: the markets thread may drain the channel between
		# these two calls, and crossing-friendly prices would let a stale
		# opposite-side order self-cross a fresh post; a cancel can never cross.
		if want_ask:
			_maintain_bid(_forward_instrument_scratch, mem_key, 0, 1, min_lot, 0.0, 0.0)
			_maintain_ask(_forward_instrument_scratch, mem_key, ask_units, ask_price,
					min_lot, price_tol, qty_tol)
		elif want_bid:
			_maintain_ask(_forward_instrument_scratch, mem_key, 0, 1, min_lot, 0.0, 0.0)
			_maintain_bid(_forward_instrument_scratch, mem_key, bid_units, bid_price,
					min_lot, price_tol, qty_tol)
		else: # cleanup only
			_maintain_ask(_forward_instrument_scratch, mem_key, 0, 1, min_lot, 0.0, 0.0)
			_maintain_bid(_forward_instrument_scratch, mem_key, 0, 1, min_lot, 0.0, 0.0)


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
	var mem_key := _order_memory_key(instrument, delivery_market_id)
	if unit_quantity:
		var ask: PackedInt32Array
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
	var mem_key := _order_memory_key(instrument, delivery_market_id)
	if unit_quantity:
		var bid: PackedInt32Array
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


# Order memory is keyed by the delivery body; resolve it from the delivery market.
func _order_memory_key(instrument: PackedInt32Array, market_id: int) -> PackedInt32Array:
	var market_proxy: MarketProxy = Proxy.proxy_bus.market_proxies[market_id]
	assert(market_proxy and market_proxy.body, "delivery market/body not resolved")
	var key := instrument.duplicate()
	key.resize(3)
	key[2] = market_proxy.body.body_id
	return key


# ****************************** INTERNAL LOGIC *******************************

## Brings our resting ask for [param instrument] in line with the desired quantity
## and price under SET semantics: a want below [param min_lot] clears any resting
## ask (the 0-set is sent only when memory holds one); otherwise posts if absent,
## or re-quotes on material divergence (see [method _needs_requote]).
## [param mem_key] is the order-memory key for [param instrument] at the delivery
## body (see [method _order_memory_key]). Facility-paired helper: the delivery
## market is always the trader's own ([member TraderProxy.market_id]).
func _maintain_ask(instrument: PackedInt32Array, mem_key: PackedInt32Array,
		want_quantity: int, want_price: int, min_lot: int, price_tol: float, qty_tol: float
		) -> void:
	if want_quantity < min_lot:
		if _asks.has(mem_key):
			_set_ask(instrument, 0, want_price, proxy.market_id)
		return
	if !_asks.has(mem_key):
		_set_ask(instrument, want_quantity, want_price, proxy.market_id)
		return
	var have := _asks[mem_key]
	if _needs_requote(have[0], have[1], want_quantity, want_price, price_tol, qty_tol):
		_set_ask(instrument, want_quantity, want_price, proxy.market_id)


## Bid counterpart of [method _maintain_ask].
func _maintain_bid(instrument: PackedInt32Array, mem_key: PackedInt32Array,
		want_quantity: int, want_price: int, min_lot: int, price_tol: float, qty_tol: float
		) -> void:
	if want_quantity < min_lot:
		if _bids.has(mem_key):
			_set_bid(instrument, 0, want_price, proxy.market_id)
		return
	if !_bids.has(mem_key):
		_set_bid(instrument, want_quantity, want_price, proxy.market_id)
		return
	var have := _bids[mem_key]
	if _needs_requote(have[0], have[1], want_quantity, want_price, price_tol, qty_tol):
		_set_bid(instrument, want_quantity, want_price, proxy.market_id)


# The market purges old-quarter resting orders at rollover without echoes; drop
# matching memory by the same rule so stale entries can't satisfy _maintain_*
# lookups (which would suppress fresh front-quarter quotes). Piggybacks the same
# iteration to rebuild _forward_mem_horizons (the farthest forward order per
# resource at the local body).
func _drop_expired_memory() -> void:
	var current_qtr := proxy.ordinal_qtr
	var local_body_id := proxy.market.body_id
	_forward_mem_horizons.fill(0)
	for key in _asks:
		if key[1] < current_qtr:
			_expired_keys.append(key)
		elif key[1] > current_qtr and key[2] == local_body_id \
				and _forward_mem_horizons[key[0]] < key[1] - current_qtr:
			_forward_mem_horizons[key[0]] = key[1] - current_qtr
	for key in _bids:
		if key[1] < current_qtr:
			_expired_keys.append(key)
		elif key[1] > current_qtr and key[2] == local_body_id \
				and _forward_mem_horizons[key[0]] < key[1] - current_qtr:
			_forward_mem_horizons[key[0]] = key[1] - current_qtr
	for key in _expired_keys: # duplicates fine; erase is idempotent
		_asks.erase(key)
		_bids.erase(key)
	_expired_keys.clear()


# Sums open long / short position units per resource for delivery at the local
# body, quarters up to and including the current one. Physical settlement lags
# fills by up to ~a trader interval, so executors net these out of want
# quantities (else they re-order already-filled demand every interval).
# proxy.positions is proxy-thread-owned like this AI; direct read is safe.
func _tally_net_positions() -> void:
	_net_long_units.fill(0)
	_net_short_units.fill(0)
	var current_qtr := proxy.ordinal_qtr
	var local_body_id := proxy.market.body_id
	var positions := proxy.positions
	for key in positions:
		if key[2] != local_body_id or key[1] > current_qtr:
			continue
		var signed_qty := positions[key][0]
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


# Cancels this trader's resting ask and bid (if any) on the front-quarter instrument
# for [param resource_type]. Called on an executor-branch change: the facility-support
# and market-making branches share price formulas (a sell ask at ref*(1-spread) equals
# the maker's bid; a buy bid at ref*(1+spread) equals the maker's ask), and those prices
# sit within [constant PRICE_TOLERANCE] of each other, so a lingering old-branch order
# would not be re-quoted and could cross the new branch's opposite quote (a self-trade).
func _clear_front_orders(resource_type: int) -> void:
	if !proxy.market:
		return
	var instrument := PackedInt32Array([resource_type, proxy.ordinal_qtr])
	var mem_key := _order_memory_key(instrument, proxy.market_id)
	if _asks.has(mem_key):
		_set_ask(instrument, 0, 1, proxy.market_id)
	if _bids.has(mem_key):
		_set_bid(instrument, 0, 1, proxy.market_id)


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
	const MARKET_MAKE := FacilityBaseAI.FacilityResourceStrategies.MARKET_MAKE
	const STRATEGIC_RESERVE := FacilityBaseAI.FacilityResourceStrategies.STRATEGIC_RESERVE
	const PHASE_OUT := FacilityBaseAI.FacilityResourceStrategies.PHASE_OUT
	match facility_strategy:
		PRIMARY_PRODUCT, SECONDARY_PRODUCT, COPRODUCT, BYPRODUCT:
			return ResourceStrategies.EXPORT_FOCUS
		CRITICAL_INPUT, ROUTINE_INPUT, CONSUMABLE:
			return ResourceStrategies.IMPORT_PRIORITY
		MARKET_MAKE:
			return ResourceStrategies.MARKET_MAKING
		STRATEGIC_RESERVE:
			return ResourceStrategies.STRATEGIC_RESERVE
		PHASE_OUT:
			return ResourceStrategies.WIND_DOWN
		CLOSED_LOOP_INTERMEDIATE:
			return ResourceStrategies.AUTARKIC
	return ResourceStrategies.NEUTRAL


func _on_facility_resource_strategy_changed(resource_type: int, strategy_id: int) -> void:
	var new_strategy := _trader_strategy_for_facility(strategy_id)
	if new_strategy == resource_strategies[resource_type]:
		return
	resource_strategies[resource_type] = new_strategy
	# A new strategy may switch the executor branch; clear the front instrument so a
	# lingering old-branch order cannot cross the new branch's quote (see _clear_front_orders).
	_clear_front_orders(resource_type)


# Mirrors the trader's current ask/bid (carried in every position notification) into
# order memory, keyed by [resource_type, ordinal_quarter, body_id]. The position
# value itself is read from proxy.positions; this handler only needs ask/bid.
func _on_positions_changed(position_key: PackedInt32Array, _value: PackedFloat64Array,
		ask: PackedInt32Array, bid: PackedInt32Array) -> void:
	if ask:
		_asks[position_key] = ask
	else:
		_asks.erase(position_key)
	if bid:
		_bids[position_key] = bid
	else:
		_bids.erase(position_key)
