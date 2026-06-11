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

## A centrally cleared, physically-settled forward market for one body.
##
## An instrument is a [resource_type, ordinal_quarter] pair; the delivery body is
## implicit (always this market's body). The current quarter is the near-immediate
## ("spot") case, later quarters forward delivery. Each trader holds at most one
## resting ask and one resting bid per instrument. Orders use SET semantics — a new
## order replaces the resting one, quantity 0 cancels — and never expire, though an
## order for a past quarter is dropped at quarter rollover. Crossing asks and bids
## match at the midpoint price.[br][br]
##
## A match moves no goods; it opens or adjusts a [b]position[/b]: the ask side goes
## (more) short (owes delivery at the body), the bid side (more) long (awaits
## pickup). The quantity sign is the side (+ long, − short); a trader may hold
## either side per instrument and may flip. Read positions on [TraderProxy] and
## [BodyProxy].[br][br]
##
## Physical settlement is bilateral, performed by the [b]short side[/b] over one or
## more intervals: it delivers stock above its reserves to matched longs, and a
## past-due short force-delivers from raw stock and may default on any shortfall.
## The market is the central counterparty; only the cash leg would be centrally
## novated, and cash is not implemented yet (TODO).[br][br]
##
## Published per-resource values: [b]price[/b] — the last current-quarter trade, or
## the best current-quarter ask until one trades, else 0; [b]ask[/b] / [b]bid[/b] —
## the current-quarter top-of-book, 0 for an empty side; [b]volume[/b] — physically
## settled trade units per day, smoothed over ~7 days. [member instruments] also
## carries per-instrument top-of-book for every quarter.[br][br]
##
## Prices and order quantities are integer "ticks": price in integer USD per trade
## unit (assumes [code]IVUnits.USD == 1.0[/code]), quantity in integer "trade units"
## ([code]trade_unit[/code] in [code]resources.tsv[/code]) — not the "sim units"
## used elsewhere ([IVUnits]). A [code]get_*_price[/code] getter returns sim units;
## "unit" in the name ([method get_unit_price]) returns the market-internal
## trade-unit value. Volume is float sim units. A stored 0 price means no current
## price.[br][br]
##
## The read side: AI and GUI read prices, volume, and [member instruments] here, and
## place or change orders via [method TraderProxy.set_ask] /
## [method TraderProxy.set_bid]. Indexed getters are defensive — an out-of-range
## index returns a safe default (see AI_ARCHITECTURE.md, "Trust the server; guard
## against AI").[br][br]
##
## WARNING: lives on the proxy thread; resizable containers and their methods are
## not threadsafe, non-container properties are safe.


var market_id := -1  ## Index into [member ProxyBus.market_proxies].
var body_id := -1  ## [member BodyProxy.body_id] of [member body].

# *****************************************************************************
# persisted

var body: BodyProxy ## Body this market serves.

# *****************************************************************************

## Top-of-book per instrument, keyed by [resource_type, ordinal_quarter] (delivery
## at this market's body). Value is [lowest_ask_price, lowest_ask_quantity,
## highest_bid_price, highest_bid_quantity] in trade units; an empty side reads 0.
## An instrument is present only while it has at least one resting order. Server-set;
## read-only here. WARNING: resizable container maintained on the proxy thread —
## access on the proxy thread only (directly or via the
## [code]get_instrument_*[/code] getters).
var instruments: Dictionary[PackedInt32Array, PackedInt32Array]

# ************************* VIRTUAL & IMPLEMENTATION **************************

func _clear_for_destruction() -> void:
	body = null


# ********************************* PROXY API *********************************

func has_markets() -> bool:
	return true


func get_market() -> MarketProxy:
	return self


# ********************************** READ *************************************
# All threadsafe. Abstract here; the concrete proxy implements.

## Returns the current trade price for [param type] in sim units, or 0.0 if
## no current price.
@abstract func get_price(type: int) -> float


## Returns the current ask price for [param type] in sim units, or 0.0 if no
## current ask.
@abstract func get_ask_price(type: int) -> float


## Returns the current bid price for [param type] in sim units, or 0.0 if no
## current bid.
@abstract func get_bid_price(type: int) -> float


## Returns the Market-internal unit price for [param type], or 0 if no
## current price.
@abstract func get_unit_price(type: int) -> int


## Returns the Market-internal ask unit price for [param type], or 0 if no
## current ask.
@abstract func get_ask_unit_price(type: int) -> int


## Returns the Market-internal bid unit price for [param type], or 0 if no
## current bid.
@abstract func get_bid_unit_price(type: int) -> int


## Returns the physically settled trade volume for [param type] in trade units
## per day, smoothed over 7 days.
@abstract func get_unit_volume(type: int) -> float


# ******************************** AI METHODS *********************************
# Call on proxy thread. Per-instrument top-of-book reads onto [member instruments];
# any quarter >= the current one is a legitimate query (an absent instrument
# reads 0).

## Returns the lowest resting ask price in trade units for the instrument
## [param type] at [param ordinal_quarter], or 0 if no resting ask.
@abstract func get_instrument_ask_unit_price(type: int, ordinal_quarter: int) -> int


## Returns the quantity in trade units at the lowest resting ask for the
## instrument [param type] at [param ordinal_quarter], or 0 if no resting ask.
@abstract func get_instrument_ask_unit_quantity(type: int, ordinal_quarter: int) -> int


## Returns the highest resting bid price in trade units for the instrument
## [param type] at [param ordinal_quarter], or 0 if no resting bid.
@abstract func get_instrument_bid_unit_price(type: int, ordinal_quarter: int) -> int


## Returns the quantity in trade units at the highest resting bid for the
## instrument [param type] at [param ordinal_quarter], or 0 if no resting bid.
@abstract func get_instrument_bid_unit_quantity(type: int, ordinal_quarter: int) -> int
