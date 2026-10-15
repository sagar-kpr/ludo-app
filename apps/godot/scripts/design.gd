extends RefCounted

const TOKENS = preload("res://resources/theme_tokens.tres")
const CREAM = Color("080b18")
const BEIGE = Color("20243d")
const FOREST = Color("2f85c8")
const GOLD = Color("ffbf4b")
const INK = Color("f5f6ff")
const MUTED = Color("969ab7")
const DIVIDER = Color("343851")
# Wire identifiers are retained so the existing engine/server remain compatible.
static var COLORS: Dictionary = TOKENS.player_colors()
const COLOR_NAMES = {"coral": "Red", "sun": "Green", "mint": "Yellow", "violet": "Blue"}
static var shadow_texture: GradientTexture2D

static func pawn_shadow_texture() -> GradientTexture2D:
	if shadow_texture == null:
		var gradient := Gradient.new()
		gradient.offsets = PackedFloat32Array([0.0, 0.35, 1.0])
		gradient.colors = PackedColorArray([Color.WHITE, Color(0.85, 0.85, 0.85, 0.75), Color(0.75, 0.75, 0.75, 0.0)])
		shadow_texture = GradientTexture2D.new()
		shadow_texture.gradient = gradient
		shadow_texture.width = 128
		shadow_texture.height = 128
		shadow_texture.fill = GradientTexture2D.FILL_RADIAL
		shadow_texture.fill_from = Vector2(0.5, 0.5)
		shadow_texture.fill_to = Vector2(0.5, 1.0)
	return shadow_texture

static func surface(color: Color = Color.WHITE, radius: int = 12, border: Color = DIVIDER) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(radius)
	style.set_border_width_all(1)
	style.border_color = border
	style.shadow_color = Color(0,0,0,0.35)
	style.shadow_size = 8
	style.shadow_offset = Vector2(0,3)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	return style

static func make_theme() -> Theme:
	var theme := TOKENS.duplicate(true) as Theme
	theme.default_font_size = 15
	var emphasis := FontVariation.new()
	emphasis.base_font = ThemeDB.fallback_font
	emphasis.variation_embolden = 0.45
	theme.set_font("font", "Button", emphasis)
	theme.set_color("font_color", "Label", INK)
	theme.set_color("font_color", "Button", Color.WHITE)
	theme.set_color("font_disabled_color", "Button", MUTED)
	theme.set_stylebox("normal", "Button", surface(FOREST, 14, FOREST))
	theme.set_stylebox("hover", "Button", surface(Color("3da8dc"), 14, GOLD))
	theme.set_stylebox("pressed", "Button", surface(Color("1b5d98"), 14, GOLD))
	theme.set_stylebox("disabled", "Button", surface(BEIGE, 14))
	theme.set_stylebox("focus", "Button", surface(Color(0, 0, 0, 0), 14, GOLD))
	theme.set_color("font_color", "LineEdit", INK)
	theme.set_color("font_placeholder_color", "LineEdit", MUTED)
	theme.set_color("caret_color", "LineEdit", FOREST)
	theme.set_stylebox("normal", "LineEdit", surface(Color("1b2038"), 14, DIVIDER))
	theme.set_stylebox("focus", "LineEdit", surface(Color("20243d"), 14, FOREST))
	theme.set_stylebox("panel", "PanelContainer", surface(Color("13172d"), 20, DIVIDER))
	return theme

static func game_surface(border: Color = Color("64b9ef")) -> StyleBoxFlat:
	var style := surface(Color("102c53"),14,border)
	style.set_border_width_all(2)
	style.shadow_color = Color(0.015,0.03,0.08,0.6)
	style.shadow_size = 5
	style.shadow_offset = Vector2(0,3)
	return style
