extends Theme

# Serialized in theme_tokens.tres. Wire identifiers are deliberately unchanged.
@export_group("Player palette")
@export var red := Color("f2131b")
@export var green := Color("00a64b")
@export var blue := Color("23ace8")
@export var yellow := Color("ffeb00")

@export_group("Board ink")
@export var cell_white := Color("ffffff")
@export var grid_ink := Color("404c56")
@export var safe_ink := Color("52606a")
@export var safe_on_color := Color("ffffff")
@export_range(0.5, 3.0, 0.1) var grid_width := 1.25
@export_range(1.0, 4.0, 0.1) var symbol_width := 2.5

@export_group("Board gradients")
@export_range(0.0, 0.3, 0.01) var yard_highlight := 0.025
@export_range(0.0, 0.3, 0.01) var yard_shade := 0.035
@export_range(0.0, 0.3, 0.01) var center_highlight := 0.04
@export_range(0.0, 0.3, 0.01) var center_shade := 0.05

@export_group("Pawn step shadows")
@export_range(0.0, 1.0, 0.01) var pawn_shadow_opacity := 0.68
@export_range(0.0, 1.0, 0.01) var step_shadow_opacity := 0.65
@export_range(0.0, 1.0, 0.05) var step_shadow_hold := 0.35
@export_range(0.1, 3.0, 0.05) var step_shadow_fade := 1.10

func player_colors() -> Dictionary:
	return {"coral": red, "sun": green, "mint": yellow, "violet": blue}
