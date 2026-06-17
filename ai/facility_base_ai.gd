# facility_base_ai.gd
# This file is part of Astropolis
# https://t2civ.com
# *****************************************************************************
# Copyright 2019-2026 Charlie Whitfield; ALL RIGHTS RESERVED
# Astropolis is a registered trademark of Charlie Whitfield in the US
# *****************************************************************************
class_name FacilityBaseAI
extends BaseAI

## Default AI for facilities the local player owns.
##
## To implement a custom facility AI, extend this class and add
## [code]const OVERRIDE_AI := true[/code].[br][br]
##
## Strategy selections are in part declarative. Note that the paired
## TraderBaseAI is aware of this AI's resource strategies.


## Emitted when [member facility_strategy] changes.
signal facility_strategy_changed(strategy_id: int)
## Emitted when an entry in [member facility_resource_strategies] changes.
signal facility_resource_strategy_changed(resource_type: int, strategy_id: int)
## Emitted when an entry in [member operation_strategies] changes.
signal operation_strategy_changed(operation_type: int, strategy_id: int)


## Facility-posture strategies.
enum FacilityStrategies {
	## Starting / no-op stance; no special posture.
	NEUTRAL,
	## Pursue expansion of capacity and footprint; accept thinner margins.
	## Analog: scale-up startup, frontier development.
	GROWTH,
	## Optimize ROI on existing capacity; defer expansion. Analog: mature
	## industrial site tuning throughput.
	PROFITABILITY,
	## Spread operations across resources and process groups to reduce
	## concentration risk. Analog: integrated conglomerate.
	DIVERSIFICATION,
	## Focus capacity on the most profitable or strategic operations; let
	## others wither. Analog: hyper-focused supplier (e.g., a single-product
	## foundry).
	SPECIALIZATION,
	## Maintain presence and capability regardless of economics. Analog:
	## forward military base, polar research station.
	STRATEGIC_OUTPOST,
	## Early-stage facility; prioritize learning, training, and capability
	## over current profit. Analog: pilot plant, new colony.
	DEVELOPMENT,
	## Mature operations; replace capacity as it depreciates; resist large
	## swings. Analog: established refinery or mill.
	STEADY_STATE,
	## Orderly wind-down of all operations; preserve safety; do not reinvest.
	## Analog: planned plant closure.
	DECOMMISSIONING,
	## Crisis mode; activate all available capacity; suspend normal economic
	## constraints. Analog: wartime production, disaster response.
	EMERGENCY,
	N_BASE_FACILITY_STRATEGIES,
}

## Per-resource facility strategies — how this facility views a particular
## resource given its own operations, inventory state, and player strategies.
enum FacilityResourceStrategies {
	## No special facility-level stance; trader applies its own per-resource
	## strategy independently.
	NEUTRAL,
	## Primary saleable output the facility exists to produce; the operations
	## that produce it carry the facility's revenue thesis. Analog: a copper
	## smelter's cathode copper.
	PRIMARY_PRODUCT,
	## Additional saleable output run only when margins justify; capacity is
	## discretionary. Analog: a refinery's specialty chemicals or asphalt.
	SECONDARY_PRODUCT,
	## Output produced in fixed ratio with another (usually primary) output;
	## cannot be throttled independently — must be sold, stored, or its
	## producing op must idle. Analog: a refinery's LPG alongside gasoline,
	## sulfur from sour-crude refining.
	COPRODUCT,
	## Low-value output of a producing operation; not a profit center, but
	## must move off-site to keep the line running. Analog: scrap metal,
	## slag, spent caustic.
	BYPRODUCT,
	## Non-commodity output that must be disposed of (vented, dumped, stored
	## as overburden); operations are constrained by available disposal
	## capacity. Analog: flare gas, mine tailings, CO2 emissions.
	WASTE,
	## Input without which primary operations halt; supply continuity matters
	## more than per-unit price. Analog: a fab's ultra-pure water and
	## photoresist; a smelter's contracted electricity.
	CRITICAL_INPUT,
	## Operating input with adequate market liquidity and substitutability;
	## buy lean at prevailing prices. Analog: a factory's commodity natural
	## gas or merchant-grade steel.
	ROUTINE_INPUT,
	## Small-quantity consumables, reagents, MRO supplies; cost of doing
	## business with no strategic weight. Analog: lubricants, catalyst
	## makeup, filter media.
	CONSUMABLE,
	## Produced and consumed within the facility's own process loop; external
	## trade is unwanted or impractical. Analog: a chemical complex's hydrogen
	## produced and consumed inside the integrated fenceline; reflux streams.
	CLOSED_LOOP_INTERMEDIATE,
	## Accumulate inventory well beyond operating need; pull supply from the
	## market or run producing ops at strategic-hold rates. Analog: a mill
	## stockpiling a sanction-vulnerable ore.
	STRATEGIC_RESERVE,
	## Inventory is being held or worked as a directional trading position
	## rather than for operational continuity. Analog: a refiner taking a
	## crude position outside normal hedging.
	SPECULATIVE_POSITION,
	## The facility is exiting this resource long-term; wind down ops that
	## produce or consume it and run inventory down. Analog: a multi-product
	## plant exiting a product line; a utility's coal phase-down.
	PHASE_OUT,
	## The facility acts as a two-sided market maker for this tradable resource it
	## can produce and/or consume; the paired trader quotes both bid and ask. Folds
	## the facility's market-maker identity into the per-resource strategy channel.
	MARKET_MAKE,
	N_BASE_FACILITY_RESOURCE_STRATEGIES,
}

