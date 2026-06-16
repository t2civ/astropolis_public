# enums.gd
# This file is part of Astropolis
# https://t2civ.com
# *****************************************************************************
# Copyright 2019-2026 Charlie Whitfield; ALL RIGHTS RESERVED
# Astropolis is a registered trademark of Charlie Whitfield in the US
# *****************************************************************************
class_name Enums
extends Object

## Astropolis-wide enums shared across server, proxy, and table-driven code.


## Generic 'type' enums may be used and re-used in different contexts.
enum Types {
	ALL,
	ELECTRICITY,
	EX_PLANET_SPACE,
	MOONS,
	OFF_HOMEWORLD,
	PLANETOIDS,
	PLANETS,
}

## Trade classes group resources by handling (electricity, bulk, cryogenic,
## etc.) for trade and storage logic.
enum TradeClasses {
	TRADE_CLASS_ELECTRICITY,
	TRADE_CLASS_BULK,
	TRADE_CLASS_ICE,
	TRADE_CLASS_LIQUID,
	TRADE_CLASS_CRYOGENIC,
	TRADE_CLASS_PRECIOUS, ## Special handling is required.
	TRADE_CLASS_CYBER, ## Tradable in the universal cyber market.
}

## Top-level kind of a [PlayerProxy] (state polity, space agency, or
## private company).
enum PlayerClasses {
	PLAYER_CLASS_POLITY,
	PLAYER_CLASS_AGENCY,
	PLAYER_CLASS_COMPANY,
}

## Process category that determines how an operation runs (renewable,
## conversion, extraction, or dev/debug).
enum ProcessGroup {
	PROCESS_GROUP_RENEWABLE,
	PROCESS_GROUP_CONVERSION,
	PROCESS_GROUP_EXTRACTION,
	PROCESS_GROUP_DONT_PROCESS, # dev/debug
}

## Financial statement that a [code]line_items.tsv[/code] line item is reported on.
## Drives quarter behavior: income and cash-flow leaves are flows (reset at quarter
## rollover); balance leaves are stocks (run).
enum StatementTypes {
	STATEMENT_INCOME,
	STATEMENT_CASH_FLOW,
	STATEMENT_BALANCE,
}

## Balance-sheet classification of a [code]line_items.tsv[/code] balance leaf, routing
## it into the assets, liabilities, or equity subtotal. Unused for flow (income and
## cash-flow) leaves.
enum BalanceClasses {
	BALANCE_CLASS_ASSET,
	BALANCE_CLASS_LIABILITY,
	BALANCE_CLASS_EQUITY,
}

## Random-player selection options for game start.
enum RandomPlayer {
	RANDOM,
#	RANDOM_SPACE_AGENCY,
#	RANDOM_SPACE_COMPANY,
}

## Astropolis additions to ivoyager [code]IVBody.BodyFlags[/code]. Bits 40+
## (ivoyager reserves the lower bits).
enum BodyFlags2 {
	BODYFLAGS_STATION = 1 << 40,
	BODYFLAGS_GUI_HAS_MOONS = 1 << 41,
	BODYFLAGS_GUI_HAS_ONE_MOON = 1 << 42, # Earth
	BODYFLAGS_GUI_CLOUDS = 1 << 43, # Gas Giants; for Development "surface" replacement
	BODYFLAGS_GUI_CLOUDS_SURFACE = 1 << 44, # Venus only; for Development "surface" replacement
}
