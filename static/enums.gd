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
	EX_PLANET_SPACE,
	MOONS,
	OFF_HOMEWORLD,
	PLANETOIDS,
	PLANETS,
}


## Identifies a resource that code finds without its name, for presentation only (such as
## the development "power" statistic); no mechanic treats it differently. Each member must
## exist exactly once in resources.tsv.
enum UniqueResources {
	ELECTRICITY,
}


## Identifies a module as having unique internal (hard-coded) mechanics. One
## and only one must exist in modules.tsv.
enum UniqueModules {
	CONSTRUCTION_YARDS,
}


## Identifies an operation with unique internal (hard-coded) mechanics. Each
## member must exist exactly once in operations.tsv. These are the renewable-power
## operations, whose run rate the simulation sets from a computed environmental
## capacity factor (by body and site) rather than from a player or market lever.
enum UniqueOperations {
	SOLAR_POWER,
	WIND_POWER,
	HYDROPOWER,
	GEOTHERMAL_POWER,
	TIDAL_POWER,
}


## Identifies a line item with unique internal (hard-coded) mechanics, booked
## directly from engine code (not referenced by operations.tsv or
## facility_classes.tsv). Each member must exist exactly once in line_items.tsv.
enum UniqueLineItems {
	OPERATION_MAINTENANCE,
	MODULE_MAINTENANCE,
	ADMINISTRATION,
	STAFFING,
	RESEARCH_DEVELOPMENT,
	TRADING_GAINS,
	TRADING_LOSSES,
	EXCHANGE_FEES,
	EXCHANGE_TAKE_REVENUE,
	EXCHANGE_TAKE_COGS,
	EXCHANGE_CLEARING_GAINS,
	DEFAULT_PENALTIES,
	DEFAULT_COMPENSATION,
	DISPOSAL_GAINS,
	DISPOSAL_LOSSES,
	SETTLEMENT_RECEIPTS,
	SETTLEMENT_PAYMENTS,
	PL_SETTLEMENTS,
	PL_PAYMENTS,
	FEES_PAID,
	BONDS_POSTED,
	BONDS_RELEASED,
	COMPENSATION_RECEIPTS,
	EXCHANGE_TAKE_RECEIVED,
	EXCHANGE_TAKE_PAID,
	CASH,
	BOND_ESCROW,
	TRADE_RECEIVABLES,
	FIXED_ASSETS,
	INCOME_TAX,
	TAX_REVENUE,
	TAX_PAID,
	TAX_RECEIVED,
	RESIDENT_RECEIPTS,
	WAGES_PAID,
	PAYOUTS_PAID,
	GOVERNMENT_PAYOUTS_RECEIVED,
	FUNDING_RECEIVED,
	GOVERNMENT_FUNDING_PAID,
	GOVERNMENT_CASH,
	CORPORATE_CASH,
	CORPORATE_PAYOUTS_RECEIVED,
	CORPORATE_FUNDING_PAID,
	APPROPRIATIONS_RECEIVED,
	APPROPRIATIONS_PAID,
	TRANSFERS_PAID,
	LEVIES_RECEIVED,
	DIVIDENDS_PAID,
	CAPITAL_PAID_IN,
	DEBT,
	BORROWED,
	REPAID,
	INTEREST_PAID,
	INTEREST_EXPENSE,
	GOVERNMENT_DEBT,
	GOVERNMENT_BORROWED,
	GOVERNMENT_REPAID,
	GOVERNMENT_INTEREST_PAID,
	INTEREST_RECEIVED,
	CORPORATE_DEBT,
	CORPORATE_BORROWED,
	CORPORATE_REPAID,
	CORPORATE_INTEREST_PAID,
	GOVERNMENT_GRANTED,
	CORPORATE_GRANTED,
	APPROPRIATION_RETURNS_RECEIVED,
	APPROPRIATION_RETURNS_PAID,
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

## Body stratum that receives a resource's disposed-of surplus (the
## [code]disposal_sink[/code] column of [code]resources.tsv[/code]).
enum DisposalSinks {
	DISPOSAL_SINK_ATMOSPHERE,
	DISPOSAL_SINK_SURFACE,
}

## Top-level kind of a [PlayerProxy] (state polity, space agency, or
## private company).
enum PlayerClasses {
	PLAYER_CLASS_POLITY,
	PLAYER_CLASS_AGENCY,
	PLAYER_CLASS_COMPANY,
}

## Life stage of a population type's age buckets: what wants, work, reports and targets read,
## however the type cuts its buckets (the [code]first_adult_bucket[/code] and
## [code]first_elder_bucket[/code] columns of [code]populations.tsv[/code]; see
## POPULATION_MODEL.md, "Demographics").
enum LifeStages {
	LIFE_STAGE_YOUNG,
	LIFE_STAGE_ADULT,
	LIFE_STAGE_ELDER,
}

## Tier of a need (the [code]tier[/code] column of [code]needs.tsv[/code]): what going without
## it does and how fast. The residents secure their existence first (POPULATION_MODEL.md,
## "Needs").
enum NeedTiers {
	NEED_TIER_EXISTENCE,
	NEED_TIER_WELLBEING,
	NEED_TIER_FULFILLMENT,
}

## Process category that determines how an operation's run is decided (see
## operations.schema.md, operation_group).
enum OperationGroup {
	OPERATION_GROUP_PRODUCTION,
	OPERATION_GROUP_BUILDOUT,
	OPERATION_GROUP_DECOMMISSIONING,
	OPERATION_GROUP_EXCHANGE,
	OPERATION_GROUP_DONT_PROCESS, # dev/debug
}

## What an operation does in the light (the [code]light_role[/code] column of
## [code]operations.tsv[/code]): which share of an interval it runs in, sunlight or shade, and so
## what it makes of a resource that has a shade form. Blank, it runs the same in light and shade.
enum LightRoles {
	LIGHT_ROLE_SOLAR, ## Makes only in sunlight, drawing shade to pair with what it makes.
	LIGHT_ROLE_PEAKER, ## Runs in sunlight and in shade apart.
	LIGHT_ROLE_STORAGE, ## Moves what it draws in sunlight into the shade.
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

## Account a [code]line_items.tsv[/code] line item belongs to: a blank cell (−1) is
## the facility's own, and the others a player's treasuries, booked at its
## administrative center (FINANCIAL_MODEL.md, "The accounts").
enum Accounts {
	ACCOUNT_GOVERNMENT,
	ACCOUNT_CORPORATE,
}

## What a [code]line_items.tsv[/code] line item is kept per (its [code]keyed_by[/code] column): a
## blank cell (−1) is kept once, and the others once per facility or player it moves money to or
## from, each a line of its own (see [method Utils.get_line_item_key]; FINANCIAL_MODEL.md, "Line
## items").
enum Counterparties {
	COUNTERPARTY_FACILITY,
	COUNTERPARTY_PLAYER,
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
