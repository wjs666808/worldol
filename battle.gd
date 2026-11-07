class_name Battle
extends Node

## 回合制战斗核心 v5:多单位战斗(英雄+宠物 vs 敌人队伍)。
## 左列敌人、右列英雄;自动战斗开关;宠物自动/主动技能;状态效果。

signal log_message(text: String)
signal battle_ended(player_won: bool)
signal player_acted

enum TurnPhase { ACTIVE, OVER }

const CharacterStatsScript := preload("res://char_stats.gd")
const SkillDataScript := preload("res://skill_data.gd")
const ItemDataScript := preload("res://item_data.gd")
const InventoryScript := preload("res://inventory.gd")
const CombatantScript := preload("res://combatant.gd")

const ACTION_DELAY := 0.55
const EXP_BASE := 60
const MP_REGEN := 4
const DAMAGE_VARIANCE_MIN := 0.85
const DAMAGE_VARIANCE_MAX := 1.15

@export var player_skills: Array[Resource] = []
@export var enemy_wave: Array[Resource] = []

var _game_state: Node
var _player_stats: CharacterStatsScript
var _player_exp: int = 0
var _phase := TurnPhase.ACTIVE
var _heroes: Array[CombatantScript] = []
var _enemies: Array[CombatantScript] = []
var _auto_battle := false
var _waiting_actor: CombatantScript
var _defended_actor: CombatantScript
var _round := 1

@onready var _inventory: InventoryScript = $Inventory
@onready var _log: RichTextLabel = $UI/Root/HBox/CenterColumn/Log
@onready var _enemy_list: VBoxContainer = $UI/Root/HBox/EnemyColumn/EnemyScroll/EnemyList
@onready var _hero_list: VBoxContainer = $UI/Root/HBox/HeroColumn/HeroScroll/HeroList
@onready var _skill_box: VBoxContainer = $UI/Root/HBox/HeroColumn/SkillScroll/SkillBox
@onready var _auto_skill_row: FlowContainer = $UI/Root/HBox/HeroColumn/SkillScroll/SkillBox/AutoRow
@onready var _active_skill_row: FlowContainer = $UI/Root/HBox/HeroColumn/SkillScroll/SkillBox/ActiveRow
@onready var _auto_button: Button = $UI/Root/HBox/CenterColumn/TopButtons/AutoButton
@onready var _defend_button: Button = $UI/Root/HBox/CenterColumn/TopButtons/DefendButton
@onready var _backpack_button: Button = $UI/Root/HBox/CenterColumn/TopButtons/BackpackButton

func _ready() -> void:
	_game_state = get_node("/root/GameState")
	_player_stats = _game_state.player_stats
	if _game_state.enemy_templates.is_empty():
		_game_state.enemy_templates = enemy_wave
	log_message.connect(_on_log_message)
	battle_ended.connect(_on_battle_ended)
	_inventory.inventory_changed.connect(_refresh_heroes)
	_inventory.consumable_used.connect(_on_consumable_used)
	_backpack_button.pressed.connect(_inventory.toggle)
	_auto_button.pressed.connect(_toggle_auto)
	_defend_button.pressed.connect(_on_defend_pressed)
	_build_hero_team()
	_build_enemy_team()
	_refresh_all()
	log_message.emit("战斗开始!英雄 %d 名(含宠物),敌人 %d 个。" % [_heroes.size(), _enemies.size()])
	_battle_loop()

func _on_log_message(text: String) -> void:
	_log.append_text("\n" + text)

## ---- 队伍构建 ----

func _build_hero_team() -> void:
	var hero_skills: Array = _game_state.skill_pool
	if hero_skills.is_empty():
		hero_skills = player_skills
	var hero_auto: Array = _game_state.auto_skills
	for i in _game_state.hero_stats.size():
		var stats := _game_state.hero_stats[i] as CharacterStatsScript
		var hero := CombatantScript.new()
		hero.setup(stats, hero_skills, hero_auto, &"hero", false)
		hero.is_player_controlled = i == 0
		_heroes.append(hero)
		var pet := CombatantScript.new()
		var pet_stats: CharacterStatsScript = _game_state.pet_template.duplicate(true)
		var pet_skills := _make_pet_skills()
		var pet_auto: Array = [pet_skills[1]]
		pet.setup(pet_stats, pet_skills, pet_auto, &"hero", true)
		pet.display_name = _game_state.pet_template.display_name + "(宠)"
		_heroes.append(pet)

