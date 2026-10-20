## 相机决策层：全局单例（Autoload 名固定为 AuCameraDirector），是对外唯一的入口。
## 每帧收集所有 AuCameraBehavior，按 priority 升序依次 resolve 共享上下文，
## 再把结果（目标位置 / 缩放）交给 AuCameraRig 执行。
extends Node


## 跟随锚点发生变化。node 为新的锚点。
signal follow_changed(node: Node2D)
## 当前生效的锁定区域发生变化。area 为 null 表示回到纯跟随。
signal active_area_changed(area: AuCameraLockArea)
## 过场接管开始。node 为被接管到的目标节点。
signal override_started(node: Node2D)
## 过场接管结束。node 为刚刚结束接管的目标节点。
signal override_ended(node: Node2D)
## 注视偏移发生变化。offset 为负表示向上看，为正表示向下看，0 表示复位。
signal look_changed(offset: float)

# 注视偏移的像素幅度（look_up 为负、look_down 为正）。
const LOOK_MAGNITUDE := 100.0

# 缩放缓动的默认时长（秒）。
const ZOOM_TWEEN_DURATION := 0.4


var _rig: AuCameraRig = null

var _behaviors: Array[AuCameraBehavior] = []
var _follow_behavior := AuFollowBehavior.new()

var _look_offset := 0.0
var _active_area: AuCameraLockArea = null
var _warned_no_follow := false

var _base_zoom: Vector2 = Vector2.ONE
var _active_zoom: Vector2 = Vector2.ONE
var _zoom_held := false


func _init() -> void:
	_behaviors.append(_follow_behavior)


## 绑定执行层 Rig，通常由 AuCameraRig._ready() 自动调用，无需手动调用。
## 绑定时会以当前 Rig 的 zoom 作为基础缩放，并重置关卡状态。
func set_rig(rig: AuCameraRig) -> void:
	if _rig == rig:
		return
	_rig = rig
	_base_zoom = rig.zoom
	_reset_level_state()

## 设置跟随锚点。建议在角色自身的 _ready() 里调用，
## 这样角色死亡重建后也能自动重新挂上相机。
func set_follow(node: Node2D) -> void:
	_follow_behavior._target = node
	_warned_no_follow = false
	follow_changed.emit(node)

## 清空除跟随锚点外的所有状态：锁定区域、过场接管、注视偏移、缩放。
## 切换关卡时必须调用，否则上一关的行为会残留。
func clear() -> void:
	_reset_level_state()

func _reset_level_state() -> void:
	for i in range(_behaviors.size() - 1, -1, -1):
		if _behaviors[i] != _follow_behavior:
			_behaviors.remove_at(i)
	_look_offset = 0.0
	_active_area = null
	_zoom_held = false
	_active_zoom = _base_zoom


## 注册锁定区域。一般由 AuCameraLockArea 的 body_entered 自动调用。
## 同一区域不会重复注册。
func register_area(area: AuCameraLockArea) -> void:
	if area == null:
		return
	for b in _behaviors:
		if b is AuLockAreaBehavior and (b as AuLockAreaBehavior).area == area:
			return
	_behaviors.append(AuLockAreaBehavior.new(area, _look_offset))

## 注销锁定区域。一般由 AuCameraLockArea 的 body_exited 自动调用。
func unregister_area(area: AuCameraLockArea) -> void:
	for i in range(_behaviors.size() - 1, -1, -1):
		if _behaviors[i] is AuLockAreaBehavior and (_behaviors[i] as AuLockAreaBehavior).area == area:
			_behaviors.remove_at(i)


## 过场接管：相机移到 node 位置。zoom 传非 ZERO 时同时改变缩放（结束后自动回落）。
func push_override(node: Node2D, zoom := Vector2.ZERO) -> void:
	if node == null:
		return
	_behaviors.append(AuShotBehavior.new(node, zoom))
	override_started.emit(node)

## 结束过场接管。node 为 null 时结束最近压入的那个，否则结束指定节点的接管。
func pop_override(node: Node2D = null) -> void:
	for i in range(_behaviors.size() - 1, -1, -1):
		if _behaviors[i] is AuShotBehavior and (node == null or (_behaviors[i] as AuShotBehavior)._node == node):
			var popped: Node2D = (_behaviors[i] as AuShotBehavior)._node
			_behaviors.remove_at(i)
			override_ended.emit(popped)
			return


## 压入自定义行为。behavior 为 null 或已存在时忽略。
func push_behavior(behavior: AuCameraBehavior) -> void:
	if behavior == null or _behaviors.has(behavior):
		return
	_behaviors.append(behavior)

## 弹出自定义行为。跟随行为（AuFollowBehavior）不可弹出。
func pop_behavior(behavior: AuCameraBehavior) -> void:
	if behavior != null and behavior != _follow_behavior:
		_behaviors.erase(behavior)

