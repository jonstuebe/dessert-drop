extends SceneTree
## Records a short gameplay clip for social posts.
## Plays the game by itself inside an off-screen 1080x1920 SubViewport and saves
## every frame as a JPG; run it under Movie Maker so the game audio is captured.
## Use tools/record_trailer.sh rather than calling this directly.
##
## godot --path . --write-movie <audio.avi> --fixed-fps 60 \
##   --script res://tools/record_trailer.gd -- <frames_dir> [seconds] [seed] [shot]
##
## shot is "auto" (default: a mid-game jar, played by aiming at twins) or one of
## the scripted SHOTS below. Every drop and merge is printed as an EVENT line
## (frame number, kind, tier) so the edit can be cut to them; a scripted shot
## ends with one more saying whether its biggest dessert is upright or tipped. A frames_dir of
## "-" is a dry run: nothing is saved, only the EVENT lines are printed.

const OUT_SIZE := Vector2i(1080, 1920)
const LOGICAL := Vector2i(833, 1481)  # >= 720x1480 stage; 9:16 like OUT_SIZE
const WARMUP := 1.5                   # seconds simulated before frames are kept

## Scripted shots. "pile" is [tier, x, y] in stage space, placed at rest before
## recording starts; "drops" is [tier, x, seconds to wait first]; "reached" is
## how far up the ladder the player is shown to have been (controls the
## "New dessert" toasts); "score" is the score on screen at the start.
const SHOTS := {
	# one macaron sets off cupcake -> donut -> cherry pie -> strawberry cake -> wedding cake
	"wedding": {
		"reached": 7, "score": 2860,
		"pile": [[7, 231.0, 1159.0], [6, 527.0, 1154.0], [5, 549.0, 959.0], [4, 318.0, 984.0], [3, 316.0, 868.0],
			[2, 150.0, 1002.0], [0, 205.0, 1030.0]],
		"drops": [[3, 316.0, 0.7]],
	},
}

var frames_dir := ""
var seconds := 22.0
var shot := "auto"
var dry := false
var rng_seed := 7
var game: Node
var vp: SubViewport
var recording := false
var frame := 0
var warmup_frames := 0

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	frames_dir = args[0]
	if args.size() > 1:
		seconds = float(args[1])
	if args.size() > 3:
		shot = args[3]
	dry = frames_dir == "-"
	if not dry:
		DirAccess.make_dir_recursive_absolute(frames_dir)

	vp = SubViewport.new()
	vp.size = OUT_SIZE
	vp.size_2d_override = LOGICAL
	vp.size_2d_override_stretch = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.audio_listener_enable_2d = true
	root.add_child(vp)
	game = load("res://scenes/main.tscn").instantiate()
	vp.add_child(game)
	rng_seed = int(args[2]) if args.size() > 2 else 7
	process_frame.connect(_on_frame)
	_play()

func _on_frame() -> void:
	if not recording:
		warmup_frames += 1
		return
	if not dry:
		var img := vp.get_texture().get_image()
		img.save_jpg(frames_dir.path_join("f%05d.jpg" % frame), 0.93)
	frame += 1

## Drops enter at the drop height; anything else that appears was baked by a merge.
func _on_spawn(d: Node) -> void:
	if recording:
		var kind := "drop" if is_equal_approx(d.position.y, game.DROP_Y) else "merge"
		print("EVENT frame=%d kind=%s tier=%d" % [frame, kind, d.tier])

func _play() -> void:
	await _wait(0.2)
	# the game calls randomize() in _ready, so the seed has to be set after it
	seed(rng_seed)
	game.get("desserts").child_entered_tree.connect(_on_spawn)
	if SHOTS.has(shot):
		await _play_shot(SHOTS[shot])
		return
	_seed_pile()
	await _wait(WARMUP)
	recording = true
	var elapsed := 0.0
	while elapsed < seconds - 1.5 and not game.get("over"):
		await _drop_one()
		elapsed = frame / 60.0
	await _wait(1.5)
	print("WARMUP_FRAMES=%d FRAMES=%d" % [warmup_frames, frame])
	quit(0)