## Per-operation strategies.
enum OperationStrategies {
	## Delegate to server-side automation hints (the [code]FROM_SERVER_MASK[/code]
	## half of operations flags); minimal AI intervention.
	AUTO,
	## Run when gross margin is positive; ramp up in favorable periods; idle
	## when unprofitable. Analog: merchant power plant on the spot market.
	PROFIT_MAXIMIZE,
	## Run at full capacity regardless of margin. Analog: wartime production
	## quota, strategic stockpile build.
	VOLUME_MAXIMIZE,
	## Run continuously at a steady rate; do not chase short-term price
	## signals. Analog: nuclear plants, blast furnaces — expensive to cycle.
	BASELOAD,
	## Idle most of the time; activate only during price spikes or shortages.
	## Analog: gas-peaking power plants.
	PEAKER,
	## Idle but preserve restart capability without decommissioning. Analog:
	## laid-up steel mills, cocooned aircraft.
	MOTHBALL,
	## Wind down toward permanent retirement; do not invest in maintenance.
	## Analog: end-of-life mine, deprecated fab.
	DECOMMISSION,
	## Throttle to match observed local offtake. Analog: load-following power
	## plant.
	DEMAND_FOLLOWING,
	## Ramp up in response to local shortages even at margin loss. Analog:
	## emergency-supply duty, public-utility obligation.
	SHORTAGE_RELIEF,
	## Run regardless of margin to drive down unit costs and accumulate
	## experience. Analog: early-stage industries (early solar, EVs) on the
	## learning curve.
	LEARNING,
	## Extract maximum output while resource quality is high; defer maintenance
	## and reinvestment. Analog: late-stage mining, declining oilfield.
	HARVEST,
	## Maintain a minimum viable run rate for strategic reasons even at a loss.
	## Analog: keeping a domestic semiconductor fab alive for national
	## security.
	STRATEGIC_HOLD,
	## Throttle run rate to match downstream clearance — disposal capacity
	## for waste, storage or offtake for byproducts and coproducts, atmospheric
	## or surface caps. The op is constrained by the slowest output we can
	## move, not by input availability or output margin. Analog: a refinery
	## limited by sulfur-handling capacity; a mine limited by tailings-pond
	## headroom.
	CLEARANCE_LIMITED,
	N_BASE_OPERATION_STRATEGIES,
}


## Short alias for the per-resource strategy enum, used by the authoring helpers.
const _RS := FacilityResourceStrategies

## Fallback growth rate for a facility posture whose def omits
## [code]buildout_intensity[/code] (matches the server-side default).
const DEFAULT_BUILDOUT_INTENSITY := 0.3


