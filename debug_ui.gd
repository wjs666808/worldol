class_name DebugUI
extends Node

## 调试设置面板:调整英雄队伍/宠物/敌人属性、队伍规模、一键获得物品。
## 挂在地图场景下,子节点 Panel 为面板 CanvasLayer(默认隐藏)。

const CharacterStatsScript := preload("res://char_stats.gd")
const ItemDataScript := preload("res://item_data.gd")

const FIELDS: Array[Dictionary] = [
	{"key": &"strength", "name": "力量", "type": "int"},
	{"key": &"intelligence", "name": "智力", "type": "int"},
	{"key": &"perception", "name": "感知", "type": "int"},
	{"key": &"agility", "name": "敏捷", "type": "int"},
	{"key": &"constitution", "name": "体质", "type": "int"},
	{"key": &"level", "name": "等级", "type": "int"},
	{"key": &"weapon_damage", "name": "武器伤害", "type": "int"},
	{"key": &"attack_count", "name": "攻击次数", "type": "int"},
	{"key": &"physical_accuracy", "name": "物理命中", "type": "int"},
	{"key": &"magic_accuracy", "name": "魔法命中", "type": "int"},
	{"key": &"crit_chance", "name": "致命率", "type": "float"},
	{"key": &"block_chance", "name": "格挡率", "type": "float"},
	{"key": &"mana_shield", "name": "法力护盾", "type": "float"},
	{"key": &"counter_chance", "name": "反击率", "type": "float"},
	{"key": &"magic_feedback", "name": "魔法反馈", "type": "float"},
	{"key": &"life_steal", "name": "生命吸收", "type": "float"},
	{"key": &"mana_steal", "name": "法力吸收", "type": "float"},
	{"key": &"force_hit", "name": "强制命中", "type": "float"},
	{"key": &"regen_hp", "name": "回复生命", "type": "int"},
	{"key": &"regen_mp", "name": "回复法力", "type": "int"},
	{"key": &"damage_shield", "name": "免伤护盾", "type": "int"},
]

var _targets: Array = []
var _selected_target := 0

@onready var _debug_button: Button = $Buttons/DebugButton
@onready var _panel: CanvasLayer = $Panel
@onready var _target_select: OptionButton = $Panel/Center/VBox/Header/TargetSelect
@onready var _add_hero_button: Button = $Panel/Center/VBox/TeamRow/AddHeroButton
@onready var _remove_hero_button: Button = $Panel/Center/VBox/TeamRow/RemoveHeroButton
@onready var _enemy_count_label: Label = $Panel/Center/VBox/TeamRow/EnemyCountLabel
@onready var _enemy_minus: Button = $Panel/Center/VBox/TeamRow/EnemyMinus
@onready var _enemy_plus: Button = $Panel/Center/VBox/TeamRow/EnemyPlus
@onready var _attr_list: VBoxContainer = $Panel/Center/VBox/AttrScroll/AttrList
@onready var _item_list: VBoxContainer = $Panel/Center/VBox/ItemList
@onready var _close_button: Button = $Panel/Center/VBox/CloseButton

func _ready() -> void:
	_debug_button.pressed.connect(toggle)
	_close_button.pressed.connect(toggle)
	_target_select.item_selected.connect(_on_target_selected)
	_add_hero_button.pressed.connect(_on_add_hero)
	_remove_hero_button.pressed.connect(_on_remove_hero)
	_enemy_minus.pressed.connect(_adjust_enemy_count.bind(-1))
	_enemy_plus.pressed.connect(_adjust_enemy_count.bind(1))
	_panel.visible = false
	_build_targets()
	_build_item_buttons()

func _build_targets() -> void:
	_targets.clear()
	_target_select.clear()
	var gs: Node = get_node("/root/GameState")
	for i in gs.hero_stats.size():
		_targets.append({"name": "英雄%d" % (i + 1), "stats": gs.hero_stats[i]})
	_targets.append({"name": "宠物", "stats": gs.pet_template})
	for i in _enemy_templates().size():
		var stats = _enemy_templates()[i]
		_targets.append({"name": "敌人%s" % stats.display_name, "stats": stats})
	for target in _targets:
		_target_select.add_item(target.name)
	_selected_target = 0

