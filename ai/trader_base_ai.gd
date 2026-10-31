# trader_base_ai.gd
# This file is part of Astropolis
# https://t2civ.com
# *****************************************************************************
# Copyright 2019-2026 Charlie Whitfield; ALL RIGHTS RESERVED
# Astropolis is a registered trademark of Charlie Whitfield in the US
# *****************************************************************************
class_name TraderBaseAI
extends BaseAI

## Default AI for every trader.
##
## To implement a custom trader AI, extend this class and add
## [code]const OVERRIDE_AI := true[/code].[br][br]
##
## Traders are paired 1-to-1 with facilities. This trader contracts toward its facility's desired
## rate of each resource over the coming horizon, within what its facility's critical rate and its
## credit allow, and skews its quotes toward its facility's own price while what it
## contracted falls short; in a two-sided posture it also keeps a quote standing on the other side
## (TRADE_MODEL.md, "The facility trader"). It reads its
## facility's rates and prices, never its stock, and trades in the posture and resource strategies
## its facility's AI authors (it trusts that these already incorporate player strategies).[br][br]
##
## A facility-paired trader orders delivery/pickup [b]only at its own facility's locus[/b], or at
## the cyber market for a cyber resource: the order helpers resolve the delivery market
## internally. The future transport trader will be this same class running different strategies,
## discriminated by [member TraderProxy.facility_id] == -1 — all facility-paired behavior is gated
## on that pairing.[br][br]
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
	## Make the facility's locus's market: keep a quote standing on both sides of every resource
	## the facility deals in, so the market always has a price (see TRADE_MODEL.md, "Market
	## makers"). The posture of a market-making facility's trader. Analog: a wholesale merchant; a
	## spaceport's commodity desk.
	MARKET_MAKING,
	N_BASE_TRADER_STRATEGIES,
}

