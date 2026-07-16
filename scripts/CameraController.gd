extends Camera3D

@export var move_speed: float = 20.0
@export var zoom_speed: float = 2.5
@export var min_ortho_size: float = 5.0
## Calculated at runtime from the map — leave at 0 to auto-compute,
## or set manually in the Inspector to override.
@export var max_ortho_size_override: float = 0.0

var target_position: Vector3
var initial_position: Vector3
var target_ortho_size: float
var max_ortho_size: float
## How many extra tiles beyond the map edge the camera can pan (to see the sea)
@export var border_margin: float = 3.0
var _bounds_min: Vector3
var _bounds_max: Vector3

func _ready():
	_compute_max_zoom()
	_compute_bounds()
	# Center the camera over the generated map
	_center_on_map()
	# Start fully zoomed out showing the whole map
	target_ortho_size = max_ortho_size
	size = max_ortho_size

## Position the camera so it looks directly at the map center.
func _center_on_map():
	var map_node = get_node_or_null("../Map")
	var map_center_local = Vector3(10.0, 0.0, 10.0) # default for MAP_SIZE=20
	if map_node:
		var ms = 20.0
		var ts = 1.0
		if "MAP_SIZE" in map_node:
			ms = float(map_node.MAP_SIZE)
		if "TILE_SIZE" in map_node:
			ts = float(map_node.TILE_SIZE)
		map_center_local = Vector3(ms * ts * 0.5, 0.0, ms * ts * 0.5)
		# Convert map-local center to world space
		var map_center_world = map_node.to_global(map_center_local)
		# Keep the camera at its original height, shift X/Z to sit over center
		# For an angled camera we need to offset along the look direction
		var cam_height = global_position.y
		# The camera looks down at an angle — to center the view on the map
		# center, we offset the camera position by the height * tan(pitch)
		# along the camera's forward direction projected onto the XZ plane.
		var forward_xz = -global_transform.basis.z
		forward_xz.y = 0
		forward_xz = forward_xz.normalized()
		# Distance from directly-above to where the camera sits so its
		# look ray hits the ground plane at the map center
		var pitch_angle = asin(abs(global_transform.basis.z.y))
		var horizontal_offset = cam_height / tan(pitch_angle)
		var new_pos = Vector3(map_center_world.x, cam_height, map_center_world.z)
		new_pos -= forward_xz * horizontal_offset
		global_position = new_pos
	else:
		# Fallback — keep wherever the scene placed us
		pass

	initial_position = global_position
	target_position = global_position

## Compute the world-space XZ boundaries the camera is allowed to pan within.
func _compute_bounds():
	var map_node = get_node_or_null("../Map")
	if map_node == null:
		# Generous fallback
		_bounds_min = Vector3(-50, 0, -50)
		_bounds_max = Vector3(50, 0, 50)
		return

	var ms = 20.0
	var ts = 1.0
	var bw = 4.0
	if "MAP_SIZE" in map_node:
		ms = float(map_node.MAP_SIZE)
	if "TILE_SIZE" in map_node:
		ts = float(map_node.TILE_SIZE)
	if "BORDER_WIDTH" in map_node:
		bw = float(map_node.BORDER_WIDTH)

	# Map local bounds: tiles span 0..MAP_SIZE, border adds BORDER_WIDTH on each side
	var local_min = Vector3(-bw - border_margin, 0, -bw - border_margin) * ts
	var local_max = Vector3(ms + bw + border_margin, 0, ms + bw + border_margin) * ts

	# Convert to world space
	_bounds_min = map_node.to_global(local_min)
	_bounds_max = map_node.to_global(local_max)

	# Ensure min < max for each axis
	if _bounds_min.x > _bounds_max.x:
		var tmp = _bounds_min.x
		_bounds_min.x = _bounds_max.x
		_bounds_max.x = tmp
	if _bounds_min.z > _bounds_max.z:
		var tmp = _bounds_min.z
		_bounds_min.z = _bounds_max.z
		_bounds_max.z = tmp

## Compute the max ortho size so the entire generated map fits on screen.
func _compute_max_zoom():
	if max_ortho_size_override > 0.0:
		max_ortho_size = max_ortho_size_override
		return

	# Pull map constants from MapGenerator script
	var map_node = get_node_or_null("../Map")
	if map_node == null:
		max_ortho_size = 40.0 # safe fallback
		return

	var map_total = 20.0  # MAP_SIZE default
	var border = 4.0      # BORDER_WIDTH default
	var tile = 1.0        # TILE_SIZE default

	# Read the constants if the script exposes them
	if "MAP_SIZE" in map_node:
		map_total = float(map_node.MAP_SIZE)
	if "BORDER_WIDTH" in map_node:
		border = float(map_node.BORDER_WIDTH)
	if "TILE_SIZE" in map_node:
		tile = float(map_node.TILE_SIZE)

	var world_extent = (map_total + border * 2.0) * tile

	# The camera is angled (~45°), so the vertical span it needs is larger
	# than the flat world extent. Use the viewport aspect ratio to pick
	# whichever axis is tighter.
	var vp = get_viewport()
	var aspect = 1.0
	if vp and vp.size.y > 0:
		aspect = float(vp.size.x) / float(vp.size.y)

	# ortho size = half the vertical span the camera sees.
	# With a ~45° pitch the ground footprint along the camera's up axis
	# is compressed by cos(pitch). For a 42-47° look-down that's ≈ 0.7.
	var pitch_factor = 0.72
	var needed_vertical = world_extent / pitch_factor
	var needed_horizontal = world_extent / aspect

	max_ortho_size = max(needed_vertical, needed_horizontal) * 0.75
	# Ensure it's never smaller than starting size
	max_ortho_size = maxf(max_ortho_size, size)

func _physics_process(delta):
	var move_dir = Vector3.ZERO
	
	# Keyboard Movement (WASD or Arrow Keys)
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
		move_dir.z -= 1
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
		move_dir.z += 1
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		move_dir.x -= 1
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		move_dir.x += 1
		
	# Apply movement — scale speed with zoom level so panning feels consistent
	if move_dir != Vector3.ZERO:
		move_dir = move_dir.normalized()
		var speed_factor = target_ortho_size / max_ortho_size
		target_position += Vector3(move_dir.x, 0, move_dir.z) * move_speed * speed_factor * delta

	# Clamp target within map boundaries
	target_position.x = clampf(target_position.x, _bounds_min.x, _bounds_max.x)
	target_position.z = clampf(target_position.z, _bounds_min.z, _bounds_max.z)

	# Smoothly interpolate position
	global_position = global_position.lerp(target_position, 10.0 * delta)
	
	# Smoothly interpolate orthographic size for zoom
	size = lerpf(size, target_ortho_size, 10.0 * delta)

func _unhandled_input(event):
	if event is InputEventKey and event.pressed and event.keycode == KEY_R:
		get_tree().reload_current_scene()
		
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			# Zoom in — decrease orthographic size
			target_ortho_size = clampf(target_ortho_size - zoom_speed, min_ortho_size, max_ortho_size)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			# Zoom out incrementally
			target_ortho_size = clampf(target_ortho_size + zoom_speed, min_ortho_size, max_ortho_size)
			# Once zoomed out past 80% of max, snap to the full overview
			if target_ortho_size >= max_ortho_size * 0.8:
				target_ortho_size = max_ortho_size
				target_position = initial_position
