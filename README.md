# Dungeon Delver

> A complete 2D roguelike dungeon crawler built as a Godot architecture work sample.
> The playable demo runs entirely in the browser via HTML5 Canvas + Web Audio API,
> with full GDScript source code showing how each system maps to native Godot 4.x.

---

## Play Now

**[▶ Open Playable Demo](index.html)** — no install, no plugins

| Key | Action |
|-----|--------|
| `WASD` | Move |
| `Mouse` | Aim |
| `Left Click` | Attack |
| `Shift + WASD` | Dodge roll (invincible during roll) |
| `Q` | Cycle weapon (Sword → Bow → Staff) |
| `E` | Interact / Pick up item / Take stairs |
| `Escape` | Pause |

---

## Architecture Overview

The codebase deliberately mirrors Godot 4's design language so every system has a 1-to-1 mapping to its engine counterpart.

```
JavaScript Demo                 Godot 4 Equivalent
─────────────────────────────────────────────────────────
EventBus (pub/sub singleton)   → EventBus.gd  (signal hub, Autoload)
InputManager                   → Input class + InputMap
AudioManager (Web Audio API)   → AudioManager.gd (Autoload) + AudioStreamPlayer
Camera (lerp + trauma shake)   → Camera2D (position_smoothing + ScreenShakeEffect)
ParticleSystem (object pool)   → CPUParticles2D nodes
DungeonGenerator (BSP)         → DungeonGenerator.gd (RefCounted utility class)
PathFinder (A* on grid)        → AStarGrid2D (built-in, used by NavigationAgent2D)
Entity (CharacterBody2D base)  → CharacterBody2D + move_and_slide()
Player (state machine)         → Player.gd  (enum State, match statement)
Enemy (base + 4 subclasses)    → Enemy.gd + Slime/Skeleton/Ghost/Boss extends Enemy
Weapon (Sword/Bow/Staff)       → Weapon.gd  (base Resource) + weapon scene children
Projectile                     → Projectile.gd (CharacterBody2D or Area2D)
Item (Potion/Gold/Chest)       → Item.gd    (Area2D with pickup signal)
HUD                            → HUD.tscn   (CanvasLayer → Control tree)
Minimap                        → Minimap.gd (SubViewport or custom _draw())
GameManager                    → GameManager.gd (Autoload state machine)
SaveSystem                     → SaveSystem.gd  (Autoload, user:// JSON)
```

---

## System Deep-Dives

### 1. BSP Dungeon Generation (`DungeonGenerator.gd`)

Binary Space Partitioning produces organic, connected dungeons:

```
partition(rect, depth):
  if depth == 0 → place room inside rect
  split rect randomly (horizontal or vertical)
  recurse both halves
  connect the two sub-tree rooms with an L-corridor
```

Key properties:
- Every room is reachable by construction (corridor carved between BSP siblings)
- Room count scales with recursion depth (set by floor number)
- Outputs a flat `grid[y][x]` integer array consumed by TileMap
- Builds an `AStarGrid2D` from the walkable tile set for enemy navigation

### 2. Event Bus / Signal Architecture (`EventBus.gd`)

All cross-system communication goes through the autoloaded `EventBus` node — no direct inter-node references between unrelated systems:

```gdscript
# Emitter (Enemy.gd) — doesn't know who's listening
EventBus.enemy_died.emit(self)

# Subscriber (GameManager.gd) — doesn't know about specific enemies
EventBus.enemy_died.connect(_on_enemy_died)
```

This makes it easy to add new observers (achievements, analytics, UI toasts) without touching existing code.

### 3. Player State Machine (`Player.gd`)

Six explicit states with guarded transitions:

```
IDLE ──► MOVE ──► ATTACK
  ▲        │         │
  └────────┘         │ (on hit)
                     ▼
               DODGE ◄── HURT ──► DEAD
```

`_inv_timer` tracks invincibility frames shared between DODGE and post-HURT windows — preventing the common bug where a player getting hit during a dodge consumes both states.

### 4. Enemy AI

