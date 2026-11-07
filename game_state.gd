extends Node

## 全局游戏状态(Autoload "GameState")。
## 唯一跨场景保留的数据:英雄队伍、宠物、敌人配置、经验、金币、背包、战斗桥接。
## 地图与战斗场景切换时本节点不被销毁。

const CharacterStatsScript := preload("res://char_stats.gd")
const ItemDataScript := preload("res://item_data.gd")
const SkillDataScript := preload("res://skill_data.gd")

const MAX_HEROES := 5
const MAX_ENEMIES := 20

## 技能池(全部可用技能,战斗前配置)
var skill_pool: Array[Resource] = []
## 自动技能队列:按顺序在多个回合循环释放(战斗中不可更改)
var auto_skills: Array = []
## 手动战斗可用的主动技能列表
var chosen_active_skills: Array = []
## 自动战斗模式每回合自动释放的主动技能(单选)
var auto_active_skill: Resource = null

## 主英雄(1 号),兼容旧引用
var player_stats: CharacterStatsScript
## 全部英雄数据(首位即 player_stats,最多 5)
var hero_stats: Array[Resource] = []
## 宠物模板(每位英雄携带一只,属性可在调试面板调整)
var pet_template: CharacterStatsScript
## 战斗敌人数量(1-20,调试面板可调)
var enemy_count: int = 3
## 敌人模板(调试面板可调,战斗按 enemy_count 循环生成)
var enemy_templates: Array[Resource] = []
var player_hp: int = 0
var player_mp: int = 0
var player_exp: int = 0
var gold: int = 0
var inventory_items: Array[Resource] = []
## 升级获得的未分配属性点
var unspent_points: int = 0
## 地图上接触敌人时写入,战斗场景读取后清空
var pending_enemy: Resource = null

## 消耗 1 点属性点,分配给指定基础属性。成功返回 true。
func spend_point(attribute: StringName) -> bool:
	if unspent_points <= 0:
		return false
	match attribute:
		&"strength":
			player_stats.strength += 1
		&"intelligence":
			player_stats.intelligence += 1
		&"perception":
			player_stats.perception += 1
		&"agility":
			player_stats.agility += 1
		&"constitution":
			player_stats.constitution += 1
		_:
			return false
	unspent_points -= 1
	return true

## 添加一位英雄(复制主英雄模板),最多 MAX_HEROES。
func add_hero() -> bool:
	if hero_stats.size() >= MAX_HEROES:
		return false
	var hero := _clone_stats(player_stats)
	hero.display_name = "英雄 %d" % (hero_stats.size() + 1)
	hero_stats.append(hero)
	return true

## 移除最后一位英雄(至少保留主英雄)。
func remove_hero() -> bool:
	if hero_stats.size() <= 1:
		return false
	hero_stats.pop_back()
	return true

func _ready() -> void:
	_create_player_stats()
	hero_stats = [player_stats]
	_create_pet_template()
	_create_skill_pool()
	chosen_active_skills = skill_pool.duplicate()
	player_hp = player_stats.max_hp
	player_mp = player_stats.max_mp
	if inventory_items.is_empty():
		_grant_starting_items()

## 技能配置接口(地图技能页调用)
func set_auto_skills(list: Array) -> void:
	auto_skills = list

func set_chosen_active_skills(list: Array) -> void:
	chosen_active_skills = list

func set_auto_active_skill(skill: Resource) -> void:
	auto_active_skill = skill

