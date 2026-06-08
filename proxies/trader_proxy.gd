# trader_proxy.gd
# This file is part of Astropolis
# https://t2civ.com
# *****************************************************************************
# Copyright 2019-2026 Charlie Whitfield; ALL RIGHTS RESERVED
# Astropolis is a registered trademark of Charlie Whitfield in the US
# *****************************************************************************
@abstract
class_name TraderProxy
extends Proxy

## [TraderProxy] buys and sells resources for a specific [FacilityProxy].
##
## A trader is paired 1-to-1 with a facility and trades on its behalf via the
## [BrokerProxy] at the facility's body.
##
## To modify AI, see [BaseAI] and the [code]*_base_ai.gd[/code] files.
##
## WARNING: Lives on the proxy thread. Containers and many methods are not
## threadsafe; accessing non-container properties is safe.


signal ask_updated(resource_type: int, unit_quantity: int, unit_price: int,
		ask_id: int, ask_status: TradeOrderStatus)
signal bid_updated(resource_type: int, unit_quantity: int, unit_price: int,
		bid_id: int, bid_status: TradeOrderStatus)


var trader_id := -1  ## Index in [member ProxyBus.trader_proxies].
var facility: FacilityProxy  ## Owning [FacilityProxy]. Immutable after init.
var facility_id := -1  ## [member FacilityProxy.facility_id] of [member facility].
var broker: BrokerProxy  ## Immutable after init. Lives on markets thread!
var broker_id := -1  ## [member BrokerProxy.broker_id] of [member broker].
var market: MarketProxy  ## May change at runtime. Lives on markets thread!
var market_id := -1  ## [member MarketProxy.market_id] of [member market].


# ************************* VIRTUAL & IMPLEMENTATION **************************

func _init() -> void:
	super()


func _clear_for_destruction() -> void:
	# Breaks the FacilityProxy.trader ↔ TraderProxy.facility 2-cycle.
	facility = null
	broker = null
	market = null


# ***************************** THREAD-SAFE READ ******************************

## Returns this trader's [MarketProxy]. Mutable but always exists after init.
func get_market(_player_id: int) -> MarketProxy:
	return market


# ******************************** AI METHODS *********************************
# Call on proxy thread.

## Adds a spot sell order. [param unit_quantity] and [param unit_price] are
## with respect to trade unit. [param expiration] is epoch day.
@abstract func spot_ask(resource_type: int, unit_quantity: int, unit_price: int,
		expiration: int) -> void


## Removes a spot sell order if not processed already.
@abstract func cancel_spot_ask(ask_id: int) -> void


## Reprices and resizes a resting spot sell order in place, keeping its id.
## [param new_quantity] becomes the new unfilled quantity and [param new_unit_price]
## the new price (both with respect to trade unit); [param expiration] is epoch day.
## No effect if the order was already filled or cancelled.
@abstract func replace_spot_ask(ask_id: int, new_quantity: int, new_unit_price: int,
		expiration: int) -> void


## Adds a spot buy order. [param unit_quantity] and [param unit_price] are
## with respect to trade unit. [param expiration] is epoch day.
@abstract func spot_bid(resource_type: int, unit_quantity: int, unit_price: int,
		expiration: int) -> void


## Removes a spot buy order if not processed already.
@abstract func cancel_spot_bid(bid_id: int) -> void


## Reprices and resizes a resting spot buy order in place, keeping its id.
## [param new_quantity] becomes the new unfilled quantity and [param new_unit_price]
## the new price (both with respect to trade unit); [param expiration] is epoch day.
## No effect if the order was already filled or cancelled.
@abstract func replace_spot_bid(bid_id: int, new_quantity: int, new_unit_price: int,
		expiration: int) -> void


## Adds, replaces, or cancels this facility's futures sell (ask) order. [param
## instrument] is composed as [resource_type, ordinal_quarter, delivery_id].
## Cancels if [param unit_quantity] is 0. [param unit_quantity] and [param
## unit_price] are in trade units. A delivery_id equal to this trader's
## facility_id opens or replaces a long (inbound) position; any other
## facility_id offsets an existing short (outbound) position. If ordinal_quarter
## is current quarter and delivery_id is same body, acts as a spot trade.
## [param delivery_market_id] is the market at the delivery facility's body; the caller
## already holds it, since it must query that market to see available instruments.
@warning_ignore("shadowed_variable")
@abstract func set_futures_ask(instrument: PackedInt32Array, unit_quantity: int,
		unit_price: int, delivery_market_id: int) -> void


## Adds, replaces, or cancels this facility's futures buy (bid) order. See
## [param instrument] composition and params in ask counterpart [method
## set_futures_ask]. A delivery_id other than this trader's facility_id opens
## or grows a short (outbound) position; the trader's facility_id offsets an
## exsiting long (inbound) position. If ordinal_quarter is current quarter and
## delivery_id is same body, acts as a spot trade.
## [param delivery_market_id] is the market at the delivery facility's body; the caller
## already holds it, since it must query that market to see available instruments.
@warning_ignore("shadowed_variable")
@abstract func set_futures_bid(instrument: PackedInt32Array, unit_quantity: int,
		unit_price: int, delivery_market_id: int) -> void
