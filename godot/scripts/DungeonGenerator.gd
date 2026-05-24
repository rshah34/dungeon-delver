## DungeonGenerator.gd
##
## Binary Space Partitioning dungeon generator.  Mirrors the DungeonGenerator
## class from the HTML5 demo; produces a TileMap-compatible grid plus a list of
## Room resources and an AStarGrid2D used by enemies.
##
## Algorithm:
##   1. Recursively split the map rectangle (BSP)
##   2. Place one room per leaf, respecting min/max size
##   3. Connect sibling leaves with L-shaped corridors
##   4. Stamp WALL_TOP tiles (wall cells whose southern neighbour is floor)
##   5. Place door tiles at room-corridor junctions
##   6. Build AStarGrid2D from the walkable tile set
class_name DungeonGenerator
extends RefCounted

const TILE_EMPTY     := 0
const TILE_FLOOR     := 1
const TILE_WALL      := 2
const TILE_WALL_TOP  := 3
const TILE_DOOR      := 4
const TILE_DOOR_OPEN := 5
const TILE_STAIRS    := 6

const MAP_W := 56
const MAP_H := 42

var grid: Array = []        # Array[Array[int]]  — [y][x]
var rooms: Array = []       # Array[DungeonRoom]
var start_room: DungeonRoom
var end_room:   DungeonRoom
var astar: AStarGrid2D

class BSPNode:
	var rect: Rect2i
	var left:  BSPNode
	var right: BSPNode
	var room:  DungeonRoom

	func _init(r: Rect2i) -> void:
		rect = r

	func is_leaf() -> bool:
		return left == null and right == null

	func get_room() -> DungeonRoom:
		if is_leaf(): return room
		var lr := left.get_room()
		var rr := right.get_room()
		if not lr: return rr
		if not rr: return lr
		return lr if randf() < 0.5 else rr

class DungeonRoom:
	var rect: Rect2i
	var center: Vector2i
	var cleared := false
	var visited := false
	var doors:   Array[Vector2i] = []
	var enemies: Array         = []

	func _init(r: Rect2i) -> void:
		rect   = r
		center = r.get_center()

	func random_floor_pos() -> Vector2i:
		return Vector2i(
			randi_range(rect.position.x + 1, rect.end.x - 2),
			randi_range(rect.position.y + 1, rect.end.y - 2)
		)

func generate(floor: int) -> void:
	_init_grid()
	rooms.clear()
	var min_room := 5 + floor / 2
	var depth    := 4 + mini(floor, 3)
	var root     := BSPNode.new(Rect2i(1, 1, MAP_W - 2, MAP_H - 2))
	_split(root, depth, min_room)
	_create_rooms(root, min_room)
	_carve_corridors(root)
	_add_wall_tops()
	_place_doors()
	_build_astar()
	rooms.sort_custom(func(a, b): return a.center.length_squared() < b.center.length_squared())
	start_room = rooms.front()
	end_room   = rooms.back()
	grid[end_room.center.y][end_room.center.x] = TILE_STAIRS

func _init_grid() -> void:
	grid = []
	for _y in MAP_H:
		var row := []
		for _x in MAP_W:
			row.append(TILE_WALL)
		grid.append(row)

func _split(node: BSPNode, depth: int, min_size: int) -> void:
	if depth == 0:
		return
	var horiz := node.rect.size.y > node.rect.size.x \
		if node.rect.size.y != node.rect.size.x else randf() < 0.5
	if horiz:
		var min_s := min_size + 2
		var max_s := node.rect.size.y - min_size - 2
		if max_s < min_s:
			return
		var split := randi_range(min_s, max_s)
		node.left  = BSPNode.new(Rect2i(node.rect.position, Vector2i(node.rect.size.x, split)))
		node.right = BSPNode.new(Rect2i(node.rect.position + Vector2i(0, split), Vector2i(node.rect.size.x, node.rect.size.y - split)))
	else:
		var min_s := min_size + 2
		var max_s := node.rect.size.x - min_size - 2
		if max_s < min_s:
			return
		var split := randi_range(min_s, max_s)
		node.left  = BSPNode.new(Rect2i(node.rect.position, Vector2i(split, node.rect.size.y)))
		node.right = BSPNode.new(Rect2i(node.rect.position + Vector2i(split, 0), Vector2i(node.rect.size.x - split, node.rect.size.y)))
	_split(node.left,  depth - 1, min_size)
	_split(node.right, depth - 1, min_size)