func _build_enemy_team() -> void:
	var count := clampi(_game_state.enemy_count, 1, 20)
	for i in count:
		var templates: Array = _game_state.enemy_templates
		if templates.is_empty():
			templates = enemy_wave
		var template := templates[i % templates.size()] as CharacterStatsScript
		if template == null:
			continue
		var unit := CombatantScript.new()
		var unit_stats: CharacterStatsScript = template.duplicate(true)
		var empty: Array[Resource] = []
		unit.setup(unit_stats, empty, empty, &"enemy", false)
		if count > 1:
			unit.display_name = "%s %d" % [template.display_name, i + 1]
		_enemies.append(unit)

func _make_pet_skills() -> Array[Resource]:
	var claw := SkillDataScript.new()
	claw.display_name = "爪击"
	claw.skill_type = SkillDataScript.SkillType.PIERCE
	claw.skill_kind = SkillDataScript.SkillKind.DAMAGE
	claw.power_multiplier = 1.2
	claw.mp_cost = 3
	var howl := SkillDataScript.new()
	howl.display_name = "野性"
	howl.skill_type = SkillDataScript.SkillType.SLASH
	howl.skill_kind = SkillDataScript.SkillKind.SELF_BUFF
	howl.effects = [{"key": &"attack_count", "value": 1.0, "turns": 2}]
	howl.mp_cost = 3
	howl.is_auto = true
	return [claw, howl]

## ---- 主循环 ----

func _battle_loop() -> void:
	while _phase == TurnPhase.ACTIVE:
		await _play_round()

func _play_round() -> void:
	log_message.emit("—— 第 %d 回合 ——" % _round)
	_round += 1
	# 自动技能阶段:所有存活单位按出手速度排序,依次释放各自自动技能队列中当前回合的技能
	var auto_units: Array[CombatantScript] = []
	for c: CombatantScript in _heroes + _enemies:
		if c.alive:
			auto_units.append(c)
	auto_units.sort_custom(func(a, b): return a.stats.speed > b.stats.speed)
	for unit in auto_units:
		var auto_skill := _next_auto_skill(unit)
		if auto_skill == null or unit.mp < auto_skill.mp_cost:
			continue
		var target: CombatantScript = unit
		if auto_skill.skill_kind != SkillDataScript.SkillKind.SELF_BUFF:
			target = _pick_target(unit.side)
			if target == null:
				continue
		_use_skill(unit, target, auto_skill)
	# 行动阶段:我方按队列(先英雄后宠物、从上到下),随后敌人
	for unit in _heroes:
		if unit.alive:
			await _act(unit)
			_refresh_all()
			if await _check_battle_end():
				return
	for unit in _enemies:
		if unit.alive:
			await _act(unit)
			_refresh_all()
			if await _check_battle_end():
				return
	_end_round()
	_refresh_all()

## 取出单位自动技能队列中当前回合要释放的技能(按回合循环)。
func _next_auto_skill(unit: CombatantScript) -> SkillDataScript:
	if unit.auto_skills.is_empty():
		return null
	var idx := (_round - 2) % unit.auto_skills.size()
	return unit.auto_skills[idx] as SkillDataScript

func _act(actor: CombatantScript) -> void:
	if actor.is_player_controlled and not _auto_battle:
		_waiting_actor = actor
		_defended_actor = null
		_refresh_skills(actor)
		await player_acted
		return
	await _auto_act(actor)

## ---- 自动行动 ----

func _auto_act(caster: CombatantScript) -> void:
	# 自动战斗模式:英雄每回合释放配置的主动技能(单选)
	if caster.side == &"hero" and not caster.is_pet:
		var chosen := _game_state.auto_active_skill as SkillDataScript
		if chosen != null and caster.mp >= chosen.mp_cost:
			var target: CombatantScript = caster
			if chosen.skill_kind != SkillDataScript.SkillKind.SELF_BUFF:
				target = _pick_target(&"hero")
				if target != null:
					_use_skill(caster, target, chosen)
			else:
				_use_skill(caster, target, chosen)
			await get_tree().create_timer(ACTION_DELAY).timeout
			return
	var target := _pick_target(caster.side)
	if target == null:
		return
	var skill := _choose_skill(caster)
	if skill == null:
		_physical_attack(caster, target)
	else:
		_use_skill(caster, target if target.side != caster.side else caster, skill)
	await get_tree().create_timer(ACTION_DELAY).timeout

