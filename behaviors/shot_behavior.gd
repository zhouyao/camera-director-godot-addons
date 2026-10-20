class_name AuShotBehavior
extends AuCameraBehavior


var _node: Node2D
var _zoom: Vector2

func _init(node: Node2D, zoom := Vector2.ZERO) -> void:
	_node = node
	_zoom = zoom
	priority = 100

func resolve(ctx: Dictionary) -> void:
	if is_instance_valid(_node):
		ctx["target"] = _node.global_position
	if _zoom != Vector2.ZERO:
		ctx["zoom"] = _zoom
