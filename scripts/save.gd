extends Node
## Persistent player data: best score, coins, and which desserts have been seen.

const PATH := "user://save.cfg"

var best := 0
var reached := 3          # the drop tiers are known from the start
var coins := 3
var earned_once := false
var first_run := false

var _cfg := ConfigFile.new()

func _ready() -> void:
	if _cfg.load(PATH) != OK:
		first_run = true   # starter coins, given once
		write()
		return
	best = _cfg.get_value("player", "best", 0)
	reached = _cfg.get_value("player", "reached", 3)
	coins = _cfg.get_value("player", "coins", 3)
	earned_once = _cfg.get_value("player", "earned_once", false)

func write() -> void:
	_cfg.set_value("player", "best", best)
	_cfg.set_value("player", "reached", reached)
	_cfg.set_value("player", "coins", coins)
	_cfg.set_value("player", "earned_once", earned_once)
	_cfg.save(PATH)
