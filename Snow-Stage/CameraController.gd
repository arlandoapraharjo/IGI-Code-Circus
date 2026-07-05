extends Camera3D

@export var move_speed: float = 20.0
@export var zoom_speed: float = 3.0
@export var min_zoom_y: float = 2.0
@export var max_zoom_y: float = 10.0
@export var edge_scroll_margin: float = 20.0

var target_position: Vector3
var initial_position: Vector3

func _ready():
	target_position = global_position
	initial_position = global_position

func _process(delta):
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
		
	# Edge Scrolling (only if window is focused to prevent runaway camera)
	if DisplayServer.window_is_focused():
		var mouse_pos = get_viewport().get_mouse_position()
		var vp_size = get_viewport().size
		
		# Ensure mouse is strictly inside the window, not just clamped at 0
		if mouse_pos.x > 0 and mouse_pos.x < vp_size.x and mouse_pos.y > 0 and mouse_pos.y < vp_size.y:
			if mouse_pos.x < edge_scroll_margin:
				move_dir.x -= 1
			elif mouse_pos.x > vp_size.x - edge_scroll_margin:
				move_dir.x += 1
				
			if mouse_pos.y < edge_scroll_margin:
				move_dir.z -= 1
			elif mouse_pos.y > vp_size.y - edge_scroll_margin:
				move_dir.z += 1
			
	# Only allow movement if we are zoomed in (target_position.y is noticeably smaller than max_zoom_y)
	if target_position.y < max_zoom_y - 0.1:
		if move_dir != Vector3.ZERO:
			move_dir = move_dir.normalized()
			# Move target_position along world X and Z axes
			target_position += Vector3(move_dir.x, 0, move_dir.z) * move_speed * delta
	else:
		# If we are fully zoomed out, snap target back to initial center position
		target_position.x = initial_position.x
		target_position.z = initial_position.z

	# Smoothly interpolate position for a nice fluid feel
	global_position = global_position.lerp(target_position, 10.0 * delta)

func _unhandled_input(event):
	if event is InputEventMouseButton and event.pressed:
		var zoom_dir = Vector3.ZERO
		
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom_dir = -global_transform.basis.z # Zoom in (move forward relative to camera)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom_dir = global_transform.basis.z # Zoom out (move backward relative to camera)
			
		if zoom_dir != Vector3.ZERO:
			var next_pos = target_position + zoom_dir * zoom_speed
			# Clamp based on Y height
			if next_pos.y <= min_zoom_y:
				# Adjust to exactly min_zoom_y
				var diff = min_zoom_y - target_position.y
				next_pos = target_position + zoom_dir * (diff / zoom_dir.y)
			elif next_pos.y >= max_zoom_y:
				# Adjust to exactly max_zoom_y
				var diff = max_zoom_y - target_position.y
				next_pos = target_position + zoom_dir * (diff / zoom_dir.y)
				
			target_position = next_pos
