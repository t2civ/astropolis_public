# player_base_ai.gd
# This file is part of Astropolis
# https://t2civ.com
# *****************************************************************************
# Copyright 2019-2026 Charlie Whitfield; ALL RIGHTS RESERVED
# Astropolis is a registered trademark of Charlie Whitfield in the US
# *****************************************************************************
class_name PlayerBaseAI
extends BaseAI

## Default AI for every player. A human player's runs too, and sets whatever its human leaves on
## auto (see [Proxy]).
##
## To implement a custom player AI, extend this class and add
## [code]const OVERRIDE_AI := true[/code].[br][br]
##
## Strategy selections are in part declarative. Note that FacilityBaseAI is
## aware of all of its PlayerBaseAI strategies.


## Emitted when [member global_strategy] changes.
signal global_strategy_changed(strategy_id: int)
## Emitted when an entry in [member player_resource_strategies] changes.
signal player_resource_strategy_changed(resource_type: int, strategy_id: int)
## Emitted when an entry in [member player_facility_strategies] changes.
signal player_facility_strategy_changed(facility_id: int, strategy_id: int)
## Emitted when an entry in [member body_strategies] changes.
signal body_strategy_changed(body_id: int, strategy_id: int)
## Emitted when an entry in [member counterparty_strategies] changes.
signal counterparty_strategy_changed(player_id: int, strategy_id: int)


## The player's grand strategic posture.
enum GlobalStrategies {
	## Starting / no-op stance; no special posture.
	NEUTRAL,
	## Pursue dominance across most sectors; accept high cost to maintain
	## primacy. Analog: post-WWII U.S. grand strategy.
	HEGEMONY,
	## Maintain rough parity with leading rivals; avoid overcommitment in any
	## single arena. Analog: classical European balance-of-power.
	BALANCING,
	## Maximize self-sufficiency in critical sectors; reduce dependency on
	## rivals. Analog: China's "dual circulation," Gaullist independence.
	AUTONOMY,
	## Pursue cooperation, joint ventures, and alliances; accept
	## interdependence. Analog: EU integration, multilateral institutions.
	INTEGRATION,
	## Maximize footprint and economic expansion; accept thinner margins.
	GROWTH,
	## Mature posture; optimize existing portfolio; minimize new commitments.
	## Analog: late-stage industrial economies.
	CONSOLIDATION,
	## Pursue flagship visible achievements over economic optimization.
	## Analog: Apollo program, Olympic hosting, national megaprojects.
	PRESTIGE,
	## Prioritize research, exploration, and knowledge production. Analog:
	## NASA / ESA mission selection, basic-research agencies.
	SCIENCE,
	## Treat all activity as profit-seeking; minimize non-economic missions.
	## Analog: SpaceX / Blue Origin business model.
	COMMERCIAL,
	## Prioritize long-term sustainability, biome health, and biodiversity
	## over output. Analog: green-economy / degrowth advocacy.
	STEWARDSHIP,
	## Pursue new bodies and frontier development at high risk. Analog:
	## age-of-exploration powers, settler colonialism.
	EXPANSION,
	## Crisis posture; preserve core capabilities; accept losses elsewhere.
	## Analog: post-Soviet Russia, post-collapse states.
	SURVIVAL,
	## Late-stage extraction; maximize cash and dividends; minimize
	## reinvestment. Analog: private-equity strip, declining empires
	## monetizing colonies.
	HARVEST,
	N_BASE_GLOBAL_STRATEGIES,
}