func _create_skill_pool() -> void:
	if not skill_pool.is_empty():
		return
	# 武圣附体(自动,我方全体祝福):免伤护盾+2、状态抵抗+300、伤害减免+300
	var wusheng := SkillDataScript.new()
	wusheng.display_name = "武圣附体"
	wusheng.skill_type = SkillDataScript.SkillType.MAGIC
	wusheng.skill_kind = SkillDataScript.SkillKind.SELF_BUFF
	wusheng.target_scope = SkillDataScript.TargetScope.PARTY
	wusheng.mp_cost = 60
	wusheng.is_auto = true
	wusheng.description = "我方全体祝福:免伤护盾+2、状态抵抗+300、伤害减免+300,持续3回合"
	wusheng.effects = [
		{"key": &"damage_shield", "value": 2.0, "turns": 3},
		{"key": &"status_resist_bonus", "value": 3.0, "turns": 3},
		{"key": &"damage_reduction_bonus", "value": 0.03, "turns": 3},
	]
	skill_pool.append(wusheng)
	# 女妖之嚎(主动,敌方6人魔法诅咒):魔防-4200、状态抵抗-70%、减免-70%、衰弱承伤+20%
	var wuyao := SkillDataScript.new()
	wuyao.display_name = "女妖之嚎"
	wuyao.skill_type = SkillDataScript.SkillType.MAGIC
	wuyao.skill_kind = SkillDataScript.SkillKind.ENEMY_DEBUFF
	wuyao.target_scope = SkillDataScript.TargetScope.ENEMY_GROUP
	wuyao.target_count = 6
	wuyao.mp_cost = 7
	wuyao.description = "敌方6人魔法诅咒7回合:魔防-4200、状态抵抗-70%、减免-70%、承受伤害+20%"
	wuyao.effects = [
		{"key": &"magic_defense_bonus", "value": -42.0, "turns": 7},
		{"key": &"status_resist_bonus", "value": -3.0, "turns": 7},
		{"key": &"damage_reduction_bonus", "value": -0.03, "turns": 7},
		{"key": &"damage_reduction_bonus", "value": -0.2, "turns": 7},
	]
	skill_pool.append(wuyao)
	# 星光漫爆(主动,敌方全体魔法攻击):4段、无视魔防4300、无视减免500、扣15%最大法力
	var xingguang := SkillDataScript.new()
	xingguang.display_name = "星光漫爆"
	xingguang.skill_type = SkillDataScript.SkillType.MAGIC
	xingguang.skill_kind = SkillDataScript.SkillKind.DAMAGE
	xingguang.target_scope = SkillDataScript.TargetScope.ENEMY_ALL
	xingguang.power_multiplier = 1.6
	xingguang.attack_count_override = 4
	xingguang.penetration_bonus = 43
	xingguang.skill_ignore_reduction = true
	xingguang.drain_mp_percent = 0.15
	xingguang.mp_cost = 55
	xingguang.description = "攻击敌方全体,4段魔法伤害,无视4300魔防与伤害减免,扣除15%最大法力"
	skill_pool.append(xingguang)
	# 魔化武器(自动,自身祝福):攻击次数+6、劈砍/穿刺攻击+24%
	var mohua := SkillDataScript.new()
	mohua.display_name = "魔化武器"
	mohua.skill_type = SkillDataScript.SkillType.SLASH
	mohua.skill_kind = SkillDataScript.SkillKind.SELF_BUFF
	mohua.target_scope = SkillDataScript.TargetScope.SELF
	mohua.mp_cost = 8
	mohua.is_auto = true
	mohua.description = "自身祝福5回合:攻击次数+6、劈砍/穿刺攻击+24%"
	mohua.effects = [
		{"key": &"attack_count", "value": 6.0, "turns": 5},
		{"key": &"strength", "value": 3.0, "turns": 5},
		{"key": &"agility", "value": 2.0, "turns": 5},
	]
	skill_pool.append(mohua)

func _create_player_stats() -> void:
	if player_stats != null:
		return
	player_stats = CharacterStatsScript.new()
	player_stats.display_name = "冒险者"
	player_stats.level = 1
	player_stats.strength = 14
	player_stats.intelligence = 14
	player_stats.perception = 10
	player_stats.agility = 10
	player_stats.constitution = 12

func _create_pet_template() -> void:
	if pet_template != null:
		return
	pet_template = CharacterStatsScript.new()
	pet_template.display_name = "小狼"
	pet_template.level = 1
	pet_template.strength = 8
	pet_template.intelligence = 4
	pet_template.perception = 8
	pet_template.agility = 12
	pet_template.constitution = 8
	pet_template.attack_count = 1
	pet_template.crit_chance = 0.08

func _clone_stats(source: CharacterStatsScript) -> CharacterStatsScript:
	var clone := CharacterStatsScript.new()
	for prop: String in source.get_property_list().map(func(p): return p.name):
		if source.get(prop) is Array:
			continue
		clone.set(prop, source.get(prop))
	return clone

func _grant_starting_items() -> void:
	var potion := ItemDataScript.new()
	potion.display_name = "治疗药水"
	potion.item_type = ItemDataScript.ItemType.CONSUMABLE
	potion.hp_restore = 50
	potion.price = 15
	potion.description = "恢复 50 点生命"
	inventory_items.append(potion)
