extends Node

## 跟随锚点变化时发出（调用 set_follow() 后）。参数 node：新的跟随目标，一般是角色身上的锚点 Marker2D。
signal follow_changed(node: Node2D)
## 当前生效的锁定区域变化时发出（进出 AuCameraLockArea，或区域优先级发生切换）。
## 参数 area：新的区域；null 表示回到自由跟随。
signal active_area_changed(area: AuCameraLockArea)
## 开始镜头接管（分镜）时发出（调用 push_override()）。参数 node：被对准的节点。
signal override_started(node: Node2D)
## 镜头接管结束时发出（调用 pop_override()，或目标节点失效被清理）。参数 node：刚才被对准的节点。
signal override_ended(node: Node2D)
## 抬头 / 低头的偏移目标变化时发出。参数 offset：垂直偏移量，负值抬头、正值低头、0 为复位。
## 注意发出的是目标值，实际偏移由 _update_look() 按 LOOK_TWEEN_DURATION 渐变逼近。
signal look_changed(offset: float)

const LOOK_MAGNITUDE := 100.0

const LOOK_TWEEN_DURATION := 0.25

const ZOOM_TWEEN_DURATION := 0.4


var _rig: AuCameraRig = null

var _behaviors: Array[AuCameraBehavior] = []
var _follow_behavior := AuFollowBehavior.new()

var _look_offset := 0.0
var _look_target := 0.0
var _active_area: AuCameraLockArea = null
var _warned_no_follow := false

var _base_zoom: Vector2 = Vector2.ONE
var _active_zoom: Vector2 = Vector2.ONE
var _zoom_held := false


func _init() -> void:
	_behaviors.append(_follow_behavior)


func set_rig(rig: AuCameraRig) -> void:
	if _rig == rig:
		return
	_rig = rig
	_base_zoom = rig.zoom
	_reset_level_state()

func set_follow(node: Node2D) -> void:
	_follow_behavior._target = node
	_warned_no_follow = false
	follow_changed.emit(node)

func clear() -> void:
	_reset_level_state()

func _reset_level_state() -> void:
	for i in range(_behaviors.size() - 1, -1, -1):
		if _behaviors[i] != _follow_behavior:
			_behaviors.remove_at(i)
	_look_offset = 0.0
	_look_target = 0.0
	_active_area = null
	_zoom_held = false
	_active_zoom = _base_zoom


func register_area(area: AuCameraLockArea) -> void:
	if area == null:
		return
	for b in _behaviors:
		if b is AuLockAreaBehavior and (b as AuLockAreaBehavior).area == area:
			return
	_behaviors.append(AuLockAreaBehavior.new(area, _look_offset))

func unregister_area(area: AuCameraLockArea) -> void:
	for i in range(_behaviors.size() - 1, -1, -1):
		if _behaviors[i] is AuLockAreaBehavior and (_behaviors[i] as AuLockAreaBehavior).area == area:
			_behaviors.remove_at(i)


func push_override(node: Node2D, zoom := Vector2.ZERO) -> void:
	if node == null:
		return
	_behaviors.append(AuShotBehavior.new(node, zoom))
	override_started.emit(node)

func pop_override(node: Node2D = null) -> void:
	for i in range(_behaviors.size() - 1, -1, -1):
		if _behaviors[i] is AuShotBehavior and (node == null or (_behaviors[i] as AuShotBehavior)._node == node):
			var popped: Node2D = (_behaviors[i] as AuShotBehavior)._node
			_behaviors.remove_at(i)
			override_ended.emit(popped)
			return


func push_behavior(behavior: AuCameraBehavior) -> void:
	if behavior == null or _behaviors.has(behavior):
		return
	_behaviors.append(behavior)

func pop_behavior(behavior: AuCameraBehavior) -> void:
	if behavior != null and behavior != _follow_behavior:
		_behaviors.erase(behavior)

func is_overridden() -> bool:
	for b in _behaviors:
		if b is AuShotBehavior:
			return true
	return false


func look_up() -> void:
	_set_look(-LOOK_MAGNITUDE)

func look_down() -> void:
	_set_look(LOOK_MAGNITUDE)

func clear_look() -> void:
	_set_look(0.0)

func _set_look(value: float) -> void:
	if _look_target == value:
		return
	_look_target = value
	look_changed.emit(value)

func _update_look(delta: float) -> void:
	if _look_offset == _look_target:
		return
	var step := LOOK_MAGNITUDE / maxf(LOOK_TWEEN_DURATION, 0.0001) * delta
	_look_offset = move_toward(_look_offset, _look_target, step)


func tween_zoom(z: Vector2, duration := ZOOM_TWEEN_DURATION) -> void:
	if is_instance_valid(_rig):
		_rig.apply_zoom(z, duration)
	_base_zoom = z
	_active_zoom = z
	_zoom_held = false

func set_limits(l: int, t: int, r: int, b: int) -> void:
	if is_instance_valid(_rig):
		_rig.set_limits(l, t, r, b)

func snap() -> void:
	if is_instance_valid(_rig):
		_rig.snap_to_target()


func shake(strength: float, fade: float, direction: Vector2 = Vector2.ZERO) -> void:
	if is_instance_valid(_rig):
		_rig.shake(strength, fade, direction)

func shake_light() -> void:
	if is_instance_valid(_rig):
		_rig.shake(_rig.shake_light.x, _rig.shake_light.y)

func shake_medium() -> void:
	if is_instance_valid(_rig):
		_rig.shake(_rig.shake_medium.x, _rig.shake_medium.y)

func shake_heavy() -> void:
	if is_instance_valid(_rig):
		_rig.shake(_rig.shake_heavy.x, _rig.shake_heavy.y)


func _process(delta: float) -> void:
	if not is_instance_valid(_rig):
		return

	if _follow_behavior._target == null or not is_instance_valid(_follow_behavior._target):
		if not _warned_no_follow and not Engine.is_editor_hint():
			push_warning("AuCameraDirector: 尚未设置跟随锚点，相机将停在原地。请确认 Player 调用了 set_follow()。")
			_warned_no_follow = true
		return
	_warned_no_follow = false

	_update_look(delta)

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
