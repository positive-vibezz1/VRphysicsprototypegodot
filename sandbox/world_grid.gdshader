shader_type spatial;
// Meter lines in world space, so the eye can judge size, distance and speed on otherwise plain surfaces.

uniform vec3 color : source_color = vec3(0.5);
uniform float line_width = 0.012;

varying vec3 world_position;
varying vec3 world_normal;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = abs(mat3(MODEL_MATRIX) * NORMAL);
}

void fragment() {
	// Distance to the nearest line on each axis, leaving out the axis the surface faces along.
	vec3 to_line = abs(fract(world_position - 0.5) - 0.5) + step(0.7, world_normal);
	float nearest = min(to_line.x, min(to_line.y, to_line.z));
	float line = 1.0 - smoothstep(line_width, line_width + fwidth(nearest), nearest);
	ALBEDO = color * (1.0 - 0.35 * line);
	ROUGHNESS = 0.9;
}
