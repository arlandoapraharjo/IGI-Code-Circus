@tool
extends PanelContainer

## Sci-Fi Hotbar Slot — configurable via Inspector or parent TurretHotbar.
## All colors and size are @export — no hardcoding.

signal slot_clicked(index: int)

# ── Data ─────────────────────────────────────────────────────────────────────

@export var slot_index: int = 0
@export var turret_name: String = ""
@export var turret_scene: PackedScene = null

# ── Layout ───────────────────────────────────────────────────────────────────

@export_group("Layout")
## Width and height of this slot in pixels.
@export var slot_size: float = 50.0:
	set(v):
		slot_size = v
		custom_minimum_size = Vector2(v, v)

# ── Colors ───────────────────────────────────────────────────────────────────

@export_group("Colors / Background")
@export var color_bg_normal: Color = Color(0.04, 0.06, 0.14, 0.88):
	set(v): color_bg_normal = v; _rebuild_styles()
@export var color_bg_hover: Color = Color(0.06, 0.12, 0.28, 0.92):
	set(v): color_bg_hover = v; _rebuild_styles()
@export var color_bg_selected: Color = Color(0.05, 0.16, 0.38, 0.95):
	set(v): color_bg_selected = v; _rebuild_styles()

@export_group("Colors / Border")
@export var color_border_normal: Color = Color(0.10, 0.30, 0.70, 0.60):
	set(v): color_border_normal = v; _rebuild_styles()
@export var color_border_hover: Color = Color(0.20, 0.60, 1.00, 0.90):
	set(v): color_border_hover = v; _rebuild_styles()
@export var color_border_selected: Color = Color(0.30, 0.80, 1.00, 1.00):
	set(v): color_border_selected = v; _rebuild_styles()
@export var color_glow: Color = Color(0.20, 0.70, 1.00, 0.50):
	set(v): color_glow = v; _rebuild_styles()

@export_group("Colors / Border Width")
@export_range(1, 6, 0.5) var border_width_normal: float = 1.5:
	set(v): border_width_normal = v; _rebuild_styles()
@export_range(1, 6, 0.5) var border_width_hover: float = 2.0:
	set(v): border_width_hover = v; _rebuild_styles()
@export_range(1, 6, 0.5) var border_width_selected: float = 2.5:
	set(v): border_width_selected = v; _rebuild_styles()

@export_group("Colors / Shape")
@export_range(0, 20) var corner_radius: int = 6:
	set(v): corner_radius = v; _rebuild_styles()
@export_range(0, 30) var glow_shadow_size: int = 14:
	set(v): glow_shadow_size = v; _rebuild_styles()

# ── Internal state ────────────────────────────────────────────────────────────

var is_selected: bool = false
var is_hovered: bool = false
var _scale_tween: Tween = null
var _rotate_tween: Tween = null
var _turret_instance: Node3D = null
var _is_desert_mode: bool = false

var bg_frames: Array[Texture2D] = []
var bg_frame_index: int = 0
var bg_timer: float = 0.0

@onready var bg_texture: TextureRect = $BgTexture
@onready var sub_viewport: SubViewport        = $HBoxContainer/MarginContainer/SubViewportContainer/SubViewport
@onready var preview_camera: Camera3D         = $HBoxContainer/MarginContainer/SubViewportContainer/SubViewport/PreviewScene/Camera3D
@onready var turret_anchor: Node3D            = $HBoxContainer/MarginContainer/SubViewportContainer/SubViewport/PreviewScene/TurretAnchor
@onready var name_label: Label                = $HBoxContainer/NameLabel
@onready var tooltip_label: Label             = $TooltipLabel

func _ready() -> void:
	custom_minimum_size = Vector2(slot_size, slot_size)
	add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	tooltip_label.hide()
	name_label.text = turret_name
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	gui_input.connect(_on_gui_input)
	sub_viewport.own_world_3d = true
	if turret_scene != null:
		_load_turret_preview()

# ── Style ─────────────────────────────────────────────────────────────────────

func _rebuild_styles() -> void:
	pass

# ── Public API ────────────────────────────────────────────────────────────────

