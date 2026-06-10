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


## Facility-posture strategy definitions; index = [enum FacilityStrategies]
## value.
static var facility_strategy_defs: Array[Dictionary] = [
	{}, # NEUTRAL
	{}, # GROWTH
	{}, # PROFITABILITY
	{}, # DIVERSIFICATION
	{}, # SPECIALIZATION
	{}, # STRATEGIC_OUTPOST
	{}, # DEVELOPMENT
	{}, # STEADY_STATE
	{}, # DECOMMISSIONING
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

## Per-operation strategy definitions; index = [enum OperationStrategies]
## value.
static var operation_strategy_defs: Array[Dictionary] = [
	{}, # AUTO
	{}, # PROFIT_MAXIMIZE
	{}, # VOLUME_MAXIMIZE
	{}, # BASELOAD
	{}, # PEAKER
	{}, # MOTHBALL
	{}, # DECOMMISSION
	{}, # DEMAND_FOLLOWING
	{}, # SHORTAGE_RELIEF
	{}, # LEARNING
	{}, # HARVEST
	{}, # STRATEGIC_HOLD
	{}, # CLEARANCE_LIMITED
]


## Member names persisted by save/load (interval timing inherited from BaseAI).
const PERSIST_PROPERTIES: Array[StringName] = [
	&"_last_interval",
	&"_next_interval",
	&"facility_strategy",
	&"facility_resource_strategies",
	&"operation_strategies",
]


static var _table_n_rows := IVTableData.table_n_rows
static var _trade_unit_multipliers := ThreadsafeGlobal.resource_trade_unit_multipliers

## Per-resource tradability mask (1 = tradable), indexed by resource_type.
## Built once; a resource is tradable if it is a commodity with a storage class.
static var _is_tradable: PackedByteArray


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
	var n_resources: int = _table_n_rows[&"resources"]
	facility_resource_strategies.resize(n_resources)
	var n_operations: int = _table_n_rows[&"operations"]
	operation_strategies.resize(n_operations)
	if _is_tradable.is_empty():
		_build_tradable_mask(n_resources)


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


## Re-author each interval (the prior cadence): identity from sticky capability is
## cheap and change-guarded, so this stays responsive to capability changes and
## keeps reserves tracking live throughput, without the rate-based / write-only smell.
func process_ai_interval(_delta: float) -> void:
	_author_resource_strategies()


## Strategic, forward-looking reassessment of sticky policy. Same authoring pass;
## the change guard makes the quarter-boundary call a no-op when nothing changed.
func process_ai_new_quarter() -> void:
	_author_resource_strategies()


# **************************** STRATEGY LISTENERS *****************************

func _on_player_global_strategy_changed(_strategy_id: int) -> void:
	_author_resource_strategies()


func _on_player_resource_strategy_changed(_resource_type: int, _strategy_id: int) -> void:
	_author_resource_strategies()


func _on_player_facility_strategy_changed(facility_id: int, _strategy_id: int) -> void:
	if facility_id == proxy.facility_id:
		_author_resource_strategies()


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
	for resource_type in _is_tradable.size():
		if !_is_tradable[resource_type]:
			continue
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


static func _build_tradable_mask(n_resources: int) -> void:
	_is_tradable.resize(n_resources)
	var resource_table: Dictionary[StringName, Array] = IVTableData.db_tables[&"resources"]
	var commodities: Array = resource_table[&"commodity"]
	var storage_classes := PackedInt32Array(resource_table[&"storage_class"])
	for resource_type in n_resources:
		var is_commodity: bool = commodities[resource_type]
		var tradable := is_commodity and storage_classes[resource_type] != -1
		_is_tradable[resource_type] = 1 if tradable else 0