## Member names persisted by save/load (interval timing inherited from BaseAI).
const PERSIST_PROPERTIES: Array[StringName] = [
	&"_last_interval",
	&"_next_interval",
	&"facility_strategy",
	&"facility_resource_strategies",
	&"operation_strategies",
]


## Facility-posture strategy definitions; index = [enum FacilityStrategies]
## value. Keys are facility-wide knob params read by [method _apply_facility_knobs]:
## [code]buildout_intensity[/code] (signed autonomous growth rate — positive grows,
## 0 holds, negative winds down), [code]buildout_by_return[/code] (let the server
## allocate buildout by economic return rather than proportionally to the existing
## mix), and [code]buildout_allow_trim[/code] (let return-based buildout decommission
## chronically idle / loss-making modules). Empty entries take
## [constant DEFAULT_BUILDOUT_INTENSITY] with proportional, no-trim growth.
static var facility_strategy_defs: Array[Dictionary] = [
	{}, # NEUTRAL
	{&"buildout_intensity": 0.5}, # GROWTH
	{&"buildout_intensity": 0.3, &"buildout_by_return": true}, # PROFITABILITY
	{}, # DIVERSIFICATION
	{}, # SPECIALIZATION
	{&"buildout_intensity": 0.1}, # STRATEGIC_OUTPOST
	{}, # DEVELOPMENT
	{&"buildout_intensity": 0.15, &"buildout_by_return": true}, # STEADY_STATE
	{&"buildout_intensity": -0.5}, # DECOMMISSIONING
	{}, # EMERGENCY
]

## Per-resource facility-level strategy definitions; index =
## [enum FacilityResourceStrategies] value. Keys are facility-side knob params
## read by [method _apply_strategy_knobs]: [code]strategic_reserve_factor[/code]
## (reserve = factor × throughput × time_horizon), [code]mm_base_lot[/code]
## (trade-unit reserve floor), [code]protect_reserve[/code],
## [code]prohibit_production[/code], [code]prohibit_consumption[/code]. Empty
## entries take all defaults (no reserve, no flags).
static var facility_resource_strategy_defs: Array[Dictionary] = [
	{}, # NEUTRAL
	{}, # PRIMARY_PRODUCT
	{}, # SECONDARY_PRODUCT
	{}, # COPRODUCT
	{}, # BYPRODUCT
	{}, # WASTE
	{&"strategic_reserve_factor": 1.0}, # CRITICAL_INPUT
	{}, # ROUTINE_INPUT
	{}, # CONSUMABLE
	{}, # CLOSED_LOOP_INTERMEDIATE
	{&"strategic_reserve_factor": 2.0, &"protect_reserve": true}, # STRATEGIC_RESERVE
	{}, # SPECULATIVE_POSITION
	{&"prohibit_production": true}, # PHASE_OUT
	{&"strategic_reserve_factor": 1.0, &"mm_base_lot": 4, &"protect_reserve": true}, # MARKET_MAKE
]

## Per-operation strategy definitions; index = [enum OperationStrategies] value.
## Keys are operation-side knob params read by [method _apply_operation_knobs]:
## [code]target_utilization[/code] (run-rate fraction of capacity, default 1.0) and
## the operation gate switches [code]margin_gated[/code], [code]shortage_priority[/code],
## [code]strategic_floor[/code], [code]clearance_limited[/code]. Empty entries take
## full target utilization with no gate (AUTO — server reactive gating only, today's
## behavior). Several entries are deliberately AUTO-equivalent for now (their
## distinguishing run-rate shaping is future tuning).
static var operation_strategy_defs: Array[Dictionary] = [
	{}, # AUTO — full target, server reactive gating only
	{&"margin_gated": true}, # PROFIT_MAXIMIZE
	{}, # VOLUME_MAXIMIZE — run full regardless of margin
	{}, # BASELOAD — steady rate (tuning TBD)
	{}, # PEAKER — idle until spike (tuning TBD)
	{&"target_utilization": 0.0}, # MOTHBALL — idle, capacity preserved
	{}, # DECOMMISSION — capacity wind-down is Tier 1/2; run as AUTO here
	{}, # DEMAND_FOLLOWING — server storage cap already follows offtake
	{&"shortage_priority": true}, # SHORTAGE_RELIEF
	{}, # LEARNING — run regardless to accumulate experience
	{}, # HARVEST — run for max output
	{&"strategic_floor": true}, # STRATEGIC_HOLD
	{&"clearance_limited": true}, # CLEARANCE_LIMITED
]

