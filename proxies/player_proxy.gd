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
## player is one with [member is_facilities] true.
##
## To modify AI, see [BaseAI] and the [code]*_base_ai.gd[/code] files.
##
## WARNING: Lives on the proxy thread. Containers and many methods are not
## threadsafe; accessing non-container properties is safe.


# public read-only
var player_id := -1 ## Index into [member ProxyBus.player_proxies].
var player_class := -1 ## Player class index ([code]PlayerClasses[/code] enum).
var homeworld := "" ## Name of this player's homeworld body.
var tax_rate := 0.0 ## Income-tax rate applied to this player's facilities.
## Its treasuries' budget lines, each kept under the key of the line item it funds by (see
## [method Utils.get_line_item_key]; FINANCIAL_MODEL.md, "Budgets"): a facility's funding by
## facility, a share of the treasury's budget over a year, and an agency's appropriation by agency,
## a share of its polity's income for now. A line with no share funds all its counterparty lacks.
## Resizable container — not threadsafe! Use [method set_budget_share].
var budget_shares: Dictionary[int, float] = {}

# *****************************************************************************
# persisted

var polity: PlayerProxy ## Self if [member player_class] == [code]PLAYER_CLASS_POLITY[/code].
## This player's treasury facility (its homeworld facility at game start; may be null).
var administrative_center: FacilityProxy
var is_facilities := true ## True while this player owns at least one facility ("alive" test).
## Facilities owned by this player. Resizable container — not threadsafe!
var facilities: Array[Proxy] = []

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


## Returns this player's [member facilities]. proxy thread only!
func get_facilities() -> Array[Proxy]:
	return facilities


## Returns the share the budget line kept under [param key] has (see [member budget_shares]), or
## INF where it has none and funds all its counterparty lacks. proxy thread only!
func get_budget_share(key: int) -> float:
	return budget_shares.get(key, INF)


# ******************************** AI METHODS *********************************

## Registers [param facility] under this player. Marks the player "alive".
@abstract func add_facility(facility: Proxy) -> void


## Removes [param facility] from this player. Updates [member is_facilities]
## to reflect whether the player still owns any facilities.
@abstract func remove_facility(facility: Proxy) -> void


## Sets the share of the budget line kept under [param key] (see [member budget_shares]) to
## [param value] (>= 0.0), or INF to fund all its counterparty lacks.
## Proxy-authoritative: this change flows proxy -> server. No-op on a negative value or NAN.
@abstract func set_budget_share(key: int, value: float) -> void
