extends Resource
class_name HotbarTheme

## HotbarTheme — one .tres file per biome.
## Assign to BiomeData.hotbar_theme in the Inspector.
## TurretHotbar.apply_biome_theme() reads this to instantly restyle the hotbar.

@export_group("Panel")
@export var panel_bg_color: Color     = Color(0.02, 0.04, 0.10, 0.90)
@export var panel_border_color: Color = Color(0.20, 0.55, 1.00, 0.75)
@export var panel_shadow_color: Color = Color(0.10, 0.50, 1.00, 0.40)


@export_group("Slot Background")
@export var slot_color_bg_normal: Color   = Color(0.04, 0.06, 0.14, 0.88)
@export var slot_color_bg_hover: Color    = Color(0.06, 0.12, 0.28, 0.92)
@export var slot_color_bg_selected: Color = Color(0.05, 0.16, 0.38, 0.95)

@export_group("Slot Border")
@export var slot_color_border_normal: Color   = Color(0.10, 0.30, 0.70, 0.60)
@export var slot_color_border_hover: Color    = Color(0.20, 0.60, 1.00, 0.90)
@export var slot_color_border_selected: Color = Color(0.30, 0.80, 1.00, 1.00)
@export var slot_color_glow: Color            = Color(0.20, 0.70, 1.00, 0.50)