static var _table_n_rows := IVTableData.table_n_rows
static var _trade_unit_multipliers := ThreadsafeGlobal.resource_trade_unit_multipliers
static var _tradable_resources: PackedInt32Array

var proxy: FacilityProxy


# *****************************************************************************
# persisted

## Facility-posture strategy. See [enum FacilityStrategies].
var facility_strategy := 0
## Per-resource facility-level strategies. See [enum FacilityResourceStrategies].
var facility_resource_strategies: PackedInt32Array
## Per-operation strategies. See [enum OperationStrategies].
var operation_strategies: PackedInt32Array

# *****************************************************************************

var _player_ai: PlayerBaseAI


# ************************* VIRTUAL & IMPLEMENTATION **************************

func _init() -> void:
	super()
	var n_resources: int = _table_n_rows[&"resources"]
	facility_resource_strategies.resize(n_resources)
	var n_operations: int = _table_n_rows[&"operations"]
	operation_strategies.resize(n_operations)
	if !_tradable_resources:
		var trade_classes: Array[int] = IVTableData.db_tables[&"resources"][&"trade_class"]
		for resource_type in n_resources:
			if trade_classes[resource_type] != -1:
				_tradable_resources.append(resource_type)


func _clear_for_destruction() -> void:
	proxy = null
	_player_ai = null


func bind_proxy(proxy_: Proxy) -> void:
	proxy = proxy_ as FacilityProxy


func ai_init() -> void:
	_player_ai = Proxy.proxy_bus.player_ais[proxy.player.player_id]
	assert(_player_ai, "FacilityBaseAI expects player's AI to be PlayerBaseAI")
	_player_ai.global_strategy_changed.connect(_on_player_global_strategy_changed)
	_player_ai.player_resource_strategy_changed.connect(_on_player_resource_strategy_changed)
	_player_ai.player_facility_strategy_changed.connect(_on_player_facility_strategy_changed)
	_player_ai.body_strategy_changed.connect(_on_player_body_strategy_changed)
	# new_quarter does not fire on load or the first adopted quarter, so author once
	# here to bootstrap (and re-author idempotently after load).
	_author_resource_strategies()
	_author_facility_strategy()
	_author_operation_strategies()


## Re-author each interval (the prior cadence): identity from sticky capability is
## cheap and change-guarded, so this stays responsive to capability changes and
## keeps reserves tracking live throughput, without the rate-based / write-only smell.
func process_ai_interval(_delta: float) -> void:
	_author_resource_strategies()


## Strategic, forward-looking reassessment of sticky policy. Same authoring pass;
## the change guard makes the quarter-boundary call a no-op when nothing changed.
func process_ai_new_quarter() -> void:
	_author_resource_strategies()
	_author_facility_strategy()
	_author_operation_strategies()


# **************************** STRATEGY LISTENERS *****************************

func _on_player_global_strategy_changed(_strategy_id: int) -> void:
	_author_resource_strategies()


func _on_player_resource_strategy_changed(_resource_type: int, _strategy_id: int) -> void:
	_author_resource_strategies()


func _on_player_facility_strategy_changed(facility_id: int, _strategy_id: int) -> void:
	if facility_id == proxy.facility_id:
		_author_resource_strategies()
		_author_facility_strategy()
		_author_operation_strategies()


func _on_player_body_strategy_changed(_target_body_id: int, _strategy_id: int) -> void:
	pass # body strategies are not folded into per-resource policy in the base AI


# **************************** INTERNAL PRIVATE *******************************

## Sets [member facility_resource_strategies] for [param resource_type],
## emitting [signal facility_resource_strategy_changed] only on change.
func _set_facility_resource_strategy(resource_type: int, strategy_id: int) -> void:
	if facility_resource_strategies[resource_type] == strategy_id:
		return
	facility_resource_strategies[resource_type] = strategy_id
	facility_resource_strategy_changed.emit(resource_type, strategy_id)


