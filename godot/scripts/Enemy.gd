## Enemy.gd  —  Base class for all enemy types
##
## CharacterBody2D with a shared behaviour interface.  Subclasses override
## _ai_process() to implement their specific decision logic.  Each enemy
## carries its own NavigationAgent2D so A* is handled per-instance by Godot's
## navigation server (no manual A* bookkeeping needed in 4.x).
##
## Subclasses:  Slime · Skeleton · Ghost · Boss
class_name Enemy
extends CharacterBody2D

signal died(enemy: Enemy)

# ── Stats set by subclass @export ─────────────────────────────────────────────
@export var max_hp:        int   = 30
@export var move_speed:    float = 70.0
@export var contact_dmg:   int   = 10
@export var attack_cd:     float = 1.2
@export var aggro_range:   float = 180.0
@export var xp_reward:     int   = 5

# ── Shared nodes ──────────────────────────────────────────────────────────────
@onready var nav_agent:      NavigationAgent2D = $NavigationAgent2D
@onready var anim:           AnimationPlayer   = $AnimationPlayer
@onready var detection_area: Area2D            = $DetectionArea
@onready var hitbox:         CollisionShape2D  = $CollisionShape2D
@onready var particles_death: CPUParticles2D   = $Particles/Death

# ── Runtime ───────────────────────────────────────────────────────────────────
var hp:          int
var _attack_rem: float = 0.0
var _inv_rem:    float = 0.0
var _flash_rem:  float = 0.0
var _alerted:    bool  = false
var _player:     Player                         # set by Dungeon on spawn

func _ready() -> void:
	hp = max_hp
	detection_area.body_entered.connect(_on_detection_entered)
	detection_area.body_exited.connect(_on_detection_exited)
	add_to_group("enemies")

func init(player: Player) -> void:
	_player = player

func _physics_process(delta: float) -> void:
	if not _player or hp <= 0:
		return
	_attack_rem -= delta
	_inv_rem    -= delta
	_flash_rem  -= delta
	modulate = Color(1, 0.4, 0.4) if _flash_rem > 0 and fmod(_flash_rem, 0.06) > 0.03 else Color.WHITE
	_ai_process(delta)
	move_and_slide()

# Subclasses implement this — mirrors the _process_* pattern from the demo
func _ai_process(_delta: float) -> void:
	pass

func _navigate_to(target_pos: Vector2, speed_mult: float = 1.0) -> void:
	nav_agent.target_position = target_pos
	if nav_agent.is_navigation_finished():
		velocity = Vector2.ZERO
		return
	var next := nav_agent.get_next_path_position()
	velocity = (next - global_position).normalized() * move_speed * speed_mult

func take_damage(amount: int, knockback: Vector2 = Vector2.ZERO) -> void:
	if _inv_rem > 0:
		return
	hp        -= amount
	velocity  += knockback
	_flash_rem = 0.25
	_inv_rem   = 0.15
	_alerted   = true
	anim.play("hurt")
	EventBus.enemy_damaged.emit(self, amount)
	if hp <= 0:
		_die()

func _die() -> void:
	hp = 0
	set_physics_process(false)
	hitbox.set_deferred("disabled", true)
	set_collision_layer_value(1, false)
	anim.play("death")
	particles_death.restart()
	EventBus.enemy_died.emit(self)
	died.emit(self)
	await get_tree().create_timer(0.8).timeout
	queue_free()

func _on_detection_entered(body: Node2D) -> void:
	if body is Player:
		_alerted = true

func _on_detection_exited(_body: Node2D) -> void:
	pass  # enemies stay alerted once triggered

# ── Utility ───────────────────────────────────────────────────────────────────
func _dist_to_player() -> float:
	if not _player: return INF
	return global_position.distance_to(_player.global_position)

func _knock_toward(target: Node2D, force: float) -> Vector2:
	return (target.global_position - global_position).normalized() * force
