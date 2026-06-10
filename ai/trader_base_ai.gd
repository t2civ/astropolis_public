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
## Trade memory is [b]optimistic about new orders, pessimistic about
## cancellations and replacements[/b]. It updates quantity memory immediately
## when placing a new order, but waits for notification when cancelling or
## replacing. This is the correct memory model.[br][br]
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


## Epoch-day conversion: market order expirations are in integer days.
const DAY := IVUnits.DAY
## Quote offset from the reference price: asks are placed this fraction below it
## and bids this fraction above, so a producer's ask and a consumer's bid cross.
const SPREAD := 0.02
## Minimum order size in trade units; smaller surpluses/deficits are not quoted.
const MIN_LOT := 1
## Market-maker bid ceiling above the trade-reserve target, in trade units; the maker
## buys up toward target + this band and sells down to its operational reserve.
const MM_BAND_LOTS := 2
## Standing-order lifetime in AI intervals. A backstop only: the AI re-evaluates
## each interval and re-quotes on material divergence, and the market reports
## CANCELLED on expiry so memory stays correct.
const ORDER_LIFETIME := 4
## Re-quote a standing order when its price drifts beyond this fraction of its price.
const PRICE_TOLERANCE := 0.05
## Re-quote a standing order when its desired quantity drifts beyond this fraction.
const QTY_TOLERANCE := 0.25


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
## [code]price_tol[/code], [code]qty_tol[/code], [code]order_lifetime[/code]) may
## override the class-constant defaults. An empty entry trades nothing.
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
	{&"sell_above_reserve": true}, # EXPORT_FOCUS
	{&"buy_to_reserve": true}, # IMPORT_PRIORITY
	{}, # OPPORTUNISTIC
	{&"sell_above_reserve": true}, # WIND_DOWN
]


## Member names persisted by save/load (interval timing inherited from BaseAI).
const PERSIST_PROPERTIES: Array[StringName] = [
	&"_last_interval",
	&"_next_interval",
	&"trader_strategy",
	&"resource_strategies",
	&"_spot_ask_totals",
	&"_spot_bid_totals",
	&"_spot_ask_prices",
	&"_spot_bid_prices",
	&"_spot_ask_ids",
	&"_spot_bid_ids",
	&"_futures_asks",
	&"_futures_bids",
]


static var _table_n_rows := IVTableData.table_n_rows
static var _trade_unit_multipliers := ThreadsafeGlobal.resource_trade_unit_multipliers
## Per-resource fiat price anchor (USD per trade unit) from resources.tsv start_price,
## used when no live spot price exists yet. Built once.
static var _start_unit_prices: PackedInt32Array


var proxy: TraderProxy


# *****************************************************************************
# persisted

## Trader-posture strategy. See [enum TraderStrategies].
var trader_strategy := 0
## Per-resource strategies. See [enum ResourceStrategies].
var resource_strategies: PackedInt32Array


## Memory of spot ask totals (unit quantity per resource).
var _spot_ask_totals: PackedInt64Array
## Memory of spot bid totals (unit quantity per resource).
var _spot_bid_totals: PackedInt64Array
## Memory of last known spot ask price for each resource. This will be THE
## resource ask price if trader AI only has one ask per resource at a time.
var _spot_ask_prices: PackedInt64Array
## Memory of last known spot bid price for each resource. This will be THE
## resource bid price if trader AI only has one bid per resource at a time.
var _spot_bid_prices: PackedInt64Array
## Memory of last known spot ask_id for each resource. This will be THE
## resource ask_id if trader AI only has one ask per resource at a time.
var _spot_ask_ids: PackedInt64Array
## Memory of last known spot bid_id for each resource. This will be THE
## resource bid_id if trader AI only has one bid per resource at a time.
var _spot_bid_ids: PackedInt64Array

## Memory of open futures asks. Indexed by 3-element key [resource_type,
## ordinal_quarter, body_id] (the delivery body) with values [unit_quantity,
## unit_price] in trade units. Mirrors the market's per-instrument ask, refreshed
## via position notifications.
var _futures_asks: Dictionary[PackedInt32Array, PackedInt32Array] = {}

## Memory of open futures bids. Indexed by 3-element key [resource_type,
## ordinal_quarter, body_id] (the delivery body) with values [unit_quantity,
## unit_price] in trade units. Mirrors the market's per-instrument bid, refreshed
## via position notifications.
var _futures_bids: Dictionary[PackedInt32Array, PackedInt32Array] = {}

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
# Collect-then-erase scratch for _drop_expired_futures_memory().
var _expired_keys: Array[PackedInt32Array] = []