## Authors sticky per-resource policy for every tradable resource and applies the
## resulting server knobs. The single authoring path for init, interval, quarter,
## and player-strategy changes.
func _author_resource_strategies() -> void:
	for resource_type in _tradable_resources:
		var capability := _capability_strategy(resource_type)
		var strategy := _reconcile_resource_strategy(resource_type, capability)
		_set_facility_resource_strategy(resource_type, strategy)
		_apply_strategy_knobs(resource_type, strategy)


## Sticky producer/consumer identity from server capability bits, never from rate.
## Returns NEUTRAL until the server has published capability for this resource.
func _capability_strategy(resource_type: int) -> int:
	const TRADABLE := FacilityProxy.InventoryFlags.TRADABLE
	const CAN_HAVE_INPUT := FacilityProxy.InventoryFlags.CAN_HAVE_INPUT
	const CAN_HAVE_OUTPUT := FacilityProxy.InventoryFlags.CAN_HAVE_OUTPUT
	var flags := proxy.get_inventory_flags(resource_type)
	if !(flags & TRADABLE):
		return _RS.NEUTRAL
	var can_produce := bool(flags & CAN_HAVE_OUTPUT)
	var can_consume := bool(flags & CAN_HAVE_INPUT)
	if !can_produce and !can_consume:
		return _RS.NEUTRAL
	if proxy.market_maker:
		return _RS.MARKET_MAKE
	if can_produce and can_consume:
		# Produced and consumed here: take no special stance and let the trader
		# balance inventory around the reserve. A true closed loop (no external
		# trade) needs production/consumption magnitude to identify — deferred.
		return _RS.NEUTRAL
	if can_produce:
		return _RS.PRIMARY_PRODUCT
	return _RS.CRITICAL_INPUT


## Folds own crisis and player influence onto the capability identity by fixed
## precedence: own crisis > player structural directive > player influence >
## capability default. A custom AI overrides this to change reconciliation.
func _reconcile_resource_strategy(resource_type: int, capability: int) -> int:
	const CAN_HAVE_INPUT := FacilityProxy.InventoryFlags.CAN_HAVE_INPUT
	const INPUT_CRISIS := FacilityProxy.FacilityFlags.INPUT_CRISIS
	const OPS_RESERVE_BREACHED := FacilityProxy.InventoryFlags.OPS_RESERVE_BREACHED
	const STRATEGIC_RESERVE_BREACHED := FacilityProxy.InventoryFlags.STRATEGIC_RESERVE_BREACHED
	const PR := PlayerBaseAI.PlayerResourceStrategies
	const PF := PlayerBaseAI.PlayerFacilityStrategies

	# (1) Own crisis: a consumed resource (not a maker) in shortage prioritizes supply
	# continuity — escalate to CRITICAL_INPUT for a protected import buffer.
	if capability != _RS.MARKET_MAKE:
		var inv_flags := proxy.get_inventory_flags(resource_type)
		if (inv_flags & CAN_HAVE_INPUT) and ((proxy.get_flags() & INPUT_CRISIS) \
				or (inv_flags & (OPS_RESERVE_BREACHED | STRATEGIC_RESERVE_BREACHED))):
			return _RS.CRITICAL_INPUT

	# (2) Player structural directive overrides influence and capability.
	if _player_ai.player_facility_strategies.get(proxy.facility_id, 0) == PF.DIVEST:
		return _RS.PHASE_OUT
	var player_resource := _player_ai.player_resource_strategies[resource_type]
	if player_resource == PR.DIVEST or player_resource == PR.EMBARGO:
		return _RS.PHASE_OUT

	# (3) Player influence: stockpile / lock-in supply accumulates a reserve.
	if player_resource == PR.STRATEGIC_STOCKPILE or player_resource == PR.DOMINATE_DEMAND:
		return _RS.STRATEGIC_RESERVE

	# (4) Capability default.
	return capability


