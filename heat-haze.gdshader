shader_type spatial; 
render_mode unshaded, fog_disabled;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
uniform sampler2D noise_texture : repeat_enable, filter_linear;
uniform float speed : hint_range(0.01, 0.2) = 0.05;
uniform float strength : hint_range(0.001, 0.1) = 0.01;

void fragment() {
	// Pan the noise upwards to simulate rising heat
	vec2 noise_uv = UV + vec2(0.0, TIME * speed);
	
	// Sample noise and remap from [0, 1] to [-1, 1]
	float noise_val = texture(noise_texture, noise_uv).r * 2.0 - 1.0;
	
	// Apply shimmering distortion (horizontal and vertical)
	vec2 distortion = vec2(noise_val) * strength;
	
	// Fetch the pixel behind this mesh using SCREEN_UV and apply the distortion
	ALBEDO = texture(screen_texture, SCREEN_UV + distortion).rgb;
}
