class_name VisionPostProcess
extends CanvasLayer
## V: Normal -> Thermal -> Night Vision. Hiệu ứng toàn màn hình bằng shader.

enum Vision { NORMAL, THERMAL, NIGHT }
signal vision_changed(mode: Vision)

var current := Vision.NORMAL
var _rect: ColorRect
var _mat: ShaderMaterial
var _time := 0.0

const SHADER_CODE := """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform int mode = 0;
uniform float time_s = 0.0;
uniform float noise_amount = 0.06;

float hash(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }

// Bảng màu "ironbow" của camera nhiệt: đen-tím -> đỏ -> cam -> trắng vàng
vec3 ironbow(float t) {
	t = clamp(t, 0.0, 1.0);
	vec3 c = mix(vec3(0.0, 0.0, 0.08), vec3(0.35, 0.0, 0.55), smoothstep(0.0, 0.25, t));
	c = mix(c, vec3(0.85, 0.12, 0.25), smoothstep(0.25, 0.5, t));
	c = mix(c, vec3(1.0, 0.65, 0.0), smoothstep(0.5, 0.75, t));
	c = mix(c, vec3(1.0, 1.0, 0.85), smoothstep(0.75, 1.0, t));
	return c;
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec3 col = texture(screen_tex, uv).rgb;
	float lum = dot(col, vec3(0.299, 0.587, 0.114));
	float n = hash(uv * vec2(1280.0, 720.0) + time_s) - 0.5;
	vec3 outc = col;

	if (mode == 1) {
		// Thermal: vật thường nguội (nén độ sáng), vật phát nhiệt (rất sáng) nóng rực
		float heat = lum * 0.35 + smoothstep(0.8, 0.97, lum) * 0.65;
		heat += n * noise_amount;
		outc = ironbow(heat);
		outc *= 0.92 + 0.08 * sin(uv.y * 700.0); // đường quét
	} else if (mode == 2) {
		// Night Vision: khuếch đại ánh sáng, tông xanh lá, nhiễu hạt, tối viền
		float g = clamp(pow(lum * 2.5, 0.8), 0.0, 1.0);
		outc = vec3(0.1, 1.0, 0.25) * g + vec3(0.3, 1.0, 0.3) * n * noise_amount * 2.0;
		outc *= 1.0 - smoothstep(0.35, 0.85, distance(uv, vec2(0.5)));
	}
	COLOR = vec4(outc, 1.0);
}
"""


func _enter_tree() -> void:
	add_to_group("vision_post")


func _ready() -> void:
	layer = 1  # Dưới HUD (layer 2), trên cảnh 3D
	var shader := Shader.new()
	shader.code = SHADER_CODE
	_mat = ShaderMaterial.new()
	_mat.shader = shader

	_rect = ColorRect.new()
	_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.material = _mat
	_rect.visible = false
	add_child(_rect)

	DroneInput.cycle_vision.connect(cycle)


func _process(delta: float) -> void:
	_time += delta
	_mat.set_shader_parameter("time_s", _time)


func cycle() -> void:
	set_vision((current + 1) % Vision.size() as Vision)


func set_vision(mode: Vision) -> void:
	current = mode
	_rect.visible = mode != Vision.NORMAL
	_mat.set_shader_parameter("mode", int(mode))
	vision_changed.emit(mode)