## Translates the resource's strategy def into server knobs: the strategic-reserve
## flow variable and the PROTECT / PROHIBIT inventory flag bits (flags written only
## on change; preserves any other FROM_PROXY bits).
func _apply_strategy_knobs(resource_type: int, strategy: int) -> void:
	const PROTECT_STRATEGIC_RESERVE := FacilityProxy.InventoryFlags.PROTECT_STRATEGIC_RESERVE
	const PROHIBIT_CONSUMPTION := FacilityProxy.InventoryFlags.PROHIBIT_CONSUMPTION
	const PROHIBIT_PRODUCTION := FacilityProxy.InventoryFlags.PROHIBIT_PRODUCTION
	const FROM_PROXY_MASK := FacilityProxy.InventoryFlags.FROM_PROXY_MASK
	const EMBARGO := PlayerBaseAI.PlayerResourceStrategies.EMBARGO
	var def := facility_resource_strategy_defs[strategy]

	var reserve_factor: float = def.get(&"strategic_reserve_factor", 0.0)
	var mm_base_lot: int = def.get(&"mm_base_lot", 0)
	var reserve := 0.0
	if reserve_factor > 0.0 or mm_base_lot > 0:
		var throughput := absf(proxy.get_inventory_expected_rate(resource_type))
		reserve = (reserve_factor * throughput * proxy.time_horizon
				+ mm_base_lot * _trade_unit_multipliers[resource_type])
	proxy.set_inventory_strategic_reserve(resource_type, reserve)

	var current := proxy.get_inventory_flags(resource_type) & FROM_PROXY_MASK
	var desired := current & ~(PROTECT_STRATEGIC_RESERVE | PROHIBIT_CONSUMPTION | PROHIBIT_PRODUCTION)
	if def.get(&"protect_reserve", false):
		desired |= PROTECT_STRATEGIC_RESERVE
	if def.get(&"prohibit_production", false):
		desired |= PROHIBIT_PRODUCTION
	if def.get(&"prohibit_consumption", false):
		desired |= PROHIBIT_CONSUMPTION
	if strategy == _RS.PHASE_OUT \
			and _player_ai.player_resource_strategies[resource_type] == EMBARGO:
		desired |= PROHIBIT_CONSUMPTION
	if desired != current:
		proxy.set_inventory_flags(resource_type, desired)


## Sets [member facility_strategy], emitting [signal facility_strategy_changed]
## only on change.
func _set_facility_strategy(strategy_id: int) -> void:
	if facility_strategy == strategy_id:
		return
	facility_strategy = strategy_id
	facility_strategy_changed.emit(strategy_id)


## Authors the facility-wide posture and applies its server buildout knobs — the
## facility analog of [method _author_resource_strategies]. Called on init, each
## quarter, and when the player's directive for this facility changes; the per-module
## build/decommission decision itself is the server's job, not the AI's.
func _author_facility_strategy() -> void:
	var strategy := _reconcile_facility_strategy()
	_set_facility_strategy(strategy)
	_apply_facility_knobs(strategy)


## Folds the player's per-facility directive into a facility posture. Contraction
## (the DECOMMISSIONING posture) is reserved for an explicit wind-down directive;
## every other directive grows or holds, leaving the facility to grow autonomously
## with no directive. A custom AI overrides this to change the mapping or to weigh
## the facility's own situation.
func _reconcile_facility_strategy() -> int:
	const PF := PlayerBaseAI.PlayerFacilityStrategies
	const FS := FacilityStrategies
	var directive: int = _player_ai.player_facility_strategies.get(proxy.facility_id, 0)
	match directive:
		PF.DIVEST:
			return FS.DECOMMISSIONING
		PF.FLAGSHIP, PF.STAR:
			return FS.GROWTH
		PF.CASH_COW, PF.QUESTION_MARK, PF.DOG:
			return FS.PROFITABILITY
		PF.STRATEGIC_OUTPOST:
			return FS.STRATEGIC_OUTPOST
		PF.SUBSIDIZED:
			return FS.STEADY_STATE
	return FS.GROWTH # NEUTRAL and any add-on directive: autonomous growth


