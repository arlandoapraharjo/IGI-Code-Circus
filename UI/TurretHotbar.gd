@tool
extends CanvasLayer

## TurretHotbar — Sci-Fi styled bottom-of-screen hotbar.
## All visual properties are @export — configure via Inspector, no hardcoding.
## Emits turret_selected(index) when a slot is clicked.

signal turret_selected(index: int, scene: PackedScene)

# ── Layout ────────────────────────────────────────────────────────────────────

@export_group("Layout")
## Number of turret slots to display.
@export_range(1, 10) var slot_count: int = 5:
	set(v):
		slot_count = v
		if is_node_ready(): _rebuild_hotbar()

## Width and height of each slot in pixels.
@export_range(40, 200, 1) var slot_size: float = 50.0:
	set(v):
		slot_size = v
		if is_node_ready(): _push_layout_to_slots()

## Pixel gap between slots.
@export_range(0, 40, 1) var slot_spacing: int = 10:
	set(v):
		slot_spacing = v
		if is_node_ready(): _apply_slot_spacing()

# ── Panel Style ───────────────────────────────────────────────────────────────

@export_group("Panel Style")
@export var panel_bg_color: Color = Color(0.02, 0.04, 0.10, 0.90):
	set(v): panel_bg_color = v; if is_node_ready(): _apply_panel_style()
@export var panel_border_color: Color = Color(0.20, 0.55, 1.00, 0.75):
	set(v): panel_border_color = v; if is_node_ready(): _apply_panel_style()
@export_range(0, 20) var panel_corner_radius: int = 10:
	set(v): panel_corner_radius = v; if is_node_ready(): _apply_panel_style()
@export_range(0, 40) var panel_shadow_size: int = 20:
	set(v): panel_shadow_size = v; if is_node_ready(): _apply_panel_style()
@export var panel_shadow_color: Color = Color(0.10, 0.50, 1.00, 0.40):
	set(v): panel_shadow_color = v; if is_node_ready(): _apply_panel_style()


# ── Slot Colors ───────────────────────────────────────────────────────────────

@export_group("Slot Colors / Background")
@export var slot_color_bg_normal: Color   = Color(0.04, 0.06, 0.14, 0.88):
	set(v): slot_color_bg_normal = v;   if is_node_ready(): _push_colors_to_slots()
@export var slot_color_bg_hover: Color    = Color(0.06, 0.12, 0.28, 0.92):
	set(v): slot_color_bg_hover = v;    if is_node_ready(): _push_colors_to_slots()
@export var slot_color_bg_selected: Color = Color(0.05, 0.16, 0.38, 0.95):
	set(v): slot_color_bg_selected = v; if is_node_ready(): _push_colors_to_slots()

@export_group("Slot Colors / Border")
@export var slot_color_border_normal: Color   = Color(0.10, 0.30, 0.70, 0.60):
	set(v): slot_color_border_normal = v;   if is_node_ready(): _push_colors_to_slots()
@export var slot_color_border_hover: Color    = Color(0.20, 0.60, 1.00, 0.90):
	set(v): slot_color_border_hover = v;    if is_node_ready(): _push_colors_to_slots()
@export var slot_color_border_selected: Color = Color(0.30, 0.80, 1.00, 1.00):
	set(v): slot_color_border_selected = v; if is_node_ready(): _push_colors_to_slots()
@export var slot_color_glow: Color            = Color(0.20, 0.70, 1.00, 0.50):
	set(v): slot_color_glow = v;            if is_node_ready(): _push_colors_to_slots()

@export_group("Slot Colors / Shape")
@export_range(1, 6, 0.5) var slot_border_width_normal: float   = 1.5:
	set(v): slot_border_width_normal = v;   if is_node_ready(): _push_colors_to_slots()
@export_range(1, 6, 0.5) var slot_border_width_hover: float    = 2.0:
	set(v): slot_border_width_hover = v;    if is_node_ready(): _push_colors_to_slots()
@export_range(1, 6, 0.5) var slot_border_width_selected: float = 2.5:
	set(v): slot_border_width_selected = v; if is_node_ready(): _push_colors_to_slots()
@export_range(0, 20) var slot_corner_radius: int = 6:
	set(v): slot_corner_radius = v;         if is_node_ready(): _push_colors_to_slots()
@export_range(0, 30) var slot_glow_shadow_size: int = 14:
	set(v): slot_glow_shadow_size = v;      if is_node_ready(): _push_colors_to_slots()

# ── Turret Assets ─────────────────────────────────────────────────────────────

const SLOT_SCENE := preload("res://UI/HotbarSlot.tscn")

const TURRET_ASSETS: Array[Dictionary] = [
	{
		"scene": preload("res://assets/Models/GLB format/desert/weapon-turret.glb"),
		"name": "Turret"
	},
	{
		"scene": preload("res://assets/Models/GLB format/desert/weapon-cannon.glb"),
		"name": "Cannon"
	},
	{
		"scene": preload("res://assets/Models/GLB format/desert/weapon-ballista.glb"),
		"name": "Ballista"
	},
	{
		"scene": preload("res://assets/Models/GLB format/desert/weapon-catapult.glb"),
		"name": "Catapult"
	},
	{
		"scene": preload("res://assets/Models/GLB format/weapon-turret.glb"),
		"name": "Heavy Turret"
	},
]

# ── Internal ──────────────────────────────────────────────────────────────────

var _slots: Array[Node] = []
var _selected_index: int = -1

@onready var slot_container: HBoxContainer = $HotbarPanel/VBox/MarginContainer/SlotContainer
@onready var hotbar_panel: PanelContainer  = $HotbarPanel

