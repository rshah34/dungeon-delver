## GameManager.gd  —  Autoload singleton
##
## Owns the high-level game state machine and orchestrates scene transitions.
## Mirrors the role of the GameManager in the HTML5 demo.
##
## State machine:
##   MENU → PLAYING ↔ PAUSED
##                 ↓
##           FLOOR_TRANSITION
##                 ↓
##           PLAYING (next floor) | WIN
##   PLAYING → GAME_OVER
extends Node

enum State { MENU, PLAYING, PAUSED, FLOOR_TRANSITION, GAME_OVER, WIN }

const FLOOR_SCENE  := "res://scenes/Dungeon.tscn"
const MENU_SCENE   := "res://scenes/MainMenu.tscn"
const MAX_FLOORS   := 5

var state: State = State.MENU
var current_floor: int = 0
var score: int = 0
var gold:  int = 0

var _dungeon_node: Node = null   # current Dungeon scene instance

func _ready() -> void:
	EventBus.player_died.connect(_on_player_died)
	EventBus.stairs_activated.connect(_on_stairs_activated)

func start_game() -> void:
	score = 0
	gold  = 0
	current_floor = 0
	_load_next_floor()

func _load_next_floor() -> void:
	current_floor += 1
	state = State.FLOOR_TRANSITION
	# Fade out, swap scene, fade in — handled by TransitionLayer CanvasLayer
	await get_tree().create_timer(0.3).timeout
	if _dungeon_node:
		_dungeon_node.queue_free()
	_dungeon_node = load(FLOOR_SCENE).instantiate()
	_dungeon_node.floor_number = current_floor
	get_tree().root.add_child(_dungeon_node)
	state = State.PLAYING
	EventBus.player_floor_changed.emit(current_floor)
	EventBus.announce.emit("Floor %d — Descend!" % current_floor, 2.5)

func _on_player_died() -> void:
	state = State.GAME_OVER
	SaveSystem.save_score(score, current_floor)
	await get_tree().create_timer(1.5).timeout
	get_tree().change_scene_to_file(MENU_SCENE)

func _on_stairs_activated() -> void:
	score += 200 + current_floor * 100
	EventBus.score_changed.emit(score)
	if current_floor >= MAX_FLOORS:
		state = State.WIN
		SaveSystem.save_score(score, current_floor)
	else:
		_load_next_floor()

func add_score(points: int) -> void:
	score += points
	EventBus.score_changed.emit(score)

func add_gold(amount: int) -> void:
	gold += amount
	EventBus.gold_changed.emit(gold)

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and state == State.PLAYING:
		state = State.PAUSED
		get_tree().paused = true
