@tool
extends Area2D
class_name AuCameraLockArea

## 相机锁定区：玩家进入本区域时，`AuCameraDirector` 把镜头 X / Y 吸附到指定参考点。
##
## Inspector 配置分区（顺序即显示顺序）：
##   1. 区域 Shape & Detection —— 触发范围多大、区域自己在哪一层
##   2. 锁定 Lock               —— 吸附到哪个参考点、允许偏离多少
##   3. 优先级 & 边界           —— 多锁区同时生效时谁说了算、能否突破 CameraBounds
##   4. 镜头行为 Look           —— 区域内是否允许抬头 / 低头
##   5. 编辑器预览              —— 四角方框（仅编辑器，运行时零开销）
##
## 约定：每个 `##` 注释即 Inspector 悬浮提示，写清"作用 / 单位 / 取值约定 / 与谁联动"。
## `@export_group` 一直作用到下一个 group —— 新增导出项必须放进对应分组，
## 别落在组外（曾出现 detect_layer 被归进"编辑器预览"组的问题）。
## 逐区调数值在 .tscn 里改；整类一起调才动脚本默认值。

# ---------------------------------------------------------------- 1. 区域

@export_group("区域 Shape & Detection")

## 触发区域的宽高（像素）。运行时写入 `CollisionShape2D` 的 `RectangleShape2D.size`，
## 同时也是编辑器四角方框的边界。改动会立即重算碰撞盒并刷新预览。
@export var area_size: Vector2 = Vector2(600, 600):
	set(value):
		area_size = value
		_apply_size()
		queue_redraw()

## 碰撞矩形是否以节点原点为中心：
##   `true`  → 覆盖 `[-size/2, +size/2]`
##   `false` → 从 `(0,0)` 向右下展开到 `(size.x, size.y)`
## 项目内 5 个锁定区都用 `false`（从左上角起算）。
@export var centered: bool = true:
	set(value):
		centered = value
		_apply_size()
		queue_redraw()

## 本区域所在的物理层（写入 `Area2D.collision_layer`），默认第 5 层 = 值 16。
## **不**决定"哪些 body 能触发本区域"——那由 `collision_mask` 与对方的 layer 决定；
## 玩家在第 1 层、Area2D 默认 mask=1，所以默认即可检测到玩家。
## 若要换检测对象，请改 Collision 面板里的 `collision_mask`，不要改这里。
@export_flags_2d_physics var detect_layer: int = 16:
	set(value):
		detect_layer = value
		collision_layer = value

# ---------------------------------------------------------------- 2. 锁定

@export_group("锁定 Lock")

@export_subgroup("参考点 Markers")
## 水平锁定参考点：玩家停留在本区域内时，相机 X 吸附到该 Marker2D 的 X。
## 留空则该轴不锁定。
@export var horizontal_lock_marker: Marker2D

## 垂直锁定参考点：相机 Y 吸附到该 Marker2D 的 Y。
## 留空则该轴不锁定（只锁水平是常见配置）。
@export var vertical_lock_marker: Marker2D

@export_subgroup("活动范围 Ranges")
## 水平锁定后可偏离的距离（像素）：以 `horizontal_lock_marker` 的 X 为中心，
## 相机 X 只能在 `±该值` 内移动。`0` = 完全钉死在该点。
## 仅在设置了 `horizontal_lock_marker` 时生效。
@export_range(0.0, 4000.0, 1.0, "or_greater") var horizontal_range: float = 0.0

## 垂直锁定后可偏离的距离（像素）：以 `vertical_lock_marker` 的 Y 为中心，
## 相机 Y 只能在 `±该值` 内移动。`0` = 完全钉死在该点。
## 仅在设置了 `vertical_lock_marker` 时生效。
@export_range(0.0, 4000.0, 1.0, "or_greater") var vertical_range: float = 0.0

# ---------------------------------------------------------------- 3. 优先级 & 边界

@export_group("优先级 & 边界 Priority & Bounds")

## 多个锁定区同时生效时的执行顺序：数值大的后执行、覆盖前面的结果。
## 参考量级：跟随 = 0，锁定区默认 = 10，过场接管 = 100。
## 不能命名为 priority —— Area2D 已内置同名属性（物理区域覆盖顺序），会报重复成员。
@export var camera_priority: int = 10

## 本区域生效时，允许锁定目标突破关卡 `CameraBounds`（Camera2D.limit_*）的硬边界。
## 只在「本区域是当前优先级最高的锁定区」时生效；离开后自动恢复关卡硬边界。
## 只放宽真正配了 Marker 的那根轴：只锁 Y 就绝不动 X，否则会跑出关卡左右边界。
## 用途：需要把镜头锁到 CameraBounds 覆盖不到的高度时打开它。
@export var override_bounds: bool = false

# ---------------------------------------------------------------- 4. 镜头行为

@export_group("镜头行为 Look")

## 本区域内是否允许抬头：决定 `AuCameraDirector.look_up()` 在此处是否生效。
@export var can_look_up: bool = false

