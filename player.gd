class_name PlayerController
extends CharacterBody2D

## 地图玩家控制器:WASD/方向键移动(物理键检测,不受输入法/InputMap 干扰)。

@export var move_speed: float = 220.0

func _physics_process(_delta: float) -> void:
	var input := Vector2.ZERO
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		input.y -= 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		input.y += 1.0
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		input.x -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		input.x += 1.0
	velocity = input.normalized() * move_speed
	move_and_slide()
