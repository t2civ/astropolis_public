# market_proxy.gd
# This file is part of Astropolis
# https://t2civ.com
# *****************************************************************************
# Copyright 2019-2026 Charlie Whitfield; ALL RIGHTS RESERVED
# Astropolis is a registered trademark of Charlie Whitfield in the US
# *****************************************************************************
@abstract
class_name MarketProxy
extends Proxy

## Provides resource spot prices and a market for spot trading.
##
## A [BodyProxy] with a [FacilityProxy] always gains a market. At minimum, the
## market provides "spot" prices for relevant resources, determined either
## via spot market trades or by fiat using a market maker functionality.[br][br]
##
## If a body has >1 facilities, the market provides a resource spot market.
## The spot market processes spot orders for within-body, immediate-delivery
## trades only. These orders originate from local [TraderProxy]s only.[br][br]
##
## All trade orders are implemented as "limit orders". Traders can specify a
## "market order", in effect, by specifying a permissive price and near-future
## expiration.[br][br]
##
## Times, prices, and order quantities are integer "ticks": time in integer
## seconds (assumes [code]IVUnits.SECOND == 1.0[/code]), price in integer USD
## (assumes [code]IVUnits.USD == 1.0[/code]), and order quantity in integer
## "trade units" (specified by [code]trade_unit[/code] in
## [code]resources.tsv[/code]). The API convention provides regular sim
## units in [method get_spot_price] and uses "unit" in the name for
## Market-internal values ([method get_spot_unit_price]).[br][br]
##
## Arrays are indexed by [code]resource_type[/code] unless indicated otherwise.
## A stored value of 0 in any internal "price" variable means N/A or no current
## price (sim-unit getters return 0.0 in that case).
##
## Indexed getters are defensive: an out-of-range index returns a safe default
## (0.0 or 0). See AI_ARCHITECTURE.md, "Trust the server; guard against AI".
##
## WARNING: Lives on the proxy thread. Resizable containers and associated
## methods are not threadsafe; non-container properties are safe.


var market_id := -1  ## Index into [member ProxyBus.market_proxies].
var body: BodyProxy ## Body of the spot market.

## Top-of-book snapshot for each available futures instrument. Keys are composed as
## [resource_type, ordinal_quarter, delivery_id]; values are [lowest_ask_price,
## lowest_ask_quantity, highest_bid_price, highest_bid_quantity], all in trade units.
## An instrument is present iff it currently has at least one ask or bid; a side with
## no orders has price and quantity 0. Server-maintained and read-only here.
var futures_instruments: Dictionary[PackedInt32Array, PackedInt32Array]

# ************************* VIRTUAL & IMPLEMENTATION **************************

func _clear_for_destruction() -> void:
	body = null


# ********************************* PROXY API *********************************

func has_markets() -> bool:
	return true


func get_market(_player_id: int) -> MarketProxy:
	return self


# ********************************** READ *************************************
# All threadsafe. Abstract here; the concrete proxy implements.

## Returns the current trade price for [param type] in sim units, or 0.0 if
## no current price.
@abstract func get_spot_price(type: int) -> float


## Returns the current ask price for [param type] in sim units, or 0.0 if no
## current ask.
@abstract func get_spot_ask_price(type: int) -> float


## Returns the current bid price for [param type] in sim units, or 0.0 if no
## current bid.
@abstract func get_spot_bid_price(type: int) -> float


## Returns the Market-internal unit price for [param type], or 0 if no
## current price.
@abstract func get_spot_unit_price(type: int) -> int


## Returns the Market-internal ask unit price for [param type], or 0 if no
## current ask.
@abstract func get_spot_ask_unit_price(type: int) -> int


## Returns the Market-internal bid unit price for [param type], or 0 if no
## current bid.
@abstract func get_spot_bid_unit_price(type: int) -> int


## Returns the trading volume for [param type] in trade units per day, smoothed
## over 7 days.
@abstract func get_spot_unit_volume(type: int) -> float
