## SaveSystem.gd  —  Autoload singleton
##
## Persists high scores and player preferences to user://save.json.
## Godot's user:// path resolves to a platform-appropriate location
## (%APPDATA%, ~/.local/share, ~/Library/Application Support, etc.).
extends Node

const SAVE_PATH := "user://save.json"
const MAX_SCORES := 10

var _data: Dictionary = {
	"high_scores": [],
	"settings": { "sfx_vol": 1.0, "music_vol": 0.8 }
}

func _ready() -> void:
	_load()

func save_score(score: int, floor_reached: int) -> void:
	_data.high_scores.append({
		"score":         score,
		"floor_reached": floor_reached,
		"date":          Time.get_date_string_from_system()
	})
	_data.high_scores.sort_custom(func(a, b): return a.score > b.score)
	if _data.high_scores.size() > MAX_SCORES:
		_data.high_scores.resize(MAX_SCORES)
	_save()

func get_high_scores() -> Array:
	return _data.high_scores

func set_setting(key: String, value: Variant) -> void:
	_data.settings[key] = value
	_save()

func get_setting(key: String, default: Variant = null) -> Variant:
	return _data.settings.get(key, default)

func _save() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(_data, "\t"))

func _load() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f:
		var parsed := JSON.parse_string(f.get_as_text())
		if parsed is Dictionary:
			_data.merge(parsed, true)
