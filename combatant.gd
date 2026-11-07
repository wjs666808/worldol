class_name Combatant
extends RefCounted

## 战斗单位:英雄/宠物/敌人通用。持有属性、技能与战斗状态。
## 由 Battle 创建并在回合制中驱动。

const CharacterStatsScript := preload("res://char_stats.gd")
const SkillDataScript := preload("res://skill_data.gd")

var display_name: String = "单位"
var stats: CharacterStatsScript
var skills: Array = []
## 自动技能队列:按顺序在多个回合循环释放(战斗前配置,战斗中不可更改)
var auto_skills: Array = []
var side: StringName = &"enemy"
var is_pet: bool = false
var is_player_controlled: bool = false
var hp: int = 0
var mp: int = 0
var shield: int = 0
var alive: bool = true
var buff_origins: Dictionary = {}
var buff_turns: Dictionary = {}

func setup(stats_res: CharacterStatsScript, skill_list: Array, auto_list: Array, side_name: StringName, pet: bool) -> void:
	stats = stats_res
	skills = skill_list
	auto_skills = auto_list
	side = side_name
	is_pet = pet
	display_name = stats_res.display_name
	hp = stats_res.max_hp
	mp = stats_res.max_mp
	shield = stats_res.damage_shield
	alive = true
	buff_origins.clear()
	buff_turns.clear()

func is_enemy_of(other: Combatant) -> bool:
	return side != other.side

func take_damage(raw: int) -> int:
	if raw <= 0:
		return 0
	var absorbed := mini(shield, raw)
	shield -= absorbed
	raw -= absorbed
	if raw > 0 and stats.mana_shield > 0.0:
		var mp_abs := mini(mp, roundi(raw * stats.mana_shield))
		mp -= mp_abs
		raw -= mp_abs
	hp = maxi(hp - raw, 0)
	if hp <= 0:
		alive = false
	return raw

func heal(amount: int) -> void:
	hp = mini(hp + amount, stats.max_hp)

func restore_mp(amount: int) -> void:
	mp = mini(mp + amount, stats.max_mp)