func _create_rooms(node: BSPNode, min_size: int) -> void:
	if node.is_leaf():
		var max_w := mini(node.rect.size.x - 2, min_size + 5)
		var max_h := mini(node.rect.size.y - 2, min_size + 5)
		if max_w < min_size or max_h < min_size:
			return
		var rw := randi_range(min_size, max_w)
		var rh := randi_range(min_size, max_h)
		var rx := node.rect.position.x + randi_range(1, node.rect.size.x - rw - 1)
		var ry := node.rect.position.y + randi_range(1, node.rect.size.y - rh - 1)
		var room := DungeonRoom.new(Rect2i(rx, ry, rw, rh))
		node.room = room
		rooms.append(room)
		for ty in range(ry, ry + rh):
			for tx in range(rx, rx + rw):
				var is_border := tx == rx or tx == rx + rw - 1 or ty == ry or ty == ry + rh - 1
				grid[ty][tx] = TILE_WALL if is_border else TILE_FLOOR
	else:
		if node.left:  _create_rooms(node.left,  min_size)
		if node.right: _create_rooms(node.right, min_size)

func _carve_corridors(node: BSPNode) -> void:
	if not node.left or not node.right:
		return
	_carve_corridors(node.left)
	_carve_corridors(node.right)
	var a := node.left.get_room()
	var b := node.right.get_room()
	if not a or not b:
		return
	if randf() < 0.5:
		_h_corridor(a.center.x, b.center.x, a.center.y)
		_v_corridor(a.center.y, b.center.y, b.center.x)
	else:
		_v_corridor(a.center.y, b.center.y, a.center.x)
		_h_corridor(a.center.x, b.center.x, b.center.y)

func _h_corridor(x1: int, x2: int, y: int) -> void:
	for x in range(mini(x1, x2), maxi(x1, x2) + 1):
		if _in_bounds(x, y):
			grid[y][x] = TILE_FLOOR

func _v_corridor(y1: int, y2: int, x: int) -> void:
	for y in range(mini(y1, y2), maxi(y1, y2) + 1):
		if _in_bounds(x, y):
			grid[y][x] = TILE_FLOOR

func _add_wall_tops() -> void:
	for y in range(MAP_H - 1):
		for x in MAP_W:
			if grid[y][x] == TILE_WALL and grid[y + 1][x] == TILE_FLOOR:
				grid[y][x] = TILE_WALL_TOP

func _place_doors() -> void:
	for room in rooms:
		var r := room.rect
		for x in range(r.position.x, r.end.x):
			_try_door(room, x, r.position.y - 1)
			_try_door(room, x, r.end.y)
		for y in range(r.position.y, r.end.y):
			_try_door(room, r.position.x - 1, y)
			_try_door(room, r.end.x, y)

func _try_door(room: DungeonRoom, tx: int, ty: int) -> void:
	if not _in_bounds(tx, ty):
		return
	if grid[ty][tx] == TILE_FLOOR:
		grid[ty][tx] = TILE_DOOR
		room.doors.append(Vector2i(tx, ty))

func _build_astar() -> void:
	astar = AStarGrid2D.new()
	astar.region          = Rect2i(0, 0, MAP_W, MAP_H)
	astar.cell_size       = Vector2(32, 32)
	astar.diagonal_mode   = AStarGrid2D.DIAGONAL_MODE_NEVER
	astar.update()
	for y in MAP_H:
		for x in MAP_W:
			var t := grid[y][x]
			var solid := t == TILE_WALL or t == TILE_WALL_TOP
			astar.set_point_solid(Vector2i(x, y), solid)

func open_doors(room: DungeonRoom) -> void:
	for pos in room.doors:
		if grid[pos.y][pos.x] == TILE_DOOR:
			grid[pos.y][pos.x] = TILE_DOOR_OPEN
			astar.set_point_solid(pos, false)

func is_walkable(tx: int, ty: int) -> bool:
	if not _in_bounds(tx, ty):
		return false
	var t := grid[ty][tx]
	return t in [TILE_FLOOR, TILE_DOOR, TILE_DOOR_OPEN, TILE_STAIRS]

func room_at(world_pos: Vector2) -> DungeonRoom:
	var tx := int(world_pos.x / 32)
	var ty := int(world_pos.y / 32)
	for room in rooms:
		if room.rect.has_point(Vector2i(tx, ty)):
			return room
	return null

func _in_bounds(x: int, y: int) -> bool:
	return x >= 0 and x < MAP_W and y >= 0 and y < MAP_H
