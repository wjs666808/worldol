class_name Inventory
extends Node

## 背包与装备管理器(16 槽位)。
## 装备加成直接叠加到 GameState.player_stats,派生属性自动包含装备效果。
## 数据源为全局 GameState,跨场景持久;背包面板为子节点 BackpackUI(CanvasLayer)。

signal inventory_changed
signal consumable_used(item: Resource)

const CharacterStatsScript := preload("res://char_stats.gd")
const ItemDataScript := preload("res://item_data.gd")

const SLOT_NAMES: Array[String] = [
	"头部", "肩部", "衣服", "手套", "靴子", "裤子", "腰带", "披风",
	"主手", "副手", "饰品1", "饰品2", "饰品3", "饰品4", "坐骑", "时装",
]
const SLOT_COUNT := 16
const ACCESSORY_SLOT_START := 10
const ACCESSORY_SLOT_END := 13
const MAIN_HAND_SLOT := 8
const OFF_HAND_SLOT := 9

var _game_state: Node
var _equipped: Array[ItemDataScript] = []
var _backpack_visible := false

@onready var _backpack_ui: CanvasLayer = $BackpackUI
@onready var _gold_label: Label = $BackpackUI/Panel/Margin/VBox/GoldLabel
@onready var _equip_list: VBoxContainer = $BackpackUI/Panel/Margin/VBox/EquipScroll/EquipList
@onready var _item_list: VBoxContainer = $BackpackUI/Panel/Margin/VBox/ItemScroll/ItemList
@onready var _close_button: Button = $BackpackUI/Panel/Margin/VBox/CloseButton

func _ready() -> void:
	_game_state = get_node("/root/GameState")
	_equipped.resize(SLOT_COUNT)
	for i in _equipped.size():
		_equipped[i] = null
	_close_button.pressed.connect(toggle)
	if has_node("Buttons/BackpackButton"):
		$Buttons/BackpackButton.pressed.connect(toggle)
	_backpack_ui.visible = false

func get_equipped(slot_index: int) -> ItemDataScript:
	return _equipped[slot_index]

func get_items() -> Array[ItemDataScript]:
	var result: Array[ItemDataScript] = []
	for item_res in _game_state.inventory_items:
		var item := item_res as ItemDataScript
		if item != null:
			result.append(item)
	return result

func get_gold() -> int:
	return _game_state.gold

func add_gold(amount: int) -> void:
	_game_state.gold += amount
	inventory_changed.emit()

func add_item(item: ItemDataScript) -> void:
	_game_state.inventory_items.append(item)
	inventory_changed.emit()

## 穿上装备:自动匹配槽位,旧装备卸下换回背包,加成实时生效。
func equip_item(item: ItemDataScript) -> bool:
	if item == null or not item.is_equippable():
		return false
	var slot_index := _find_slot(item)
	if slot_index < 0:
		return false
	if _equipped[slot_index] == item:
		return false
	if _equipped[slot_index] != null:
		_unequip_bonus(_equipped[slot_index])
		_game_state.inventory_items.append(_equipped[slot_index])
	_equipped[slot_index] = item
	_apply_bonus(item)
	_game_state.inventory_items.erase(item)
	_refresh_after_change()
	return true

## 卸下装备:加成移除,装备回到背包。
func unequip_item(slot_index: int) -> bool:
	var item := _equipped[slot_index]
	if item == null:
		return false
	_unequip_bonus(item)
	_equipped[slot_index] = null
	_game_state.inventory_items.append(item)
	_refresh_after_change()
	return true

## 使用消耗品:从背包移除并发出信号,由战斗层应用恢复效果。
func use_consumable(item: ItemDataScript) -> bool:
	if item == null or item.item_type != ItemDataScript.ItemType.CONSUMABLE:
		return false
	_game_state.inventory_items.erase(item)
	consumable_used.emit(item)
	_refresh_after_change()
	return true

func toggle() -> void:
	_backpack_visible = not _backpack_visible
	_backpack_ui.visible = _backpack_visible
	if _backpack_visible:
		_rebuild_ui()

## 查找物品可穿的槽位:饰品找空槽,双手武器只装主手。
func _find_slot(item: ItemDataScript) -> int:
	if item.item_type == ItemDataScript.ItemType.ACCESSORY:
		for i in range(ACCESSORY_SLOT_START, ACCESSORY_SLOT_END + 1):
			if _equipped[i] == null:
				return i
		return ACCESSORY_SLOT_START
	var slot := _slot_for_type(item.item_type)
	if slot < 0:
		return -1
	if item.item_type == ItemDataScript.ItemType.WEAPON and item.two_handed:
		return MAIN_HAND_SLOT
	return slot

func _slot_for_type(item_type: int) -> int:
	match item_type:
		ItemDataScript.ItemType.HEAD:
			return 0
		ItemDataScript.ItemType.SHOULDER:
			return 1
		ItemDataScript.ItemType.CHEST:
			return 2
		ItemDataScript.ItemType.GLOVES:
			return 3
		ItemDataScript.ItemType.BOOTS:
			return 4
		ItemDataScript.ItemType.LEGS:
			return 5
		ItemDataScript.ItemType.BELT:
			return 6
		ItemDataScript.ItemType.CLOAK:
			return 7
		ItemDataScript.ItemType.WEAPON:
			return MAIN_HAND_SLOT
		ItemDataScript.ItemType.OFFHAND:
			return OFF_HAND_SLOT
		ItemDataScript.ItemType.RIDER:
			return 14
		ItemDataScript.ItemType.FASHION:
			return 15
	return -1

