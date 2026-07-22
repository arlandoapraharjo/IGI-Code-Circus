extends Control

func _on_start_button_pressed() -> void:
	var fade_rect = ColorRect.new()
	fade_rect.color = Color(0, 0, 0, 0)
	fade_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(fade_rect)
	
	var tween = create_tween()
	tween.tween_property(fade_rect, "color", Color(0, 0, 0, 1), 0.3)
	tween.tween_callback(func(): get_tree().change_scene_to_file("res://map.tscn"))

func _on_exit_button_pressed() -> void:
	get_tree().quit()