## 当前是否处于过场接管中（存在 AuShotBehavior）。
func is_overridden() -> bool:
	for b in _behaviors:
		if b is AuShotBehavior:
			return true
	return false


## 向上看：在允许 look up 的锁定区域内把相机上移 LOOK_MAGNITUDE。
func look_up() -> void:
	_set_look(-LOOK_MAGNITUDE)

## 向下看：在允许 look down 的锁定区域内把相机下移 LOOK_MAGNITUDE。
func look_down() -> void:
	_set_look(LOOK_MAGNITUDE)

## 取消注视偏移，相机回到区域锁定位置。
func clear_look() -> void:
	_set_look(0.0)

func _set_look(value: float) -> void:
	_look_offset = value
	look_changed.emit(value)


## 直接缓动缩放，并把 z 设为新的基础缩放（后续回落到该值）。
func tween_zoom(z: Vector2, duration := ZOOM_TWEEN_DURATION) -> void:
	if is_instance_valid(_rig):
		_rig.apply_zoom(z, duration)
	_base_zoom = z
	_active_zoom = z
	_zoom_held = false

## 设置相机边界（世界坐标像素：左、上、右、下）。
func set_limits(l: int, t: int, r: int, b: int) -> void:
	if is_instance_valid(_rig):
		_rig.set_limits(l, t, r, b)

## 立即对齐到目标位置并重置平滑，用于切场景 / 传送后消除拖尾。
func snap() -> void:
	if is_instance_valid(_rig):
		_rig.snap_to_target()


## 自定义抖动。strength 为像素幅度，fade 为每秒衰减系数，
## direction 非 ZERO 时叠加方向性偏置。已存在更强抖动时不会被覆盖。
func shake(strength: float, fade: float, direction: Vector2 = Vector2.ZERO) -> void:
	if is_instance_valid(_rig):
		_rig.shake(strength, fade, direction)

## 轻微抖动，使用 Rig 上配置的 shake_light 预设。
func shake_light() -> void:
	if is_instance_valid(_rig):
		_rig.shake(_rig.shake_light.x, _rig.shake_light.y)

## 中等抖动，使用 Rig 上配置的 shake_medium 预设。
func shake_medium() -> void:
	if is_instance_valid(_rig):
		_rig.shake(_rig.shake_medium.x, _rig.shake_medium.y)

## 强烈抖动，使用 Rig 上配置的 shake_heavy 预设。
func shake_heavy() -> void:
	if is_instance_valid(_rig):
		_rig.shake(_rig.shake_heavy.x, _rig.shake_heavy.y)


func _process(_delta: float) -> void:
	if not is_instance_valid(_rig):
		return

	if _follow_behavior._target == null or not is_instance_valid(_follow_behavior._target):
		if not _warned_no_follow and not Engine.is_editor_hint():
			push_warning("AuCameraDirector: 尚未设置跟随锚点，相机将停在原地。请确认 Player 调用了 set_follow()。")
			_warned_no_follow = true
		return
	_warned_no_follow = false

	for b in _behaviors:
		if b is AuLockAreaBehavior:
			var la := b as AuLockAreaBehavior
			la.look_offset = _look_offset

	_prune_invalid()

	_behaviors.sort_custom(_sort_by_priority)

	var ctx := {"target": Vector2.ZERO, "zoom": null}
	for b in _behaviors:
		b.resolve(ctx)

	_rig.set_target_pos(ctx["target"])
	_apply_zoom(ctx["zoom"])

	var top_area := _top_area()
	if top_area != _active_area:
		_active_area = top_area
		active_area_changed.emit(top_area)

func _apply_zoom(desired: Variant) -> void:
	if desired != null:
		if not _zoom_held or _active_zoom != desired:
			_rig.apply_zoom(desired, ZOOM_TWEEN_DURATION)
			_active_zoom = desired
			_zoom_held = true
	else:
		if _zoom_held:
			_rig.apply_zoom(_base_zoom, ZOOM_TWEEN_DURATION)
			_active_zoom = _base_zoom
			_zoom_held = false

func _sort_by_priority(a: AuCameraBehavior, b: AuCameraBehavior) -> bool:
	return a.priority < b.priority

func _prune_invalid() -> void:
	for i in range(_behaviors.size() - 1, -1, -1):
		var b = _behaviors[i]
		if b == _follow_behavior:
			continue
		if b is AuLockAreaBehavior and not is_instance_valid((b as AuLockAreaBehavior).area):
			_behaviors.remove_at(i)
		elif b is AuShotBehavior and not is_instance_valid((b as AuShotBehavior)._node):
			_behaviors.remove_at(i)

func _top_area() -> AuCameraLockArea:
	var found: AuCameraLockArea = null
	for b in _behaviors:
		if b is AuLockAreaBehavior and is_instance_valid((b as AuLockAreaBehavior).area):
			found = (b as AuLockAreaBehavior).area
	return found