## Called by TurretHotbar to bulk-apply a style config dict.
func apply_theme_config(cfg: Dictionary) -> void:
	if cfg.has("slot_size"):             slot_size             = cfg["slot_size"]
	if cfg.has("color_bg_normal"):       color_bg_normal       = cfg["color_bg_normal"]
	if cfg.has("color_bg_hover"):        color_bg_hover        = cfg["color_bg_hover"]
	if cfg.has("color_bg_selected"):     color_bg_selected     = cfg["color_bg_selected"]
	if cfg.has("color_border_normal"):   color_border_normal   = cfg["color_border_normal"]
	if cfg.has("color_border_hover"):    color_border_hover    = cfg["color_border_hover"]
	if cfg.has("color_border_selected"): color_border_selected = cfg["color_border_selected"]
	if cfg.has("color_glow"):            color_glow            = cfg["color_glow"]
	if cfg.has("border_width_normal"):   border_width_normal   = cfg["border_width_normal"]
	if cfg.has("border_width_hover"):    border_width_hover    = cfg["border_width_hover"]
	if cfg.has("border_width_selected"): border_width_selected = cfg["border_width_selected"]
	if cfg.has("corner_radius"):         corner_radius         = cfg["corner_radius"]
	if cfg.has("glow_shadow_size"):      glow_shadow_size      = cfg["glow_shadow_size"]
	_rebuild_styles()

func set_turret(p_scene: PackedScene, p_name: String) -> void:
	turret_scene = p_scene
	turret_name  = p_name
	if is_inside_tree():
		name_label.text = p_name
		_load_turret_preview()

func set_desert_mode(is_desert: bool) -> void:
	if not is_node_ready():
		await ready
	_is_desert_mode = is_desert

	var margin_container: MarginContainer = $HBoxContainer/MarginContainer
	var spacer: Control = $HBoxContainer/Spacer

	if is_desert:
		# ── Smaller card ─────────────────────────────────────────────────────
		custom_minimum_size = Vector2(72, 68)

		# ── Tight internal margins so the 3D view fills the card ─────────────
		margin_container.add_theme_constant_override("margin_left",   2)
		margin_container.add_theme_constant_override("margin_top",    2)
		margin_container.add_theme_constant_override("margin_right",  2)
		margin_container.add_theme_constant_override("margin_bottom", 16)  # room for label
		margin_container.custom_minimum_size = Vector2(50, 50)

		# Hide the spacer so the HBox doesn't push things apart
		spacer.hide()

		# ── Label: hide from HBoxContainer and show as a bottom overlay ───────
		# Re-parent label to root PanelContainer so it can overlay the card.
		if name_label.get_parent() != self:
			name_label.reparent(self)
		name_label.show()
		
		# In a PanelContainer, anchors/offsets are ignored.
		# Use size_flags to push the label to the bottom.
		name_label.size_flags_vertical = Control.SIZE_SHRINK_END
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_label.vertical_alignment   = VERTICAL_ALIGNMENT_BOTTOM
		
		name_label.add_theme_color_override("font_color", Color(1.0, 0.96, 0.78, 1.0))
		name_label.add_theme_font_size_override("font_size", 9)
		name_label.z_index = 2
	else:
		# ── Restore defaults ─────────────────────────────────────────────────
		custom_minimum_size = Vector2(slot_size, slot_size)
		margin_container.add_theme_constant_override("margin_left",   5)
		margin_container.add_theme_constant_override("margin_top",    5)
		margin_container.add_theme_constant_override("margin_right",  5)
		margin_container.add_theme_constant_override("margin_bottom", 5)
		margin_container.custom_minimum_size = Vector2(50, 50)
		spacer.show()
		# Restore label to HBoxContainer
		if name_label.get_parent() != $HBoxContainer:
			name_label.reparent($HBoxContainer)
		name_label.hide()

func set_selected(value: bool) -> void:
	is_selected = value
	_refresh_visual()

func set_bg_frames(frames: Array[Texture2D]) -> void:
	bg_frames = frames
	_refresh_visual()

# ── Turret Preview ────────────────────────────────────────────────────────────

func _load_turret_preview() -> void:
	if turret_scene == null:
		return
	for child in turret_anchor.get_children():
		child.queue_free()
	_turret_instance = turret_scene.instantiate() as Node3D
	if _turret_instance == null:
		return
	turret_anchor.add_child(_turret_instance)
	await get_tree().process_frame
	_fit_camera_to_turret()
	_start_rotation_animation()

func _fit_camera_to_turret() -> void:
	if not is_instance_valid(_turret_instance):
		return
	var aabb := _collect_aabb(_turret_instance, _turret_instance.transform)
	if aabb.size == Vector3.ZERO:
		preview_camera.position = Vector3(2.0, 2.0, 3.0)
		preview_camera.look_at(Vector3.ZERO, Vector3.UP)
		return
	var center := aabb.get_center()
	var radius := aabb.size.length() * 0.5
	turret_anchor.position = -center
	var fov_rad := deg_to_rad(preview_camera.fov)
	# Use a tighter multiplier in desert mode to make the turret fill more of the card
	var multiplier: float = 1.1 if _is_desert_mode else 1.5
	var dist: float = (radius / tan(fov_rad * 0.5)) * multiplier
	dist = max(dist, 0.5)
	var dir := Vector3(0.7, 0.6, 1.0).normalized()
	preview_camera.position = dir * dist
	preview_camera.look_at(Vector3.ZERO, Vector3.UP)

