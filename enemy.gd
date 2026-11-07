class_name EnemySpot
extends Area2D

## 地图敌人节点:玩家接触时写入 GameState 并切换至战斗场景。

const CharacterStatsScript := preload("res://char_stats.gd")

@export var enemy_stats: CharacterStatsScript

func _ready() -> void:
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node) -> void:
	if body is CharacterBody2D:
		var game_state := get_node("/root/GameState")
		game_state.pending_enemy = enemy_stats
		get_tree().change_scene_to_file("res://battle.tscn")