func _apply_bonus(item: ItemDataScript) -> void:
	var stats: CharacterStatsScript = _game_state.player_stats
	stats.strength += item.strength_bonus
	stats.intelligence += item.intelligence_bonus
	stats.perception += item.perception_bonus
	stats.agility += item.agility_bonus
	stats.constitution += item.constitution_bonus
	stats.weapon_damage += item.weapon_damage_bonus
	stats.attack_count = maxi(stats.attack_count + item.attack_count_bonus, 1)
	stats.physical_accuracy += item.physical_accuracy_bonus
	stats.magic_accuracy += item.magic_accuracy_bonus
	stats.crit_chance += item.crit_bonus
	stats.block_chance += item.block_bonus
	stats.mana_shield += item.mana_shield_bonus
	stats.counter_chance += item.counter_bonus
	stats.magic_feedback += item.magic_feedback_bonus
	stats.life_steal += item.life_steal_bonus
	stats.mana_steal += item.mana_steal_bonus
	stats.force_hit += item.force_hit_bonus
	stats.regen_hp += item.regen_hp_bonus
	stats.regen_mp += item.regen_mp_bonus
	stats.damage_shield += item.damage_shield_bonus
	stats.ignore_block = stats.ignore_block or item.ignore_block_bonus
	stats.ignore_counter = stats.ignore_counter or item.ignore_counter_bonus
	stats.ignore_feedback = stats.ignore_feedback or item.ignore_feedback_bonus
	stats.ignore_reduction = stats.ignore_reduction or item.ignore_reduction_bonus

func _unequip_bonus(item: ItemDataScript) -> void:
	var stats: CharacterStatsScript = _game_state.player_stats
	stats.strength -= item.strength_bonus
	stats.intelligence -= item.intelligence_bonus
	stats.perception -= item.perception_bonus
	stats.agility -= item.agility_bonus
	stats.constitution -= item.constitution_bonus
	stats.weapon_damage -= item.weapon_damage_bonus
	stats.attack_count = maxi(stats.attack_count - item.attack_count_bonus, 1)
	stats.physical_accuracy -= item.physical_accuracy_bonus
	stats.magic_accuracy -= item.magic_accuracy_bonus
	stats.crit_chance -= item.crit_bonus
	stats.block_chance -= item.block_bonus
	stats.mana_shield -= item.mana_shield_bonus
	stats.counter_chance -= item.counter_bonus
	stats.magic_feedback -= item.magic_feedback_bonus
	stats.life_steal -= item.life_steal_bonus
	stats.mana_steal -= item.mana_steal_bonus
	stats.force_hit -= item.force_hit_bonus
	stats.regen_hp -= item.regen_hp_bonus
	stats.regen_mp -= item.regen_mp_bonus
	stats.damage_shield -= item.damage_shield_bonus
	stats.ignore_block = _recompute_ignore(&"ignore_block")
	stats.ignore_counter = _recompute_ignore(&"ignore_counter")
	stats.ignore_feedback = _recompute_ignore(&"ignore_feedback")
	stats.ignore_reduction = _recompute_ignore(&"ignore_reduction")

func _recompute_ignore(prop: StringName) -> bool:
	for slot_index in _equipped.size():
		var item := _equipped[slot_index]
		if item == null:
			continue
		match prop:
			&"ignore_block":
				if item.ignore_block_bonus:
					return true
			&"ignore_counter":
				if item.ignore_counter_bonus:
					return true
			&"ignore_feedback":
				if item.ignore_feedback_bonus:
					return true
			&"ignore_reduction":
				if item.ignore_reduction_bonus:
					return true
	return false

func _refresh_after_change() -> void:
	if _backpack_visible:
		_rebuild_ui()
	inventory_changed.emit()

func _rebuild_ui() -> void:
	_clear_container(_equip_list)
	_clear_container(_item_list)
	_gold_label.text = "金币: %d" % _game_state.gold
	for i in _equipped.size():
		_equip_list.add_child(_build_equip_row(i))
	for item: ItemDataScript in get_items():
		_item_list.add_child(_build_item_row(item))

func _build_equip_row(slot_index: int) -> HBoxContainer:
	var row := HBoxContainer.new()
	var item := _equipped[slot_index]
	var name_label := Label.new()
	name_label.custom_minimum_size = Vector2(320, 30)
	if item != null:
		name_label.text = "%s: %s %s" % [SLOT_NAMES[slot_index], item.display_name, item.get_bonus_text()]
	else:
		name_label.text = "%s: 空" % SLOT_NAMES[slot_index]
	var button := Button.new()
	button.text = "卸下"
	button.disabled = item == null
	button.pressed.connect(unequip_item.bind(slot_index))
	row.add_child(name_label)
	row.add_child(button)
	return row

func _build_item_row(item: ItemDataScript) -> HBoxContainer:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.custom_minimum_size = Vector2(380, 30)
	var kind_text := "·%s" % item.get_weapon_kind_name() if item.get_weapon_kind_name() != "" else ""
	label.text = "%s(%s%s) %s" % [item.display_name, item.get_type_name(), kind_text, item.get_bonus_text()]
	var button := Button.new()
	if item.is_equippable():
		button.text = "装备"
		button.pressed.connect(equip_item.bind(item))
	else:
		button.text = "使用"
		button.pressed.connect(use_consumable.bind(item))
	row.add_child(label)
	row.add_child(button)
	return row

func _clear_container(container: Container) -> void:
	for child: Node in container.get_children():
		container.remove_child(child)
		child.queue_free()
