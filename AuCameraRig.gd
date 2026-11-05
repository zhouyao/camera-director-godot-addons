extends Node2D
class_name AuCameraRig


## 缩放发生变化时发出（包含 tween 期间的逐帧变化）。
## 项目侧可借此同步任何依赖 zoom 的逻辑（例如相机边界的换算）。
## 插件本身不引用项目 autoload，保持可复用。
signal zoom_changed(new_zoom: Vector2)


## 相机基础偏移（像素）：在不移动锚点的前提下微调取景，同时也是抖动结束后的归位基准。
@export var base_offset: Vector2 = Vector2(-27.585, -13.195):
	set(value):
		base_offset = value
		if camera != null:
			camera.offset = value

## 缩放：分量大于 1 画面拉近、小于 1 拉远。可用 AuCameraDirector.tween_zoom() 做平滑过渡。
@export var zoom: Vector2 = Vector2.ONE:
	set(value):
		zoom = value
		if camera != null:
			camera.zoom = value
		zoom_changed.emit(value)

@export_group("Camera2D")

## 是否开启位置平滑：开启后相机缓动逼近锚点，关闭则硬跟随。
@export var position_smoothing_enabled: bool = true:
	set(value):
		position_smoothing_enabled = value
		if camera != null:
			camera.position_smoothing_enabled = value

## 平滑跟随速度：值越大越紧跟目标，越小越"飘"。
@export var position_smoothing_speed: float = 6.0:
	set(value):
		position_smoothing_speed = value
		if camera != null:
			camera.position_smoothing_speed = value

## 相机左边界（世界坐标像素）：限制可视范围，防止露出关卡外。默认 ±1000 万即不限制。
@export var limit_left: int = -10000000:
	set(value):
		limit_left = value
		if camera != null:
			camera.limit_left = value

## 相机上边界（世界坐标像素），语义同 limit_left。
@export var limit_top: int = -10000000:
	set(value):
		limit_top = value
		if camera != null:
			camera.limit_top = value

## 相机右边界（世界坐标像素），语义同 limit_left。
@export var limit_right: int = 10000000:
	set(value):
		limit_right = value
		if camera != null:
			camera.limit_right = value

## 相机下边界（世界坐标像素），语义同 limit_left。
@export var limit_bottom: int = 10000000:
	set(value):
		limit_bottom = value
		if camera != null:
			camera.limit_bottom = value

@export_group("Dead Zone")

## 死区尺寸（像素）：目标在该矩形内移动时相机不动，超出才被拖动。为 0 表示紧跟随。
## 只在对应轴大于 0 时对该轴生效。
@export var dead_zone: Vector2 = Vector2.ZERO

@export_group("Shake")

## 抖动收敛阈值：强度衰减到该值以下即视为结束，直接归位到 base_offset，避免残留微抖。
@export var shake_cutoff: float = 0.05

## 轻微抖动：x = 强度（像素振幅），y = 衰减速度（越大收得越快）。
@export var shake_light: Vector2 = Vector2(5.0, 3.0)
## 中等抖动：x = 强度，y = 衰减速度。
@export var shake_medium: Vector2 = Vector2(12.0, 1.5)
## 强烈抖动：x = 强度，y = 衰减速度。
@export var shake_heavy: Vector2 = Vector2(20.0, 0.8)

var camera: Camera2D

var _anchor: Vector2
var _has_anchor := false

var _shake_strength: float = 0.0
var _shake_fade: float = 0.0
var _shake_direction := Vector2.ZERO
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	if camera == null:
		camera = Camera2D.new()
		camera.name = "Camera2D"
		# 本项目开启了 2D 物理插值，相机必须按物理帧采样；显式声明可避免
		# "overridden to physics process mode due to use of physics interpolation" 警告
		# （该警告在相机 ENTER_TREE 时判定，所以必须在 add_child 之前设置）。
		camera.process_callback = Camera2D.CAMERA2D_PROCESS_PHYSICS
		add_child(camera)

	camera.process_callback = Camera2D.CAMERA2D_PROCESS_PHYSICS
	camera.zoom = zoom
	camera.offset = base_offset
	camera.position_smoothing_enabled = position_smoothing_enabled
	camera.position_smoothing_speed = position_smoothing_speed
	camera.limit_left = limit_left
	camera.limit_top = limit_top
	camera.limit_right = limit_right
	camera.limit_bottom = limit_bottom
	AuCameraDirector.set_rig(self)

func shake(strength: float, fade: float, direction: Vector2 = Vector2.ZERO) -> void:
	_shake_strength = maxf(_shake_strength, strength)
	_shake_fade = fade
	_shake_direction = direction.normalized() if direction != Vector2.ZERO else Vector2.ZERO


func set_target_pos(pos: Vector2) -> void:
	if not _has_anchor:
		_has_anchor = true
		_anchor = pos
		camera.global_position = pos
		return
	_update_anchor(pos)


func apply_zoom(z: Vector2, duration := 0.0) -> void:
	if duration <= 0.0:
		zoom = z
	else:
		var t := create_tween()
		t.tween_property(self, "zoom", z, duration)

func set_limits(l: int, t: int, r: int, b: int) -> void:
	limit_left = l
	limit_top = t
	limit_right = r
	limit_bottom = b

func snap_to_target() -> void:
	if not _has_anchor:
		return
	camera.global_position = _anchor
	if camera.has_method("reset_smoothing"):
		camera.reset_smoothing()


## 抖动用物理帧驱动：物理插值模式下 Camera2D 只在物理 tick 采样 offset，
## 放在 _process 里改 offset 实际要等到下个物理帧才生效，会出现阶梯感。
func _physics_process(delta: float) -> void:
	if _shake_strength <= 0.0:
		return

	_shake_strength = lerpf(_shake_strength, 0.0, _shake_fade * delta)

	if _shake_strength < shake_cutoff:
		_shake_strength = 0.0
		camera.offset = base_offset
	else:
		camera.offset = base_offset + _random_offset()


func _update_anchor(target: Vector2) -> void:
	if dead_zone.x > 0.0:
		var dx := target.x - _anchor.x
		if absf(dx) > dead_zone.x:
			_anchor.x = target.x - signf(dx) * dead_zone.x
	else:
		_anchor.x = target.x

	if dead_zone.y > 0.0:
		var dy := target.y - _anchor.y
		if absf(dy) > dead_zone.y:
			_anchor.y = target.y - signf(dy) * dead_zone.y
	else:
		_anchor.y = target.y

	camera.global_position = _anchor


func _random_offset() -> Vector2:
	var offset := Vector2(
		_rng.randf_range(-_shake_strength, _shake_strength),
		_rng.randf_range(-_shake_strength, _shake_strength)
	)
	if _shake_direction != Vector2.ZERO:
		offset += _shake_direction * _shake_strength * 0.6
	return offset