func _choose_skill(caster: CombatantScript) -> SkillDataScript:
	var heal_skill: SkillDataScript = null
	var buff_skill: SkillDataScript = null
	var damage_skills: Array[SkillDataScript] = []
	for res in caster.skills:
		var s := res as SkillDataScript
		if s == null or s.is_auto or caster.mp < s.mp_cost:
			continue
		match s.skill_kind:
			SkillDataScript.SkillKind.HEAL:
				heal_skill = s
			SkillDataScript.SkillKind.SELF_BUFF:
				buff_skill = s
			_:
				damage_skills.append(s)
	if heal_skill != null and caster.hp < caster.stats.max_hp * 0.5:
		return heal_skill
	if buff_skill != null and caster.buff_turns.is_empty():
		return buff_skill
	if not damage_skills.is_empty():
		return damage_skills.pick_random()
	return null

func _pick_target(attacker_side: StringName) -> CombatantScript:
	var pool: Array[CombatantScript] = _enemies if attacker_side == &"hero" else _heroes
	var alive_pool: Array[CombatantScript] = []
	for c: CombatantScript in pool:
		if c.alive:
			alive_pool.append(c)
	if alive_pool.is_empty():
		return null
	return alive_pool.pick_random()

## ---- 技能与攻击 ----

func _physical_attack(caster: CombatantScript, target: CombatantScript) -> void:
	var attack_type := _best_attack_type(caster.stats)
	var result := _perform_attack(caster, target, attack_type, 1.0, true)
	_log_attack_result(caster, target, result, SkillDataScript.TYPE_NAMES[attack_type])

## 施放技能:按目标范围解析目标,按类别结算(伤害/治疗/增益/减益)。
func _use_skill(caster: CombatantScript, target: CombatantScript, skill: SkillDataScript) -> void:
	if caster.mp < skill.mp_cost:
		return
	caster.mp -= skill.mp_cost
	var targets := _resolve_targets(caster, skill, target)
	if targets.is_empty():
		return
	match skill.skill_kind:
		SkillDataScript.SkillKind.HEAL:
			for t in targets:
				t.heal(skill.compute_power(caster.stats.magic_attack))
			log_message.emit("%s 施放 %s,恢复 %d 点生命!" % [caster.display_name, skill.display_name, skill.compute_power(caster.stats.magic_attack)])
		SkillDataScript.SkillKind.SELF_BUFF:
			for t in targets:
				_apply_effects(t, skill)
			log_message.emit("%s 施放 %s,%s" % [caster.display_name, skill.display_name, skill.description])
		SkillDataScript.SkillKind.ENEMY_DEBUFF:
			var hit_count := 0
			for t in targets:
				if _is_debuff_resisted(caster, t):
					log_message.emit("%s 抵抗了 %s!" % [t.display_name, skill.display_name])
					continue
				_apply_effects(t, skill)
				hit_count += 1
			if hit_count > 0:
				log_message.emit("%s 施放 %s,诅咒 %d 个目标,%s" % [caster.display_name, skill.display_name, hit_count, skill.description])
		_:
			for t in targets:
				if not t.alive:
					continue
				var result := _perform_attack(caster, t, skill.skill_type, skill.power_multiplier, true, skill)
				_log_attack_result(caster, t, result, skill.display_name)

