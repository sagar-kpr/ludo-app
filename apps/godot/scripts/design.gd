extends RefCounted

const CREAM = Color("f4f6fa")
const BEIGE = Color("e9edf5")
const FOREST = Color("4658d8")
const GOLD = Color("4658d8")
const INK = Color("20283e")
const MUTED = Color("737d91")
const DIVIDER = Color("dfe4ee")
# Wire identifiers are retained so the existing engine/server remain compatible.
const COLORS = {"coral": Color("db2027"), "sun": Color("009c46"), "mint": Color("f5c400"), "violet": Color("006dc9")}
const COLOR_NAMES = {"coral": "Red", "sun": "Green", "mint": "Yellow", "violet": "Blue"}

static func surface(color: Color = Color.WHITE, radius: int = 12, border: Color = DIVIDER) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(radius)
	style.set_border_width_all(1)
	style.border_color = border
	style.shadow_color = Color(0.15,0.20,0.40,0.055)
	style.shadow_size = 5
	style.shadow_offset = Vector2(0,3)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	return style

static func make_theme() -> Theme:
	var theme := Theme.new()
	theme.default_font_size = 15
	var emphasis := FontVariation.new()
	emphasis.base_font = ThemeDB.fallback_font
	emphasis.variation_embolden = 0.45
	theme.set_font("font", "Button", emphasis)
	theme.set_color("font_color", "Label", INK)
	theme.set_color("font_color", "Button", Color.WHITE)
	theme.set_color("font_disabled_color", "Button", MUTED)
	theme.set_stylebox("normal", "Button", surface(FOREST, 14, FOREST))
	theme.set_stylebox("hover", "Button", surface(FOREST.lightened(0.1), 14, GOLD))
	theme.set_stylebox("pressed", "Button", surface(FOREST.darkened(0.15), 14, GOLD))
	theme.set_stylebox("disabled", "Button", surface(BEIGE, 14))
	theme.set_stylebox("focus", "Button", surface(Color(0, 0, 0, 0), 14, GOLD))
	theme.set_color("font_color", "LineEdit", INK)
	theme.set_color("font_placeholder_color", "LineEdit", MUTED)
	theme.set_color("caret_color", "LineEdit", FOREST)
	theme.set_stylebox("normal", "LineEdit", surface())
	theme.set_stylebox("focus", "LineEdit", surface(Color.WHITE, 18, FOREST))
	theme.set_stylebox("panel", "PanelContainer", surface())
	return theme

static func game_surface(border: Color = Color("64b9ef")) -> StyleBoxFlat:
	var style := surface(Color("102c53"),14,border)
	style.set_border_width_all(2)
	style.shadow_color = Color(0.015,0.03,0.08,0.6)
	style.shadow_size = 5
	style.shadow_offset = Vector2(0,3)
	return style
