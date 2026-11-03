@tool
extends Area2D
class_name AuCameraLockArea


## 水平锁定参考点：角色停留在本区域内时，相机 X 轴吸附到该 Marker2D。
@export var horizontal_lock_marker: Marker2D
## 垂直锁定参考点：相机 Y 轴吸附到该 Marker2D。不指定则只锁水平。
@export var vertical_lock_marker: Marker2D

## 水平锁定可移动距离（像素）：以 horizontal_lock_marker 的 X 为中心，相机 X 只能在 ±该值内移动。
## 为 0 表示完全钉死在该点（旧行为）。仅在设置了 horizontal_lock_marker 时生效。
@export_range(0.0, 4000.0, 1.0, "or_greater") var horizontal_range: float = 0.0
## 垂直锁定可移动距离（像素）：以 vertical_lock_marker 的 Y 为中心，相机 Y 只能在 ±该值内移动。
## 为 0 表示完全钉死在该点（旧行为）。仅在设置了 vertical_lock_marker 时生效。
@export_range(0.0, 4000.0, 1.0, "or_greater") var vertical_range: float = 0.0

## 在本区域内是否允许抬头（影响 AuCameraDirector.look_up() 是否生效）。
@export var can_look_up: bool = false
## 在本区域内是否允许低头（影响 AuCameraDirector.look_down() 是否生效）。
@export var can_look_down: bool = false

## 区域尺寸（像素）：决定碰撞矩形的大小，也就决定了相机锁定的触发范围。
@export var area_size: Vector2 = Vector2(600, 600):
	set(value):
		area_size = value
		_apply_size()

## 碰撞矩形是否以节点原点为中心。false 时矩形从原点向右下方向展开。
@export var centered: bool = true:
	set(value):
		centered = value
		_apply_size()

## 检测用物理层：只有该层的 body 进出区域才会注册 / 注销相机锁定，默认第 5 层（值 16）。
@export_flags_2d_physics var detect_layer: int = 16:
	set(value):
		detect_layer = value
		collision_layer = value


func _ready() -> void:
	_get_or_create_collision()
	collision_layer = detect_layer
	_apply_size()

	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
	if not body_exited.is_connected(_on_body_exited):
		body_exited.connect(_on_body_exited)


func _get_or_create_collision() -> CollisionShape2D:
	var collision := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if collision == null:
		collision = CollisionShape2D.new()
		collision.name = "CollisionShape2D"
		collision.debug_color = Color(0.249, 1.046, 0.0, 0.3)
		collision.shape = RectangleShape2D.new()
		add_child(collision)
		return collision
	# 复用已存在的 CollisionShape2D 时，强制每个节点持有独立的 RectangleShape2D。
	# 否则场景保存去重 / 节点复制会导致多个 lock 共享同一份 shape 子资源，
	# 出现"改一个、另一个也变"的联动。（duplicate 总会生成新的独立实例，
	# 比判断 resource_local_to_scene 更可靠，因为嵌入 .tscn 的共享子资源也标记为 local。）
	if collision.shape is RectangleShape2D:
		collision.shape = collision.shape.duplicate()
	else:
		collision.shape = RectangleShape2D.new()
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