func _enemy_templates() -> Array:
	return get_node("/root/GameState").enemy_templates

func toggle() -> void:
	_panel.visible = not _panel.visible
	if _panel.visible:
		_rebuild()

func _on_target_selected(index: int) -> void:
	_selected_target = index
	_rebuild()

func _current_stats() -> CharacterStatsScript:
	if _targets.is_empty():
		return null
	return _targets[_selected_target]["stats"] as CharacterStatsScript

func _rebuild() -> void:
	_clear_container(_attr_list)
	var gs: Node = get_node("/root/GameState")
	_enemy_count_label.text = "敌人数量: %d" % gs.enemy_count
	_add_hero_button.disabled = gs.hero_stats.size() >= 5
	_remove_hero_button.disabled = gs.hero_stats.size() <= 1
	var stats := _current_stats()
	if stats == null:
		return
	for field in FIELDS:
		_attr_list.add_child(_build_attr_row(field, stats))

func _build_attr_row(field: Dictionary, stats: CharacterStatsScript) -> HBoxContainer:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.custom_minimum_size = Vector2(200, 28)
	label.text = "%s: %s" % [field["name"], _fmt_value(stats[field["key"]], field["type"])]
	var minus := Button.new()
	minus.text = "-"
	minus.custom_minimum_size = Vector2(34, 28)
	minus.pressed.connect(_adjust.bind(stats, field, -1.0))
	var plus := Button.new()
	plus.text = "+"
	plus.custom_minimum_size = Vector2(34, 28)
	plus.pressed.connect(_adjust.bind(stats, field, 1.0))
	row.add_child(label)
	row.add_child(minus)
	row.add_child(plus)
	return row

func _adjust(stats: CharacterStatsScript, field: Dictionary, direction: float) -> void:
	var key: StringName = field["key"]
	var ftype: String = field["type"]
	if key == &"attack_count":
		stats.attack_count = maxi(stats.attack_count + int(direction), 1)
	elif key == &"level":
		stats.level = maxi(stats.level + int(direction), 1)
	elif ftype == "float":
		stats[key] = clampf(float(stats[key]) + direction * 0.05, 0.0, 2.0)
	else:
		stats[key] = maxi(int(stats[key]) + int(direction), 0)
	_rebuild()

func _fmt_value(value: Variant, ftype: String) -> String:
	if ftype == "float":
		return "%d%%" % roundf(float(value) * 100.0)
	return str(int(value))

func _on_add_hero() -> void:
	var gs: Node = get_node("/root/GameState")
	if gs.add_hero():
		_build_targets()
		_rebuild()

func _on_remove_hero() -> void:
	var gs: Node = get_node("/root/GameState")
	if gs.remove_hero():
		_build_targets()
		_rebuild()

func _adjust_enemy_count(direction: int) -> void:
	var gs: Node = get_node("/root/GameState")
	gs.enemy_count = clampi(gs.enemy_count + direction, 1, 20)
	_rebuild()

func _build_item_buttons() -> void:
	for item: ItemDataScript in _make_gift_items():
		var button := Button.new()
		button.text = "+ %s" % item.display_name
		button.pressed.connect(_grant_item.bind(item))
		_item_list.add_child(button)

func _grant_item(item: ItemDataScript) -> void:
	var gs: Node = get_node("/root/GameState")
	gs.inventory_items.append(item)
	_item_list.add_child(_make_granted_label(item))

func _make_granted_label(item: ItemDataScript) -> Label:
	var label := Label.new()
	label.text = "已获得:%s" % item.display_name
	label.modulate = Color(0.4, 0.9, 0.4, 1.0)
	return label

