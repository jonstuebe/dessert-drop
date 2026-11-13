extends SceneTree
## Visual smoke test: plays the game by itself and saves screenshots.
## godot --path . --script res://tools/autoplay.gd -- <out_dir> [drops] [showcase]

var out := "user://shots"
var game: Node

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = args[0]
	DirAccess.make_dir_recursive_absolute(out)
	var drops := int(args[1]) if args.size() > 1 else 30
	var showcase := args.size() > 2 and args[2] == "showcase"
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await _wait(1.2)
	_shot("00_start")
	if showcase:
		for i in range(8, -1, -1):
			game.call("_spawn", i, Vector2(randf_range(160, 560), 520))
			await _wait(0.35)
		await _wait(2.0)
		_shot("01_showcase")
	for k in drops:
		game.call("_aim", randf_range(100, 620))
		await _wait(0.05)
		game.call("_drop")
		await _wait(0.5)
		if k == drops / 2:
			_shot("02_mid")
		if game.get("over"):
			break
	await _wait(1.5)
	_shot("03_end")
	quit(0)

func _wait(s: float) -> void:
	await create_timer(s).timeout

func _shot(name: String) -> void:
	var img := root.get_texture().get_image()
	img.save_png(out.path_join(name + ".png"))
	print("shot ", name)
