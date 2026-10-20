class_name AuFollowBehavior
extends AuCameraBehavior


var _target: Node2D

func _init(target: Node2D = null) -> void:
	_target = target
	priority = 0

func resolve(ctx: Dictionary) -> void:
	if is_instance_valid(_target):
		ctx["target"] = _target.global_position