## 按技能目标范围解析实际目标列表。
func _resolve_targets(caster: CombatantScript, skill: SkillDataScript, fallback: CombatantScript) -> Array[CombatantScript]:
	var result: Array[CombatantScript] = []
	match skill.target_scope:
		SkillDataScript.TargetScope.SELF:
			result.append(caster)
		SkillDataScript.TargetScope.PARTY:
			var pool := _heroes if caster.side == &"hero" else _enemies
			for c: CombatantScript in pool:
				if c.alive:
					result.append(c)
		SkillDataScript.TargetScope.ENEMY_ALL:
			var pool_e := _enemies if caster.side == &"hero" else _heroes
			for c: CombatantScript in pool_e:
				if c.alive:
					result.append(c)
		SkillDataScript.TargetScope.ENEMY_GROUP:
			var pool_g := _enemies if caster.side == &"hero" else _heroes
			var alive_g: Array[CombatantScript] = []
			for c: CombatantScript in pool_g:
				if c.alive:
					alive_g.append(c)
			alive_g.shuffle()
			result = alive_g.slice(0, mini(skill.target_count, alive_g.size()))
		_:
			if fallback != null and fallback.alive:
				result.append(fallback)
	return result

## 应用技能全部效果(多效果减益/增益)。
func _apply_effects(unit: CombatantScript, skill: SkillDataScript) -> void:
	for eff in skill.effects:
		_apply_effect(unit, eff["key"], eff["value"], eff["turns"])

## 玩家点击技能按钮(手动技能集,战斗前配置)。
func _on_player_skill_pressed(skill_index: int) -> void:
	if _waiting_actor == null:
		return
	var skills: Array = _game_state.chosen_active_skills
	if skill_index >= skills.size():
		return
	var skill := skills[skill_index] as SkillDataScript
	if skill == null:
		return
	var target: CombatantScript = _waiting_actor
	if skill.skill_kind != SkillDataScript.SkillKind.SELF_BUFF:
		target = _pick_target(&"hero")
		if target == null:
			return
	_use_skill(_waiting_actor, target, skill)
	_waiting_actor = null
	player_acted.emit()

## 玩家点击攻击(普攻)。
func _on_attack_pressed() -> void:
	if _waiting_actor == null:
		return
	var target := _pick_target(&"hero")
	if target == null:
		return
	_physical_attack(_waiting_actor, target)
	_waiting_actor = null
	player_acted.emit()

func _on_defend_pressed() -> void:
	if _waiting_actor == null:
		return
	_defended_actor = _waiting_actor
	log_message.emit("%s 摆出防御姿态,本回合受到的伤害减半!" % _waiting_actor.display_name)
	_waiting_actor = null
	player_acted.emit()

func _toggle_auto() -> void:
	_auto_battle = not _auto_battle
	_auto_button.text = "自动战斗:开" if _auto_battle else "自动战斗:关"
	log_message.emit("自动战斗已%s。" % ("开启" if _auto_battle else "关闭"))
	if _auto_battle and _waiting_actor != null:
		var actor := _waiting_actor
		_waiting_actor = null
		player_acted.emit()
		_auto_act(actor)

## ---- 攻击结算(Combatant 版) ----

func _perform_attack(caster: CombatantScript, target: CombatantScript, attack_type: int, multiplier: float, allow_reaction: bool, skill: SkillDataScript = null) -> Dictionary:
	var result := {"missed": false, "hits": 0, "total": 0, "crit": false, "blocked": false, "counter": 0, "feedback": 0}
	if _is_attack_missed(attack_type, caster.stats, target.stats):
		result["missed"] = true
		return result
	var attack_count := caster.stats.attack_count
	if skill != null and skill.attack_count_override > 0:
		attack_count = skill.attack_count_override
	var pen_bonus := skill.penetration_bonus if skill != null else 0
	var ignore_red := caster.stats.ignore_reduction or (skill != null and skill.skill_ignore_reduction)
	for _i in maxi(attack_count, 1):
		if _is_attack_missed(attack_type, caster.stats, target.stats):
			continue
		var dmg := _damage_for(attack_type, caster.stats, target.stats, pen_bonus, ignore_red)
		dmg = maxi(roundi(dmg * multiplier), 1)
		if target == _defended_actor:
			dmg = maxi(roundi(dmg * 0.5), 1)
		if attack_type != SkillDataScript.SkillType.MAGIC and not caster.stats.ignore_block \
				and randf() < target.stats.block_chance:
			dmg = maxi(roundi(dmg * 0.5), 1)
			result["blocked"] = true
		if randf() < caster.stats.crit_chance:
			dmg = roundi(dmg * 1.5)
			result["crit"] = true
		var dealt := target.take_damage(dmg)
		result["total"] += dealt
		result["hits"] += 1
	if result["total"] > 0:
		if caster.stats.life_steal > 0.0:
			caster.heal(roundi(result["total"] * caster.stats.life_steal))
		if caster.stats.mana_steal > 0.0:
			caster.restore_mp(roundi(result["total"] * caster.stats.mana_steal))
		if skill != null and skill.drain_mp_percent > 0.0:
			target.mp = maxi(target.mp - roundi(target.stats.max_mp * skill.drain_mp_percent), 0)
	if allow_reaction and result["total"] > 0:
		if attack_type != SkillDataScript.SkillType.MAGIC and not caster.stats.ignore_counter \
				and randf() < target.stats.counter_chance:
			result["counter"] = _perform_attack(target, caster, _best_attack_type(target.stats), 1.0, false)["total"]
		elif attack_type == SkillDataScript.SkillType.MAGIC and not caster.stats.ignore_feedback \
				and randf() < target.stats.magic_feedback:
			result["feedback"] = _perform_attack(target, caster, SkillDataScript.SkillType.MAGIC, 1.0, false)["total"]
	return result

