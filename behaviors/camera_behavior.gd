## 相机行为基类。继承它并覆写 resolve() 即可扩展新的镜头类型，
## 通过 AuCameraDirector.push_behavior() 挂载。
class_name AuCameraBehavior
extends RefCounted


## 优先级，数值越大越晚执行，可覆盖低优先级行为写入的结果。
## 参考值：跟随 0、锁定区域 10、过场接管 100。
var priority: int = 0

## 每帧被调用，用于读写共享上下文。
## ctx["target"] 为相机目标位置（Vector2）；ctx["zoom"] 为期望缩放（Vector2 或 null 表示不改）。
func resolve(ctx: Dictionary) -> void:
	pass
