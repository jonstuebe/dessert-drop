extends Node
## Tiny sound player with a pool of voices so effects can overlap.

const NAMES := ["merge", "drop", "chime", "coin", "pop", "sweep", "upgrade", "fanfare", "gameover", "tap", "nope"]
const VOICES := 10

var _streams: Dictionary = {}
var _players: Array[AudioStreamPlayer] = []
var _next := 0

func _ready() -> void:
	for n: String in NAMES:
		_streams[n] = load("res://assets/sfx/%s.wav" % n)
	for i in VOICES:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)

func play(name: String, pitch: float = 1.0, volume_db: float = 0.0) -> void:
	var p := _players[_next]
	_next = (_next + 1) % VOICES
	p.stream = _streams[name]
	p.pitch_scale = pitch
	p.volume_db = volume_db
	p.play()
