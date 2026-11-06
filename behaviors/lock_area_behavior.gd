class_name AuLockAreaBehavior
extends AuCameraBehavior


var area: AuCameraLockArea
var look_offset: float

func _init(a: AuCameraLockArea, look: float) -> void:
	area = a
	look_offset = look
	priority = a.camera_priority

func resolve(ctx: Dictionary) -> void:
	if not is_instance_valid(area):
		return
	var pos: Vector2 = ctx.get("target", Vector2.ZERO)
	if is_instance_valid(area.horizontal_lock_marker):
		var cx := area.horizontal_lock_marker.global_position.x
		var rx := maxf(0.0, area.horizontal_range)
		pos.x = clampf(pos.x, cx - rx, cx + rx)
	if is_instance_valid(area.vertical_lock_marker):
		var cy := area.vertical_lock_marker.global_position.y
		var ry := maxf(0.0, area.vertical_range)
		pos.y = clampf(pos.y, cy - ry, cy + ry)
	if look_offset < 0.0 and area.can_look_up:
		pos.y += look_offset
	elif look_offset > 0.0 and area.can_look_down:
		pos.y += look_offset
	ctx["target"] = pos
