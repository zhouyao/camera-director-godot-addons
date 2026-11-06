extends Node2D
class_name AuCameraRig


## 缩放发生变化时发出（包含 tween 期间的逐帧变化）。
## 项目侧可借此同步任何依赖 zoom 的逻辑（例如相机边界的换算）。
## 插件本身不引用项目 autoload，保持可复用。
signal zoom_changed(new_zoom: Vector2)


## 边界收缩判定容差（像素）：判据是「画面实际中心」，所以这个值直接等于
## 收回 limit 时可能造成的最大可见位移。取值要盖住"目标合法地略微越界"的情况：
## level_2 地面玩家中心 y=425，而基底范围下沿是 432，差 7px。
const LIMIT_SHRINK_TOLERANCE := 10.0


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

## 关卡硬边界（CameraBounds 换算后写入）：锁定区的边界覆盖撤销时回落到这里。
var _base_limits := Rect2i(-10000000, -10000000, 20000000, 20000000)
## 锁定区的边界覆盖请求：相机中心需要能到达的世界矩形（range = 0 时退化成一点）。
var _center_override: Variant = null
## 允许突破的轴：x / y 分量为 1 才放宽该轴。
var _override_axes := Vector2i.ZERO
## 上一次真正写进 Camera2D 的 limits，避免每帧重复赋值。
var _applied_limits := Rect2i()
## 覆盖撤销后等"相机目标回到基准范围"再收缩，见 _refresh_limits()。
var _shrink_pending := false
## 撤销时被放宽的轴：只在这几根轴上等目标回来（未放宽的轴可能合法地常年越界）。
var _shrink_axes := Vector2i.ZERO

var _shake_strength: float = 0.0
var _shake_fade: float = 0.0
var _shake_direction := Vector2.ZERO
var _rng := RandomNumberGenerator.new()
## 上一次 zoom 缓动：进出缩放区域很快时会有多条 tween 同时写 zoom，必须先杀掉旧的。
var _zoom_tween: Tween = null
## 硬切（teleport_to）后还剩几个物理帧要维持"关平滑"，见 teleport_to()。
var _smoothing_off_frames := 0


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
	# 导出的四条 limit 就是本关的初始基准边界。
	_base_limits = Rect2i(limit_left, limit_top, limit_right - limit_left, limit_bottom - limit_top)
	_applied_limits = _base_limits
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
	if is_instance_valid(_zoom_tween):
		_zoom_tween.kill()
		_zoom_tween = null
	if duration <= 0.0:
		zoom = z
	else:
		_zoom_tween = create_tween()
		_zoom_tween.tween_property(self, "zoom", z, duration)

## 设置关卡硬边界（基底）。锁定区开了 override_bounds 时，会在其锁定的轴上临时放宽；
## 覆盖撤销后回落到这里记下的基底，而不是最后写入的值。
func set_limits(l: int, t: int, r: int, b: int) -> void:
	_base_limits = Rect2i(l, t, r - l, b - t)
	_refresh_limits()


## 覆盖关卡硬边界：reach = 相机中心需要能到达的世界矩形（锁定点 ± range），
## axes.x / axes.y 为 1 的轴才放宽。传同样的值重复调用是空操作。
func set_center_override(reach: Rect2, axes: Vector2i) -> void:
	if _center_override is Rect2 and (_center_override as Rect2).is_equal_approx(reach) and _override_axes == axes:
		return
	_center_override = reach
	_override_axes = axes
	_shrink_pending = false
	_shrink_axes = Vector2i.ZERO
	_refresh_limits()

## 撤销覆盖。这里不立刻收缩 limit：此刻相机目标可能还在基准范围之外，
## 一收就会被 Camera2D 硬钳回去、画面瞬移；等目标回到范围内再收。
func clear_center_override() -> void:
	if _center_override == null and _override_axes == Vector2i.ZERO:
		return
	_center_override = null
	_shrink_axes = _override_axes
	_override_axes = Vector2i.ZERO
	_shrink_pending = true
	_refresh_limits()

func _viewport_half() -> Vector2:
	var vp := Vector2(1920, 1080)
	if is_inside_tree():
		var v := get_viewport()
		if v != null:
			vp = v.get_visible_rect().size
	var z := Vector2(maxf(absf(zoom.x), 0.001), maxf(absf(zoom.y), 0.001))
	return vp / (2.0 * z)