func _play_shot(cfg: Dictionary) -> void:
	var save := root.get_node("Save")
	save.set("reached", cfg["reached"])
	game.get("hud").call("set_ladder", -1)
	for item: Array in cfg["pile"]:
		game.call("_spawn", item[0], Vector2(item[1], item[2]))
	game.call("_clear_hint")
	game.set("score", 0)
	game.call("_add_score", cfg["score"])
	var drops: Array = cfg["drops"]
	if not drops.is_empty():
		game.set("current", drops[0][0])
		game.call("_show_preview", false)
		game.call("_aim", 360.0)
	await _wait(WARMUP)
	recording = true
	for k in drops.size():
		var step: Array = drops[k]
		while not game.get("can_drop"):
			await _wait(1.0 / 60.0)
		game.set("current", step[0])
		if k > 0:
			game.call("_show_preview", true)
		await _wait(step[2])
		await _glide_to(step[1])
		await _wait(0.14)
		if k + 1 < drops.size():
			game.set("next", drops[k + 1][0])
		game.call("_drop")
		if k + 1 < drops.size():
			game.get("hud").call("set_next", drops[k + 1][0])
	while frame < int(seconds * 60.0):
		await _wait(1.0 / 60.0)
	# say how the biggest dessert came to rest, so a take where it tipped over can be redone
	var top: Node = null
	for d in game.get("desserts").get_children():
		if top == null or d.tier > top.tier:
			top = d
	if top:
		print("EVENT frame=%d kind=%s tier=%d" % [frame, "upright" if absf(sin(top.rotation)) < 0.2 else "tipped", top.tier])
	print("WARMUP_FRAMES=%d FRAMES=%d" % [warmup_frames, frame])
	quit(0)

## A mid-game jar so the clip opens on merges instead of an empty jar.
func _seed_pile() -> void:
	var layout := [
		[6, 200.0], [5, 380.0], [4, 540.0],
		[3, 150.0], [2, 290.0], [4, 430.0], [1, 590.0],
		[0, 230.0], [2, 520.0],
	]
	var y := 1100.0
	for item: Array in layout:
		game.call("_spawn", item[0], Vector2(item[1], y))
		y -= 110.0
	game.call("_clear_hint")
	game.set("score", 0)
	game.call("_add_score", 1240)

func _drop_one() -> void:
	while not game.get("can_drop") and not game.get("over"):
		await _wait(1.0 / 60.0)
	if game.get("over"):
		return
	var target := _pick_target()
	if target:
		game.set("current", target.tier)
		game.call("_show_preview", true)
		await _glide_to(target.position.x)
	else:
		await _glide_to(randf_range(160.0, 560.0))
	await _wait(randf_range(0.12, 0.22))
	game.call("_drop")
	await _wait(randf_range(0.35, 0.6))

## An exposed droppable dessert (tier 0-3) to land a twin on. Prefers higher tiers
## and spots next to the next tier up, so merges chain into each other.
func _pick_target() -> Node:
	var all: Array = game.get("desserts").get_children()
	var best: Node = null
	var best_score := -INF
	for d in all:
		if d.merging or d.is_queued_for_deletion() or d.tier > 3:
			continue
		if not _exposed(d, all):
			continue
		var s: float = d.tier * 2.0 + randf() * 1.5
		for o in all:
			if o != d and o.tier == d.tier + 1 and o.position.distance_to(d.position) < Tiers.radius(d.tier) + Tiers.radius(o.tier) + 30.0:
				s += 3.0
		if s > best_score:
			best_score = s
			best = d
	return best

func _exposed(d: Node, all: Array) -> bool:
	var r: float = Tiers.radius(d.tier)
	for o in all:
		if o == d or o.is_queued_for_deletion():
			continue
		if o.position.y < d.position.y - 4.0 and absf(o.position.x - d.position.x) < (r + Tiers.radius(o.tier)) * 0.75:
			return false
	return true

## Moves the aim like a finger sliding across, instead of snapping.
func _glide_to(x: float) -> void:
	var from: float = game.get("aim_x")
	var steps := int(clampf(absf(x - from) / 14.0, 6.0, 22.0))
	for i in steps:
		var t := float(i + 1) / steps
		t = t * t * (3.0 - 2.0 * t)
		game.call("_aim", lerpf(from, x, t))
		await _wait(1.0 / 60.0)

func _wait(s: float) -> void:
	await create_timer(s).timeout
