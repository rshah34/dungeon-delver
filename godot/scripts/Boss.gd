## Boss.gd
##
## Multi-phase boss enemy.  Phase 1 fires radial / spread bullet patterns.
## Phase 2 (≤50% HP) enrages: more shots, faster, summons minions periodically.
## Uses a timer-driven pattern switcher rather than hard-coding frame counts.
class_name Boss
extends Enemy

@export_override var max_hp:      int   = 350
@export_override var move_speed:  float = 55.0
@export_override var contact_dmg: int   = 25
@export_override var attack_cd:   float = 0.8
@export_override var xp_reward:   int   = 100

var _phase:          int   = 1
var _enraged:        bool  = false
var _summon_timer:   float = 10.0
var _pattern_timer:  float = 0.0
var _pattern:        String = "radial"

const BossProjectile := preload("res://scenes/BossProjectile.tscn")
const SlimeScene     := preload("res://scenes/enemies/Slime.tscn")
const GhostScene     := preload("res://scenes/enemies/Ghost.tscn")

func _ai_process(delta: float) -> void:
	_check_phase_transition()
	_pattern_timer -= delta
	_summon_timer  -= delta

	if _summon_timer <= 0:
		_summon_timer = 6.0 if _enraged else 10.0
		_summon_minions()

	if _pattern_timer <= 0:
		_pattern_timer = randf_range(3.0, 6.0)
		_pattern = "spread" if randf() < 0.5 else "radial"

	_navigate_to(_player.global_position)

	if _attack_rem <= 0:
		_attack_rem = attack_cd
		_fire_pattern()

func _check_phase_transition() -> void:
	if _phase == 1 and hp < max_hp * 0.5:
		_phase    = 2
		_enraged  = true
		move_speed      = 90.0
		attack_cd       = 0.5
		EventBus.boss_phase_changed.emit(2)
		EventBus.boss_enraged.emit()
		EventBus.announce.emit("THE BOSS ENRAGES!", 3.0)
		anim.play("enrage")

func _fire_pattern() -> void:
	AudioManager.play("boss_attack")
	if _pattern == "radial":
		var shots := 8 if _enraged else 5
		for i in shots:
			var angle := (float(i) / shots) * TAU
			_spawn_projectile(Vector2.from_angle(angle))
	else:  # spread toward player
		var base_angle := global_position.angle_to_point(_player.global_position)
		var spread_count := 5 if _enraged else 3
		for i in spread_count:
			var offset := (i - spread_count / 2) * 0.2
			_spawn_projectile(Vector2.from_angle(base_angle + offset))

func _spawn_projectile(direction: Vector2) -> void:
	var proj := BossProjectile.instantiate()
	get_tree().root.add_child(proj)
	proj.global_position = global_position
	proj.direction       = direction
	proj.damage          = int(contact_dmg * (1.3 if _enraged else 1.0))
	proj.is_enemy        = true

func _summon_minions() -> void:
	var count := 2 + _phase
	for _i in count:
		var angle := randf() * TAU
		var offset := Vector2.from_angle(angle) * randf_range(60, 100)
		var minion := (GhostScene if randf() < 0.5 else SlimeScene).instantiate()
		get_tree().root.add_child(minion)
		minion.global_position = global_position + offset
		minion.init(_player)
	EventBus.announce.emit("Minions summoned!", 1.5)
