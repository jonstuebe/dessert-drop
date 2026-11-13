extends Node
## Tiny sound player with a pool of voices so effects can overlap.
## Sounds with several takes (merge, drop, land) pick one at random, never the same twice running.

## Sound name -> number of takes. One take lives in <name>.wav, several in <name>_1.wav, <name>_2.wav...
const SOUNDS := {
	"merge": 3, "drop": 3, "land": 3, "chime": 1, "coin": 1, "pop": 1, "sweep": 1,
	"upgrade": 1, "fanfare": 1, "gameover": 1, "tap": 1, "nope": 1,
}
const VOICES := 12
const LAND_MIN_SPEED := 240.0   # px/s; gentler touches stay silent
const LAND_GAP_MS := 80         # a settling pile makes at most one bump per this long

var _streams: Dictionary = {}   # name -> Array of AudioStream
var _last: Dictionary = {}      # name -> index of the take played last
var _players: Array[AudioStreamPlayer] = []
var _next := 0
var _land_ms := -1000

func _ready() -> void:
	for n: String in SOUNDS:
		var takes: Array[AudioStream] = []
		var count: int = SOUNDS[n]
		for i in count:
			var path := "res://assets/sfx/%s.wav" % n if count == 1 else "res://assets/sfx/%s_%d.wav" % [n, i + 1]
			takes.append(load(path))
		_streams[n] = takes
	for i in VOICES:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)
	# Safety net for big moments (a chain of merges plus coins plus a fanfare): never clip the output.
	var limiter := AudioEffectHardLimiter.new()
	limiter.ceiling_db = -1.0
	AudioServer.add_bus_effect(AudioServer.get_bus_index("Master"), limiter)

func play(name: String, pitch: float = 1.0, volume_db: float = 0.0) -> void:
	var takes: Array = _streams.get(name, [])
	if takes.is_empty():
		return
	var i := 0
	if takes.size() > 1:
		var last: int = _last.get(name, -1)
		if last < 0:
			i = randi() % takes.size()
		else:
			i = (last + 1 + randi() % (takes.size() - 1)) % takes.size()
		_last[name] = i
	var p := _free_voice()
	p.stream = takes[i]
	p.pitch_scale = maxf(pitch, 0.05)
	p.volume_db = volume_db
	p.play()

## Soft bump for a dessert hitting the jar or another dessert. Louder for harder hits,
## lower for bigger desserts, and rate-limited so a settling pile does not rattle.
func land(speed: float, tier: int = 0) -> void:
	if speed < LAND_MIN_SPEED:
		return
	var now := Time.get_ticks_msec()
	if now - _land_ms < LAND_GAP_MS:
		return
	_land_ms = now
	var k := clampf((speed - LAND_MIN_SPEED) / 1300.0, 0.0, 1.0)
	play("land", randf_range(0.92, 1.08) * (1.25 - tier * 0.06), lerpf(-14.0, -3.0, sqrt(k)))

## An idle voice if there is one, otherwise the next in line (roughly the oldest).
func _free_voice() -> AudioStreamPlayer:
	for k in VOICES:
		var p := _players[(_next + k) % VOICES]
		if not p.playing:
			_next = (_next + k + 1) % VOICES
			return p
	var q := _players[_next]
	_next = (_next + 1) % VOICES
	return q