## Translates the posture's def into server knobs: the buildout-intensity flow
## variable and the BUILDOUT_* algorithm flag bits (flags written only on change;
## preserves any other FROM_PROXY bits).
func _apply_facility_knobs(strategy: int) -> void:
	const BUILDOUT_BY_RETURN := FacilityProxy.FacilityFlags.BUILDOUT_BY_RETURN
	const BUILDOUT_ALLOW_TRIM := FacilityProxy.FacilityFlags.BUILDOUT_ALLOW_TRIM
	const FROM_PROXY_MASK := FacilityProxy.FacilityFlags.FROM_PROXY_MASK
	var def := facility_strategy_defs[strategy]
	var intensity: float = def.get(&"buildout_intensity", DEFAULT_BUILDOUT_INTENSITY)
	proxy.set_buildout_intensity(intensity)
	var current := proxy.get_flags() & FROM_PROXY_MASK
	var desired := current & ~(BUILDOUT_BY_RETURN | BUILDOUT_ALLOW_TRIM)
	if def.get(&"buildout_by_return", false):
		desired |= BUILDOUT_BY_RETURN
	if def.get(&"buildout_allow_trim", false):
		desired |= BUILDOUT_ALLOW_TRIM
	if desired != current:
		proxy.set_flags(desired)


## Sets [member operation_strategies] for [param operation_type], emitting
## [signal operation_strategy_changed] only on change.
func _set_operation_strategy(operation_type: int, strategy_id: int) -> void:
	if operation_strategies[operation_type] == strategy_id:
		return
	operation_strategies[operation_type] = strategy_id
	operation_strategy_changed.emit(operation_type, strategy_id)


## Authors per-operation run-rate policy (Tier 3) and applies its server knobs — the
## operation analog of [method _author_resource_strategies]. v1 derives one
## posture-driven strategy for all of the facility's operations; the server's
## per-interval gating then acts on it. Called wherever the facility posture is
## (re)authored.
func _author_operation_strategies() -> void:
	const CAN_HAVE := FacilityProxy.OperationsFlags.CAN_HAVE
	var strategy := _reconcile_operation_strategy()
	for operation_type in operation_strategies.size():
		if !(proxy.get_operations_flags(operation_type) & CAN_HAVE):
			continue
		_set_operation_strategy(operation_type, strategy)
		_apply_operation_knobs(operation_type, strategy)


## Maps the facility posture to a per-operation run-rate strategy. v1: a
## profit-optimizing posture margin-gates operations; every other posture runs AUTO
## (server-gated full run, today's behavior). A custom AI overrides this for richer
## per-operation policy (e.g. from each op's resource strategies).
func _reconcile_operation_strategy() -> int:
	if facility_strategy == FacilityStrategies.PROFITABILITY:
		return OperationStrategies.PROFIT_MAXIMIZE
	return OperationStrategies.AUTO


## Translates the operation's strategy def into the operation gate-flag bits (flags
## written only on change; preserves any other FROM_PROXY bits). The run-rate target
## itself is now server-authoritative (set by the Tier-3 controller, later stage).
func _apply_operation_knobs(operation_type: int, strategy: int) -> void:
	const MARGIN_GATED := FacilityProxy.OperationsFlags.MARGIN_GATED
	const SHORTAGE_PRIORITY := FacilityProxy.OperationsFlags.SHORTAGE_PRIORITY
	const STRATEGIC_FLOOR := FacilityProxy.OperationsFlags.STRATEGIC_FLOOR
	const CLEARANCE_LIMITED := FacilityProxy.OperationsFlags.CLEARANCE_LIMITED
	const FROM_PROXY_MASK := FacilityProxy.OperationsFlags.FROM_PROXY_MASK
	var def := operation_strategy_defs[strategy]
	var current := proxy.get_operations_flags(operation_type) & FROM_PROXY_MASK
	var desired := current & ~(MARGIN_GATED | SHORTAGE_PRIORITY | STRATEGIC_FLOOR | CLEARANCE_LIMITED)
	if def.get(&"margin_gated", false):
		desired |= MARGIN_GATED
	if def.get(&"shortage_priority", false):
		desired |= SHORTAGE_PRIORITY
	if def.get(&"strategic_floor", false):
		desired |= STRATEGIC_FLOOR
	if def.get(&"clearance_limited", false):
		desired |= CLEARANCE_LIMITED
	if desired != current:
		proxy.set_operations_flags(operation_type, desired)
