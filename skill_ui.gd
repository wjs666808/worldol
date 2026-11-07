class_name SkillUI
extends Node

## 地图技能配置页:战斗前设置自动技能队列、手动主动技能集、自动战斗技能。
## 自动技能按顺序在多个回合循环释放,战斗中不可更改。

const SkillDataScript := preload("res://skill_data.gd")

@onready var _skill_button: Button = $Buttons/SkillButton
@onready var _panel: CanvasLayer = $Panel
@onready var _auto_list: VBoxContainer = $Panel/Center/VBox/AutoScroll/AutoList
@onready var _manual_list: VBoxContainer = $Panel/Center/VBox/ManualScroll/ManualList
@onready var _auto_active_label: Label = $Panel/Center/VBox/AutoActiveRow/AutoActiveLabel
@onready var _pool_list: VBoxContainer = $Panel/Center/VBox/PoolScroll/PoolList
@onready var _close_button: Button = $Panel/Center/VBox/CloseButton

func _ready() -> void:
	_skill_button.pressed.connect(toggle)
	_close_button.pressed.connect(toggle)
	_panel.visible = false

func toggle() -> void:
	_panel.visible = not _panel.visible
	if _panel.visible:
		_rebuild()

func _rebuild() -> void:
	var gs: Node = get_node("/root/GameState")
	_clear_container(_auto_list)
	_clear_container(_manual_list)
	_clear_container(_pool_list)
	for i in gs.auto_skills.size():
		_auto_list.add_child(_build_auto_row(gs.auto_skills[i], i, gs))
	for i in gs.chosen_active_skills.size():
		_manual_list.add_child(_build_manual_row(gs.chosen_active_skills[i], i, gs))
	var aa := gs.auto_active_skill as SkillDataScript
	_auto_active_label.text = "自动战斗技能: %s" % (aa.display_name if aa != null else "无(自动选择)")
	for res in gs.skill_pool:
		_pool_list.add_child(_build_pool_row(res, gs))

## 技能池行:加入自动队列 / 加入手动技能 / 设为自动战斗技能。
func _build_pool_row(res: Resource, gs: Node) -> HBoxContainer:
	var skill := res as SkillDataScript
	var row := HBoxContainer.new()
	var label := Label.new()
	label.custom_minimum_size = Vector2(200, 30)
	label.text = "%s(%s,%dMP)" % [skill.display_name, skill.get_kind_name(), skill.mp_cost]
	var auto_button := Button.new()
	auto_button.text = "自动"
	auto_button.pressed.connect(_add_auto.bind(gs, skill))
	var manual_button := Button.new()
	manual_button.text = "手动"
	manual_button.pressed.connect(_add_manual.bind(gs, skill))
	var active_button := Button.new()
	active_button.text = "自动战"
	active_button.pressed.connect(_set_auto_active.bind(gs, skill))
	row.add_child(label)
	row.add_child(auto_button)
	row.add_child(manual_button)
	row.add_child(active_button)
	return row

func _build_auto_row(res: Resource, index: int, gs: Node) -> HBoxContainer:
	var skill := res as SkillDataScript
	var row := HBoxContainer.new()
	var label := Label.new()
	label.custom_minimum_size = Vector2(240, 30)
	label.text = "第%d回合段: %s" % [index + 1, skill.display_name]
	var up := Button.new()
	up.text = "上移"
	up.pressed.connect(_move_auto.bind(gs, index, -1))
	var down := Button.new()
	down.text = "下移"
	down.pressed.connect(_move_auto.bind(gs, index, 1))
	var remove := Button.new()
	remove.text = "移除"
	remove.pressed.connect(_remove_auto.bind(gs, skill))
	row.add_child(label)
	row.add_child(up)
	row.add_child(down)
	row.add_child(remove)
	return row

func _build_manual_row(res: Resource, index: int, gs: Node) -> HBoxContainer:
	var skill := res as SkillDataScript
	var row := HBoxContainer.new()
	var label := Label.new()
	label.custom_minimum_size = Vector2(240, 30)
	label.text = skill.display_name
	var remove := Button.new()
	remove.text = "移除"
	remove.pressed.connect(_remove_manual.bind(gs, skill))
	row.add_child(label)
	row.add_child(remove)
	return row

func _add_auto(gs: Node, skill: SkillDataScript) -> void:
	if not gs.auto_skills.has(skill):
		var list: Array = gs.auto_skills.duplicate()
		list.append(skill)
		gs.set_auto_skills(list)
	_rebuild()

func _move_auto(gs: Node, index: int, direction: int) -> void:
	var list: Array = gs.auto_skills.duplicate()
	var target := index + direction
	if target < 0 or target >= list.size():
		return
	var item = list[index]
	list[index] = list[target]
	list[target] = item
	gs.set_auto_skills(list)
	_rebuild()

func _remove_auto(gs: Node, skill: SkillDataScript) -> void:
	var list: Array = gs.auto_skills.duplicate()
	list.erase(skill)
	gs.set_auto_skills(list)
	_rebuild()

func _add_manual(gs: Node, skill: SkillDataScript) -> void:
	if not gs.chosen_active_skills.has(skill):
		var list: Array = gs.chosen_active_skills.duplicate()
		list.append(skill)
		gs.set_chosen_active_skills(list)
	_rebuild()

func _remove_manual(gs: Node, skill: SkillDataScript) -> void:
	var list: Array = gs.chosen_active_skills.duplicate()
	list.erase(skill)
	gs.set_chosen_active_skills(list)
	_rebuild()

func _set_auto_active(gs: Node, skill: SkillDataScript) -> void:
	gs.set_auto_active_skill(skill)
	_rebuild()

func _clear_container(container: Container) -> void:
	for child: Node in container.get_children():
		container.remove_child(child)
		child.queue_free()