## 本区域内是否允许低头：决定 `AuCameraDirector.look_down()` 在此处是否生效。
@export var can_look_down: bool = false

# ---------------------------------------------------------------- 5. 编辑器预览

@export_group("编辑器预览 Editor Preview")

## 在 2D 编辑器里把区域四个角画成实心方框（运行时不画）。
@export var show_corners_in_editor: bool = true:
	set(value):
		show_corners_in_editor = value
		queue_redraw()

## 矩形内部填充的不透明度：`0` = **完全透明**（默认），只留轮廓与四角方框，
## 不遮挡底下的关卡内容；调大则铺淡色块。
## 作用于 Godot 自带的 `CollisionShape2D.debug_color`（编辑器绘制专用），
## 所以即使没有任何脚本绘制，这项也能控制那层绿色半透明填充。
@export_range(0.0, 1.0, 0.01) var fill_alpha: float = 0.0:
	set(value):
		fill_alpha = clampf(value, 0.0, 1.0)
		_sync_debug_color()
		queue_redraw()

## 四角方框的颜色。
@export var corner_color: Color = Color(0.0, 0.0, 0.0):
	set(value):
		corner_color = value
		queue_redraw()

## 四角方框的边长（世界单位）。编辑器缩得很小时会自动放大，
## 保证至少有 6 个屏幕像素，不至于看不到。最小值为 1。
@export var corner_size: float = 80.0:
	set(value):
		corner_size = maxf(value, 1.0)
		queue_redraw()


func _ready() -> void:
	_get_or_create_collision()
	collision_layer = detect_layer
	_apply_size()

	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
	if not body_exited.is_connected(_on_body_exited):
		body_exited.connect(_on_body_exited)

	# 编辑器下定时重绘：_ready 的那一次会被 2D 视口初始化冲掉，
	# 之后若属性没变化就再也看不到四角方框。
	if Engine.is_editor_hint():
		_sync_debug_color()
		set_process(true)
		queue_redraw()
	else:
		set_process(false)


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


## Godot 编辑器用 `CollisionShape2D.debug_color` 画碰撞形状的填充。
## 把它的 alpha 与 `fill_alpha` 对齐：默认 0 = 矩形中间完全透明，只留轮廓与四角方框。
## 仅在编辑器里改（运行时不碰节点属性）；值相同时不写，避免反复把场景标脏。
func _sync_debug_color() -> void:
	if not Engine.is_editor_hint():
		return
	var collision := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if collision == null:
		return
	var dc := collision.debug_color
	if is_equal_approx(dc.a, fill_alpha):
		return
	dc.a = fill_alpha
	collision.debug_color = dc


func _on_body_entered(_body: Node2D) -> void:
	AuCameraDirector.register_area(self)


func _on_body_exited(_body: Node2D) -> void:
	AuCameraDirector.unregister_area(self)


# ---------------------------------------------------------------- 编辑器绘制

const REDRAW_INTERVAL := 0.5

var _redraw_accum := 0.0


func _notification(what: int) -> void:
	if Engine.is_editor_hint() and (what == NOTIFICATION_ENTER_TREE or what == NOTIFICATION_VISIBILITY_CHANGED):
		queue_redraw()


func _process(delta: float) -> void:
	if not Engine.is_editor_hint():
		set_process(false)
		return
	_redraw_accum += delta
	if _redraw_accum >= REDRAW_INTERVAL:
		_redraw_accum = 0.0
		queue_redraw()


func _draw() -> void:
	if not Engine.is_editor_hint() or not show_corners_in_editor:
		return
	if area_size.x <= 0.0 or area_size.y <= 0.0:
		return

	# _draw 用局部坐标；area_size / centered 正好描述碰撞矩形在局部的位置
	var rect := Rect2(-area_size * 0.5, area_size) if centered else Rect2(Vector2.ZERO, area_size)

	var canvas_scale := 1.0
	var vp := get_viewport()
	if vp != null:
		canvas_scale = maxf(vp.get_global_canvas_transform().get_scale().x, 0.001)
	# 实心方框在任何缩放下都要看得见：至少 6 个屏幕像素
	var s := maxf(corner_size, 6.0 / canvas_scale)
	var half := Vector2(s, s) * 0.5
	var lw := clampf(2.0 / canvas_scale, 1.0, 120.0)

	# 引擎的 debug 形状在 alpha=0 时可能连轮廓都不画，这里补一条描边保证矩形仍可辨。
	# 只描边、不填充 —— 中间是否铺色由 CollisionShape2D.debug_color 的 alpha（fill_alpha）决定。
	draw_rect(rect, corner_color, false, lw)

	var corners := [
		rect.position,
		Vector2(rect.end.x, rect.position.y),
		rect.end,
		Vector2(rect.position.x, rect.end.y),
	]
	for p in corners:
		draw_rect(Rect2(p - half, Vector2(s, s)), corner_color, true)
