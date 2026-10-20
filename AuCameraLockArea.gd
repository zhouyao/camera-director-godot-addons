## 锁定区域触发器：角色进入时把相机锁到指定 Marker 上，离开时解锁。
## 进出信号由本脚本自动连接，无需在场景里手动连线。
@tool
extends Area2D
class_name AuCameraLockArea


## 非空时，把相机 X 锁定到该 Marker2D 的全局 X（留空则不锁定 X）。
@export var horizontal_lock_marker: Marker2D
## 非空时，把相机 Y 锁定到该 Marker2D 的全局 Y（留空则不锁定 Y）。
@export var vertical_lock_marker: Marker2D

## 该区域内是否允许玩家向上看（配合 AuCameraDirector.look_up()）。
@export var can_look_up: bool = false
## 该区域内是否允许玩家向下看（配合 AuCameraDirector.look_down()）。
@export var can_look_down: bool = false

## 区域碰撞矩形的尺寸（像素）。
@export var area_size: Vector2 = Vector2(600, 600):
	set(value):
		area_size = value
		_apply_size()

## 碰撞矩形是否以节点原点为中心；关闭则以节点原点为左上角。
@export var centered: bool = true:
	set(value):
		centered = value
		_apply_size()

## 用于检测角色进出的物理层，会同步写入 Area2D.collision_layer。
## 角色的 collision_mask 必须包含该层，否则进/出区域不会被检测到。
@export_flags_2d_physics var detect_layer: int = 16:
	set(value):
		detect_layer = value
		collision_layer = value


func _ready() -> void:
	# 每个节点的 shape 都由本节点独立创建，无共享资源，可直接改 size。
	_get_or_create_collision()
	collision_layer = detect_layer
	_apply_size()

	# 裸加类节点无场景连线，这里确保进/出信号已连接。
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
	if not body_exited.is_connected(_on_body_exited):
		body_exited.connect(_on_body_exited)


func _get_or_create_collision() -> CollisionShape2D:
	var collision := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if collision != null:
		return collision
	collision = CollisionShape2D.new()
	collision.name = "CollisionShape2D"
	collision.shape = RectangleShape2D.new()
	add_child(collision)
	return collision


func _apply_size() -> void:
	var collision := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if collision == null or not (collision.shape is RectangleShape2D):
		return
	collision.shape.size = area_size
	collision.position = Vector2.ZERO if centered else area_size / 2.0


func _on_body_entered(_body: Node2D) -> void:
	AuCameraDirector.register_area(self)


func _on_body_exited(_body: Node2D) -> void:
	AuCameraDirector.unregister_area(self)
