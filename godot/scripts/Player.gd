## Player.gd
##
## CharacterBody2D controller.  Uses an explicit state machine rather than
## Godot's AnimationTree so state transitions are readable and testable.
##
## States: IDLE → MOVE → ATTACK → DODGE → HURT → DEAD
##
## Children (set up in Player.tscn):
##   - CollisionShape2D        (20×20 px capsule)
##   - AnimationPlayer         (idle, run, attack, hurt, death sprites)
##   - HitboxArea2D            (sword melee range — enabled only during ATTACK)
##   - WeaponPivot/Node2D      (rotates toward mouse; holds weapon sprites)
##   - CPUParticles2D x3       (blood, sparks, dodge_smoke)
##   - Camera2D                (position_smoothing_enabled = true)
##   - InteractRay             (RayCast2D pointing toward mouse for interact)
class_name Player
extends CharacterBody2D

signal died

enum State { IDLE, MOVE, ATTACK, DODGE, HURT, DEAD }

# ── Stats ─────────────────────────────────────────────────────────────────────
@export var max_hp:      int   = 120
@export var move_speed:  float = 160.0
@export var dodge_speed: float = 310.0
@export var dodge_dur:   float = 0.28
@export var dodge_cd:    float = 0.9

# ── Nodes (assigned in _ready via $path) ─────────────────────────────────────
@onready var anim:          AnimationPlayer = $AnimationPlayer
@onready var hitbox:        Area2D          = $HitboxArea2D
@onready var weapon_pivot:  Node2D          = $WeaponPivot
@onready var particles_blood:  CPUParticles2D = $Particles/Blood
@onready var particles_sparks: CPUParticles2D = $Particles/Sparks
@onready var particles_dodge:  CPUParticles2D = $Particles/DodgeSmoke
@onready var camera:        Camera2D        = $Camera2D
@onready var interact_ray:  RayCast2D       = $InteractRay

# ── Weapons (child nodes of WeaponPivot) ─────────────────────────────────────
@onready var weapons: Array[Node] = [
	$WeaponPivot/Sword,
	$WeaponPivot/Bow,
	$WeaponPivot/Staff,
]
var weapon_idx: int = 0
var current_weapon: Node:
	get: return weapons[weapon_idx]

# ── Runtime state ─────────────────────────────────────────────────────────────
var hp:             int   = max_hp
var gold:           int   = 0
var score:          int   = 0
var _state:         State = State.IDLE
var _dodge_timer:   float = 0.0
var _dodge_cd_rem:  float = 0.0
var _dodge_dir:     Vector2
var _inv_timer:     float = 0.0   # invincibility window
var _flash_timer:   float = 0.0
var _death_timer:   float = 1.5

func _ready() -> void:
	hp = max_hp
	hitbox.monitoring = false
	hitbox.body_entered.connect(_on_hitbox_body_entered)
	EventBus.room_cleared.connect(_on_room_cleared)
	_update_weapon_visibility()

func _physics_process(delta: float) -> void:
	if _flash_timer > 0:
		_flash_timer -= delta
		modulate = Color.WHITE if fmod(_flash_timer, 0.08) > 0.04 else Color(1, 0.3, 0.3)
	else:
		modulate = Color.WHITE

	if _inv_timer  > 0: _inv_timer  -= delta
	if _dodge_cd_rem > 0: _dodge_cd_rem -= delta

	match _state:
		State.IDLE, State.MOVE: _process_locomotion(delta)
		State.DODGE:            _process_dodge(delta)
		State.HURT:             _process_hurt(delta)
		State.DEAD:             _process_dead(delta)

	move_and_slide()
	_aim_weapon()

func _process_locomotion(delta: float) -> void:
	var dir := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	velocity = dir * move_speed

	if dir != Vector2.ZERO:
		_state = State.MOVE
		anim.play("run")
	else:
		_state = State.IDLE
		anim.play("idle")

	# Dodge
	if Input.is_action_pressed("dodge") and dir != Vector2.ZERO and _dodge_cd_rem <= 0:
		_dodge_dir    = dir.normalized()
		_dodge_timer  = dodge_dur
		_dodge_cd_rem = dodge_cd
		_inv_timer    = dodge_dur
		_state        = State.DODGE
		particles_dodge.restart()
		anim.play("dodge")

	# Weapon cycle
	if Input.is_action_just_pressed("cycle_weapon"):
		weapon_idx = (weapon_idx + 1) % weapons.size()
		_update_weapon_visibility()
		EventBus.weapon_changed.emit(current_weapon.weapon_name)

	# Attack
	if Input.is_action_pressed("attack"):
		_start_attack()

func _process_dodge(delta: float) -> void:
	velocity      = _dodge_dir * dodge_speed
	_dodge_timer -= delta
	if _dodge_timer <= 0:
		_state = State.IDLE

func _process_hurt(delta: float) -> void:
	velocity = velocity.move_toward(Vector2.ZERO, 600 * delta)
	if _flash_timer <= 0:
		_state = State.IDLE

func _process_dead(delta: float) -> void:
	velocity = velocity.move_toward(Vector2.ZERO, 400 * delta)
	_death_timer -= delta
	if fmod(_death_timer, 0.15) < 0.075:
		particles_blood.restart()

func _aim_weapon() -> void:
	var mouse_world := get_global_mouse_position()
	weapon_pivot.look_at(mouse_world)
	interact_ray.target_position = (mouse_world - global_position).normalized() * 40

func _start_attack() -> void:
	if _state in [State.HURT, State.DEAD]:
		return
	current_weapon.try_fire(self)

func _on_hitbox_body_entered(body: Node2D) -> void:
	# Called when sword hitbox overlaps an enemy (during ATTACK state)
	if body.has_method("take_damage"):
		var knock := (body.global_position - global_position).normalized() * 130
		body.take_damage(current_weapon.damage, knock)
		particles_sparks.global_position = body.global_position
		particles_sparks.restart()
		camera.trauma += 0.25

func take_damage(amount: int, knockback: Vector2 = Vector2.ZERO) -> void:
	if _inv_timer > 0 or _state == State.DODGE or _state == State.DEAD:
		return
	hp          = max(0, hp - amount)
	velocity   += knockback
	_flash_timer = 0.3
	_inv_timer   = 0.4
	_state       = State.HURT
	anim.play("hurt")
	particles_blood.restart()
	camera.trauma += 0.4
	EventBus.player_damaged.emit(amount)
	if hp <= 0:
		_die()

func heal(amount: int) -> void:
	hp = min(max_hp, hp + amount)
	EventBus.player_healed.emit(amount)

func _die() -> void:
	_state = State.DEAD
	anim.play("death")
	hitbox.set_deferred("monitoring", false)
	set_collision_layer_value(1, false)
	await get_tree().create_timer(1.5).timeout
	EventBus.player_died.emit()
	died.emit()

func _on_room_cleared(_room) -> void:
	score += 50
	EventBus.score_changed.emit(score)

func _update_weapon_visibility() -> void:
	for i in weapons.size():
		weapons[i].visible = i == weapon_idx