func _collect_aabb(node: Node3D, xform: Transform3D) -> AABB:
	var result := AABB()
	var combined := xform * node.transform
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh != null:
			var w := combined * mi.mesh.get_aabb()
			result = result.merge(w) if result.size != Vector3.ZERO else w
	for child in node.get_children():
		if child is Node3D:
			var ca := _collect_aabb(child as Node3D, combined)
			if ca.size != Vector3.ZERO:
				result = result.merge(ca) if result.size != Vector3.ZERO else ca
	return result

func _start_rotation_animation() -> void:
	if _rotate_tween:
		_rotate_tween.kill()
	_rotate_tween = create_tween().set_loops()
	_rotate_tween.tween_property(turret_anchor, "rotation:y", TAU, 6.0) \
		.from(0.0).set_trans(Tween.TRANS_LINEAR)

# ── Animation ─────────────────────────────────────────────────────────────────

## Animate the whole card (slot container) scale — used for desert mode.
func _animate_card_scale(target: float) -> void:
	if _scale_tween:
		_scale_tween.kill()
	_scale_tween = create_tween()
	_scale_tween.set_ease(Tween.EASE_OUT)
	_scale_tween.set_trans(Tween.TRANS_BACK)
	_scale_tween.tween_property(self, "scale", Vector2(target, target), 0.18)

## Animate the 3D turret model scale via turret_anchor — desert mode only.
## A scale > 1 makes the model visually "break out" of the card boundary.
func _animate_turret_scale(target: float) -> void:
	if not is_instance_valid(turret_anchor):
		return
	var tw := create_tween()
	tw.set_ease(Tween.EASE_OUT)
	tw.set_trans(Tween.TRANS_BACK)
	tw.tween_property(turret_anchor, "scale", Vector3(target, target, target), 0.22)

## Legacy whole-slot scale — used for non-desert biomes.
func _animate_scale(target: float) -> void:
	if _scale_tween:
		_scale_tween.kill()
	_scale_tween = create_tween()
	_scale_tween.set_ease(Tween.EASE_OUT)
	_scale_tween.set_trans(Tween.TRANS_BACK)
	_scale_tween.tween_property(self, "scale", Vector2(target, target), 0.18)

# ── Process / Visuals ─────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	# Desert cards use a static card tile — no frame animation needed.
	if bg_frames.is_empty() or _is_desert_mode:
		return
	if not is_selected:
		return
	bg_timer += delta
	if bg_timer >= 0.1:
		bg_timer = 0.0
		bg_frame_index = (bg_frame_index + 1) % bg_frames.size()
		bg_texture.texture = bg_frames[bg_frame_index]

func _refresh_visual() -> void:
	if not is_node_ready():
		return

	# Show the card background texture.
	if bg_frames.size() > 0:
		if _is_desert_mode:
			# Desert 6 — always the static card tile.
			bg_texture.texture = bg_frames[0]
		else:
			if not is_selected:
				bg_texture.texture = bg_frames[0]
				bg_frame_index = 0
				bg_timer = 0.0

	if _is_desert_mode:
		if is_selected:
			# Card grows bigger; 3D turret visually breaks beyond the card edge.
			_animate_card_scale(1.15)
			_animate_turret_scale(1.35)
		elif is_hovered:
			# Push-in effect: card slightly shrinks as if pressed inward.
			_animate_card_scale(0.92)
			_animate_turret_scale(0.90)
		else:
			_animate_card_scale(1.0)
			_animate_turret_scale(1.0)
	else:
		if is_selected:
			_animate_scale(1.08)
		elif is_hovered:
			_animate_scale(0.95)
		else:
			_animate_scale(1.0)

# ── Input ──────────────────────────────────────────────────────────────────────

func _on_mouse_entered() -> void:
	is_hovered = true
	_refresh_visual()
	if turret_name != "" and not name_label.visible:
		tooltip_label.text = turret_name
		tooltip_label.show()

func _on_mouse_exited() -> void:
	is_hovered = false
	_refresh_visual()
	tooltip_label.hide()

func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				slot_clicked.emit(slot_index)
			else:
				if not get_global_rect().has_point(get_global_mouse_position()):
					var builder = get_tree().get_root().find_child("BuilderController", true, false)
					if builder and builder.has_method("_try_place_turret"):
						builder._try_place_turret()