# ************************* VIRTUAL & IMPLEMENTATION **************************

func _init() -> void:
	var n_resources: int = _table_n_rows[&"resources"]
	resource_strategies.resize(n_resources)
	_spot_ask_totals.resize(n_resources)
	_spot_bid_totals.resize(n_resources)
	_spot_ask_prices.resize(n_resources)
	_spot_bid_prices.resize(n_resources)
	_spot_ask_ids.resize(n_resources)
	_spot_bid_ids.resize(n_resources)
	_spot_ask_ids.fill(-1)
	_spot_bid_ids.fill(-1)
	_net_long_units.resize(n_resources)
	_net_short_units.resize(n_resources)
	_instrument_scratch.resize(2)
	if _start_unit_prices.is_empty():
		var resources_table: Dictionary[StringName, Array] = IVTableData.db_tables[&"resources"]
		_start_unit_prices = PackedInt32Array(resources_table[&"start_price"])


func _clear_for_destruction() -> void:
	proxy = null
	_facility_ai = null
	_facility = null


func bind_proxy(proxy_: Proxy) -> void:
	proxy = proxy_ as TraderProxy
	proxy.ask_updated.connect(_on_ask_updated)
	proxy.bid_updated.connect(_on_bid_updated)


func ai_init() -> void:
	_facility = proxy.facility
	proxy.futures_positions_changed.connect(_on_futures_positions_changed)
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
## selects the executor branch: two-sided maker vs. one-sided facility support.
## Orders are forward SET orders on the front (current-quarter) instrument at the
## trader's local market.
func process_ai_interval(_delta: float) -> void:
	var market := proxy.market
	if !market:
		return
	_drop_expired_futures_memory()
	_tally_net_positions()
	var delivery_market_id := proxy.market_id
	_instrument_scratch[1] = proxy.ordinal_qtr
	for resource_type in resource_strategies.size():
		_instrument_scratch[0] = resource_type
		var def := resource_strategy_defs[resource_strategies[resource_type]]
		if def.get(&"two_sided", false):
			_process_market_making(resource_type, market, _instrument_scratch,
					delivery_market_id, def)
		else:
			_process_facility_support(resource_type, market, _instrument_scratch,
					delivery_market_id, def)


## Trades one resource to service facility operations: clears stock above the reserve
## target (sell) and/or replenishes up toward it (buy), per the def switches. With both
## enabled it self-balances around the reserve — stock can't be both over and under, so
## at most one side quotes. A still-valid resting order is left untouched; we re-quote
## only on material divergence. Open positions count against the want quantities: a
## filled order is committed in/outflow until the short side physically settles it
## (up to ~a trader interval), so quoting without netting would re-order
## already-filled demand every interval.
func _process_facility_support(resource_type: int, market: MarketProxy,
		instrument: PackedInt32Array, delivery_market_id: int, def: Dictionary) -> void:
	var sell: bool = def.get(&"sell_above_reserve", false)
	var buy: bool = def.get(&"buy_to_reserve", false)
	var mem_key := _futures_memory_key(instrument, delivery_market_id)
	var reference_price := market.get_unit_price(resource_type)
	if reference_price <= 0 or (not sell and not buy):
		# Not trading this resource now: drop any resting orders (placeholder
		# price 1 — the proxy rejects price <= 0 even for a cancel).
		_maintain_futures_ask(instrument, mem_key, 0, 1, MIN_LOT, 0.0, 0.0, delivery_market_id)
		_maintain_futures_bid(instrument, mem_key, 0, 1, MIN_LOT, 0.0, 0.0, delivery_market_id)
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
	_maintain_futures_ask(instrument, mem_key, ask_units, ask_price, min_lot, price_tol,
			qty_tol, delivery_market_id)
	var bid_units := 0
	if buy: # open longs are committed inbound goods, like in-transit stock
		bid_units = (int((target - stock - _facility.get_inventory_in_transit(resource_type))
				/ multiplier) - _net_long_units[resource_type])
	var bid_price := maxi(1, ceili(reference_price * (1.0 + spread)))
	_maintain_futures_bid(instrument, mem_key, bid_units, bid_price, min_lot, price_tol,
			qty_tol, delivery_market_id)


