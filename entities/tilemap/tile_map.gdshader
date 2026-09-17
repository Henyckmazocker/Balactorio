shader_type canvas_item;
void fragment() {
	vec2 uv = UV;

	// Transform to isometric coordinates
	vec2 isoUV;
	isoUV.x = (uv.x - uv.y) * 0.5 + 0.5; 
	isoUV.y = (uv.x + uv.y) * 0.25 + 0.25;

	// Discard pixels outside the isometric diamond shape
	float dx = abs(uv.x - 0.5);  // Horizontal distance from center
	float dy = abs(uv.y - 0.5) * 2.0;  // Vertical distance from center (scaled)

	if (dx + dy > 0.5) {
		discard;
	}

    COLOR = texture(TEXTURE, isoUV);
    COLOR.rgb *= vec3(1.15); // Aumenta brillo
    COLOR.a = 0.8; // Transparencia
}