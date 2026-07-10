shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_opaque, cull_back;

uniform vec4 base_color : source_color = vec4(0.2, 0.8, 1.0, 0.5);
uniform float rim_power : hint_range(0.1, 10.0) = 2.0;

void fragment() {
    // Simple fresnel rim effect
    float NdotV = dot(normalize(NORMAL), normalize(VIEW));
    float rim = 1.0 - max(NdotV, 0.0);
    rim = smoothstep(0.0, 1.0, pow(rim, rim_power));
    
    // Mix solid color with rim for a hologram feel
    ALBEDO = base_color.rgb;
    ALPHA = base_color.a * (0.3 + rim * 0.7);
}
