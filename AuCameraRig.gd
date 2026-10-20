## 相机执行层：持有并驱动 Camera2D，负责平滑、死区、边界、缩放与抖动。
## 场景里挂上本脚本后，_ready() 会自动把自己注册给 AuCameraDirector。
extends Node2D
class_name AuCameraRig


## 相机的静态偏移（像素）。抖动结束后会复位到该值。
@export var base_offset: Vector2 = Vector2(-27.585, -13.195):
	set(value):
		base_offset = value
		if camera != null:
			camera.offset = value

## 初始缩放，同时作为基础缩放：退出锁定区域 / 过场接管的缩放后回落到该值。
@export var zoom: Vector2 = Vector2.ONE:
	set(value):
		zoom = value
		if camera != null:
			camera.zoom = value

@export_group("Camera2D")

## 是否启用 Camera2D 自带的位置平滑；关闭后为硬跟随。
@export var position_smoothing_enabled: bool = true:
	set(value):
		position_smoothing_enabled = value
		if camera != null:
			camera.position_smoothing_enabled = value

## 位置平滑速度，越大跟随越紧、越小越拖尾。
@export var position_smoothing_speed: float = 6.0:
	set(value):
		position_smoothing_speed = value
		if camera != null:
			camera.position_smoothing_speed = value

## 相机内容左边界（世界坐标像素）。
@export var limit_left: int = -10000000:
	set(value):
		limit_left = value
		if camera != null:
			camera.limit_left = value

## 相机内容上边界（世界坐标像素）。
@export var limit_top: int = -10000000:
	set(value):
		limit_top = value
		if camera != null:
			camera.limit_top = value

## 相机内容右边界（世界坐标像素）。
@export var limit_right: int = 10000000:
	set(value):
		limit_right = value
		if camera != null:
			camera.limit_right = value

## 相机内容下边界（世界坐标像素）。
@export var limit_bottom: int = 10000000:
	set(value):
		limit_bottom = value
		if camera != null:
			camera.limit_bottom = value

@export_group("Dead Zone")

## 死区半尺寸（像素）：目标超出该范围才推动相机；保持 ZERO 则为完全硬跟随。
@export var dead_zone: Vector2 = Vector2.ZERO

@export_group("Shake")

## 抖动强度低于该值时判定结束，并复位相机偏移。
@export var shake_cutoff: float = 0.05

## 轻微档预设：x = 像素幅度，y = 每秒衰减系数。
@export var shake_light: Vector2 = Vector2(5.0, 3.0)
## 中等档预设：x = 像素幅度，y = 每秒衰减系数。
@export var shake_medium: Vector2 = Vector2(12.0, 1.5)
## 强烈档预设：x = 像素幅度，y = 每秒衰减系数。
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
		add_child(camera)

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


func _process(delta: float) -> void:
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
