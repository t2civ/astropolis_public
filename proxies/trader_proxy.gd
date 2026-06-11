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
## [MarketProxy] at the facility's body.
##
## To modify AI, see [BaseAI] and the [code]*_base_ai.gd[/code] files.
##
## WARNING: Lives on the proxy thread. Containers and many methods are not
## threadsafe; accessing non-container properties is safe.


## Emitted when a position changes. [param position_key] is the 3-element
## key [resource_type, ordinal_quarter, body_id] (the delivery body). [param value] is
## the resulting position [signed_unit_quantity, unit_price] in trade units (empty if
## the position cleared); the quantity sign gives the side (+ long, − short). [param
## ask] and [param bid] are the trader's outstanding ask and bid [unit_quantity,
## unit_price] in trade units for this instrument; an empty array is a cleared ask or bid.
signal positions_changed(position_key: PackedInt32Array, value: PackedFloat64Array,
		ask: PackedInt32Array, bid: PackedInt32Array)


## Upper bound on forward orders: [method set_ask] / [method set_bid] accept
## instrument ordinal quarters in [code][ordinal_qtr, ordinal_qtr +
## MAX_FORWARD_QUARTERS)[/code]; a call outside the range is a no-op.
const MAX_FORWARD_QUARTERS := 40


var trader_id := -1  ## Index in [member ProxyBus.trader_proxies].
var player_id := -1  ## [member PlayerProxy.player_id] of the owning facility's player.
var facility_id := -1  ## [member FacilityProxy.facility_id] of [member facility].
var market_id := -1  ## [member MarketProxy.market_id] of [member market].

# *****************************************************************************
# persisted

var facility: FacilityProxy  ## Owning [FacilityProxy]. Immutable after init.
var market: MarketProxy  ## May change at runtime. Lives on markets thread!

# *****************************************************************************

## Positions indexed by the 3-element position key [resource_type,
## ordinal_quarter, body_id] (the delivery body). Values are [signed_unit_quantity,
## unit_price] in trade units; the quantity sign gives the side (+ long / pick up at
## the body, − short / drop off).
var positions: Dictionary[PackedInt32Array, PackedFloat64Array] = {}


# ************************* VIRTUAL & IMPLEMENTATION **************************

func _init() -> void:
	super()


func _clear_for_destruction() -> void:
	# Breaks the FacilityProxy.trader ↔ TraderProxy.facility 2-cycle.
	facility = null
	market = null


# ***************************** THREAD-SAFE READ ******************************

## Returns this trader's [MarketProxy]. Mutable but always exists after init.
func get_market() -> MarketProxy:
	return market


# ******************************** AI METHODS *********************************
# Call on proxy thread.

## Adds, replaces, or cancels this trader's sell (ask) order. [param
## instrument] is composed as [resource_type, ordinal_quarter]; the delivery body
## is the body of [param delivery_market_id]. Cancels if [param unit_quantity] is
## 0. [param unit_quantity] and [param unit_price] are in trade units. The
## resulting position side (long/short) follows from matching; a trader may hold
## either side at any delivery body and may flip. The current quarter is the
## near-immediate ("spot") case; later quarters are forward delivery, accepted
## up to (excluding) ordinal_qtr + [constant MAX_FORWARD_QUARTERS]. [param
## delivery_market_id] is the market at the delivery body; the caller already
## holds it, since it must query that market to see available instruments.
@abstract func set_ask(instrument: PackedInt32Array, unit_quantity: int,
		unit_price: int, delivery_market_id: int) -> void


## Adds, replaces, or cancels this trader's buy (bid) order. See [param
## instrument] composition and params in the ask counterpart [method
## set_ask]. The resulting position side (long/short) follows from
## matching; a trader may hold either side at any delivery body and may flip.
@abstract func set_bid(instrument: PackedInt32Array, unit_quantity: int,
		unit_price: int, delivery_market_id: int) -> void
