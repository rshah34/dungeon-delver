## EventBus.gd  —  Autoload singleton
##
## Central signal hub following the "signal bus" pattern. All cross-system
## communication goes through here so nodes stay loosely coupled — no direct
## Node references between unrelated systems.
##
## Usage:
##   EventBus.player_damaged.emit(amount)      # from anywhere
##   EventBus.player_damaged.connect(_on_player_damaged)  # subscriber
extends Node

# ── Player signals ────────────────────────────────────────────────────────────
signal player_damaged(amount: int)
signal player_healed(amount: int)
signal player_died
signal player_floor_changed(floor: int)
signal weapon_changed(weapon_name: String)

# ── Enemy signals ─────────────────────────────────────────────────────────────
signal enemy_damaged(enemy: Node, amount: int)
signal enemy_died(enemy: Node)
signal boss_phase_changed(phase: int)
signal boss_enraged

# ── World signals ─────────────────────────────────────────────────────────────
signal room_entered(room: Resource)
signal room_cleared(room: Resource)
signal door_opened(position: Vector2i)
signal stairs_activated

# ── Item signals ──────────────────────────────────────────────────────────────
signal item_collected(item_type: String, value: int)
signal gold_changed(total: int)

# ── UI signals ────────────────────────────────────────────────────────────────
signal announce(message: String, duration: float)
signal score_changed(score: int)