func _is_attack_missed(attack_type: int, attacker: CharacterStatsScript, defender: CharacterStatsScript) -> bool:
	if randf() < attacker.force_hit:
		return false
	if attack_type == SkillDataScript.SkillType.MAGIC:
		return randf() > attacker.magic_hit_chance
	if randf() > attacker.physical_hit_chance:
		return true
	return randf() < defender.dodge_chance

func _damage_for(attack_type: int, attacker: CharacterStatsScript, defender: CharacterStatsScript, pen_bonus := 0, ignore_red := false) -> int:
	match attack_type:
		SkillDataScript.SkillType.SLASH:
			return _compute_damage(attacker.slash_attack, defender.slash_defense, attacker.armor_break, defender.damage_reduction, ignore_red or attacker.ignore_reduction)
		SkillDataScript.SkillType.PIERCE:
			return _compute_damage(attacker.pierce_attack, defender.pierce_defense, attacker.armor_break, defender.damage_reduction, ignore_red or attacker.ignore_reduction)
		SkillDataScript.SkillType.MAGIC:
			return _compute_damage(attacker.magic_attack, defender.magic_defense, attacker.magic_penetration + pen_bonus, defender.damage_reduction, ignore_red or attacker.ignore_reduction)
		_:
			return 1

func _compute_damage(attack: int, defense: int, bonus: int, reduction: float, ignore_reduction: bool) -> int:
	var base := maxi(attack - defense + bonus, 1)
	var variance := randf_range(DAMAGE_VARIANCE_MIN, DAMAGE_VARIANCE_MAX)
	var damage := maxi(roundi(base * variance), 1)
	if ignore_reduction:
		return damage
	return maxi(roundi(damage * (1.0 - reduction)), 1)

func _best_attack_type(stats: CharacterStatsScript) -> int:
	var slash := stats.slash_attack
	var pierce := stats.pierce_attack
	var magic := stats.magic_attack
	if slash >= pierce and slash >= magic:
		return SkillDataScript.SkillType.SLASH
	if pierce >= magic:
		return SkillDataScript.SkillType.PIERCE
	return SkillDataScript.SkillType.MAGIC

func _log_attack_result(caster: CombatantScript, target: CombatantScript, result: Dictionary, action_name: String) -> void:
	if result["missed"]:
		log_message.emit("%s 的攻击被 %s 躲开了!" % [caster.display_name, target.display_name])
		return
	var parts: Array[String] = []
	parts.append("造成 %d 点伤害" % result["total"])
	if result["hits"] > 1:
		parts.append("共 %d 段" % result["hits"])
	if result["crit"]:
		parts.append("致命一击")
	if result["blocked"]:
		parts.append("被格挡")
	log_message.emit("%s %s,%s!" % [caster.display_name, action_name, "，".join(parts)])
	if result["counter"] > 0:
		log_message.emit("%s 反击了 %s,造成 %d 点伤害!" % [target.display_name, caster.display_name, result["counter"]])
	if result["feedback"] > 0:
		log_message.emit("魔法反馈!%s 反震 %s,造成 %d 点伤害!" % [target.display_name, caster.display_name, result["feedback"]])

