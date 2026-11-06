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

## 入场硬切窗口（_process 帧数）：窗口内锁区注册就立刻重切，覆盖 Area2D 晚注册的情况。
const ENTRY_SNAP_FRAMES := 30


var _rig: AuCameraRig = null

var _behaviors: Array[AuCameraBehavior] = []
var _follow_behavior := AuFollowBehavior.new()

var _look_offset := 0.0
var _look_target := 0.0
var _active_area: AuCameraLockArea = null
var _warned_no_follow := false
var _entry_snap_frames := 0

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
	# 换关时玩家会被暂时摘出场景树，但锚点对象仍然合法：留着它，_process 会继续
	# 把相机写到"旧房间坐标"，等玩家落到新入口再硬切，中间那段位移就容易露出残留滑动。
	_follow_behavior._target = null
	# 换关期间没有跟随目标是正常状态，别刷"尚未设置跟随锚点"的警告。
	_warned_no_follow = true
	# 换关即开启入场窗口：锁区由 body_entered 异步注册，窗口内注册会自动硬切。
	# 项目侧只需照常 clear() + teleport_to()，不用再补任何 snap 时机。
	_entry_snap_frames = ENTRY_SNAP_FRAMES

func _reset_level_state() -> void:
	for i in range(_behaviors.size() - 1, -1, -1):
		if _behaviors[i] != _follow_behavior:
			_behaviors.remove_at(i)
	_look_offset = 0.0
	_look_target = 0.0
	_active_area = null
	_zoom_held = false
	_active_zoom = _base_zoom
	_entry_snap_frames = 0
	# 换关 / 重绑 Rig 时收回上一关的边界覆盖，否则会把旧关卡的放宽 limits 带过来。
	if is_instance_valid(_rig):
		_rig.clear_center_override()


func register_area(area: AuCameraLockArea) -> void:
	if area == null:
		return
	for b in _behaviors:
		if b is AuLockAreaBehavior and (b as AuLockAreaBehavior).area == area:
			return
	_behaviors.append(AuLockAreaBehavior.new(area, _look_offset))
	# 入场窗口内注册：立刻按最新目标硬切，否则 Camera2D 平滑会把镜头从入口高度慢慢拉过去。
	# snap() 经 teleport_to() 刷新窗口，所以同帧连续注册多个锁区会各自重切，
	# 最终落在最后一个锁区的目标上；窗口过期后正常进出锁区仍走平滑。
	if _entry_snap_frames > 0:
		snap()

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

## 刷新入场窗口（由 AuCameraRig.teleport_to() 自动调用，项目侧不用管）。
## 瞬移是"入场事务"的天然起点：窗口按 _process 帧递减，暂停期间不消耗，
## 因此冷启动黑场里加载再久、解锁后锁区才注册，也仍在窗口内会被自动硬切。
func begin_entry_snap() -> void:
	_entry_snap_frames = ENTRY_SNAP_FRAMES


## 把相机硬切到"当前行为链"解析出的目标（跟随锚点 + 锁定区 + 分镜）。
## 换关 / 读档后调用：只对准跟随锚点会让 Camera2D 平滑把镜头从入口高度拉到锁定高度。
func snap() -> void:
	if not is_instance_valid(_rig):
		return
	if not is_instance_valid(_follow_behavior._target):
		_rig.snap_to_target()
		return
	_prune_invalid()
	for b in _behaviors:
		if b is AuLockAreaBehavior:
			(b as AuLockAreaBehavior).look_offset = _look_offset
	# 必须在 teleport_to() 之前：入场锁区若开了 override_bounds，旧 limit 会先把镜头夹回去。
	_update_bounds_override()
	var ctx := _resolve_context()
	var target: Vector2 = ctx["target"]
	_rig.teleport_to(target)


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
	# 入场窗口只在 _process 里消耗：暂停期间（冷启动黑场）不递减，
	# 解锁后锁区才注册也仍在窗口内。
	if _entry_snap_frames > 0:
		_entry_snap_frames -= 1

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

	var ctx := _resolve_context()
	_update_bounds_override()
	_rig.set_target_pos(ctx["target"])
	_apply_zoom(ctx["zoom"])

	var top_area := _top_area()
	if top_area != _active_area:
		_active_area = top_area
		active_area_changed.emit(top_area)

## 让优先级最高的锁定区决定能否突破关卡硬边界。
## Camera2D 的 limit_* 是最终位置的硬钳制，行为优先级再高也改不了它：
## 锁区目标一旦落在 limit 之外，镜头就会被拉回来，看起来像"锁定没生效"。
func _update_bounds_override() -> void:
	if not is_instance_valid(_rig):
		return
	var area := _top_area()
	if area == null or not area.override_bounds:
		_rig.clear_center_override()
		return

	# reach = 相机中心需要能到达的世界矩形；axes 标记哪根轴可以突破。
	var reach := Rect2()
	var axes := Vector2i.ZERO
	if is_instance_valid(area.horizontal_lock_marker):
		var rx := maxf(0.0, area.horizontal_range)
		reach.size.x = rx * 2.0
		reach.position.x = area.horizontal_lock_marker.global_position.x - rx
		axes.x = 1
	if is_instance_valid(area.vertical_lock_marker):
		var ry := maxf(0.0, area.vertical_range)
		# 抬头 / 低头偏移也是本区域加上去的，边界要留够 LOOK_MAGNITUDE，否则会被夹回去。
		var look := LOOK_MAGNITUDE if (area.can_look_up or area.can_look_down) else 0.0
		reach.size.y = (ry + look) * 2.0
		reach.position.y = area.vertical_lock_marker.global_position.y - ry - look
		axes.y = 1
	if axes == Vector2i.ZERO:
		_rig.clear_center_override()
		return
	_rig.set_center_override(reach, axes)

## 按当前行为链同步解析相机目标与缩放；抽出来给 snap() 复用，不依赖 _process 的帧序。
func _resolve_context() -> Dictionary:
	_behaviors.sort_custom(_sort_by_priority)
	var ctx := {"target": Vector2.ZERO, "zoom": null}
	for b in _behaviors:
		b.resolve(ctx)
	return ctx

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
	# 取 camera_priority 最大的那个；同优先级时后注册者胜出（与行为链"后执行覆盖"一致）。
	var found: AuCameraLockArea = null
	var best := -2147483648
	for b in _behaviors:
		if b is AuLockAreaBehavior:
			var a: AuCameraLockArea = (b as AuLockAreaBehavior).area
			if is_instance_valid(a) and a.camera_priority >= best:
				best = a.camera_priority
				found = a
	return found