## Per-resource trading strategies.
enum ResourceStrategies {
	## No special stance: contract toward the facility's desired rate on whichever side it asks.
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


## Share of the way, in ratio, from the market's reference price toward its facility's own local
## price that a trader skews its quotes at a full gap between what it has contracted and what it
## would: up while short of what it would buy, where its facility prices the resource above the
## market, and down while short of what it would sell, where its facility prices it below (def key
## [code]skew[/code] overrides per resource strategy).
const SKEW := 0.5
## Least a trader's skew takes its facility's price to be, as a share of the market's: a facility
## that prices a resource at nothing would give it away.
const OWN_PRICE_FLOOR := 0.001
## How many of its facility's time horizons ahead a trader contracts (def key
## [code]contract_horizons[/code] overrides per resource strategy): about a year for a facility on
## Earth, further for one resupplied seldom, as far as [constant TraderProxy.MAX_FORWARD_QUARTERS]
## reaches. The current quarter is always held whole.
const CONTRACT_HORIZONS := 12.0
## Share of its facility's credit a trader may commit: what its open longs and resting bids will
## cost less what its open shorts will earn (def key [code]credit_share[/code] overrides per
## posture).
const CREDIT_SHARE := 0.5
## Minimum order size in trade units; smaller wants are not quoted.
const MIN_LOT := 1
## Re-quote a standing order when its price drifts beyond this fraction of its price.
const PRICE_TOLERANCE := 0.005
## Re-quote a standing order when its desired quantity drifts beyond this fraction.
const QTY_TOLERANCE := 0.1


## Trader-posture strategy definitions; index = [enum TraderStrategies] value.
## [code]credit_share[/code] sets the share of its facility's credit the trader may commit (see
## [constant CREDIT_SHARE]). The [code]two_sided[/code] switch makes markets in every resource the
## facility deals in (see [method is_market_resource]), for which the facility AI holds stock
## against its market's swings: the trader keeps a quote standing on the side its gap doesn't ask
## for (see [method _plan_resource]).
static var trader_strategy_defs: Array[Dictionary] = [
	{}, # INIT
	{}, # FACILITY_SUPPORT
	{}, # PROFIT_FOCUS
	{}, # CONSERVATIVE
	{}, # OPPORTUNISTIC
	{}, # POLICY_AGENT
	{&"two_sided": true}, # MARKET_MAKING
]

## Per-resource strategy definitions; index = [enum ResourceStrategies] value. The switches
## [code]buy[/code] and [code]sell[/code] select the sides on which the trader contracts toward its
## facility's desired rate; an entry with neither trades nothing. Tuning keys: [code]skew[/code]
## (see [constant SKEW]), [code]contract_horizons[/code] (see [constant CONTRACT_HORIZONS]),
## [code]min_lot[/code], [code]price_tol[/code] and [code]qty_tol[/code]. A stockpile or a
## shortage reaches the trader through the desired rate, which the facility's levels move.
static var resource_strategy_defs: Array[Dictionary] = [
	{&"buy": true, &"sell": true}, # NEUTRAL
	{}, # JUST_IN_TIME
	{&"buy": true, &"sell": true}, # STRATEGIC_RESERVE
	{}, # LIQUIDATE
	{}, # HOARD
	{}, # DUMP
	{}, # SPECULATIVE_LONG
	{}, # SPECULATIVE_SHORT
	{}, # AUTARKIC
	{&"buy": true, &"sell": true}, # EXPORT_FOCUS
	{&"buy": true, &"sell": true}, # IMPORT_PRIORITY
	{}, # OPPORTUNISTIC
	{&"sell": true}, # WIND_DOWN
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
## Per-resource 0/1; trade_class == CYBER (orders route to the cyber market). Built once.
static var _cyber_resource: PackedByteArray


var proxy: TraderProxy


# *****************************************************************************
# persisted

## Trader-posture strategy. See [enum TraderStrategies].
var trader_strategy := 0
## Per-resource strategies. See [enum ResourceStrategies].
var resource_strategies: PackedInt32Array


## Memory of open asks, keyed at this trader's order-key width (see [member _key_width]):
## the 2-element instrument [resource_type, ordinal_quarter] for a facility trader (one
## market per resource makes the locus redundant), or 3-element [resource_type,
## ordinal_quarter, locus_id] for a transport trader (which trades a resource at many
## loci). Values are [unit_quantity, unit_price] in trade units; unique per key. Mirrors
## the market's resting ask, refreshed via position notifications.
var _asks: Dictionary[PackedInt32Array, PackedInt64Array] = {}

## Memory of open bids, keyed like [member _asks] with values [unit_quantity, unit_price]
## in trade units.
var _bids: Dictionary[PackedInt32Array, PackedInt64Array] = {}

# *****************************************************************************

var _facility_ai: FacilityBaseAI
var _facility: FacilityProxy  # paired facility proxy

# Facility-trader auxiliary: this trader's positions keyed by the 2-element instrument
# [resource_type, ordinal_quarter], locus projected out (unique per instrument because a
# facility trades each resource in exactly one market — home or cyber). Maintained in
# _on_positions_changed, seeded in ai_init. Stays empty for a transport trader, which is
# inherently multi-locus and works off proxy.positions directly.
var _positions_by_instrument: Dictionary[PackedInt32Array, PackedFloat64Array] = {}
# This trader's cyber market id, resolved once in ai_init; the routing target for cyber
# resources (see _delivery_market_id). -1 for a transport trader.
var _cyber_market_id := -1
# Width of this trader's order keys (_asks / _bids / _on_positions_changed): 2 for a
# facility trader ([resource, quarter]), 3 for a transport trader ([resource, quarter,
# locus_id]). Set in ai_init.
var _key_width := 2
# Per resource, the span of its flow this interval's quotes contract, what its facility foresees of
# how far ahead they reach, in sim time; 0.0 where it isn't traded.
var _windows: PackedFloat64Array
# This interval's quotes, one entry per instrument: its key, the ask and the bid its gap wants and
# those a two-sided posture keeps standing on the other side (trade units), the ask's and the bid's
# price, and the resource's def. Built by _plan_resource, cut by _bound_commitments and placed by
# _place_quotes.
var _plan_keys: Array[PackedInt32Array] = []
var _plan_asks: PackedInt64Array
var _plan_bids: PackedInt64Array
var _plan_standing_asks: PackedInt64Array
var _plan_standing_bids: PackedInt64Array
var _plan_ask_prices: PackedInt64Array
var _plan_bid_prices: PackedInt64Array
var _plan_defs: Array[Dictionary] = []
# The instruments this interval's quotes cover; an order resting on any other is cancelled.
var _planned: Dictionary[PackedInt32Array, bool] = {}
# Collect-then-act key scratch for _drop_expired_memory() and _cancel_unplanned().
var _expired_keys: Array[PackedInt32Array] = []


# ********************************** STATIC ***********************************

## True if inventory [param flags] mark a resource a market-making posture makes a
## market in: tradable, and one the facility deals in.
static func is_market_resource(flags: int) -> bool:
	const TRADABLE := FacilityProxy.InventoryFlags.TRADABLE
	const IS_MARKET := FacilityProxy.InventoryFlags.IS_MARKET
	return (flags & TRADABLE) != 0 and (flags & IS_MARKET) != 0


# ************************* VIRTUAL & IMPLEMENTATION **************************

func _init() -> void:
	super()
	var n_resources: int = _table_n_rows[&"resources"]
	resource_strategies.resize(n_resources)
	_windows.resize(n_resources)
	if _cyber_resource.is_empty():
		const TRADE_CLASS_CYBER := Enums.TradeClasses.TRADE_CLASS_CYBER
		var resources_table: Dictionary[StringName, Array] = IVTableData.db_tables[&"resources"]
		var trade_classes := PackedInt32Array(resources_table[&"trade_class"])
		_cyber_resource.resize(trade_classes.size())
		for resource_type in trade_classes.size():
			_cyber_resource[resource_type] = 1 if trade_classes[resource_type] == TRADE_CLASS_CYBER else 0


func _clear_for_destruction() -> void:
	proxy = null
	_facility_ai = null
	_facility = null


func bind_proxy(proxy_: Proxy) -> void:
	proxy = proxy_ as TraderProxy


func ai_init() -> void:
	proxy.positions_changed.connect(_on_positions_changed)
	if proxy.facility_id == -1:
		_key_width = 3 # transport: order keys carry the delivery locus (see _key_width)
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


## Each interval contracts every resource its facility flags
## [constant FacilityProxy.InventoryFlags.TRADABLE] toward the facility's desired rate, as its
## strategy's def directs, a two-sided posture quoting both sides of each one its facility deals in
## (see [method _plan_resource]); cuts what it would bid to what its facility's credit allows (see
## [method _bound_commitments]); then places the quotes and cancels any order resting outside them.
func process_ai_interval(_delta: float) -> void:
	const TRADABLE := FacilityProxy.InventoryFlags.TRADABLE
	var market := proxy.market
	if !market or !_facility:
		return # no market yet, or transport trader (transport strategies TBD)
	_drop_expired_memory()
	_clear_plan()
	var posture_def := trader_strategy_defs[trader_strategy]
	var two_sided: bool = posture_def.get(&"two_sided", false)
	for resource_type in resource_strategies.size():
		if _stop:
			return # cooperative bail; nothing placed, so the last interval's quotes stand
		_windows[resource_type] = 0.0
		var flags := _facility.get_inventory_flags(resource_type)
		if !(flags & TRADABLE):
			continue
		var def := resource_strategy_defs[resource_strategies[resource_type]]
		_plan_resource(resource_type, market, def, two_sided and is_market_resource(flags))
	_bound_commitments(posture_def)
	_place_quotes()


## Plans this interval's quotes for [param resource_type] under its strategy's [param def]. The
## trader contracts the coming window, the def's [code]contract_horizons[/code] of its facility's
## time horizon, and the rest of the current quarter at least, toward the desired rate D: each
## quarter the window spans wants D's flow, read off its curve over price at that quarter's own
## price, times what its facility foresees of the part of the window it holds, and the current
## quarter D's step besides, once,
## net of the position there, as a bid or an ask. Each quarter's target is held to the def's sides,
## never below what the facility could spare (-C, the critical rate, its flow and step alike) and
## at least C where the facility must take. Each quarter's quotes skew off its own price (see
## [method MarketProxy.get_instrument_unit_price]) toward the facility's local price, as far as the
## def's [code]skew[/code] times the quarter's gap as a share of what it would contract there, each
## side quoting that limit, a bid no more than the facility's price unless it buys back a short
## and an ask no less unless it offers back a long.[br][br]
##
## With [param standing], a two-sided posture's, each quarter also keeps a lot (the def's
## [code]min_lot[/code]) standing on the side its gap doesn't ask for, where the def trades that
## side: an ask where the facility could spare a lot over the quarter's part of the window, a bid
## where it uses one. Toward the facility's price it skews the def's whole skew, and on the far side
## it stands at that price, so its market always has a price, and one that follows its facilities
## (TRADE_MODEL.md, "Market makers").
func _plan_resource(resource_type: int, market: MarketProxy, def: Dictionary, standing: bool
		) -> void:
	var buys: bool = def.get(&"buy", false)
	var sells: bool = def.get(&"sell", false)
	var desired_step := _facility.get_inventory_desired_step(resource_type)
	var reference_price := market.get_unit_price(resource_type)
	if !(buys or sells) or is_nan(desired_step) or reference_price <= 0:
		return # not traded: any order resting on it is cancelled with the unplanned
	var critical_step := _facility.get_inventory_critical_step(resource_type)
	var curve_price := _facility.get_inventory_curve_price(resource_type)
	if !(curve_price > 0.0):
		return
	var desired_flows := _facility.get_inventory_desired_flow_curve(resource_type)
	var critical_flow := _facility.get_inventory_critical_flow(resource_type)
	var critical := _facility.get_inventory_critical_rate(resource_type)
	var contract_horizons: float = def.get(&"contract_horizons", CONTRACT_HORIZONS)
	var horizon := _facility.time_horizon
	var window := maxf(horizon * contract_horizons, 0.0)
	var multiplier := _trade_unit_multipliers[resource_type]
	var spare := maxf(-critical, 0.0) # the most its facility could spare
	var min_lot: int = def.get(&"min_lot", MIN_LOT)
	var use := _facility.get_inventory_use(resource_type) if standing else 0.0
	var now := _last_interval
	var current_quarter := proxy.ordinal_qtr
	# Settlement delivers a current quarter's position by the quarter's end, so the window holds that
	# time whole and what deliveries draw from it falls out of the target with them.
	var end := maxf(now + window, Utils.get_time_at_ordinal_quarter(current_quarter + 1))
	_windows[resource_type] = TraderProxy.get_foreseen_span(end - now, horizon)
	var local_price := _facility.get_inventory_local_price(resource_type) * multiplier
	var skew_share: float = def.get(&"skew", SKEW)
	var quarter_price := reference_price # this quarter's own, or the quarter before it's
	var quarter := current_quarter
	var start := now
	while start < end and quarter < current_quarter + TraderProxy.MAX_FORWARD_QUARTERS:
		var quarter_end := Utils.get_time_at_ordinal_quarter(quarter + 1)
		var held := minf(end, quarter_end) - start
		var key := PackedInt32Array([resource_type, quarter])
		var is_current := quarter == current_quarter
		# A buyer takes all it contracted, and a need contracted at once for a year held a spike
		# of a month's use for all of it. What a quarter holds counts as far as its facility
		# foresees it.
		var foreseen := held
		if held > 0.0:
			foreseen = (TraderProxy.get_foreseen_span(start + held - now, horizon)
					- TraderProxy.get_foreseen_span(start - now, horizon))
		start = quarter_end
		quarter += 1
		if held <= 0.0:
			continue
		# What a later quarter trades is its own price: priced off the current quarter's, a book a
		# quarter ahead moved no price at all.
		if !is_current:
			var own := market.get_instrument_unit_price(resource_type, key[1])
			if own > 0:
				quarter_price = own
		var position: PackedFloat64Array = _positions_by_instrument.get(key, PackedFloat64Array())
		var position_quantity := position[0] if position else 0.0
		# Each quarter wants what its facility's flow would be at that quarter's price: at the
		# current quarter's, a later quarter's price moved and no quantity answered it.
		var factor := quarter_price / multiplier / curve_price
		var wanted := FacilityProxy.get_curve_value(desired_flows, factor) * foreseen
		var must := critical_flow * foreseen
		if is_current:
			wanted += desired_step
			must += critical_step
		if !buys:
			wanted = minf(wanted, 0.0)
		if !sells:
			wanted = maxf(wanted, 0.0)
		wanted = maxf(wanted, minf(must, 0.0)) # gives no more than its facility could spare
		if buys:
			wanted = maxf(wanted, must) # takes at least what its facility must
		var want := roundi(wanted / multiplier - position_quantity)
		var ask := maxi(-want, 0)
		var bid := maxi(want, 0)
		var standing_ask := 0
		var standing_bid := 0
		# A lot gives the market its price: quotes sized to the facility's flow traded on the gap
		# between prices as much as on the desired rate. A bid where the facility uses nothing is
		# demand nobody has, which held a good nobody used at whatever its makers last traded it
		# among themselves.
		if standing:
			if (sells and ask < min_lot
					and position_quantity + spare * held / multiplier >= min_lot):
				standing_ask = min_lot
				ask = 0
			if buys and bid < min_lot and use * held / multiplier >= min_lot:
				standing_bid = min_lot
				bid = 0
		# A gap as a share of what it would contract: scaled to an unbounded desired rate, a seller
		# held to the little it could spare skewed next to nothing, and one stale ask held a market
		# at many times what every facility valued it.
		var target := absf(wanted / multiplier)
		var gap_share := clampf(want / maxf(target, absi(want)), -1.0, 1.0) if want else 0.0
		# The facility's own price says how far the market's stands from where the facility would
		# trade no more: a fixed step took years to close seeds ten or a hundred times off. A buyer
		# skews up only where its facility prices the resource above the market, a seller down only
		# below; one that prices it at nothing skews toward the floor.
		var own_price := maxf(local_price, OWN_PRICE_FLOOR * quarter_price)
		var price_gap := log(own_price / quarter_price)
		var full_skew := skew_share * price_gap
		var skew := 0.0
		if price_gap * gap_share > 0.0:
			skew = absf(gap_share) * full_skew
		var limit_price := quarter_price * exp(skew)
		# Bidding the reference where its facility priced the good below it, every buyer carried a
		# reference one trader had lifted into the next contracts, and asking it where above, a
		# seller sold what its own facility needed more (TRADE_MODEL.md, "Where it stands", a trader
		# held to its own price). A position it closes trades at the market's price: a buy-back held
		# to its facility's left a seller owing past what it could spare for longer.
		var bid_limit := limit_price if position_quantity < 0.0 else minf(limit_price, own_price)
		var ask_limit := limit_price if position_quantity > 0.0 else maxf(limit_price, own_price)
		var bid_price := maxi(floori(bid_limit), 1)
		var ask_price := maxi(ceili(ask_limit), 1)
		# Quoted off the reference alone, a market whose traders' gaps had closed held its last
		# trade's price while every facility's own moved away from it. Each quotes its own limit,
		# and a cross matches at the midpoint (TRADE_MODEL.md, "The price"). A standing quote stays
		# clear of the trader's own on the other side, which wouldn't trade.
		var skewed_price := quarter_price * exp(full_skew)
		var standing_bid_price := floori(minf(own_price, skewed_price))
		if standing_ask:
			ask_price = maxi(ceili(maxf(own_price, skewed_price)),
					(bid_price if bid else standing_bid_price) + 1)
		if standing_bid:
			bid_price = standing_bid_price
			if ask or standing_ask:
				bid_price = mini(bid_price, ask_price - 1)
			if bid_price < 1:
				standing_bid = 0
				bid_price = maxi(floori(limit_price), 1)
		_plan_keys.append(key)
		_plan_asks.append(ask)
		_plan_bids.append(bid)
		_plan_standing_asks.append(standing_ask)
		_plan_standing_bids.append(standing_bid)
		_plan_ask_prices.append(ask_price)
		_plan_bid_prices.append(bid_price)
		_plan_defs.append(def)


## Cuts this interval's planned bids in proportion so that what the trader commits, its open
## positions net (longs to pay less shorts to be paid) and the bids, stays within its posture's
## [code]credit_share[/code] of its facility's credit (see [member FacilityProxy.credit]). The bids
## its gaps ask for come first; the standing bids of a two-sided posture take what room they
## leave.
func _bound_commitments(posture_def: Dictionary) -> void:
	var payable := 0.0
	for key in _positions_by_instrument:
		var position := _positions_by_instrument[key]
		payable += position[0] * position[1]
	var bid_value := 0.0
	var standing_value := 0.0
	for i in _plan_keys.size():
		bid_value += float(_plan_bids[i]) * _plan_bid_prices[i]
		standing_value += float(_plan_standing_bids[i]) * _plan_bid_prices[i]
	if !(bid_value + standing_value > 0.0):
		return
	var credit_share: float = posture_def.get(&"credit_share", CREDIT_SHARE)
	var room := credit_share * _facility.credit - payable
	if bid_value + standing_value <= room:
		return
	var share := 1.0
	if bid_value > 0.0:
		share = clampf(room / bid_value, 0.0, 1.0)
	var standing_share := 1.0
	if standing_value > 0.0:
		standing_share = clampf((room - bid_value) / standing_value, 0.0, 1.0)
	for i in _plan_keys.size():
		_plan_bids[i] = floori(_plan_bids[i] * share)
		_plan_standing_bids[i] = floori(_plan_standing_bids[i] * standing_share)


## Places this interval's planned quotes, each side re-quoted only where it drifted past its def's
## tolerances, and cancels every order resting on an instrument the plan doesn't cover. A quarter's
## gap wants one side only, so the other side's order, if any, is cancelled with it unless a
## two-sided posture keeps a quote standing there.
func _place_quotes() -> void:
	for i in _plan_keys.size():
		var key := _plan_keys[i]
		var def := _plan_defs[i]
		var min_lot: int = def.get(&"min_lot", MIN_LOT)
		var price_tol: float = def.get(&"price_tol", PRICE_TOLERANCE)
		var qty_tol: float = def.get(&"qty_tol", QTY_TOLERANCE)
		_maintain_ask(key, _plan_asks[i] + _plan_standing_asks[i], _plan_ask_prices[i], min_lot,
				price_tol, qty_tol)
		var bid_quantity := _plan_bids[i] + _plan_standing_bids[i]
		var bid_price := _plan_bid_prices[i]
		var bid_price_tol := price_tol
		if _asks.has(key):
			# An ask kept within its tolerance can stand below the price planned for it, and the
			# market removes its own bid at or above it unmatched.
			var ask_price := _asks[key][1]
			bid_price = mini(bid_price, ask_price - 1)
			if bid_price < 1:
				bid_quantity = 0
			if _bids.has(key) and _bids[key][1] >= ask_price:
				bid_price_tol = 0.0
		_maintain_bid(key, bid_quantity, maxi(bid_price, 1), min_lot, bid_price_tol, qty_tol)
		_planned[key] = true
	_cancel_unplanned()


# ******************************* AI / PROXY API ******************************
# Call on proxy thread.

## Adds, replaces, or cancels a sell (ask) order. See [method
## TraderProxy.set_ask] for instrument composition and params, including
## [param market_id] (the market at the delivery locus). This method
## updates AI ask memory on the outgoing call. Rejects if specified
## ordinal_quarter < proxy.ordinal_qtr (proxy would reject if it went through
## here).
func _set_ask(instrument: PackedInt32Array, unit_quantity: int,
		unit_price: int, delivery_market_id: int) -> void:
	if instrument[1] < proxy.ordinal_qtr:
		return
	var mem_key := instrument.duplicate() # facility: 2-element [resource, quarter]
	if _key_width == 3: # transport: append the delivery locus (see _key_width)
		mem_key.append(_market_locus_id(delivery_market_id))
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
## [param market_id] (the market at the delivery locus). This method
## updates AI bid memory on the outgoing call. Rejects if specified
## ordinal_quarter < proxy.ordinal_qtr (proxy would reject if it went through
## here).
func _set_bid(instrument: PackedInt32Array, unit_quantity: int,
		unit_price: int, delivery_market_id: int) -> void:
	if instrument[1] < proxy.ordinal_qtr:
		return
	var mem_key := instrument.duplicate() # facility: 2-element [resource, quarter]
	if _key_width == 3: # transport: append the delivery locus (see _key_width)
		mem_key.append(_market_locus_id(delivery_market_id))
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


# Resolves which market an order for [param resource_type] routes to: the cyber market
# for a cyber resource, else this facility trader's home locus market.
func _delivery_market_id(resource_type: int) -> int:
	return _cyber_market_id if _cyber_resource[resource_type] else proxy.market_id


# Resolves the delivery locus of [param market_id], for a transport trader's 3-element
# order key (see _key_width). Not called on the facility path (_key_width == 2).
func _market_locus_id(market_id: int) -> int:
	var market_proxy: MarketProxy = Proxy.proxy_bus.market_proxies[market_id]
	assert(market_proxy and market_proxy.locus, "delivery market/locus not resolved")
	return market_proxy.locus.locus_id


# The market purges old-quarter resting orders at rollover without echoes; drop
# matching memory by the same rule so stale entries can't satisfy _maintain_*
# lookups (which would suppress fresh front-quarter quotes).
func _drop_expired_memory() -> void:
	var current_qtr := proxy.ordinal_qtr
	for key in _asks:
		if key[1] < current_qtr:
			_expired_keys.append(key)
	for key in _bids:
		if key[1] < current_qtr:
			_expired_keys.append(key)
	for key in _expired_keys: # duplicates fine; erase is idempotent
		_asks.erase(key)
		_bids.erase(key)
	_expired_keys.clear()


# Empties the last interval's plan.
func _clear_plan() -> void:
	_plan_keys.clear()
	_plan_asks.clear()
	_plan_bids.clear()
	_plan_standing_asks.clear()
	_plan_standing_bids.clear()
	_plan_ask_prices.clear()
	_plan_bid_prices.clear()
	_plan_defs.clear()
	_planned.clear()


# Cancels every order resting on an instrument this interval's plan doesn't cover: a resource no
# longer traded, a quarter the window has left, a strategy that dropped a side.
func _cancel_unplanned() -> void:
	for key in _asks: # collect-then-act; _set_* mutates the dicts
		if !_planned.has(key):
			_expired_keys.append(key)
	for key in _bids:
		if !_planned.has(key):
			_expired_keys.append(key)
	for key in _expired_keys: # duplicates fine; the has() checks make this idempotent
		var market_id := _delivery_market_id(key[0])
		if _asks.has(key):
			_set_ask(key, 0, 1, market_id) # placeholder price: the proxy rejects price <= 0
		if _bids.has(key):
			_set_bid(key, 0, 1, market_id)
	_expired_keys.clear()


## True when a standing order's price or quantity has drifted from the desired values by more
## than [param price_tol] / [param qty_tol] (see [constant PRICE_TOLERANCE] and
## [constant QTY_TOLERANCE]).
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
# delivery locus for a transport — see _key_width). The locus-less position view
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