## ---- 状态效果 ----

func _apply_effect(unit: CombatantScript, key: StringName, value: float, turns: int) -> void:
	if key == &"":
		return
	if not unit.buff_origins.has(key):
		unit.buff_origins[key] = unit.stats.get(key)
	unit.stats.set(key, float(unit.stats.get(key)) + value)
	unit.buff_turns[key] = turns

func _tick_buffs(unit: CombatantScript) -> void:
	for key: StringName in unit.buff_turns.keys():
		var remaining: int = int(unit.buff_turns[key]) - 1
		if remaining <= 0:
			unit.stats.set(key, unit.buff_origins[key])
			unit.buff_turns.erase(key)
			unit.buff_origins.erase(key)
			log_message.emit("%s 的 %s 效果消失了!" % [unit.display_name, key])
		else:
			unit.buff_turns[key] = remaining

func _clear_all_buffs() -> void:
	for unit: CombatantScript in _heroes + _enemies:
		for key: StringName in unit.buff_origins.keys():
			unit.stats.set(key, unit.buff_origins[key])
		unit.buff_origins.clear()
		unit.buff_turns.clear()

func _is_debuff_resisted(caster: CombatantScript, target: CombatantScript) -> bool:
	if caster.stats.ignore_status_resist:
		return false
	var resist := float(target.stats.status_resist)
	var insight := float(caster.stats.insight)
	if caster.stats.ignore_insight:
		insight = 0.0
	return randf() < clampf((resist - insight) * 0.02, 0.0, 0.5)

## ---- 回合结算 ----

func _end_round() -> void:
	for unit: CombatantScript in _heroes + _enemies:
		if not unit.alive:
			continue
		_tick_buffs(unit)
		unit.hp = mini(unit.hp + unit.stats.regen_hp, unit.stats.max_hp)
		unit.mp = mini(unit.mp + unit.stats.regen_mp + MP_REGEN, unit.stats.max_mp)
		unit.shield = unit.stats.damage_shield
	_defended_actor = null

func _check_battle_end() -> bool:
	if _all_dead(_heroes):
		_phase = TurnPhase.OVER
		log_message.emit("英雄队伍全灭,战斗失败……")
		battle_ended.emit(false)
		return true
	if _all_dead(_enemies):
		_phase = TurnPhase.OVER
		log_message.emit("所有敌人被消灭,战斗胜利!")
		_grant_rewards()
		battle_ended.emit(true)
		return true
	return false

func _all_dead(units: Array) -> bool:
	for unit: CombatantScript in units:
		if unit.alive:
			return false
	return true

func _grant_rewards() -> void:
	var total_exp := 0
	var total_gold := 0
	var loots: Array[Resource] = []
	for e: CombatantScript in _enemies:
		total_exp += e.stats.level * 20
		total_gold += e.stats.gold_reward
		for res in e.stats.loot_items:
			loots.append(res)
	_player_exp = _game_state.player_exp + total_exp
	_inventory.add_gold(total_gold)
	log_message.emit("获得 %d 点经验与 %d 枚金币!" % [total_exp, total_gold])
	for res in loots:
		var item := res as ItemDataScript
		if item != null:
			_inventory.add_item(item)
			log_message.emit("拾取了物品:%s!" % item.display_name)
	while _player_exp >= _exp_to_next():
		_player_exp -= _exp_to_next()
		_level_up()

func _exp_to_next() -> int:
	return EXP_BASE * _player_stats.level

func _level_up() -> void:
	_player_stats.level += 1
	_game_state.unspent_points += 3
	log_message.emit("升级!你现在是 Lv.%d,获得 3 点属性点!" % _player_stats.level)

## ---- 消耗品 ----

func _on_consumable_used(item: Resource) -> void:
	var data := item as ItemDataScript
	if data == null:
		return
	var hero := _heroes[0] if _heroes.size() > 0 else null
	if hero != null:
		hero.hp = mini(hero.hp + data.hp_restore, hero.stats.max_hp)
		hero.mp = mini(hero.mp + data.mp_restore, hero.stats.max_mp)
	log_message.emit("使用了 %s!" % data.display_name)
	_refresh_all()

