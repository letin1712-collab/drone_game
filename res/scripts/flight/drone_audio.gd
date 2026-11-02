class_name DroneAudio
extends Node
## Âm thanh tạo bằng code (AudioStreamGenerator), không cần file ngoài:
## động cơ (theo lực đẩy), gió (theo tốc độ), mưa, còi pin yếu.

@export var drone: DroneController
@export var weather: WeatherSystem
@export_range(0.0, 1.0) var master_volume := 0.5

const MIX_RATE := 22050.0

var _player: AudioStreamPlayer
var _pb: AudioStreamGeneratorPlayback
var _phase := 0.0
var _beep_phase := 0.0
var _beep_t := 0.0
var _freq := 0.0
var _motor_vol := 0.0
var _lp_wind := 0.0
var _lp_rain := 0.0


func _ready() -> void:
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = MIX_RATE
	gen.buffer_length = 0.12
	_player = AudioStreamPlayer.new()
	_player.stream = gen
	add_child(_player)
	_player.play()
	_pb = _player.get_stream_playback() as AudioStreamGeneratorPlayback


func _process(delta: float) -> void:
	if drone == null or _pb == null:
		return

	# Tần số động cơ 70 → 230 Hz theo lực đẩy; làm mượt để nghe như động cơ tăng/giảm tốc
	var ratio := drone.get_thrust_ratio()
	var f_target := lerpf(70.0, 230.0, ratio) if ratio > 0.01 else 0.0
	var k := 1.0 - exp(-delta * 8.0)
	_freq = lerpf(_freq, f_target, k)
	_motor_vol = lerpf(_motor_vol, 0.0 if ratio <= 0.01 else lerpf(0.12, 0.30, ratio), k)

	var wind_vol := clampf(drone.get_speed() / 15.0, 0.0, 1.0) * 0.25
	var rain_vol := 0.0
	if weather:
		rain_vol = weather.rain_level * 0.18
		wind_vol += clampf(drone.get_wind().length() / 20.0, 0.0, 1.0) * 0.12

	_beep_t += delta
	var beeping := drone.get_battery_percent() < 15.0 and drone.battery_wh > 0.0 \
		and fposmod(_beep_t, 0.6) < 0.15

	for i in _pb.get_frames_available():
		_phase = fposmod(_phase + _freq / MIX_RATE, 1.0)
		var motor := sin(TAU * _phase) * 0.5 + sin(TAU * _phase * 2.0) * 0.25 \
			+ sin(TAU * _phase * 3.0) * 0.12 + (randf() * 2.0 - 1.0) * 0.08
		var s := motor * _motor_vol

		var noise := randf() * 2.0 - 1.0
		_lp_wind += (noise - _lp_wind) * 0.05            # lọc thấp → tiếng ù của gió
		s += _lp_wind * wind_vol * 3.0

		_lp_rain += (noise - _lp_rain) * 0.3
		s += (noise - _lp_rain) * rain_vol                # lọc cao → tiếng rì rào của mưa

		if beeping:
			_beep_phase = fposmod(_beep_phase + 1000.0 / MIX_RATE, 1.0)
			s += sin(TAU * _beep_phase) * 0.2

		s = clampf(s * master_volume, -1.0, 1.0)
		_pb.push_frame(Vector2(s, s))