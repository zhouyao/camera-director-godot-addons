class_name AuLockAreaBehavior
extends AuCameraBehavior


var area: AuCameraLockArea
var look_offset: float

func _init(a: AuCameraLockArea, look: float) -> void:
	area = a
	look_offset = look
	priority = 10

func resolve(ctx: Dictionary) -> void:
	if not is_instance_valid(area):
		return
	var pos: Vector2 = ctx.get("target", Vector2.ZERO)
	if is_instance_valid(area.horizontal_lock_marker):
		pos.x = area.horizontal_lock_marker.global_position.x
	if is_instance_valid(area.vertical_lock_marker):
		pos.y = area.vertical_lock_marker.global_position.y
	if look_offset < 0.0 and area.can_look_up:
		pos.y += look_offset
	elif look_offset > 0.0 and area.can_look_down:
		pos.y += look_offset
	ctx["target"] = pos