## Quotes both sides for a market-relevant resource: bid below the reference price, ask
## above it, so the maker earns the spread and provides liquidity (the inverse of
## facility-support, which crosses to transact). Quantities self-balance inventory toward
## the trade-reserve target as fills occur, netting open positions like facility-support.
## Falls back to the resource's start_price when no live market price exists.
func _process_market_making(resource_type: int, market: MarketProxy,
		instrument: PackedInt32Array, delivery_market_id: int, def: Dictionary) -> void:
	var spread: float = def.get(&"spread", SPREAD)
	var min_lot: int = def.get(&"min_lot", MIN_LOT)
	var band_lots: int = def.get(&"band_lots", MM_BAND_LOTS)
	var price_tol: float = def.get(&"price_tol", PRICE_TOLERANCE)
	var qty_tol: float = def.get(&"qty_tol", QTY_TOLERANCE)
	var mem_key := _futures_memory_key(instrument, delivery_market_id)
	var multiplier := _trade_unit_multipliers[resource_type]
	var reference_price := market.get_unit_price(resource_type)
	if reference_price <= 0:
		reference_price = _start_unit_prices[resource_type]
	if reference_price <= 0:
		_maintain_futures_ask(instrument, mem_key, 0, 1, min_lot, 0.0, 0.0, delivery_market_id)
		_maintain_futures_bid(instrument, mem_key, 0, 1, min_lot, 0.0, 0.0, delivery_market_id)
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
	_maintain_futures_ask(instrument, mem_key, maxi(0, ask_units), ask_price, min_lot,
			price_tol, qty_tol, delivery_market_id)
	_maintain_futures_bid(instrument, mem_key, maxi(0, bid_units), bid_price, min_lot,
			price_tol, qty_tol, delivery_market_id)


# ******************************* AI / PROXY API ******************************
# Call on proxy thread.

## Submit ask orders here so we can track our own ask totals. Resulting BOOKED
## ask_id and/or subsequent trades come back via _on_ask_updated().
func _spot_ask(resource_type: int, unit_quantity: int, unit_price: int, expiration: int) -> void:
	_spot_ask_totals[resource_type] += unit_quantity
	_spot_ask_prices[resource_type] = unit_price
	proxy.spot_ask(resource_type, unit_quantity, unit_price, expiration)


## Submit bid orders here so we can track our own bid totals. Resulting BOOKED
## bid_id and/or subsequent trades come back via _on_bid_updated().
func _spot_bid(resource_type: int, unit_quantity: int, unit_price: int, expiration: int) -> void:
	_spot_bid_totals[resource_type] += unit_quantity
	_spot_bid_prices[resource_type] = unit_price
	proxy.spot_bid(resource_type, unit_quantity, unit_price, expiration)


## Reprices/resizes our standing ask for [param resource_type] in place to
## [param new_quantity] / [param new_price], keeping its id. No-op if we have no
## known resting ask id. We assume nothing at submit time (the order may already be
## gone); local memory is updated when the REPLACED echo (or a fill) arrives via
## [method _on_ask_updated].
func _replace_ask(resource_type: int, new_quantity: int, new_price: int, expiration: int) -> void:
	var ask_id := _spot_ask_ids[resource_type]
	if ask_id == -1:
		return
	proxy.replace_spot_ask(ask_id, new_quantity, new_price, expiration)


## Bid counterpart of [method _replace_ask].
func _replace_bid(resource_type: int, new_quantity: int, new_price: int, expiration: int) -> void:
	var bid_id := _spot_bid_ids[resource_type]
	if bid_id == -1:
		return
	proxy.replace_spot_bid(bid_id, new_quantity, new_price, expiration)


## Cancels our standing ask for [param resource_type] (if any). Local memory is
## cleared when the market's CANCELLED update arrives (see [method _on_ask_updated]),
## not here, so fills already in flight are still counted correctly.
func _cancel_ask(resource_type: int) -> void:
	var ask_id := _spot_ask_ids[resource_type]
	if ask_id == -1:
		return
	proxy.cancel_spot_ask(ask_id)


## Bid counterpart of [method _cancel_ask].
func _cancel_bid(resource_type: int) -> void:
	var bid_id := _spot_bid_ids[resource_type]
	if bid_id == -1:
		return
	proxy.cancel_spot_bid(bid_id)


## Adds, replaces, or cancels a futures sell (ask) order. See [method
## TraderProxy.set_futures_ask] for instrument composition and params, including
## [param market_id] (the market at the delivery body). This method
## updates AI ask memory on the outgoing call. Rejects if specified
## ordinal_quarter < proxy.ordinal_qtr (proxy would reject if it went through
## here).
func _set_futures_ask(instrument: PackedInt32Array, unit_quantity: int,
		unit_price: int, delivery_market_id: int) -> void:
	if instrument[1] < proxy.ordinal_qtr:
		return
	var mem_key := _futures_memory_key(instrument, delivery_market_id)
	if unit_quantity:
		var ask: PackedInt32Array
		if _futures_asks.has(mem_key):
			ask = _futures_asks[mem_key]
		else:
			ask.resize(2)
			_futures_asks[mem_key] = ask
		ask[0] = unit_quantity
		ask[1] = unit_price
	else:
		_futures_asks.erase(mem_key)
	proxy.set_futures_ask(instrument, unit_quantity, unit_price, delivery_market_id)