## Per-resource player-level strategies — this is how the player wants the
## global market for the resource to look.
enum PlayerResourceStrategies {
	## No special player stance; traders apply their own per-resource
	## strategies independently.
	NEUTRAL,
	## Pursue market-share leadership in production and export; undercut
	## rivals if needed. Analog: Saudi Arabia in oil, China in rare earths.
	DOMINATE_SUPPLY,
	## Be the buyer-of-resort; lock in supply via long-term contracts.
	## Analog: China's commodity-securing diplomacy.
	DOMINATE_DEMAND,
	## Maintain reserves across the portfolio well beyond operational need.
	## Analog: U.S. Strategic Petroleum Reserve, national grain reserves.
	STRATEGIC_STOCKPILE,
	## Produce all internal needs domestically; avoid net imports. Analog:
	## food-security policy, semiconductor independence.
	SELF_SUFFICIENCY,
	## Treat the resource as a primary revenue source; maximize external
	## sales. Analog: petrostates.
	EXPORT_REVENUE,
	## Reduce exposure; phase out production and inventory. Analog: coal
	## divestment, fossil-fuel phase-out commitments.
	DIVEST,
	## Refuse to trade with specified counterparties. Analog: U.S.
	## semiconductor export controls.
	EMBARGO,
	## Buy to maintain a price floor; subsidize producers. Analog:
	## agricultural price supports, sovereign oil-purchase programs.
	PRICE_SUPPORT,
	## Release reserves or overproduce to depress price. Analog: Saudi oil
	## price wars, strategic-reserve releases.
	PRICE_SUPPRESS,
	## Watch closely without active intervention; reserve right to act later.
	## Analog: contingency planning.
	MONITOR,
	N_BASE_PLAYER_RESOURCE_STRATEGIES,
}

## Per-owned-facility player-level strategies — this is how the player views
## the role of each owned facility in the portfolio).
enum PlayerFacilityStrategies {
	## Let the facility's own AI determine its posture.
	NEUTRAL,
	## Showcase asset; priority resourcing and attention. Analog: corporate
	## flagship factory, prestige research center.
	FLAGSHIP,
	## High-growth, high-margin asset; reinvest aggressively. Analog:
	## BCG-matrix "star."
	STAR,
	## Mature profitable asset; optimize for cash extraction; minimal
	## reinvestment. Analog: BCG-matrix "cash cow."
	CASH_COW,
	## Uncertain prospect; monitor closely; willing to cut if it doesn't
	## perform. Analog: BCG-matrix "question mark."
	QUESTION_MARK,
	## Underperformer; candidate for divestiture or closure. Analog:
	## BCG-matrix "dog."
	DOG,
	## Maintain regardless of economics for sovereignty or presence reasons.
	## Analog: forward military bases, polar research stations.
	STRATEGIC_OUTPOST,
	## Sustained at a loss for political reasons; receives transfers from
	## rest of portfolio. Analog: state-owned enterprises kept alive for
	## employment or prestige.
	SUBSIDIZED,
	## Active wind-down; planned closure or sale. Analog: planned plant
	## closure.
	DIVEST,
	N_BASE_PLAYER_FACILITY_STRATEGIES,
}

## Per-body player-level strategies. By convention id 0 is the no-op default.
## Add-on strategies begin at [code]N_BASE_BODY_STRATEGIES[/code].
enum BodyStrategies {
	## No special player stance toward this body.
	NEUTRAL,
	## Concentrate new facility-building and resourcing here. Analog: Project
	## Apollo's Moon focus, Mars-first agencies.
	PRIORITY_DEVELOPMENT,
	## Maintain a footprint but don't grow it aggressively. Analog: minor
	## research outposts.
	SECONDARY_PRESENCE,
	## Treat the body primarily as a resource source; extract aggressively.
	## Analog: colonial extractive economies.
	EXPLOIT,
	## Limit development for environmental or scientific reasons. Analog:
	## protected reserves, Antarctica-treaty-style scientific zones.
	CONSERVE,
	## Wind down all facilities on this body; withdraw entirely.
	EXIT,
	N_BASE_BODY_STRATEGIES,
}

## Per-other-player strategies (diplomatic / trade posture). By convention
## id 0 is the no-op default. Add-on strategies begin at
## [code]N_BASE_COUNTERPARTY_STRATEGIES[/code].
enum CounterpartyStrategies {
	## No special stance toward this counterparty.
	NEUTRAL,
	## Preferred trading partner; willing to support via favorable terms or
	## joint ventures. Analog: NATO members, EU partners.
	ALLY,
	## Normal commercial relationship; treat as standard counterparty.
	PARTNER,
	## Compete actively; deny advantages where practical without open
	## hostility. Analog: U.S.–China economic competition.
	RIVAL,
	## Refuse to deal; pursue measures to harm their economy. Analog: Cold
	## War-era trade blocs.
	HOSTILE,
	## Comprehensive trade prohibition. Analog: U.S. sanctions on Iran, North
	## Korea.
	EMBARGOED,
	## Subordinate counterparty; provide support in exchange for political
	## alignment. Analog: patron-client state relationships.
	CLIENT,
	N_BASE_COUNTERPARTY_STRATEGIES,
}


