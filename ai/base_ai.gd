# base_ai.gd
# This file is part of Astropolis
# https://t2civ.com
# *****************************************************************************
# Copyright 2019-2026 Charlie Whitfield; ALL RIGHTS RESERVED
# Astropolis is a registered trademark of Charlie Whitfield in the US
# *****************************************************************************
@abstract
class_name BaseAI
extends RefCounted

## Abstract base for AI classes paired 1-to-1 with a [Proxy].
##
## Concrete subclasses ([FacilityBaseAI], [PlayerBaseAI], [TraderBaseAI])
## declare a typed [code]proxy[/code] field and drive AI logic on the proxy
## thread. To write custom AI, extend a [code]*BaseAI[/code] class and add
## [code]const OVERRIDE_AI := true[/code]; see [PlayerCustomAI] for the
## template.[br][br]
##
## WARNING: Lives on the proxy thread. AI instances exist only on peers that
## run the AI for their entity (typically the owning player); peers that don't
## run it have no AI instance for that entity.


## Time between [method process_ai_interval] calls. Mirrors [constant Proxy.INTERVAL].
const INTERVAL := Proxy.INTERVAL

## ivoyager save/load category. AI instances are rebuilt on game load. Persisted
## members are listed by the concrete [code]*BaseAI[/code] subclass in its
## [code]PERSIST_PROPERTIES[/code] (interval timing + strategy state); this keeps
## [code]PERSIST_PROPERTIES2[/code] free for a [code]*CustomAI[/code] subclass to
## persist its own added state.
const PERSIST_MODE := IVGlobal.PERSIST_PROCEDURAL


var _last_interval := -INF
var _next_interval := -INF
var _ordinal_qtr := -1


# ************************* VIRTUAL & IMPLEMENTATION **************************

func _init() -> void:
	IVStateManager.about_to_free_procedural_nodes.connect.call_deferred(_clear_for_destruction)


## Override to null every outgoing Proxy / BaseAI ref. Both sides of a 2-cycle
## should clear — redundant on success, robust under refactoring.
func _clear_for_destruction() -> void:
	pass


## Required override. Stores [param proxy] in the subclass's typed
## [code]proxy[/code] field. Called by [code]ProxyServer[/code] immediately
## after AI instantiation.
@abstract func bind_proxy(_proxy: Proxy) -> void


## Required override. Called once per process lifetime after the paired
## [Proxy] has had its cross-proxy refs resolved by the server. Override to
## resolve cross-AI refs (via the [ProxyBus] AI registries) and to
## perform one-time AI setup. Runs again on the fresh post-load instance
## after a game load. Idempotent overrides required.
@abstract func process_ai_init() -> void


## Required override. Called once per [constant INTERVAL] during AI
## processing. Most component data changes every [constant INTERVAL], so this
## is the recommended place for AI logic.
@abstract func process_ai_interval(_delta: float) -> void


## Optional override. Called by [method process_ai] when the proxy's
## [member Proxy.ordinal_qtr] advances (after the interval hook, so component
## histories are current).
func process_ai_new_quarter() -> void:
	pass


# **************************** INTERNAL PRIVATE *******************************
# Don't override!

## Per-tick driver called by ProxyServer with the current time and the proxy's
## quarter. Schedules [method process_ai_interval] at staggered intervals and
## fires [method process_ai_new_quarter] when the quarter advances.
func process_ai(time: float, ordinal_qtr: int) -> void:
	var is_new_quarter := false
	if _ordinal_qtr != ordinal_qtr:
		assert(_ordinal_qtr < ordinal_qtr)
		is_new_quarter = _ordinal_qtr != -1 # adopt the first quarter without firing
		_ordinal_qtr = ordinal_qtr
	if time > _next_interval:
		if _next_interval == -INF: # init
			_last_interval = time
			_next_interval = time + randf_range(0.0, INTERVAL) # stagger AI processing
		else:
			var delta := time - _last_interval
			_last_interval = time
			while _next_interval < time:
				_next_interval += INTERVAL
			process_ai_interval(delta)
	if is_new_quarter:
		process_ai_new_quarter()