## Adds, replaces, or cancels a futures buy (bid) order. See [method
## TraderProxy.set_futures_bid] for instrument composition and params, including
## [param market_id] (the market at the delivery body). This method
## updates AI bid memory on the outgoing call. Rejects if specified
## ordinal_quarter < proxy.ordinal_qtr (proxy would reject if it went through
## here).
func _set_futures_bid(instrument: PackedInt32Array, unit_quantity: int,
		unit_price: int, delivery_market_id: int) -> void:
	if instrument[1] < proxy.ordinal_qtr:
		return
	var mem_key := _futures_memory_key(instrument, delivery_market_id)
	if unit_quantity:
		var bid: PackedInt32Array
		if _futures_bids.has(mem_key):
			bid = _futures_bids[mem_key]
		else:
			bid.resize(2)
			_futures_bids[mem_key] = bid
		bid[0] = unit_quantity
		bid[1] = unit_price
	else:
		_futures_bids.erase(mem_key)
	proxy.set_futures_bid(instrument, unit_quantity, unit_price, delivery_market_id)


# Futures order memory is keyed by the delivery body; resolve it from the delivery market.
func _futures_memory_key(instrument: PackedInt32Array, market_id: int) -> PackedInt32Array:
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
## body (see [method _futures_memory_key]).
func _maintain_futures_ask(instrument: PackedInt32Array, mem_key: PackedInt32Array,
		want_quantity: int, want_price: int, min_lot: int, price_tol: float, qty_tol: float,
		delivery_market_id: int) -> void:
	if want_quantity < min_lot:
		if _futures_asks.has(mem_key):
			_set_futures_ask(instrument, 0, want_price, delivery_market_id)
		return
	if !_futures_asks.has(mem_key):
		_set_futures_ask(instrument, want_quantity, want_price, delivery_market_id)
		return
	var have := _futures_asks[mem_key]
	if _needs_requote(have[0], have[1], want_quantity, want_price, price_tol, qty_tol):
		_set_futures_ask(instrument, want_quantity, want_price, delivery_market_id)


## Bid counterpart of [method _maintain_futures_ask].
func _maintain_futures_bid(instrument: PackedInt32Array, mem_key: PackedInt32Array,
		want_quantity: int, want_price: int, min_lot: int, price_tol: float, qty_tol: float,
		delivery_market_id: int) -> void:
	if want_quantity < min_lot:
		if _futures_bids.has(mem_key):
			_set_futures_bid(instrument, 0, want_price, delivery_market_id)
		return
	if !_futures_bids.has(mem_key):
		_set_futures_bid(instrument, want_quantity, want_price, delivery_market_id)
		return
	var have := _futures_bids[mem_key]
	if _needs_requote(have[0], have[1], want_quantity, want_price, price_tol, qty_tol):
		_set_futures_bid(instrument, want_quantity, want_price, delivery_market_id)


# The market purges old-quarter resting orders at rollover without echoes; drop
# matching memory by the same rule so stale entries can't satisfy _maintain_*
# lookups (which would suppress fresh front-quarter quotes).
func _drop_expired_futures_memory() -> void:
	var current_qtr := proxy.ordinal_qtr
	for key in _futures_asks:
		if key[1] < current_qtr:
			_expired_keys.append(key)
	for key in _futures_bids:
		if key[1] < current_qtr:
			_expired_keys.append(key)
	for key in _expired_keys: # duplicates fine; erase is idempotent
		_futures_asks.erase(key)
		_futures_bids.erase(key)
	_expired_keys.clear()


# Sums open long / short position units per resource for delivery at the local
# body, quarters up to and including the current one. Physical settlement lags
# fills by up to ~a trader interval, so executors net these out of want
# quantities (else they re-order already-filled demand every interval).
# proxy.futures_positions is proxy-thread-owned like this AI; direct read is safe.
func _tally_net_positions() -> void:
	_net_long_units.fill(0)
	_net_short_units.fill(0)
	var current_qtr := proxy.ordinal_qtr
	var local_body_id := proxy.market.body_id
	var positions := proxy.futures_positions
	for key in positions:
		if key[2] != local_body_id or key[1] > current_qtr:
			continue
		var signed_qty := positions[key][0]
		if signed_qty > 0.0:
			_net_long_units[key[0]] += int(signed_qty)
		else:
			_net_short_units[key[0]] += int(-signed_qty)


