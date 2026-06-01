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


static var _table_n_rows := IVTableData.table_n_rows


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


# ************************* VIRTUAL & IMPLEMENTATION **************************

func _init() -> void:
	persist.append(&"trader_strategy")
	persist.append(&"resource_strategies")
	persist.append(&"_spot_ask_totals")
	persist.append(&"_spot_bid_totals")
	persist.append(&"_spot_ask_prices")
	persist.append(&"_spot_bid_prices")
	persist.append(&"_spot_ask_ids")
	persist.append(&"_spot_bid_ids")
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


func _clear_for_destruction() -> void:
	proxy = null
	_facility_ai = null


func bind_proxy(proxy_: Proxy) -> void:
	proxy = proxy_ as TraderProxy
	proxy.ask_updated.connect(_on_ask_updated)
	proxy.bid_updated.connect(_on_bid_updated)


func process_ai_init() -> void:
	_facility_ai = proxy.facility.ai as FacilityBaseAI
	assert(_facility_ai, "TraderBaseAI expects facility's AI to be FacilityBaseAI")
	_facility_ai.facility_resource_strategy_changed.connect(_on_facility_resource_strategy_changed)


func process_ai_interval(_delta: float) -> void:
	pass


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


# ********************************* LISTENERS *********************************

func _on_facility_resource_strategy_changed(_resource_type: int, _strategy_id: int) -> void:
	pass


func _on_ask_updated(resource_type: int, unit_quantity: int, _unit_price: int,
		ask_id: int, ask_status: Proxy.TradeOrderStatus) -> void:
	const BOOKED := Proxy.TradeOrderStatus.BOOKED
	const PARTIALLY_FILLED := Proxy.TradeOrderStatus.PARTIALLY_FILLED
	if ask_status == BOOKED:
		_spot_ask_ids[resource_type] = ask_id
		return
	_spot_ask_totals[resource_type] -= unit_quantity
	if ask_status != PARTIALLY_FILLED and ask_id == _spot_ask_ids[resource_type]:
		_spot_ask_ids[resource_type] = -1
		_spot_ask_prices[resource_type] = 0


func _on_bid_updated(resource_type: int, unit_quantity: int, _unit_price: int,
		bid_id: int, bid_status: Proxy.TradeOrderStatus) -> void:
	const BOOKED := Proxy.TradeOrderStatus.BOOKED
	const PARTIALLY_FILLED := Proxy.TradeOrderStatus.PARTIALLY_FILLED
	if bid_status == BOOKED:
		_spot_bid_ids[resource_type] = bid_id
		return
	_spot_bid_totals[resource_type] -= unit_quantity
	if bid_status != PARTIALLY_FILLED and bid_id == _spot_bid_ids[resource_type]:
		_spot_bid_ids[resource_type] = -1
		_spot_bid_prices[resource_type] = 0