## 把「基底 limits」和「锁区覆盖」合成一份最终 limits 写给 Camera2D，只在结果变化时写。
func _refresh_limits() -> void:
	if camera == null:
		return
	var l := _base_limits.position.x
	var t := _base_limits.position.y
	var r := _base_limits.end.x
	var b := _base_limits.end.y

	if _center_override is Rect2 and _override_axes != Vector2i.ZERO:
		var reach := _center_override as Rect2
		var half := _viewport_half()
		if _override_axes.x == 1:
			l = mini(l, int(reach.position.x - half.x))
			r = maxi(r, int(reach.end.x + half.x))
		if _override_axes.y == 1:
			t = mini(t, int(reach.position.y - half.y))
			b = maxi(b, int(reach.end.y + half.y))
	elif _shrink_pending:
		if _screen_center_needs_wide_limits(l, t, r, b, _shrink_axes):
			return
		_shrink_pending = false
		_shrink_axes = Vector2i.ZERO

	var limits := Rect2i(l, t, r - l, b - t)
	if limits == _applied_limits:
		return
	_applied_limits = limits
	camera.limit_left = limits.position.x
	camera.limit_top = limits.position.y
	camera.limit_right = limits.end.x
	camera.limit_bottom = limits.end.y

## 画面实际中心是否还在基准边界之外。只检查 axes 指定的轴 ——
## 没被放宽过的轴本来就允许越界（例如玩家站在关卡左边界之外），检查它会永远等不到收缩。
##
## 为什么不用 `_anchor`（相机目标）：开了位置平滑时，目标每帧立刻等于玩家位置，
## 而画面要滞后好几帧才跟上。目标已经回到框内、画面却还留在上方时收 limit，
## Camera2D 会把当前画面直接钳到边界上 —— 表现为跳下平台瞬间镜头猛地一顿。
## get_screen_center_position() 已含 base_offset 与当前 limit 的钳制结果，
## 减掉 offset 即还原成"可以拿去和 limit 比"的相机中心。
func _screen_center_needs_wide_limits(l: int, t: int, r: int, b: int, axes: Vector2i) -> bool:
	if camera == null:
		return false
	var center := camera.get_screen_center_position() - base_offset
	var half := _viewport_half()
	var tol := LIMIT_SHRINK_TOLERANCE
	if axes.x == 1 and (center.x < l + half.x - tol or center.x > r - half.x + tol):
		return true
	if axes.y == 1 and (center.y < t + half.y - tol or center.y > b - half.y + tol):
		return true
	return false

## 硬切位移：换关 / 读档 / 传送专用（一般在黑场里调用）。
##
## 为什么不能只靠 Camera2D.reset_smoothing()：
##   · 它内部只是 `_update_scroll()` 后把 smoothed_camera_pos 对齐到 camera_pos，
##     而 camera_pos 只在 Camera2D 自己的物理 tick 里（get_camera_transform）刷新。
##     从 _process / await physics_frame 里调用，对齐到的是"上一物理帧"的旧值，
##     平滑等于没清掉，相机仍会从旧位置滑过来。
##   · 本项目开了 physics_interpolation，还必须 reset_physics_interpolation()，
##     否则渲染层会在 prev/curr 两个物理变换之间插值，瞬移必然拖影。
## 做法：本帧直接关平滑摆位，撑过两个物理帧（保证 camera_pos / smoothed_camera_pos
## 都跑过新位置）再恢复 —— 期间画面不晃，黑场里也看不见。
func teleport_to(pos: Vector2) -> void:
	if camera == null:
		return
	_has_anchor = true
	_anchor = pos
	# 硬切没有画面连续性要保护：待收缩的边界立刻收回，同时兜住换关时"旧坐标永远等不到回归"的情况。
	if _shrink_pending:
		_shrink_pending = false
		_refresh_limits()
	camera.position_smoothing_enabled = false
	_smoothing_off_frames = 2
	camera.global_position = pos
	camera.offset = base_offset
	camera.reset_physics_interpolation()  # 顺序关键：先清插值历史
	camera.force_update_scroll()          # 再立刻重算 canvas transform
	# 瞬移即刷新入场窗口：之后若锁区才由 body_entered 注册，由插件自动硬切到最终目标。
	AuCameraDirector.begin_entry_snap()

func snap_to_target() -> void:
	if not _has_anchor:
		return
	teleport_to(_anchor)


## 抖动用物理帧驱动：物理插值模式下 Camera2D 只在物理 tick 采样 offset，
## 放在 _process 里改 offset 实际要等到下个物理帧才生效，会出现阶梯感。
func _physics_process(delta: float) -> void:
	# 覆盖撤销后的待收缩状态：相机目标回到基准范围就立刻收回 limit。
	if _shrink_pending:
		_refresh_limits()

	# 硬切后的"关平滑"窗口：必须放在抖动早退之前，否则不抖时永远恢复不了。
	if _smoothing_off_frames > 0:
		_smoothing_off_frames -= 1
		if _smoothing_off_frames == 0:
			camera.position_smoothing_enabled = position_smoothing_enabled
			camera.reset_smoothing()

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