| Enemy | Speed | Behaviour | Special |
|-------|-------|-----------|---------|
| **Slime** | Slow | Wanders → charges | Sine-wave movement |
| **Skeleton** | Medium | A* pathfind + backs off when too close | Ranged bone throw |
| **Ghost** | Medium | Ignores walls, directly approaches | Life drain on contact |
| **Boss** | Slow | A* pathfind + bullet patterns | Two phases, minion summon |

Enemies share a base `Enemy.gd` CharacterBody2D. Each overrides `_ai_process(delta)` — the same hook pattern as Godot's `_physics_process`. NavigationAgent2D handles A* server queries asynchronously so path requests don't stall the main thread.

### 5. Weapon System

Three weapon archetypes as child nodes of `WeaponPivot`:

| Weapon | Mechanic | Cooldown |
|--------|----------|----------|
| **Sword** | Melee arc — `HitboxArea2D` enabled briefly | 0.45 s |
| **Bow** | Hitscan projectile (CharacterBody2D) | 0.70 s |
| **Staff** | Slow AOE projectile — damages all enemies in radius on hit | 1.40 s |

`WeaponPivot` rotates toward the mouse each frame (`look_at(get_global_mouse_position())`). Switching weapons is O(1): toggle `visible` on the active weapon node.

### 6. Particle System

The HTML5 demo uses an explicit object pool of 800 `Particle` instances to avoid GC pressure — an important consideration in game loops. The Godot version replaces this with dedicated `CPUParticles2D` nodes (one per effect type per entity), leveraging Godot's own pooling.

### 7. Camera Trauma Shake

```gdscript
# trauma accumulates on hits; shake magnitude = trauma²  (ensures small hits feel light)
camera.trauma = min(1.0, camera.trauma + hit_trauma)

func _process(delta):
    trauma = max(0, trauma - decay * delta)
    var shake := trauma * trauma * MAX_OFFSET
    offset = Vector2(randf_range(-shake, shake), randf_range(-shake, shake))
```

The quadratic decay curve (`trauma²`) is a well-established game feel pattern — small hits feel proportionally lighter than large ones.

---

## Project Structure

```
dungeon-delver/
├── index.html                 # Self-contained HTML5 playable demo (~3,500 lines)
├── README.md
└── godot/                     # Native Godot 4.x implementation
    ├── project.godot
    ├── scripts/
    │   ├── EventBus.gd        # Autoload: signal hub
    │   ├── GameManager.gd     # Autoload: scene/state management
    │   ├── AudioManager.gd    # Autoload: SFX + music bus
    │   ├── SaveSystem.gd      # Autoload: JSON persistence (user://)
    │   ├── DungeonGenerator.gd # BSP generation + AStarGrid2D
    │   ├── Player.gd          # CharacterBody2D + state machine
    │   ├── Enemy.gd           # Base enemy CharacterBody2D
    │   ├── Skeleton.gd        # Ranged pathfinding enemy
    │   ├── Boss.gd            # Multi-phase bullet-pattern boss
    │   └── ...
    └── scenes/
        ├── Main.tscn
        ├── Dungeon.tscn       # TileMap + spawner + room tracker
        ├── Player.tscn        # Player + Camera2D + weapons
        └── enemies/
```

---

## Technical Highlights

- **Zero external dependencies** — vanilla JS, Web Audio API, Canvas 2D
- **No image assets** — all visuals drawn procedurally with Canvas primitives
- **Procedural audio** — synthesized via Web Audio API oscillators and noise buffers
- **Object-pooled particles** — 800-particle pool, zero allocations per frame
- **Priority-queue A\*** — binary min-heap, O(log n) push/pop
- **BSP dungeon** — guaranteed-connected rooms via sibling corridor linking
- **localStorage high scores** — persisted across sessions

---

## Running the Godot Project

1. Install [Godot 4.2+](https://godotengine.org/download)
2. Open `godot/project.godot` in the editor
3. Press **F5** to run

The HTML5 demo is fully standalone — open `index.html` in any modern browser.