## Brings our standing ask for [param resource_type] in line with the desired
## quantity and price, re-quoting only on material divergence (see
## [method _needs_requote]). A desired quantity below [constant MIN_LOT] drops
## any standing ask.
func _maintain_ask(resource_type: int, want_quantity: int, want_price: int, expiration: int,
		min_lot: int, price_tol: float, qty_tol: float) -> void:
	if want_quantity < min_lot:
		_cancel_ask(resource_type)
		return
	if _spot_ask_ids[resource_type] == -1:
		# No resting order known: post only if nothing is still outstanding (a
		# posted-but-unacknowledged order keeps totals > 0 — wait for its update).
		if _spot_ask_totals[resource_type] == 0:
			_spot_ask(resource_type, want_quantity, want_price, expiration)
		return
	if _needs_requote(_spot_ask_totals[resource_type], _spot_ask_prices[resource_type],
			want_quantity, want_price, price_tol, qty_tol):
		_replace_ask(resource_type, want_quantity, want_price, expiration)


## Bid counterpart of [method _maintain_ask].
func _maintain_bid(resource_type: int, want_quantity: int, want_price: int, expiration: int,
		min_lot: int, price_tol: float, qty_tol: float) -> void:
	if want_quantity < min_lot:
		_cancel_bid(resource_type)
		return
	if _spot_bid_ids[resource_type] == -1:
		if _spot_bid_totals[resource_type] == 0:
			_spot_bid(resource_type, want_quantity, want_price, expiration)
		return
	if _needs_requote(_spot_bid_totals[resource_type], _spot_bid_prices[resource_type],
			want_quantity, want_price, price_tol, qty_tol):
		_replace_bid(resource_type, want_quantity, want_price, expiration)


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
	resource_strategies[resource_type] = _trader_strategy_for_facility(strategy_id)


func _on_ask_updated(resource_type: int, unit_quantity: int, unit_price: int,
		ask_id: int, ask_status: Proxy.TradeOrderStatus) -> void:
	const BOOKED := Proxy.TradeOrderStatus.BOOKED
	const PARTIALLY_FILLED := Proxy.TradeOrderStatus.PARTIALLY_FILLED
	const REPLACED := Proxy.TradeOrderStatus.REPLACED
	if ask_status == BOOKED:
		_spot_ask_ids[resource_type] = ask_id
		return
	if ask_status == REPLACED:
		# unit_quantity is a signed unfilled delta here; the order keeps its id.
		if ask_id == _spot_ask_ids[resource_type]:
			_spot_ask_totals[resource_type] += unit_quantity
			_spot_ask_prices[resource_type] = unit_price
		return
	_spot_ask_totals[resource_type] -= unit_quantity
	if ask_status != PARTIALLY_FILLED and ask_id == _spot_ask_ids[resource_type]:
		_spot_ask_ids[resource_type] = -1
		_spot_ask_prices[resource_type] = 0


func _on_bid_updated(resource_type: int, unit_quantity: int, unit_price: int,
		bid_id: int, bid_status: Proxy.TradeOrderStatus) -> void:
	const BOOKED := Proxy.TradeOrderStatus.BOOKED
	const PARTIALLY_FILLED := Proxy.TradeOrderStatus.PARTIALLY_FILLED
	const REPLACED := Proxy.TradeOrderStatus.REPLACED
	if bid_status == BOOKED:
		_spot_bid_ids[resource_type] = bid_id
		return
	if bid_status == REPLACED:
		# unit_quantity is a signed unfilled delta here; the order keeps its id.
		if bid_id == _spot_bid_ids[resource_type]:
			_spot_bid_totals[resource_type] += unit_quantity
			_spot_bid_prices[resource_type] = unit_price
		return
	_spot_bid_totals[resource_type] -= unit_quantity
	if bid_status != PARTIALLY_FILLED and bid_id == _spot_bid_ids[resource_type]:
		_spot_bid_ids[resource_type] = -1
		_spot_bid_prices[resource_type] = 0


# Mirrors the trader's current ask/bid (carried in every position notification) into
# futures order memory, keyed by [resource_type, ordinal_quarter, body_id]. The position
# value itself is read from proxy.futures_positions; this handler only needs ask/bid.
func _on_futures_positions_changed(position_key: PackedInt32Array, _value: PackedFloat64Array,
		ask: PackedInt32Array, bid: PackedInt32Array) -> void:
	if ask:
		_futures_asks[position_key] = ask
	else:
		_futures_asks.erase(position_key)
	if bid:
		_futures_bids[position_key] = bid
	else:
		_futures_bids.erase(position_key)
