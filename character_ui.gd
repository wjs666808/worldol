class_name CharacterUI
extends Node

## 角色属性面板:展示五维基础属性与全部派生/高级属性,支持属性点分配。
## 挂在地图场景下,子节点 Panel 为面板 CanvasLayer(默认隐藏)。

const CharacterStatsScript := preload("res://char_stats.gd")

const STAT_KEYS: Array[StringName] = [
	&"strength", &"intelligence", &"perception", &"agility", &"constitution",
]
const STAT_NAMES: Array[String] = ["力量", "智力", "感知", "敏捷", "体质"]

@onready var _character_button: Button = $Buttons/CharacterButton
@onready var _panel: CanvasLayer = $Panel
@onready var _hero_select: OptionButton = $Panel/Center/VBox/Header/HeroSelect
@onready var _info_label: Label = $Panel/Center/VBox/InfoLabel
@onready var _stat_list: VBoxContainer = $Panel/Center/VBox/StatList
@onready var _derived_label: Label = $Panel/Center/VBox/DerivedScroll/DerivedLabel
@onready var _close_button: Button = $Panel/Center/VBox/CloseButton

var _hero_index := 0

func _ready() -> void:
	_character_button.pressed.connect(toggle)
	_close_button.pressed.connect(toggle)
	_hero_select.item_selected.connect(_on_hero_selected)
	_panel.visible = false

func toggle() -> void:
	_panel.visible = not _panel.visible
	if _panel.visible:
		_rebuild()

func _current_hero() -> CharacterStatsScript:
	var gs: Node = get_node("/root/GameState")
	if gs.hero_stats.is_empty():
		return null
	_hero_index = clampi(_hero_index, 0, gs.hero_stats.size() - 1)
	return gs.hero_stats[_hero_index] as CharacterStatsScript

func _on_hero_selected(index: int) -> void:
	_hero_index = index
	_rebuild()

func _rebuild() -> void:
	var gs: Node = get_node("/root/GameState")
	_hero_select.clear()
	for i in gs.hero_stats.size():
		var stats := gs.hero_stats[i] as CharacterStatsScript
		_hero_select.add_item(stats.display_name)
	_hero_select.select(_hero_index)
	var stats := _current_hero()
	if stats == null:
		return
	_info_label.text = "%s Lv.%d    未分配属性点:%d" % [stats.display_name, stats.level, gs.unspent_points]
	_clear_container(_stat_list)
	for i in STAT_KEYS.size():
		_stat_list.add_child(_build_stat_row(STAT_KEYS[i], STAT_NAMES[i], stats, gs))
	_derived_label.text = _build_derived_text(stats)

func _build_stat_row(attr: StringName, attr_name: String, stats: CharacterStatsScript, gs: Node) -> HBoxContainer:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.custom_minimum_size = Vector2(220, 32)
	label.text = "%s: %d" % [attr_name, _get_stat(stats, attr)]
	var add_button := Button.new()
	add_button.text = "+"
	add_button.custom_minimum_size = Vector2(44, 32)
	add_button.disabled = gs.unspent_points <= 0
	add_button.pressed.connect(_on_add_pressed.bind(stats, attr))
	row.add_child(label)
	row.add_child(add_button)
	return row

func _get_stat(stats: CharacterStatsScript, attr: StringName) -> int:
	match attr:
		&"strength":
			return stats.strength
		&"intelligence":
			return stats.intelligence
		&"perception":
			return stats.perception
		&"agility":
			return stats.agility
		&"constitution":
			return stats.constitution
	return 0

func _on_add_pressed(stats: CharacterStatsScript, attr: StringName) -> void:
	var gs: Node = get_node("/root/GameState")
	if gs.unspent_points <= 0:
		return
	match attr:
		&"strength":
			stats.strength += 1
		&"intelligence":
			stats.intelligence += 1
		&"perception":
			stats.perception += 1
		&"agility":
			stats.agility += 1
		&"constitution":
			stats.constitution += 1
	gs.unspent_points -= 1
	_rebuild()

## 完整派生/高级属性展示,无视属性逐项分开。
func _build_derived_text(stats: CharacterStatsScript) -> String:
	return """生命 %d    魔法 %d
劈砍攻击 %d    穿刺攻击 %d    魔法攻击 %d
劈砍防御 %d    穿刺防御 %d    魔法防御 %d
破甲 %d    魔法穿透 %d
武器伤害 %d    攻击次数 %d
物理命中 %.1f%%    魔法命中 %.1f%%    闪避 %.1f%%
致命 %.1f%%    格挡 %.1f%%    强制命中 %.1f%%
法力护盾 %.1f%%    反击 %.1f%%    魔法反馈 %.1f%%
生命吸收 %.1f%%    法力吸收 %.1f%%
出手速度 %d    状态抵抗 %d    洞察 %d    伤害减免 %.1f%%
回复生命 %d    回复法力 %d    免伤护盾 %d
无视格挡:%s    无视反击:%s
无视魔法反馈:%s    无视伤害减免:%s
无视洞察:%s    无视状态抵抗:%s""" % [
		stats.max_hp, stats.max_mp,
		stats.slash_attack, stats.pierce_attack, stats.magic_attack,
		stats.slash_defense, stats.pierce_defense, stats.magic_defense,
		stats.armor_break, stats.magic_penetration,
		stats.weapon_damage, stats.attack_count,
		stats.physical_hit_chance * 100.0, stats.magic_hit_chance * 100.0, stats.dodge_chance * 100.0,
		stats.crit_chance * 100.0, stats.block_chance * 100.0, stats.force_hit * 100.0,
		stats.mana_shield * 100.0, stats.counter_chance * 100.0, stats.magic_feedback * 100.0,
		stats.life_steal * 100.0, stats.mana_steal * 100.0,
		stats.speed, stats.status_resist, stats.insight, stats.damage_reduction * 100.0,
		stats.regen_hp, stats.regen_mp, stats.damage_shield,
		_on_off(stats.ignore_block), _on_off(stats.ignore_counter),
		_on_off(stats.ignore_feedback), _on_off(stats.ignore_reduction),
		_on_off(stats.ignore_insight), _on_off(stats.ignore_status_resist),
	]

func _on_off(value: bool) -> String:
	return "是" if value else "否"

func _clear_container(container: Container) -> void:
	for child: Node in container.get_children():
		container.remove_child(child)
		child.queue_free()
