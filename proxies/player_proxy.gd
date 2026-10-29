# player_proxy.gd
# This file is part of Astropolis
# https://t2civ.com
# *****************************************************************************
# Copyright 2019-2026 Charlie Whitfield; ALL RIGHTS RESERVED
# Astropolis is a registered trademark of Charlie Whitfield in the US
# *****************************************************************************
@abstract
class_name PlayerProxy
extends Proxy

## [PlayerProxy] represents a polity, faction, or sub-entity that owns
## [FacilityProxy]s.
##
## Server-side Player aggregates component data from facilities and pushes
## changes to PlayerProxy. Players are never removed during a game; an "alive"
## player is one with [member has_facilities] true.
##
## To modify AI, see [BaseAI] and the [code]*_base_ai.gd[/code] files.
##
## WARNING: Lives on the proxy thread. Containers and many methods are not
## threadsafe; accessing non-container properties is safe.


# public read-only
var player_id := -1 ## Index into [member ProxyBus.player_proxies].
var player_class := -1 ## Player class index ([code]PlayerClasses[/code] enum).
var homeworld := "" ## Name of this player's homeworld body.
## A polity's taxes (FINANCIAL_MODEL.md, "Taxes"): its corporate tax, a share of its facilities'
## private operating income; its income tax on wages, the payroll tax, a share of the wages they
## pay, and on the interest and the dividends its residents are paid; and its wealth tax, a share a
## year of what its residents hold past [member wealth_tax_threshold], a share of their mean wealth.
## Its agencies' and companies' facilities pay its rates.
var corporate_tax_rate := 0.0
var payroll_tax_rate := 0.0 ## See [member corporate_tax_rate].
var interest_tax_rate := 0.0 ## See [member corporate_tax_rate].
var dividend_tax_rate := 0.0 ## See [member corporate_tax_rate].
var wealth_tax_rate := 0.0 ## See [member corporate_tax_rate].
var wealth_tax_threshold := 0.0 ## See [member corporate_tax_rate].
## True if a human plays this player, as set when the game started; only a playable player may be.
## Its AI still runs, and sets whatever its human leaves on auto. Whether this machine's human
## plays it is [method is_local_human].
var human := false
## Its treasuries' budget lines, each kept under the key of the line item it funds by (see
## [method Utils.get_line_item_key]; FINANCIAL_MODEL.md, "Budgets"), each a share of the
## treasury's budget over a year: a facility's funding by facility, an agency's appropriation by
## agency, and a polity's public provision. A line with no share funds all its counterparty lacks,
## but provision, which a budget with no share for it doesn't buy.
## Resizable container — not threadsafe! Use [method set_budget_share].
var budget_shares: Dictionary[int, float] = {}
## What each of its treasuries is set to spend a year past its committed lines, by
## [code]Enums.Accounts[/code], NAN where it spends what its revenue gives it (see
## [member budgets]). Resizable container — not threadsafe! Use [method set_budget_target].
var budget_targets := PackedFloat64Array()
## What each of its treasuries has to spend a year past what its committed lines take, what its
## discretionary lines share, by [code]Enums.Accounts[/code], as of its administrative center's last
## interval (FINANCIAL_MODEL.md, "Budgets"); empty where it has none. Server-authoritative.
## Resizable container — not threadsafe! Use [method get_budget].
var budgets := PackedFloat64Array()
## Its treasuries' lines a year, as of its administrative center's last interval, each kept under
## the key of the line item that books its use (see [method Utils.get_line_item_key]): each
## treasury's interest, a committed line, its funding by facility and appropriation by agency, and
## a polity's public provision, INF where a line funds all its counterparty lacks. Server-authoritative.
## Resizable container — not threadsafe! Use [method get_budget_line].
var budget_lines: Dictionary[int, float] = {}

# *****************************************************************************
# persisted

var polity: PlayerProxy ## Self if [member player_class] == [code]PLAYER_CLASS_POLITY[/code].
## This player's treasury facility (its homeworld facility at game start; may be null).
var administrative_center: FacilityProxy
var has_facilities := true ## True while this player owns at least one facility ("alive" test).
## Facilities owned by this player. Resizable container — not threadsafe!
var facilities: Array[Proxy] = []
## The budget lines held off auto, by key, each at its share (see [method hold_budget_share]).
## Resizable container — not threadsafe!
var held_budget_shares: Dictionary[int, float] = {}
## The budget targets held off auto, by [code]Enums.Accounts[/code], each at its target (see
## [method hold_budget_target]). Resizable container — not threadsafe!
var held_budget_targets: Dictionary[int, float] = {}

