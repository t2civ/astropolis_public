# development_panel.gd
# This file is part of Astropolis
# Copyright 2019-2023 Charlie Whitfield, all rights reserved
# *****************************************************************************
extends PanelContainer


const PERSIST_MODE := IVEnums.PERSIST_PROPERTIES_ONLY
const PERSIST_PROPERTIES := [
	"anchor_top",
	"anchor_left",
	"anchor_right",
	"anchor_bottom",
]


func _ready() -> void:
	theme = IVGlobal.themes.main_menu
	$ControlMod.init_min_size(-1, Vector2.ZERO)
	var style_box := StyleBoxFlat.new()
	style_box.bg_color = Color(1.0, 1.0, 1.0, 0.05) # almost transparent
	set("theme_override_styles/panel", style_box)
	$Timer.connect("timeout", Callable($StatsGrid, "update"))
	IVGlobal.connect("system_tree_ready", Callable(self, "_delayed_timer_start"))
	IVGlobal.connect("simulator_started", Callable(self, "_delayed_1st_update"))
	IVGlobal.connect("about_to_free_procedural_nodes", Callable($Timer, "stop"))


func _delayed_timer_start(_is_new_game: bool) -> void:
	# wait 0.5 s to offset from InfoPanel/Timer
	await get_tree().create_timer(0.6).timeout
	$Timer.start()


func _delayed_1st_update() -> void:
	# wait for initial server back-and-forth so there is data to get
	var i := 0
	while i < 8: # add more if needed
		await get_tree().idle_frame
		i += 1
	$StatsGrid.update()