## ---- 战斗结束 ----

func _on_battle_ended(player_won: bool) -> void:
	_clear_all_buffs()
	var hero := _heroes[0] if _heroes.size() > 0 else null
	if hero != null:
		_game_state.player_hp = hero.hp
		_game_state.player_mp = hero.mp
	_game_state.player_exp = _player_exp
	_game_state.pending_enemy = null
	await get_tree().create_timer(2.0).timeout
	get_tree().change_scene_to_file("res://world.tscn")

## ---- UI ----

func _refresh_all() -> void:
	_refresh_units()
	_refresh_skills(_waiting_actor if _waiting_actor != null else (_heroes[0] if _heroes.size() > 0 else null))

func _refresh_units() -> void:
	_clear_container(_enemy_list)
	_clear_container(_hero_list)
	for c: CombatantScript in _enemies:
		_enemy_list.add_child(_build_unit_row(c))
	for c: CombatantScript in _heroes:
		_hero_list.add_child(_build_unit_row(c))

func _build_unit_row(c: CombatantScript) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(0, 0)
	var name_label := Label.new()
	var hp_pct := float(c.hp) / maxi(c.stats.max_hp, 1) * 100.0
	var mp_pct := float(c.mp) / maxi(c.stats.max_mp, 1) * 100.0
	var dead_tag := "  [阵亡]" if not c.alive else ""
	name_label.text = "%s  Lv.%d%s" % [c.display_name, c.stats.level, dead_tag]
	name_label.modulate = Color(0.9, 0.4, 0.4) if c.side == &"enemy" else Color(0.4, 0.8, 1.0)
	var hp_bar := ProgressBar.new()
	hp_bar.max_value = 100.0
	hp_bar.value = hp_pct
	hp_bar.custom_minimum_size = Vector2(180, 14)
	hp_bar.show_percentage = false
	hp_bar.modulate = Color(0.9, 0.3, 0.3) if c.side == &"enemy" else Color(0.3, 0.9, 0.3)
	var mp_bar := ProgressBar.new()
	mp_bar.max_value = 100.0
	mp_bar.value = mp_pct
	mp_bar.custom_minimum_size = Vector2(180, 10)
	mp_bar.show_percentage = false
	mp_bar.modulate = Color(0.4, 0.5, 0.9)
	box.add_child(name_label)
	box.add_child(hp_bar)
	box.add_child(mp_bar)
	return box

func _refresh_heroes() -> void:
	_refresh_units()

func _refresh_skills(actor: CombatantScript) -> void:
	_clear_container(_auto_skill_row)
	_clear_container(_active_skill_row)
	if actor == null:
		return
	# 自动技能栏:显示当前单位自动技能队列(战斗中不可更改,只读展示)
	for i in actor.auto_skills.size():
		var skill := actor.auto_skills[i] as SkillDataScript
		if skill == null:
			continue
		var tag := Button.new()
		tag.text = "第%d回合: %s" % [i + 1, skill.display_name]
		tag.custom_minimum_size = Vector2(150, 32)
		tag.disabled = true
		_auto_skill_row.add_child(tag)
	# 主动技能栏:玩家控制单位可点击,其余单位只读展示
	var skills: Array = _game_state.chosen_active_skills
	if actor.is_pet:
		skills = actor.skills
	var controllable := actor.is_player_controlled and not _auto_battle
	for i in skills.size():
		var skill := skills[i] as SkillDataScript
		if skill == null:
			continue
		var button := Button.new()
		button.text = "%s(%d MP)" % [skill.display_name, skill.mp_cost]
		button.custom_minimum_size = Vector2(130, 40)
		button.disabled = (not controllable) or actor.mp < skill.mp_cost
		if controllable:
			button.pressed.connect(_on_player_skill_pressed.bind(i))
		_active_skill_row.add_child(button)
	if controllable:
		var attack_button := Button.new()
		attack_button.text = "普通攻击"
		attack_button.custom_minimum_size = Vector2(130, 40)
		attack_button.pressed.connect(_on_attack_pressed)
		_active_skill_row.add_child(attack_button)

func _clear_container(container: Container) -> void:
	for child: Node in container.get_children():
		container.remove_child(child)
		child.queue_free()