func _make_gift_items() -> Array[ItemDataScript]:
	var items: Array[ItemDataScript] = []
	items.append(_make_potion())
	items.append(_make_item("铁甲", ItemDataScript.ItemType.CHEST, {"constitution_bonus": 2, "perception_bonus": 1}))
	items.append(_make_item("哥布林短剑", ItemDataScript.ItemType.WEAPON, {"strength_bonus": 3, "weapon_damage_bonus": 4, "weapon_kind": ItemDataScript.WeaponKind.SWORD}))
	items.append(_make_item("野狼爪", ItemDataScript.ItemType.ACCESSORY, {"strength_bonus": 2, "agility_bonus": 1}))
	items.append(_make_item("铁血指环", ItemDataScript.ItemType.ACCESSORY, {"strength_bonus": 5, "crit_bonus": 0.1, "life_steal_bonus": 0.15, "force_hit_bonus": 0.1}))
	items.append(_make_item("巨力双手剑", ItemDataScript.ItemType.WEAPON, {"strength_bonus": 8, "weapon_damage_bonus": 12, "attack_count_bonus": 1, "weapon_kind": ItemDataScript.WeaponKind.BLADE}, true))
	items.append(_make_item("雷鸣战锤", ItemDataScript.ItemType.WEAPON, {"strength_bonus": 6, "weapon_damage_bonus": 10, "block_bonus": 0.1, "weapon_kind": ItemDataScript.WeaponKind.HAMMER}, true))
	items.append(_make_item("精灵长弓", ItemDataScript.ItemType.WEAPON, {"agility_bonus": 5, "weapon_damage_bonus": 8, "physical_accuracy_bonus": 10, "weapon_kind": ItemDataScript.WeaponKind.BOW}))
	items.append(_make_item("龙脊长枪", ItemDataScript.ItemType.WEAPON, {"agility_bonus": 4, "weapon_damage_bonus": 9, "counter_bonus": 0.1, "weapon_kind": ItemDataScript.WeaponKind.SPEAR}))
	items.append(_make_item("秘法权杖", ItemDataScript.ItemType.WEAPON, {"intelligence_bonus": 6, "magic_accuracy_bonus": 12, "magic_feedback_bonus": 0.1, "weapon_kind": ItemDataScript.WeaponKind.STAFF}))
	items.append(_make_item("玄机法器", ItemDataScript.ItemType.WEAPON, {"intelligence_bonus": 5, "perception_bonus": 3, "mana_steal_bonus": 0.15, "weapon_kind": ItemDataScript.WeaponKind.ARTIFACT}))
	items.append(_make_item("炽炎炮", ItemDataScript.ItemType.WEAPON, {"strength_bonus": 4, "weapon_damage_bonus": 14, "crit_bonus": 0.08, "weapon_kind": ItemDataScript.WeaponKind.CANNON}, true))
	items.append(_make_item("荆棘披风", ItemDataScript.ItemType.CLOAK, {"counter_bonus": 0.2, "block_bonus": 0.15}))
	items.append(_make_item("魔法斗篷", ItemDataScript.ItemType.CLOAK, {"magic_feedback_bonus": 0.25, "magic_accuracy_bonus": 15}))
	items.append(_make_item("生命头盔", ItemDataScript.ItemType.HEAD, {"constitution_bonus": 3, "regen_hp_bonus": 8}))
	items.append(_make_item("疾风坐骑", ItemDataScript.ItemType.RIDER, {"agility_bonus": 6, "perception_bonus": 2}))
	items.append(_make_item("勇者时装", ItemDataScript.ItemType.FASHION, {"perception_bonus": 2, "regen_mp_bonus": 3}))
	return items

func _make_potion() -> ItemDataScript:
	var potion := ItemDataScript.new()
	potion.display_name = "治疗药水"
	potion.item_type = ItemDataScript.ItemType.CONSUMABLE
	potion.hp_restore = 50
	potion.price = 15
	return potion

func _make_item(display_name: String, item_type: int, bonuses: Dictionary, two_handed := false) -> ItemDataScript:
	var item := ItemDataScript.new()
	item.display_name = display_name
	item.item_type = item_type
	item.two_handed = two_handed
	for key: String in bonuses:
		item.set(key, bonuses[key])
	return item

func _clear_container(container: Container) -> void:
	for child: Node in container.get_children():
		container.remove_child(child)
		child.queue_free()