func _ready() -> void:
	_rebuild_hotbar()
	_apply_panel_style()
	_populate_slots()
	# Auto-connect to MapGenerator so theme swaps when the biome changes
	call_deferred("_connect_to_map_generator")

func _connect_to_map_generator() -> void:
	# MapGenerator lives as a sibling node named "Map" under the World root
	var map := get_tree().get_root().find_child("Map", true, false)
	if map:
		if map.has_signal("biome_changed") and not map.biome_changed.is_connected(_on_biome_changed):
			map.biome_changed.connect(_on_biome_changed)
		# If map already initialized its biome before we connected, grab it now!
		if "active_biome" in map and map.active_biome != null:
			_on_biome_changed(map.active_biome)

# ── Build / Rebuild ────────────────────────────────────────────────────────────

func _rebuild_hotbar() -> void:
	# Clear existing slots
	for slot in _slots:
		if is_instance_valid(slot):
			slot.queue_free()
	_slots.clear()
	_selected_index = -1
	# Build fresh
	for i in range(slot_count):
		var slot: Node = SLOT_SCENE.instantiate()
		slot.slot_index = i
		slot.slot_clicked.connect(_on_slot_clicked)
		slot_container.add_child(slot)
		_slots.append(slot)
	_push_layout_to_slots()
	_push_colors_to_slots()
	_apply_slot_spacing()

func _populate_slots() -> void:
	for i in range(min(TURRET_ASSETS.size(), _slots.size())):
		var entry: Dictionary = TURRET_ASSETS[i]
		set_slot_turret(i, entry["scene"], entry["name"])

# ── Style application ──────────────────────────────────────────────────────────

func _apply_panel_style() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color    = panel_bg_color
	style.border_color = panel_border_color
	style.set_border_width_all(2)
	style.corner_radius_top_left     = panel_corner_radius
	style.corner_radius_top_right    = panel_corner_radius
	style.corner_radius_bottom_left  = 0
	style.corner_radius_bottom_right = 0
	style.shadow_color  = panel_shadow_color
	style.shadow_size   = panel_shadow_size
	style.shadow_offset = Vector2(0, -4)
	hotbar_panel.add_theme_stylebox_override("panel", style)

func _apply_slot_spacing() -> void:
	slot_container.add_theme_constant_override("separation", slot_spacing)

func _push_layout_to_slots() -> void:
	for slot in _slots:
		if is_instance_valid(slot):
			slot.slot_size = slot_size

func _push_colors_to_slots() -> void:
	var cfg := _build_slot_config()
	for slot in _slots:
		if is_instance_valid(slot):
			slot.apply_theme_config(cfg)

func _build_slot_config() -> Dictionary:
	return {
		"slot_size":             slot_size,
		"color_bg_normal":       slot_color_bg_normal,
		"color_bg_hover":        slot_color_bg_hover,
		"color_bg_selected":     slot_color_bg_selected,
		"color_border_normal":   slot_color_border_normal,
		"color_border_hover":    slot_color_border_hover,
		"color_border_selected": slot_color_border_selected,
		"color_glow":            slot_color_glow,
		"border_width_normal":   slot_border_width_normal,
		"border_width_hover":    slot_border_width_hover,
		"border_width_selected": slot_border_width_selected,
		"corner_radius":         slot_corner_radius,
		"glow_shadow_size":      slot_glow_shadow_size,
	}

# ── Public API ─────────────────────────────────────────────────────────────────

## Assign a turret scene + name to a specific slot index (0-based).
func set_slot_turret(index: int, scene: PackedScene, p_name: String) -> void:
	if index < 0 or index >= _slots.size():
		push_warning("TurretHotbar: slot index %d out of range" % index)
		return
	_slots[index].set_turret(scene, p_name)

## Programmatically select a slot.
func select_slot(index: int) -> void:
	_on_slot_clicked(index)

## Returns the currently selected slot index (-1 if none).
func get_selected_index() -> int:
	return _selected_index

## Instantly apply a HotbarTheme resource to the hotbar and all slots.
## Call this directly or let _on_biome_changed handle it automatically.
func apply_biome_theme(theme: HotbarTheme) -> void:
	if theme == null:
		return
	# Panel
	panel_bg_color     = theme.panel_bg_color
	panel_border_color = theme.panel_border_color
	panel_shadow_color = theme.panel_shadow_color
	_apply_panel_style()
	# Slot colors
	slot_color_bg_normal       = theme.slot_color_bg_normal
	slot_color_bg_hover        = theme.slot_color_bg_hover
	slot_color_bg_selected     = theme.slot_color_bg_selected
	slot_color_border_normal   = theme.slot_color_border_normal
	slot_color_border_hover    = theme.slot_color_border_hover
	slot_color_border_selected = theme.slot_color_border_selected
	slot_color_glow            = theme.slot_color_glow
	_push_colors_to_slots()

# ── Internal ───────────────────────────────────────────────────────────────────

func _on_biome_changed(biome: BiomeData) -> void:
	apply_biome_theme(biome.hotbar_theme)

func _on_slot_clicked(index: int) -> void:
	if _selected_index == index:
		_slots[index].set_selected(false)
		_selected_index = -1
		turret_selected.emit(-1)
		return
	if _selected_index >= 0 and _selected_index < _slots.size():
		_slots[_selected_index].set_selected(false)
	_selected_index = index
	_slots[index].set_selected(true)
	turret_selected.emit(index, TURRET_ASSETS[index]["scene"])
