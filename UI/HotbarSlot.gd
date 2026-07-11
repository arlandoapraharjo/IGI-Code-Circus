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
var _style_normal: StyleBoxFlat
var _style_hover: StyleBoxFlat
var _style_selected: StyleBoxFlat

@onready var sub_viewport: SubViewport        = $MarginContainer/SubViewportContainer/SubViewport
@onready var preview_camera: Camera3D         = $MarginContainer/SubViewportContainer/SubViewport/PreviewScene/Camera3D
@onready var turret_anchor: Node3D            = $MarginContainer/SubViewportContainer/SubViewport/PreviewScene/TurretAnchor
@onready var tooltip_label: Label             = $TooltipLabel

func _ready() -> void:
	custom_minimum_size = Vector2(slot_size, slot_size)
	_rebuild_styles()
	add_theme_stylebox_override("panel", _style_normal)
	tooltip_label.hide()
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	gui_input.connect(_on_gui_input)
	sub_viewport.own_world_3d = true
	if turret_scene != null:
		_load_turret_preview()

# ── Style ─────────────────────────────────────────────────────────────────────

func _rebuild_styles() -> void:
	if not is_node_ready():
		return
	_style_normal   = _make_style(color_bg_normal,   color_border_normal,   border_width_normal,   0.0)
	_style_hover    = _make_style(color_bg_hover,    color_border_hover,    border_width_hover,    4.0)
	_style_selected = _make_style(color_bg_selected, color_border_selected, border_width_selected, float(glow_shadow_size))
	_style_selected.shadow_color = color_glow
	# Apply current state style immediately
	if is_selected:
		add_theme_stylebox_override("panel", _style_selected)
	elif is_hovered:
		add_theme_stylebox_override("panel", _style_hover)
	else:
		add_theme_stylebox_override("panel", _style_normal)

func _make_style(bg: Color, border: Color, bw: float, shadow: float) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color    = bg
	s.border_color = border
	s.set_border_width_all(int(bw))
	s.corner_radius_top_left     = corner_radius
	s.corner_radius_top_right    = corner_radius
	s.corner_radius_bottom_left  = corner_radius
	s.corner_radius_bottom_right = corner_radius
	s.shadow_color  = Color(border.r, border.g, border.b, 0.40)
	s.shadow_size   = int(shadow)
	s.shadow_offset = Vector2.ZERO
	return s

# ── Public API ────────────────────────────────────────────────────────────────

## Called by TurretHotbar to bulk-apply a style config dict.
## Keys: slot_size, color_bg_normal, color_bg_hover, color_bg_selected,
##       color_border_normal, color_border_hover, color_border_selected,
##       color_glow, border_width_normal, border_width_hover,
##       border_width_selected, corner_radius, glow_shadow_size
func apply_theme_config(cfg: Dictionary) -> void:
	if cfg.has("slot_size"):            slot_size            = cfg["slot_size"]
	if cfg.has("color_bg_normal"):      color_bg_normal      = cfg["color_bg_normal"]
	if cfg.has("color_bg_hover"):       color_bg_hover       = cfg["color_bg_hover"]
	if cfg.has("color_bg_selected"):    color_bg_selected    = cfg["color_bg_selected"]
	if cfg.has("color_border_normal"):  color_border_normal  = cfg["color_border_normal"]
	if cfg.has("color_border_hover"):   color_border_hover   = cfg["color_border_hover"]
	if cfg.has("color_border_selected"):color_border_selected= cfg["color_border_selected"]
	if cfg.has("color_glow"):           color_glow           = cfg["color_glow"]
	if cfg.has("border_width_normal"):  border_width_normal  = cfg["border_width_normal"]
	if cfg.has("border_width_hover"):   border_width_hover   = cfg["border_width_hover"]
	if cfg.has("border_width_selected"):border_width_selected= cfg["border_width_selected"]
	if cfg.has("corner_radius"):        corner_radius        = cfg["corner_radius"]
	if cfg.has("glow_shadow_size"):     glow_shadow_size     = cfg["glow_shadow_size"]
	
	_rebuild_styles()

func set_turret(p_scene: PackedScene, p_name: String) -> void:
	turret_scene = p_scene
	turret_name  = p_name
	if is_inside_tree():
		_load_turret_preview()

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
	var dist   := (radius / tan(fov_rad * 0.5)) * 1.5
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

# ── Selection ──────────────────────────────────────────────────────────────────

func set_selected(value: bool) -> void:
	is_selected = value
	_refresh_visual()

func _refresh_visual() -> void:
	if not is_node_ready():
		return
	if is_selected:
		add_theme_stylebox_override("panel", _style_selected)
		_animate_scale(1.08)
	elif is_hovered:
		add_theme_stylebox_override("panel", _style_hover)
		_animate_scale(1.03)
	else:
		add_theme_stylebox_override("panel", _style_normal)
		_animate_scale(1.0)

func _animate_scale(target: float) -> void:
	if _scale_tween:
		_scale_tween.kill()
	_scale_tween = create_tween()
	_scale_tween.set_ease(Tween.EASE_OUT)
	_scale_tween.set_trans(Tween.TRANS_BACK)
	_scale_tween.tween_property(self, "scale", Vector2(target, target), 0.18)

# ── Input ──────────────────────────────────────────────────────────────────────

func _on_mouse_entered() -> void:
	is_hovered = true
	_refresh_visual()
	if turret_name != "":
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