# *****************************************************************************


# ************************* VIRTUAL & IMPLEMENTATION **************************

func _clear_for_destruction() -> void:
	polity = null
	administrative_center = null
	facilities.clear()


# ***************************** THREAD-SAFE READ ******************************

func has_development() -> bool:
	return true


func get_player_name() -> StringName:
	return name


func get_player_class() -> int:
	return player_class


func get_polity_name() -> StringName:
	return polity.name


## Returns true if this machine's human plays this player, and so may adjust it in the GUI: in a
## single-player game, a [member human] player.
func is_local_human() -> bool:
	return human


## Returns this player's [member facilities]. proxy thread only!
func get_facilities() -> Array[Proxy]:
	return facilities


## Returns the share the budget line kept under [param key] has (see [member budget_shares]), or
## INF where it has none and funds all its counterparty lacks. proxy thread only!
func get_budget_share(key: int) -> float:
	return budget_shares.get(key, INF)


## Returns what the treasury [param account], an [code]Enums.Accounts[/code], has to spend a year
## past its committed lines (see [member budgets]), or NAN where the player has no treasuries.
## proxy thread only!
func get_budget(account: int) -> float:
	if account < 0 or account >= budgets.size():
		return NAN
	return budgets[account]


## Returns the line a year kept under [param key] (see [member budget_lines]): INF where it funds
## all its counterparty lacks, and NAN where there is none. proxy thread only!
func get_budget_line(key: int) -> float:
	return budget_lines.get(key, NAN)


## Returns what the treasury [param account], an [code]Enums.Accounts[/code], is set to spend a
## year past its committed lines (see [member budget_targets]), or NAN where it spends what its
## revenue gives it. proxy thread only!
func get_budget_target(account: int) -> float:
	if account < 0 or account >= budget_targets.size():
		return NAN
	return budget_targets[account]


## Returns true if the budget line kept under [param key] is held off auto (see
## [method hold_budget_share]). proxy thread only!
func is_budget_share_held(key: int) -> bool:
	return held_budget_shares.has(key)


## Returns true if the budget target of the treasury [param account] is held off auto (see
## [method hold_budget_target]). proxy thread only!
func is_budget_target_held(account: int) -> bool:
	return held_budget_targets.has(account)


# ******************************** AI METHODS *********************************

## Registers [param facility] under this player. Marks the player "alive".
@abstract func add_facility(facility: Proxy) -> void


## Removes [param facility] from this player. Updates [member has_facilities]
## to reflect whether the player still owns any facilities.
@abstract func remove_facility(facility: Proxy) -> void


## Sets the share of the budget line kept under [param key] (see [member budget_shares]) to
## [param value] (>= 0.0), or INF to fund all its counterparty lacks.
## Proxy-authoritative: this change flows proxy -> server. No-op on a negative value or NAN, or
## where the line is held (see [method hold_budget_share]).
@abstract func set_budget_share(key: int, value: float) -> void


## Holds the budget line kept under [param key] off auto at the share [param value], as
## [method set_budget_share] takes it, until [method release_budget_share]. No-op on a negative
## value or NAN.
@abstract func hold_budget_share(key: int, value: float) -> void


## Returns the budget line kept under [param key] to auto, where [method set_budget_share] sets it
## again. It keeps its share until then.
func release_budget_share(key: int) -> void:
	held_budget_shares.erase(key)


## Sets what the treasury [param account], an [code]Enums.Accounts[/code], spends a year past its
## committed lines to [param value] (>= 0.0), or NAN to have it spend what its revenue gives it
## (the default). Its discretionary lines are shares of it. Proxy-authoritative: this change flows
## proxy -> server. No-op on an out-of-range account or a negative value, or where the target is
## held (see [method hold_budget_target]).
@abstract func set_budget_target(account: int, value: float) -> void


## Holds the budget target of the treasury [param account] off auto at [param value], as
## [method set_budget_target] takes it, until [method release_budget_target]. No-op on an
## out-of-range account or a negative value.
@abstract func hold_budget_target(account: int, value: float) -> void


## Returns the budget target of the treasury [param account] to auto, where
## [method set_budget_target] sets it again. It keeps its target until then.
func release_budget_target(account: int) -> void:
	held_budget_targets.erase(account)
