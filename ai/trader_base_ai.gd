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
static var resource_strategy_defs: Array[Dictionary] = [
	{}, # NEUTRAL
	{}, # JUST_IN_TIME
	{}, # STRATEGIC_RESERVE
	{}, # LIQUIDATE
	{}, # HOARD
	{}, # DUMP
	{}, # MARKET_MAKING
	{}, # SPECULATIVE_LONG
	{}, # SPECULATIVE_SHORT
	{}, # AUTARKIC
	{}, # EXPORT_FOCUS
	{}, # IMPORT_PRIORITY
	{}, # OPPORTUNISTIC
	{}, # WIND_DOWN
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
]


static var _table_n_rows := IVTableData.table_n_rows
static var _times: Array = IVGlobal.times
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

# *****************************************************************************

var _facility_ai: FacilityBaseAI
var _facility: FacilityProxy  ## Paired facility proxy, cached for inventory reads.


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


func process_ai_init() -> void:
	_facility = proxy.facility
	_facility_ai = Proxy.proxy_bus.facility_ais[proxy.facility_id]
	assert(_facility_ai, "TraderBaseAI expects facility's AI to be FacilityBaseAI")
	_facility_ai.facility_resource_strategy_changed.connect(_on_facility_resource_strategy_changed)


func process_ai_interval(_delta: float) -> void:
	# A market maker quotes both sides for its market-relevant resources; every other
	# resource is traded one-sided to service facility operations (see the two helpers).
	const CAN_HAVE_INPUT_OUTPUT := FacilityProxy.InventoryFlags.CAN_HAVE_INPUT_OUTPUT
	const NEUTRAL := ResourceStrategies.NEUTRAL
	const MARKET_MAKING := ResourceStrategies.MARKET_MAKING
	var market := proxy.market
	if !market:
		return
	var time: float = _times[0]
	var epoch_day := int(time / DAY)
	var expiration := epoch_day + ORDER_LIFETIME * int(INTERVAL / DAY)
	var market_maker := _facility.market_maker
	for resource_type in resource_strategies.size():
		if market_maker and (_facility.get_inventory_flags(resource_type) & CAN_HAVE_INPUT_OUTPUT):
			resource_strategies[resource_type] = MARKET_MAKING
			_process_market_making(resource_type, market, expiration)
		else:
			resource_strategies[resource_type] = NEUTRAL
			_process_facility_support(resource_type, market, expiration)


## Trades one resource to service facility operations: a producer sells stock held above
## its reserve target; a consumer buys up toward it. A still-valid standing order is left
## untouched; we re-quote only on material divergence (see [method _maintain_ask] /
## [method _maintain_bid]). Order memory stays truthful via the market's status updates.
func _process_facility_support(resource_type: int, market: MarketProxy, expiration: int) -> void:
	const PRIMARY_PRODUCT := FacilityBaseAI.FacilityResourceStrategies.PRIMARY_PRODUCT
	const SECONDARY_PRODUCT := FacilityBaseAI.FacilityResourceStrategies.SECONDARY_PRODUCT
	const COPRODUCT := FacilityBaseAI.FacilityResourceStrategies.COPRODUCT
	const BYPRODUCT := FacilityBaseAI.FacilityResourceStrategies.BYPRODUCT
	const CRITICAL_INPUT := FacilityBaseAI.FacilityResourceStrategies.CRITICAL_INPUT
	const ROUTINE_INPUT := FacilityBaseAI.FacilityResourceStrategies.ROUTINE_INPUT
	const CONSUMABLE := FacilityBaseAI.FacilityResourceStrategies.CONSUMABLE
	var fstrat := _facility_ai.facility_resource_strategies[resource_type]
	var is_producer := (fstrat == PRIMARY_PRODUCT or fstrat == SECONDARY_PRODUCT
			or fstrat == COPRODUCT or fstrat == BYPRODUCT)
	var is_consumer := (fstrat == CRITICAL_INPUT or fstrat == ROUTINE_INPUT
			or fstrat == CONSUMABLE)
	var reference_price := market.get_spot_unit_price(resource_type)
	if reference_price <= 0 or (not is_producer and not is_consumer):
		# Not trading this resource now: drop any standing orders.
		_cancel_ask(resource_type)
		_cancel_bid(resource_type)
		return
	var multiplier := _trade_unit_multipliers[resource_type]
	var target := (_facility.get_inventory_ops_reserve(resource_type)
			+ _facility.get_inventory_strategic_reserve(resource_type))
	if is_producer:
		_cancel_bid(resource_type)
		var surplus := _facility.get_inventory_stock(resource_type) - target
		var ask_price := maxi(1, floori(reference_price * (1.0 - SPREAD)))
		_maintain_ask(resource_type, int(surplus / multiplier), ask_price, expiration)
	else:
		_cancel_ask(resource_type)
		var deficit := (target - _facility.get_inventory_stock(resource_type)
				- _facility.get_inventory_in_transit(resource_type))
		var bid_price := maxi(1, ceili(reference_price * (1.0 + SPREAD)))
		_maintain_bid(resource_type, int(deficit / multiplier), bid_price, expiration)


