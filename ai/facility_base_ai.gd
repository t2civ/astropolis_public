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


## Net-rate deadband for classifying a resource as net producer vs. net
## consumer; magnitudes within this band are treated as NEUTRAL (not traded).
const RATE_EPSILON := 1e-9
## Strategic reserve held for a critical input, as a multiple of its
## (consumption rate × facility time horizon), beyond the operational reserve.
const STRATEGIC_RESERVE_FACTOR := 1.0
## Market-maker trade-reserve floor per relevant resource, in trade units; gives a
## standing two-sided quote even for resources with no current throughput.
const MM_BASE_LOT := 4


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
## [enum FacilityResourceStrategies] value.
static var facility_resource_strategy_defs: Array[Dictionary] = [
	{}, # NEUTRAL
	{}, # PRIMARY_PRODUCT
	{}, # SECONDARY_PRODUCT
	{}, # COPRODUCT
	{}, # BYPRODUCT
	{}, # WASTE
	{}, # CRITICAL_INPUT
	{}, # ROUTINE_INPUT
	{}, # CONSUMABLE
	{}, # CLOSED_LOOP_INTERMEDIATE
	{}, # STRATEGIC_RESERVE
	{}, # SPECULATIVE_POSITION
	{}, # PHASE_OUT
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

## Per-resource spot-tradability mask (1 = tradable), indexed by resource_type.
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
var _was_market_maker := false # last-seen market_maker; drives one-shot revert cleanup


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


func process_ai_init() -> void:
	_player_ai = Proxy.proxy_bus.player_ais[proxy.player.player_id]
	assert(_player_ai, "FacilityBaseAI expects player's AI to be PlayerBaseAI")
	_player_ai.global_strategy_changed.connect(_on_player_global_strategy_changed)
	_player_ai.player_resource_strategy_changed.connect(_on_player_resource_strategy_changed)
	_player_ai.player_facility_strategy_changed.connect(_on_player_facility_strategy_changed)
	_player_ai.body_strategy_changed.connect(_on_player_body_strategy_changed)


func process_ai_interval(_delta: float) -> void:
	# Classify each tradable resource by its net rate so the paired trader knows
	# whether to sell surplus or buy toward reserve, and set a strategic reserve
	# for critical inputs. Non-tradable resources are left NEUTRAL.
	const NEUTRAL := FacilityResourceStrategies.NEUTRAL
	const PRIMARY_PRODUCT := FacilityResourceStrategies.PRIMARY_PRODUCT
	const CRITICAL_INPUT := FacilityResourceStrategies.CRITICAL_INPUT
	var time_horizon := proxy.time_horizon
	for resource_type in _is_tradable.size():
		if !_is_tradable[resource_type]:
			continue
		var expected_rate := proxy.get_resource_expected_rate(resource_type)
		if expected_rate > RATE_EPSILON:
			_set_facility_resource_strategy(resource_type, PRIMARY_PRODUCT)
			proxy.set_inventory_strategic_reserve(resource_type, 0.0)
		elif expected_rate < -RATE_EPSILON:
			_set_facility_resource_strategy(resource_type, CRITICAL_INPUT)
			proxy.set_inventory_strategic_reserve(resource_type,
					-expected_rate * time_horizon * STRATEGIC_RESERVE_FACTOR)
		else:
			_set_facility_resource_strategy(resource_type, NEUTRAL)
			proxy.set_inventory_strategic_reserve(resource_type, 0.0)
	_update_market_maker_reserves()


# **************************** STRATEGY LISTENERS *****************************

func _on_player_global_strategy_changed(_strategy_id: int) -> void:
	pass


func _on_player_resource_strategy_changed(_resource_type: int, _strategy_id: int) -> void:
	pass


func _on_player_facility_strategy_changed(_facility_id: int, _strategy_id: int) -> void:
	pass


func _on_player_body_strategy_changed(_target_body_id: int, _strategy_id: int) -> void:
	pass


# **************************** INTERNAL PRIVATE *******************************

## Sets [member facility_resource_strategies] for [param resource_type],
## emitting [signal facility_resource_strategy_changed] only on change.
func _set_facility_resource_strategy(resource_type: int, strategy_id: int) -> void:
	if facility_resource_strategies[resource_type] == strategy_id:
		return
	facility_resource_strategies[resource_type] = strategy_id
	facility_resource_strategy_changed.emit(resource_type, strategy_id)


func _update_market_maker_reserves() -> void:
	const CAN_HAVE_INPUT_OUTPUT := FacilityProxy.InventoryFlags.CAN_HAVE_INPUT_OUTPUT
	const PROTECT_STRATEGIC_RESERVE := FacilityProxy.InventoryFlags.PROTECT_STRATEGIC_RESERVE
	const FROM_PROXY_MASK := FacilityProxy.InventoryFlags.FROM_PROXY_MASK
	if proxy.market_maker:
		# Hold a trade reserve on every market-relevant resource and protect it from the
		# facility's own operations, so the trader always has buffer stock to quote.
		var time_horizon := proxy.time_horizon
		for resource_type in _is_tradable.size():
			var inv_flags := proxy.get_inventory_flags(resource_type)
			if !(inv_flags & CAN_HAVE_INPUT_OUTPUT):
				continue
			var throughput := absf(proxy.get_resource_expected_rate(resource_type))
			var reserve := (time_horizon * throughput
					+ MM_BASE_LOT * _trade_unit_multipliers[resource_type])
			proxy.set_inventory_strategic_reserve(resource_type, reserve)
			proxy.set_inventory_flags(resource_type,
					(inv_flags & FROM_PROXY_MASK) | PROTECT_STRATEGIC_RESERVE)
	elif _was_market_maker:
		# No longer a market maker: drop the protect bit we may have set (the classify
		# loop already reset the reserve itself).
		for resource_type in _is_tradable.size():
			var inv_flags := proxy.get_inventory_flags(resource_type) & FROM_PROXY_MASK
			proxy.set_inventory_flags(resource_type, inv_flags & ~PROTECT_STRATEGIC_RESERVE)
	_was_market_maker = proxy.market_maker


static func _build_tradable_mask(n_resources: int) -> void:
	_is_tradable.resize(n_resources)
	var resource_table: Dictionary[StringName, Array] = IVTableData.db_tables[&"resources"]
	var commodities: Array = resource_table[&"commodity"]
	var storage_classes := PackedInt32Array(resource_table[&"storage_class"])
	for resource_type in n_resources:
		var is_commodity: bool = commodities[resource_type]
		var tradable := is_commodity and storage_classes[resource_type] != -1
		_is_tradable[resource_type] = 1 if tradable else 0
