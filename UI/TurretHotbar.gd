@tool
extends CanvasLayer

## TurretHotbar — Sci-Fi styled bottom-of-screen hotbar.
## All visual properties are @export — configure via Inspector, no hardcoding.
## Emits turret_selected(index) when a slot is clicked.

signal turret_selected(index: int, scene: PackedScene, attack_range: float)

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
		"name": "Turret",
		"attack_range": 1.5
	},
	{
		"scene": preload("res://assets/Models/GLB format/desert/weapon-cannon.glb"),
		"name": "Cannon",
		"attack_range": 1.5
	},
	{
		"scene": preload("res://assets/Models/GLB format/desert/weapon-ballista.glb"),
		"name": "Ballista",
		"attack_range": 2.5
	},
	{
		"scene": preload("res://assets/Models/GLB format/desert/weapon-catapult.glb"),
		"name": "Catapult",
		"attack_range": 2.0
	},
	{
		"scene": preload("res://assets/Models/GLB format/weapon-turret.glb"),
		"name": "Heavy Turret",
		"attack_range": 2.5
	},
]

# ── Internal ──────────────────────────────────────────────────────────────────

var _slots: Array[Node] = []
var _selected_index: int = -1
var _is_open: bool = false
var _toggle_btn: Button = null
var _panel_tween: Tween = null
var _panel_target_y: float = 0.0

@onready var slot_container: HBoxContainer = $HotbarPanel/VBox/MarginContainer/SlotContainer
@onready var hotbar_panel: PanelContainer  = $HotbarPanel
@onready var border_overlay: TextureRect   = $HotbarPanel/VBox/MarginContainer/BorderOverlay
@onready var bg_overlay: TextureRect       = $HotbarPanel/VBox/MarginContainer/BgOverlay

func _ready() -> void:
	_rebuild_hotbar()
	_apply_panel_style()
	_populate_slots()
	# Create the toggle button and set up popup behavior
	call_deferred("_setup_popup")
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

# ── Popup Toggle ───────────────────────────────────────────────────────────────

func _setup_popup() -> void:
	# Wait one frame so the panel has its final size
	await get_tree().process_frame

	# Store the panel's "open" Y position and hide it off-screen
	_panel_target_y = hotbar_panel.position.y
	hotbar_panel.position.y = hotbar_panel.position.y + hotbar_panel.size.y + 20
	hotbar_panel.visible = true

	# Create the toggle button at the bottom center
	_toggle_btn = Button.new()
	_toggle_btn.text = "▲ Turrets"
	_toggle_btn.custom_minimum_size = Vector2(120, 32)
	_toggle_btn.pressed.connect(_toggle_hotbar)
	# Style the button to match the hotbar theme
	_apply_toggle_style()
	# Add as a sibling control so it lives in the same CanvasLayer
	add_child(_toggle_btn)
	# Position it at bottom center
	_toggle_btn.anchor_left = 0.5
	_toggle_btn.anchor_right = 0.5
	_toggle_btn.anchor_top = 1.0
	_toggle_btn.anchor_bottom = 1.0
	_toggle_btn.offset_left = -60
	_toggle_btn.offset_right = 60
	_toggle_btn.offset_top = -32
	_toggle_btn.offset_bottom = 0
	_toggle_btn.grow_horizontal = Control.GROW_DIRECTION_BOTH

func _apply_toggle_style() -> void:
	var style_normal := StyleBoxFlat.new()
	style_normal.bg_color = panel_bg_color
	style_normal.border_color = panel_border_color
	style_normal.set_border_width_all(2)
	style_normal.corner_radius_top_left = 8
	style_normal.corner_radius_top_right = 8
	style_normal.corner_radius_bottom_left = 0
	style_normal.corner_radius_bottom_right = 0
	_toggle_btn.add_theme_stylebox_override("normal", style_normal)

	var style_hover := style_normal.duplicate()
	style_hover.bg_color = Color(panel_bg_color.r + 0.05, panel_bg_color.g + 0.05, panel_bg_color.b + 0.1, panel_bg_color.a)
	style_hover.border_color = Color(panel_border_color.r, panel_border_color.g, panel_border_color.b, 1.0)
	_toggle_btn.add_theme_stylebox_override("hover", style_hover)

	var style_pressed := style_normal.duplicate()
	style_pressed.bg_color = Color(panel_bg_color.r + 0.08, panel_bg_color.g + 0.08, panel_bg_color.b + 0.15, panel_bg_color.a)
	_toggle_btn.add_theme_stylebox_override("pressed", style_pressed)

	_toggle_btn.add_theme_color_override("font_color", panel_border_color)
	_toggle_btn.add_theme_color_override("font_hover_color", Color(1, 1, 1, 1))

func _toggle_hotbar() -> void:
	if _is_open:
		_hide_hotbar()
	else:
		_show_hotbar()