## Grand-strategy definitions; index = [enum GlobalStrategies] value.
static var global_strategy_defs: Array[Dictionary] = [
	{}, # NEUTRAL
	{}, # HEGEMONY
	{}, # BALANCING
	{}, # AUTONOMY
	{}, # INTEGRATION
	{}, # GROWTH
	{}, # CONSOLIDATION
	{}, # PRESTIGE
	{}, # SCIENCE
	{}, # COMMERCIAL
	{}, # STEWARDSHIP
	{}, # EXPANSION
	{}, # SURVIVAL
	{}, # HARVEST
]

## Per-resource player-level strategy definitions; index =
## [enum PlayerResourceStrategies] value.
static var player_resource_strategy_defs: Array[Dictionary] = [
	{}, # NEUTRAL
	{}, # DOMINATE_SUPPLY
	{}, # DOMINATE_DEMAND
	{}, # STRATEGIC_STOCKPILE
	{}, # SELF_SUFFICIENCY
	{}, # EXPORT_REVENUE
	{}, # DIVEST
	{}, # EMBARGO
	{}, # PRICE_SUPPORT
	{}, # PRICE_SUPPRESS
	{}, # MONITOR
]

## Per-owned-facility player-level strategy definitions; index =
## [enum PlayerFacilityStrategies] value.
static var player_facility_strategy_defs: Array[Dictionary] = [
	{}, # NEUTRAL
	{}, # FLAGSHIP
	{}, # STAR
	{}, # CASH_COW
	{}, # QUESTION_MARK
	{}, # DOG
	{}, # STRATEGIC_OUTPOST
	{}, # SUBSIDIZED
	{}, # DIVEST
]

## Per-body player-level strategy definitions; index = [enum BodyStrategies]
## value.
static var body_strategy_defs: Array[Dictionary] = [
	{}, # NEUTRAL
	{}, # PRIORITY_DEVELOPMENT
	{}, # SECONDARY_PRESENCE
	{}, # EXPLOIT
	{}, # CONSERVE
	{}, # EXIT
]

## Per-counterparty strategy definitions; index =
## [enum CounterpartyStrategies] value.
static var counterparty_strategy_defs: Array[Dictionary] = [
	{}, # NEUTRAL
	{}, # ALLY
	{}, # PARTNER
	{}, # RIVAL
	{}, # HOSTILE
	{}, # EMBARGOED
	{}, # CLIENT
]


## Member names persisted by save/load (interval timing inherited from BaseAI).
const PERSIST_PROPERTIES: Array[StringName] = [
	&"_last_interval",
	&"_next_interval",
	&"global_strategy",
	&"player_resource_strategies",
	&"player_facility_strategies",
	&"body_strategies",
	&"counterparty_strategies",
]


static var _table_n_rows := IVTableData.table_n_rows


var proxy: PlayerProxy


# *****************************************************************************
# persisted

## Grand strategic posture. See [enum GlobalStrategies].
var global_strategy := 0
## Per-resource strategies. See [enum PlayerResourceStrategies].
var player_resource_strategies: PackedInt32Array
## Per-facility strategies keyed by [member FacilityProxy.facility_id]. Absent
## is the same as "NEUTRAL". See [enum PlayerFacilityStrategies].
var player_facility_strategies: Dictionary[int, int]
## Per-body strategies keyed by [member BodyProxy.body_id]. Absent is the same
## as "NEUTRAL". See [enum BodyStrategies].
var body_strategies: Dictionary[int, int]
## Per-counterparty strategies keyed by [member PlayerProxy.player_id]. Absent
## is the same as "NEUTRAL". See [enum CounterpartyStrategies].
var counterparty_strategies: Dictionary[int, int]

# *****************************************************************************


# ************************* VIRTUAL & IMPLEMENTATION **************************

func _init() -> void:
	super()
	var n_resources: int = _table_n_rows[&"resources"]
	player_resource_strategies.resize(n_resources)


func _clear_for_destruction() -> void:
	proxy = null


func bind_proxy(proxy_: Proxy) -> void:
	proxy = proxy_ as PlayerProxy


func ai_init() -> void:
	pass


func process_ai_interval(_delta: float) -> void:
	_author_budget_shares()
	_author_budget_targets()


# ***************************** INTERNAL PRIVATE ******************************

