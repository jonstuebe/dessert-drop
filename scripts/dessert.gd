class_name Dessert
extends RigidBody2D
## One dessert in the jar. Reports touching a twin through `twin_touched`.

signal twin_touched(a: Dessert, b: Dessert)

const MASS_PER_PX2 := 1.0 / 1000.0

var tier := 0
var born_ms := 0
var merging := false
var over_time := 0.0      # seconds spent resting above the danger line
var no_coins := false     # made by the Upgrade perk: pays no coins

var sprite: Sprite2D

## Jar floor in stage space (set by the game); used to place landing dust.
static var floor_y := 1264.0
var _squash := Vector2.ONE

func setup(t: int) -> void:
	tier = t
	var info := Tiers.info(t)
	var sz := Tiers.size(t)
	var r := Tiers.radius(t)

	# collision follows the drawn silhouette (see Tiers.shapes)
	for sh in Tiers.shapes(t):
		var shape := CollisionShape2D.new()
		shape.shape = sh
		add_child(shape)

	sprite = Sprite2D.new()
	sprite.texture = Art.dessert(t, r)
	sprite.scale = Vector2.ONE / Art.SS
	add_child(sprite)

	mass = maxf(sz.x * sz.y * MASS_PER_PX2, 1.0)
	var mat := PhysicsMaterial.new()
	mat.friction = info.get("friction", 0.35)
	mat.bounce = info.get("bounce", 0.25) * 0.55
	physics_material_override = mat
	linear_damp = 0.15
	angular_damp = 1.2
	continuous_cd = RigidBody2D.CCD_MODE_CAST_SHAPE
	contact_monitor = true
	max_contacts_reported = 8
	can_sleep = true
	body_entered.connect(_on_body_entered)
	born_ms = Time.get_ticks_msec()

func age() -> float:
	return (Time.get_ticks_msec() - born_ms) / 1000.0

## Pop-in animation for a freshly baked dessert.
func appear(from_scale: float = 0.55) -> void:
	sprite.scale = Vector2.ONE / Art.SS * from_scale
	var tw := create_tween()
	tw.tween_property(sprite, "scale", Vector2.ONE / Art.SS, 0.35).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)

func _on_body_entered(body: Node) -> void:
	var other := body as Dessert
	if other == null:
		var speed := linear_velocity.length()
		var half := Tiers.size(tier).y / 2.0 if absf(cos(rotation)) > 0.7 else Tiers.size(tier).x / 2.0
		if position.y + half > floor_y - 14.0:
			_dust(Vector2(position.x, floor_y - 4.0), speed)
		_impact(speed)
		return
	if other.tier == tier and not merging and not other.merging:
		merging = true
		other.merging = true
		twin_touched.emit(self, other)
	else:
		var rel := (linear_velocity - other.linear_velocity).length()
		# one of the pair reports it, at roughly where they touch
		if get_instance_id() < other.get_instance_id():
			var ra := Tiers.radius(tier)
			_dust(position.lerp(other.position, ra / (ra + Tiers.radius(other.tier))), rel)
		_impact(rel)

## A puff of flour at a hard landing. Purely cosmetic.
func _dust(at: Vector2, speed: float) -> void:
	if speed < 420.0 or age() < 0.05:
		return
	var fx := get_tree().get_first_node_in_group("fx") as Fx
	if fx:
		fx.dust(at, clampf((speed - 420.0) / 900.0, 0.0, 1.0))

## Small squash when something lands hard.
func _impact(speed: float) -> void:
	if age() >= 0.08:
		Sfx.land(speed, tier)
	if speed < 260.0 or sprite == null:
		return
	var k := clampf((speed - 260.0) / 900.0, 0.0, 0.18)
	var base := Vector2.ONE / Art.SS
	var tw := create_tween()
	tw.tween_property(sprite, "scale", base * Vector2(1.0 + k, 1.0 - k), 0.06)
	tw.tween_property(sprite, "scale", base, 0.25).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