func _show_hotbar() -> void:
	if _is_open:
		return
	_is_open = true
	_toggle_btn.text = "▼ Close"

	if _panel_tween:
		_panel_tween.kill()
	_panel_tween = create_tween()
	_panel_tween.set_ease(Tween.EASE_OUT)
	_panel_tween.set_trans(Tween.TRANS_BACK)
	# Slide panel up, push toggle button up above it
	_panel_tween.tween_property(hotbar_panel, "position:y", _panel_target_y, 0.35)
	_panel_tween.parallel().tween_property(_toggle_btn, "offset_top", -32 - hotbar_panel.size.y - 4, 0.35)
	_panel_tween.parallel().tween_property(_toggle_btn, "offset_bottom", 0 - hotbar_panel.size.y - 4, 0.35)

func _hide_hotbar() -> void:
	if not _is_open:
		return
	_is_open = false
	_toggle_btn.text = "▲ Turrets"

	if _panel_tween:
		_panel_tween.kill()
	_panel_tween = create_tween()
	_panel_tween.set_ease(Tween.EASE_IN)
	_panel_tween.set_trans(Tween.TRANS_CUBIC)
	# Slide panel back down off screen, toggle button returns to bottom
	var hidden_y = _panel_target_y + hotbar_panel.size.y + 20
	_panel_tween.tween_property(hotbar_panel, "position:y", hidden_y, 0.25)
	_panel_tween.parallel().tween_property(_toggle_btn, "offset_top", -32, 0.25)
	_panel_tween.parallel().tween_property(_toggle_btn, "offset_bottom", 0, 0.25)

func _unhandled_input(event: InputEvent) -> void:
	# Close the hotbar when clicking outside it
	if _is_open and event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var panel_rect = hotbar_panel.get_global_rect()
		var btn_rect = _toggle_btn.get_global_rect()
		var mouse = event.position
		if not panel_rect.has_point(mouse) and not btn_rect.has_point(mouse):
			_hide_hotbar()

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

var current_biome_folder: String = "Desert"
var _biome_frames: Array[Texture2D] = []

func _load_biome_frames() -> void:
	_biome_frames.clear()
	for i in range(2, 9):
		var tex_path = "res://UI/%s/Sprite-000%d.png" % [current_biome_folder, i]
		if ResourceLoader.exists(tex_path):
			_biome_frames.append(load(tex_path))
			
	if is_node_ready() and border_overlay:
		var border_path = "res://UI/%s/%s Border Trial 1.png" % [current_biome_folder, current_biome_folder]
		if ResourceLoader.exists(border_path):
			border_overlay.texture = load(border_path)
			hotbar_panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
			# Optional: hide the title label if there's a custom pixel-art border
			$HotbarPanel/VBox/TitleLabel.hide()
		else:
			border_overlay.texture = null
			_apply_panel_style()
			$HotbarPanel/VBox/TitleLabel.show()
			
	if is_node_ready() and bg_overlay:
		var bg_path = "res://UI/%s/%s Border BG Trial 1.png" % [current_biome_folder, current_biome_folder]
		if ResourceLoader.exists(bg_path):
			bg_overlay.texture = load(bg_path)
		else:
			bg_overlay.texture = null

func _populate_slots() -> void:
	if _biome_frames.is_empty():
		_load_biome_frames()
	for i in range(min(TURRET_ASSETS.size(), _slots.size())):
		var entry: Dictionary = TURRET_ASSETS[i]
		set_slot_turret(i, entry["scene"], entry["name"])
		if _slots[i].has_method("set_bg_frames"):
			_slots[i].set_bg_frames(_biome_frames)

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
	if biome.hotbar_theme != null:
		var path = biome.hotbar_theme.resource_path.to_lower()
		if path.find("desert") != -1: current_biome_folder = "Desert"
		elif path.find("grass") != -1: current_biome_folder = "Grass"
		elif path.find("snow") != -1 or path.find("ice") != -1: current_biome_folder = "Ice"
	_load_biome_frames()
	_populate_slots()
	if _toggle_btn:
		_apply_toggle_style()

func _on_slot_clicked(index: int) -> void:
	if _selected_index == index:
		_slots[index].set_selected(false)
		_selected_index = -1
		var builder = get_tree().get_root().find_child("BuilderController", true, false)
		if builder and builder.has_method("stop_building"):
			builder.stop_building()
		return
	if _selected_index >= 0 and _selected_index < _slots.size():
		_slots[_selected_index].set_selected(false)
	_selected_index = index
	_slots[index].set_selected(true)
	turret_selected.emit(index, TURRET_ASSETS[index]["scene"], TURRET_ASSETS[index].get("attack_range", 1.5))

func _on_building_stopped() -> void:
	if _selected_index != -1 and _selected_index < _slots.size():
		_slots[_selected_index].set_selected(false)
		_selected_index = -1
	_hide_hotbar()