# Sets its treasuries' budget lines (FINANCIAL_MODEL.md, "Budgets"): a polity's government
# treasury's appropriation of each of its agencies, the agency's appropriation_share in
# players.tsv, and its residents' public provision, its own provision_share there, and its
# funding of each of its facilities from each treasury that owns it, the
# facility's funding_share in facilities.tsv, those on auto filling what its human's held lines of
# the same treasury leave, in proportion to their seeds, with the treasury's residual where it has
# one. An agency's treasury has none, so its lines on auto fill its budget. A line no table seeds
# funds all its counterparty lacks. TEMPORARY PATCH: each line is its table seed, read again each
# interval so a line its human returns to auto goes back to it, until the AI weighs its lines.
func _author_budget_shares() -> void:
	const PLAYER_CLASS_AGENCY := Enums.PlayerClasses.PLAYER_CLASS_AGENCY
	const PLAYER_CLASS_COMPANY := Enums.PlayerClasses.PLAYER_CLASS_COMPANY
	var appropriations_paid := IVTableData.db_find(&"line_items", &"unique_type",
			Enums.UniqueLineItems.APPROPRIATIONS_PAID)
	var public_provision_paid := IVTableData.db_find(&"line_items", &"unique_type",
			Enums.UniqueLineItems.PUBLIC_PROVISION_PAID)
	var appropriation_shares: Array[float] = IVTableData.db_tables[&"players"][&"appropriation_share"]
	var provision_shares: Array[float] = IVTableData.db_tables[&"players"][&"provision_share"]
	var funding_items: Array[int] = [
		IVTableData.db_find(&"line_items", &"unique_type",
				Enums.UniqueLineItems.GOVERNMENT_FUNDING_PAID),
		IVTableData.db_find(&"line_items", &"unique_type",
				Enums.UniqueLineItems.CORPORATE_FUNDING_PAID),
	]
	var funding_shares: Array[float] = IVTableData.db_tables[&"facilities"][&"funding_share"]
	var has_residual := proxy.player_class != PLAYER_CLASS_AGENCY
	for account in funding_items.size():
		var keys := PackedInt32Array()
		var seeds := PackedFloat64Array()
		if account == Enums.Accounts.ACCOUNT_GOVERNMENT:
			for agency in Proxy.proxy_bus.player_proxies:
				if (agency == proxy or agency.polity != proxy
						or agency.player_class != PLAYER_CLASS_AGENCY):
					continue
				var player_type := IVTableData.get_row(agency.name)
				if player_type != -1 and appropriation_shares[player_type] >= 0.0:
					keys.append(Utils.get_line_item_key(appropriations_paid, agency.player_id))
					seeds.append(appropriation_shares[player_type])
			var own_type := IVTableData.get_row(proxy.name)
			if own_type != -1 and provision_shares[own_type] >= 0.0:
				keys.append(Utils.get_line_item_key(public_provision_paid))
				seeds.append(provision_shares[own_type])
		for facility in proxy.facilities:
			var facility_type := IVTableData.get_row(facility.name)
			if facility_type == -1 or !(funding_shares[facility_type] >= 0.0):
				continue
			var facility_proxy := facility as FacilityProxy
			var is_owner := proxy.player_class != PLAYER_CLASS_COMPANY
			if account == Enums.Accounts.ACCOUNT_CORPORATE:
				is_owner = (proxy.player_class != PLAYER_CLASS_AGENCY
						and facility_proxy.public_sector < 1.0)
			if !is_owner:
				continue
			keys.append(Utils.get_line_item_key(funding_items[account], facility_proxy.facility_id))
			seeds.append(funding_shares[facility_type])
		var held_shares := PackedFloat64Array()
		var is_any_held := false
		for key in keys:
			var is_held := proxy.is_budget_share_held(key)
			is_any_held = is_any_held or is_held
			held_shares.append(proxy.get_budget_share(key) if is_held else NAN)
		var shares := seeds
		if is_any_held:
			shares = Utils.get_filled_budget_shares(seeds, held_shares, has_residual)
		for i in keys.size():
			proxy.set_budget_share(keys[i], shares[i])


# Has each of its treasuries spend what its revenue gives it (see PlayerProxy.set_budget_target).
func _author_budget_targets() -> void:
	for account in Enums.Accounts.size():
		proxy.set_budget_target(account, NAN)