## Quotes both sides for a market-relevant resource: bid below mid, ask above mid, so the
## maker earns the spread and provides liquidity (the inverse of facility-support, which
## crosses to transact). Quantities self-balance inventory toward the trade-reserve target
## as fills occur. Falls back to the resource's start_price when no live spot price exists.
func _process_market_making(resource_type: int, market: MarketProxy, expiration: int) -> void:
	var multiplier := _trade_unit_multipliers[resource_type]
	var reference_price := market.get_spot_unit_price(resource_type)
	if reference_price <= 0:
		reference_price = _start_unit_prices[resource_type]
	if reference_price <= 0:
		_cancel_ask(resource_type)
		_cancel_bid(resource_type)
		return
	var ask_price := maxi(1, ceili(reference_price * (1.0 + SPREAD)))
	var bid_price := maxi(1, floori(reference_price * (1.0 - SPREAD)))
	var ops_reserve := _facility.get_inventory_ops_reserve(resource_type)
	var target := ops_reserve + _facility.get_inventory_strategic_reserve(resource_type)
	var ceiling := target + MM_BAND_LOTS * multiplier
	var stock := _facility.get_inventory_stock(resource_type)
	var ask_quantity := int((stock - ops_reserve) / multiplier)
	var bid_quantity := int((ceiling - stock - _facility.get_inventory_in_transit(resource_type))
			/ multiplier)
	_maintain_ask(resource_type, maxi(0, ask_quantity), ask_price, expiration)
	_maintain_bid(resource_type, maxi(0, bid_quantity), bid_price, expiration)


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


## Brings our standing ask for [param resource_type] in line with the desired
## quantity and price, re-quoting only on material divergence (see
## [method _needs_requote]). A desired quantity below [constant MIN_LOT] drops
## any standing ask.
func _maintain_ask(resource_type: int, want_quantity: int, want_price: int, expiration: int
		) -> void:
	if want_quantity < MIN_LOT:
		_cancel_ask(resource_type)
		return
	if _spot_ask_ids[resource_type] == -1:
		# No resting order known: post only if nothing is still outstanding (a
		# posted-but-unacknowledged order keeps totals > 0 — wait for its update).
		if _spot_ask_totals[resource_type] == 0:
			_spot_ask(resource_type, want_quantity, want_price, expiration)
		return
	if _needs_requote(_spot_ask_totals[resource_type], _spot_ask_prices[resource_type],
			want_quantity, want_price):
		_replace_ask(resource_type, want_quantity, want_price, expiration)


## Bid counterpart of [method _maintain_ask].
func _maintain_bid(resource_type: int, want_quantity: int, want_price: int, expiration: int
		) -> void:
	if want_quantity < MIN_LOT:
		_cancel_bid(resource_type)
		return
	if _spot_bid_ids[resource_type] == -1:
		if _spot_bid_totals[resource_type] == 0:
			_spot_bid(resource_type, want_quantity, want_price, expiration)
		return
	if _needs_requote(_spot_bid_totals[resource_type], _spot_bid_prices[resource_type],
			want_quantity, want_price):
		_replace_bid(resource_type, want_quantity, want_price, expiration)


## True when a standing order's price or quantity has drifted from the desired
## values by more than [constant PRICE_TOLERANCE] / [constant QTY_TOLERANCE].
func _needs_requote(have_quantity: int, have_price: int, want_quantity: int, want_price: int
		) -> bool:
	if have_price <= 0 or have_quantity <= 0:
		return true
	if absf(float(want_price - have_price) / have_price) > PRICE_TOLERANCE:
		return true
	if absf(float(want_quantity - have_quantity) / have_quantity) > QTY_TOLERANCE:
		return true
	return false


# ********************************* LISTENERS *********************************

func _on_facility_resource_strategy_changed(_resource_type: int, _strategy_id: int) -> void:
	pass


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
