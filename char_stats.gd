class_name CharacterStats
extends Resource

## 角色完整属性模型:五维基础属性 + 战斗派生 + 装备可加成的高级属性。
## 参考世界OL:三系(劈砍/穿刺/魔法)战斗 + 格挡/反击/护盾/吸收等机制。

@export var display_name: String = "冒险者"
@export var level: int = 1

## ---- 五维基础属性 ----
## 力量:劈砍攻击、破甲、生命
@export var strength: int = 10
## 智力:魔法攻击、魔法穿透、洞察
@export var intelligence: int = 10
## 感知:出手速度、状态抵抗、魔法攻击、魔法防御
@export var perception: int = 10
## 敏捷:穿刺攻击、出手速度、闪避
@export var agility: int = 10
## 体质:生命、伤害减免、劈砍+穿刺防御
@export var constitution: int = 10

## ---- 高级属性(装备/技能提供) ----
## 武器伤害:直接叠加到物理攻击
@export var weapon_damage: int = 0
## 攻击次数:每次行动攻击 N 段
@export var attack_count: int = 1
## 物理命中:数值越大命中率越高
@export var physical_accuracy: int = 0
## 魔法命中:数值越大命中率越高,同时提升魔法攻击力
@export var magic_accuracy: int = 0
## 致命率(暴击),基础 5%
@export var crit_chance: float = 0.05
## 格挡率(最高 70%):物理攻击被格挡时伤害减半
@export var block_chance: float = 0.0
## 法力护盾:受到伤害时,按比例由魔法值抵消
@export var mana_shield: float = 0.0
## 反击率(最高 70%):受到物理攻击时反击一次
@export var counter_chance: float = 0.0
## 魔法反馈率(最高 70%):受到魔法攻击时反馈伤害
@export var magic_feedback: float = 0.0
## 生命吸收:攻击造成伤害的百分比转化为生命
@export var life_steal: float = 0.0
## 法力吸收:攻击造成伤害的百分比转化为魔法
@export var mana_steal: float = 0.0
## 强制命中率(最高 70%):攻击无视闪避/格挡的概率
@export var force_hit: float = 0.0
## 自动回复生命(每个回合)
@export var regen_hp: int = 0
## 自动回复法力(每个回合)
@export var regen_mp: int = 0
## 免伤护盾:每个回合开始时充能,优先抵挡伤害
@export var damage_shield: int = 0

## ---- 无视(攻击时忽略对方对应防御机制) ----
@export var ignore_block: bool = false
@export var ignore_counter: bool = false
@export var ignore_feedback: bool = false
@export var ignore_reduction: bool = false
@export var ignore_insight: bool = false
@export var ignore_status_resist: bool = false

## ---- 掉落(仅敌人) ----
@export var gold_reward: int = 10
@export var loot_items: Array[Resource] = []

## ---- 可被增益/减益修改的派生修正项 ----
## 状态抵抗修正(感知派生基础上加减)
@export var status_resist_bonus: int = 0
## 伤害减免修正(体质派生基础上加减,可为负=承伤加深)
@export var damage_reduction_bonus: float = 0.0
## 魔法防御修正(感知派生基础上加减)
@export var magic_defense_bonus: int = 0

## ---- 派生属性 ----
## 攻击力与防御力上限
const STAT_CAP := 10000000

var max_hp: int:
	get: return 40 + strength * 4 + constitution * 8 + level * 5

var max_mp: int:
	get: return 20 + intelligence * 8 + level * 4

var slash_attack: int:
	get: return mini(strength * 2 + weapon_damage, STAT_CAP)

var pierce_attack: int:
	get: return mini(agility * 2 + weapon_damage, STAT_CAP)

var magic_attack: int:
	get: return mini(intelligence * 2 + perception + magic_accuracy, STAT_CAP)

var slash_defense: int:
	get: return mini(constitution * 2, STAT_CAP)

var pierce_defense: int:
	get: return mini(constitution * 2, STAT_CAP)

var magic_defense: int:
	get: return mini(perception * 2 + magic_defense_bonus, STAT_CAP)

var armor_break: int:
	get: return mini(strength, STAT_CAP)

var magic_penetration: int:
	get: return mini(intelligence, STAT_CAP)

var dodge_chance: float:
	get: return clampf(0.03 + agility * 0.004, 0.0, 0.4)

var speed: int:
	get: return perception * 2 + agility

var status_resist: int:
	get: return perception * 2 + status_resist_bonus

var insight: int:
	get: return intelligence

var damage_reduction: float:
	get: return clampf(constitution * 0.006 + damage_reduction_bonus, -0.5, 0.5)

## 物理命中率
var physical_hit_chance: float:
	get: return clampf(0.85 + physical_accuracy * 0.005, 0.05, 1.0)

## 魔法命中率
var magic_hit_chance: float:
	get: return clampf(0.85 + magic_accuracy * 0.005, 0.05, 1.0)

## 上限约束辅助:格挡/反击/魔法反馈/强制命中最高 70%
func get_clamped(value: float) -> float:
	return clampf(value, 0.0, 0.7)
