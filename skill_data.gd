class_name SkillData
extends Resource

## 技能静态数据,支持群体目标、多效果减益、技能级伤害覆盖。

enum SkillType { SLASH, PIERCE, MAGIC, HEAL }

const TYPE_NAMES: Array[String] = ["劈砍", "穿刺", "魔法", "治疗"]

## 技能类别:造成伤害 / 自身增益 / 敌方减益 / 治疗
enum SkillKind { DAMAGE, SELF_BUFF, ENEMY_DEBUFF, HEAL }

const KIND_NAMES: Array[String] = ["伤害", "自身增益", "敌方减益", "治疗"]

## 目标范围
enum TargetScope { SELF, PARTY, ENEMY_GROUP, ENEMY_ALL }

const SCOPE_NAMES: Array[String] = ["自身", "我方全体", "敌方若干", "敌方全体"]

@export var display_name: String = "技能"
@export var skill_type: SkillType = SkillType.SLASH
@export var skill_kind: SkillKind = SkillKind.DAMAGE
## 伤害/治疗倍率,作用于对应系别的攻击力
@export var power_multiplier: float = 1.0
@export var mp_cost: int = 0
@export var description: String = ""
## 自动技能标记(战斗前配置,战斗中不可更改)
@export var is_auto: bool = false
## 目标范围(群体技能用)
@export var target_scope: TargetScope = TargetScope.SELF
## 目标数量(ENEMY_GROUP 时生效)
@export var target_count: int = 1

## 多效果列表:[{"key": 属性键, "value": 数值, "turns": 持续回合}]
@export var effects: Array = []

## ---- 技能级伤害覆盖(星光漫爆类) ----
## 覆盖攻击次数(0=使用单位自身攻击次数)
@export var attack_count_override: int = 0
## 额外魔法穿透
@export var penetration_bonus: int = 0
## 无视目标伤害减免
@export var skill_ignore_reduction: bool = false
## 扣除目标最大法力值百分比(0-1)
@export var drain_mp_percent: float = 0.0

func compute_power(base_attack: int) -> int:
	return maxi(roundi(base_attack * power_multiplier), 1)

func get_type_name() -> String:
	return TYPE_NAMES[skill_type]

func get_kind_name() -> String:
	return KIND_NAMES[skill_kind]

func get_scope_name() -> String:
	return SCOPE_NAMES[target_scope]
