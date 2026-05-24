## Skeleton.gd
##
## Ranged enemy.  Keeps its distance from the player, pathfinds using
## NavigationAgent2D, and fires bone projectiles on a cooldown.
## Transitions into a "flee" sub-state when the player gets too close.
class_name Skeleton
extends Enemy

@export_override var max_hp:      int   = 55
@export_override var move_speed:  float = 85.0
@export_override var contact_dmg: int   = 15
@export_override var attack_cd:   float = 1.8
@export_override var aggro_range: float = 220.0
@export_override var xp_reward:   int   = 12

const PREFERRED_DIST := 90.0
const FLEE_DIST      := 60.0
const SHOOT_DIST     := 180.0

const BoneProjectile := preload("res://scenes/BoneProjectile.tscn")

func _ai_process(delta: float) -> void:
	var d := _dist_to_player()
	if not _alerted and d > aggro_range:
		velocity = velocity.move_toward(Vector2.ZERO, move_speed * delta * 4)
		return

	_alerted = true

	if d < FLEE_DIST:
		# Back away — reverse navigation direction
		var away := (global_position - _player.global_position).normalized()
		velocity = away * move_speed * 0.8
	elif d < PREFERRED_DIST:
		velocity = velocity.move_toward(Vector2.ZERO, move_speed * delta * 3)
	else:
		_navigate_to(_player.global_position)

	# Ranged attack
	if _attack_rem <= 0 and d < SHOOT_DIST:
		_attack_rem = attack_cd
		_shoot_projectile()

func _shoot_projectile() -> void:
	var proj := BoneProjectile.instantiate()
	get_tree().root.add_child(proj)
	proj.global_position = global_position
	var dir := ((_player.global_position) - global_position).normalized()
	proj.direction  = dir
	proj.damage     = contact_dmg
	proj.is_enemy   = true
	AudioManager.play("arrow")
