class_name ItemData
extends Resource

## 物品静态数据:装备与消耗品通用,支持全部高级属性加成。
## 创建方式:右键 > 新建资源 > ItemData,在检查器中配置。

enum ItemType {
	HEAD, SHOULDER, CHEST, GLOVES, BOOTS, LEGS, BELT, CLOAK,
	WEAPON, OFFHAND, ACCESSORY, RIDER, FASHION, CONSUMABLE,
}

const TYPE_NAMES: Array[String] = [
	"头部", "肩部", "衣服", "手套", "靴子", "裤子", "腰带", "披风",
	"武器", "副手", "饰品", "坐骑", "时装", "消耗品",
]

## 武器子类:剑/炮/刀/杖/弓/锤/长枪/法器
enum WeaponKind { SWORD, CANNON, BLADE, STAFF, BOW, HAMMER, SPEAR, ARTIFACT }

const WEAPON_NAMES: Array[String] = ["剑", "炮", "刀", "杖", "弓", "锤", "长枪", "法器"]

@export var display_name: String = "物品"
@export var item_type: ItemType = ItemType.WEAPON
@export var price: int = 10
@export var description: String = ""
## 双手武器:占用主手与副手两个槽(装备时只允许装入主手)
@export var two_handed: bool = false
## 武器子类(仅武器生效)
@export var weapon_kind: WeaponKind = WeaponKind.SWORD

## ---- 五维基础属性加成 ----
@export var strength_bonus: int = 0
@export var intelligence_bonus: int = 0
@export var perception_bonus: int = 0
@export var agility_bonus: int = 0
@export var constitution_bonus: int = 0

## ---- 高级属性加成 ----
@export var weapon_damage_bonus: int = 0
@export var attack_count_bonus: int = 0
@export var physical_accuracy_bonus: int = 0
@export var magic_accuracy_bonus: int = 0
@export var crit_bonus: float = 0.0
@export var block_bonus: float = 0.0
@export var mana_shield_bonus: float = 0.0
@export var counter_bonus: float = 0.0
@export var magic_feedback_bonus: float = 0.0
@export var life_steal_bonus: float = 0.0
@export var mana_steal_bonus: float = 0.0
@export var force_hit_bonus: float = 0.0
@export var regen_hp_bonus: int = 0
@export var regen_mp_bonus: int = 0
@export var damage_shield_bonus: int = 0

## ---- 无视效果 ----
@export var ignore_block_bonus: bool = false
@export var ignore_counter_bonus: bool = false
@export var ignore_feedback_bonus: bool = false
@export var ignore_reduction_bonus: bool = false

## ---- 消耗品 ----
@export var hp_restore: int = 0
@export var mp_restore: int = 0

func is_equippable() -> bool:
	return item_type != ItemType.CONSUMABLE

func get_type_name() -> String:
	return TYPE_NAMES[item_type]

## 武器子类名(非武器返回空)。
func get_weapon_kind_name() -> String:
	if item_type != ItemType.WEAPON:
		return ""
	return WEAPON_NAMES[weapon_kind]

func get_bonus_text() -> String:
	var parts: Array[String] = []
	_append_bonus(parts, "力量", strength_bonus)
	_append_bonus(parts, "智力", intelligence_bonus)
	_append_bonus(parts, "感知", perception_bonus)
	_append_bonus(parts, "敏捷", agility_bonus)
	_append_bonus(parts, "体质", constitution_bonus)
	_append_bonus(parts, "武器伤害", weapon_damage_bonus)
	_append_bonus(parts, "攻击次数", attack_count_bonus)
	_append_bonus(parts, "物命中", physical_accuracy_bonus)
	_append_bonus(parts, "魔命中", magic_accuracy_bonus)
	_append_percent(parts, "致命", crit_bonus)
	_append_percent(parts, "格挡", block_bonus)
	_append_percent(parts, "法力护盾", mana_shield_bonus)
	_append_percent(parts, "反击", counter_bonus)
	_append_percent(parts, "魔法反馈", magic_feedback_bonus)
	_append_percent(parts, "吸血", life_steal_bonus)
	_append_percent(parts, "吸蓝", mana_steal_bonus)
	_append_percent(parts, "强制命中", force_hit_bonus)
	_append_bonus(parts, "回复生命", regen_hp_bonus)
	_append_bonus(parts, "回复法力", regen_mp_bonus)
	_append_bonus(parts, "免伤护盾", damage_shield_bonus)
	if ignore_block_bonus:
		parts.append("无视格挡")
	if ignore_counter_bonus:
		parts.append("无视反击")
	if ignore_feedback_bonus:
		parts.append("无视反馈")
	if ignore_reduction_bonus:
		parts.append("无视减免")
	if hp_restore > 0:
		parts.append("恢复 %d 生命" % hp_restore)
	if mp_restore > 0:
		parts.append("恢复 %d 魔法" % mp_restore)
	if parts.is_empty():
		return "无属性"
	return " ".join(parts)

func _append_bonus(parts: Array[String], name: String, value: int) -> void:
	if value != 0:
		parts.append("%s %s" % [name, _fmt_bonus(value)])

func _append_percent(parts: Array[String], name: String, value: float) -> void:
	if value != 0.0:
		parts.append("%s %s" % [name, _fmt_bonus(value)])

func _fmt_bonus(value: Variant) -> String:
	if value is int:
		var v: int = value
		return "+%d" % v if v >= 0 else "%d" % v
	var vf: float = value
	var pct := roundf(vf * 100.0)
	return "+%d%%" % pct if vf >= 0.0 else "%d%%" % pct
