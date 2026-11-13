shader_type canvas_item;
// Top-to-bottom colour fade for a Label's fill (used by the logo).
uniform vec4 top : source_color = vec4(1.0);
uniform vec4 bottom : source_color = vec4(1.0);
uniform float y0 = 0.0;
uniform float y1 = 64.0;
varying float vy;

void vertex() {
	vy = VERTEX.y;
}

void fragment() {
	float k = smoothstep(y0, y1, vy);
	COLOR.rgb = mix(top.rgb, bottom.rgb, k);
}
