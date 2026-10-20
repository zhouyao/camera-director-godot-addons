# Camera Director

决策 / 执行 / 行为三层分离的 2D 相机系统。跟随、锁定区域、过场接管、缩放、边界、注视、抖动全部经由单点入口 `AuCameraDirector` 转发。
新增一种镜头 = 新增一个 `AuCameraBehavior` 子类，核心循环无需改动。

## 结构

```
addons/camera_director/
├── plugin.cfg / plugin.gd           # 插件注册（仅提供自定义类型，不含编辑器 UI）
├── AuCameraDirector.gd              # 决策层：全局单例（Autoload），唯一对外入口
├── AuCameraRig.gd                   # 执行层：持有 Camera2D，负责平滑 / 死区 / 边界 / 缩放 / 抖动
├── AuCameraLockArea.gd              # 锁定区域触发器（Area2D）
└── behaviors/
	├── camera_behavior.gd           # AuCameraBehavior 基类（RefCounted）
	├── follow_behavior.gd           # priority = 0    跟随
	├── lock_area_behavior.gd        # priority = 10   锁定区域
	└── shot_behavior.gd             # priority = 100  过场接管
```

**数据流**：`AuCameraDirector._process()` → 按 `priority` 升序排序所有行为 → 依次 `resolve(ctx)` 修改共享上下文 `ctx = {"target": Vector2, "zoom": Vector2|null}` → 把结果交给 `AuCameraRig` 执行。
优先级高的行为后执行，因此**可以覆盖低优先级写入的值**（锁定区域盖住跟随，过场盖住锁定区域）。

## 安装

1. 项目设置 → 插件，启用 **Camera Director**。
2. 项目设置 → 全局 → Autoload，添加：
   - 节点名：`AuCameraDirector`
   - 路径：`res://addons/camera_director/AuCameraDirector.gd`

> 单例名必须是 `AuCameraDirector`：`AuCameraRig` 与 `AuCameraLockArea` 内部均直接按这个名字引用。

## 场景搭建

### 1. 相机 Rig

在关卡场景中放一个 `Node2D`，挂上 `AuCameraRig` 脚本（必须有一个名为 `Camera2D` 的子节点，缺失时会自动创建）。
`_ready()` 里会自动 `AuCameraDirector.set_rig(self)`，并对齐导出参数到 `Camera2D`。

| 分组 | 导出参数 | 说明 |
| --- | --- | --- |
| — | `base_offset` | Camera2D 静态偏移，抖动结束后会复位到它 |
| — | `zoom` | 初始缩放（同时作为 `_base_zoom`，退出锁定/过场时回落的目标） |
| Camera2D | `position_smoothing_enabled` / `position_smoothing_speed` | 平滑开关与速度 |
| Camera2D | `limit_left/top/right/bottom` | 边界，默认 ±10000000 |
| Dead Zone | `dead_zone` | 死区半尺寸，目标超出该范围才推动相机；`= ZERO` 表示硬跟随 |
| Shake | `shake_cutoff` | 抖动强度低于此值即结束（默认 0.05） |
| Shake | `shake_light/medium/heavy` | 三档预设 `Vector2(strength, fade)` |

### 2. 设置跟随锚点

由被跟随者自己上报，这样角色死亡重建后能自动重新挂上：

```gdscript
func _ready() -> void:
	AuCameraDirector.set_follow(camera_marker)   # 传一个 Node2D，通常是角色身上的 Marker2D
```

未设置跟随目标时相机会停在原地，控制台只警告一次。

### 3. 锁定区域

放一个 `Area2D`，挂 `AuCameraLockArea` 脚本：

| 导出参数 | 说明 |
| --- | --- |
| `horizontal_lock_marker` | 非空则把相机 X 锁到该 Marker2D 的全局 X |
| `vertical_lock_marker` | 非空则把相机 Y 锁到该 Marker2D 的全局 Y |
| `can_look_up` / `can_look_down` | 是否允许该区域内用注视偏移推动相机 |
| `area_size` | 碰撞矩形尺寸（默认 600×600） |
| `centered` | 碰撞矩形是否以节点原点为中心 |
| `detect_layer` | 检测角色进出所用的物理层（默认 `16`，即第 5 层 “Areas and Zones”），会同步写入 `Area2D.collision_layer` |

玩家进入 / 离开自动 `register_area` / `unregister_area`，无需手写信号连接。

> **碰撞层**：请通过 `detect_layer` 配置，不要直接改内置的 `collision_layer`——`_ready()` 会用 `detect_layer` 覆盖它。角色的 `collision_mask` 必须包含该层，否则进出不会被检测到。

## API（全部通过 `AuCameraDirector` 单例调用）

### 跟随与状态

| 方法 | 说明 |
| --- | --- |
| `set_follow(node: Node2D)` | 设置跟随锚点 |
| `set_rig(rig: AuCameraRig)` | 绑定执行层（通常由 Rig 的 `_ready()` 自动调用） |
| `clear()` | 清空除跟随外的所有行为、注视、缩放与激活区域（换关卡时调用） |

### 锁定区域

| 方法 | 说明 |
| --- | --- |
| `register_area(area)` / `unregister_area(area)` | 手动注册 / 注销锁定区域（一般由 Area 自动调用） |

### 过场接管

| 方法 | 说明 |
| --- | --- |
| `push_override(node, zoom = Vector2.ZERO)` | 相机移到 `node` 位置；`zoom` 非 ZERO 时同时改缩放 |
| `pop_override(node = null)` | 结束最近一个（或指定节点的）接管，缩放回落 `_base_zoom` |
| `is_overridden() -> bool` | 当前是否处于接管中 |

### 自定义行为

| 方法 | 说明 |
| --- | --- |
| `push_behavior(behavior)` / `pop_behavior(behavior)` | 压入 / 弹出任意 `AuCameraBehavior`（跟随行为不可弹出） |

### 注视

| 方法 | 说明 |
| --- | --- |
| `look_up()` / `look_down()` / `clear_look()` | 在允许的区域上偏移相机 Y，幅度 `LOOK_MAGNITUDE = 100`（负=向上） |

### 缩放与边界

| 方法 | 说明 |
| --- | --- |
| `tween_zoom(z, duration = 0.4)` | 直接缓动缩放，并把 `_base_zoom` 设为 `z` |
| `set_limits(l, t, r, b)` | 设置相机边界 |
| `snap()` | 立即对齐到目标并重置平滑（切场景/传送后消除拖尾） |

### 抖动

| 方法 | 说明 |
| --- | --- |
| `shake(strength, fade, direction = Vector2.ZERO)` | 自定义抖动；`direction` 非 ZERO 时带方向性偏置 |
| `shake_light()` / `shake_medium()` / `shake_heavy()` | 使用 Rig 上配置的三档预设 |

## 信号

| 信号 | 触发时机 |
| --- | --- |
| `follow_changed(node)` | 跟随锚点变更 |
| `active_area_changed(area)` | 生效的锁定区域变化（可为 `null`） |
| `override_started(node)` / `override_ended(node)` | 过场接管开始 / 结束 |
| `look_changed(offset)` | 注视偏移变化 |

## 用法示例

```gdscript
# 过场：镜头切到 Boss 并拉近
AuCameraDirector.push_override($Boss, Vector2(1.5, 1.5))
await get_tree().create_timer(2.0).timeout
AuCameraDirector.pop_override($Boss)

# 受击反馈
AuCameraDirector.shake_medium()

# 关卡切换后重置并立刻对位
AuCameraDirector.clear()
AuCameraDirector.set_limits(0, 0, 3200, 1800)
AuCameraDirector.snap()

# 按住方向上/下键时（Timer 驱动）
AuCameraDirector.look_up()
AuCameraDirector.clear_look()
```

## 扩展新镜头类型

继承 `AuCameraBehavior`，设定 `priority` 并覆写 `resolve(ctx)`：

```gdscript
class_name AuShakeZoomBehavior
extends AuCameraBehavior

func _init() -> void:
	priority = 50          # 10(锁定) < 50 < 100(过场)

func resolve(ctx: Dictionary) -> void:
	ctx["target"] += Vector2(0.0, -20.0)   # 可读取并改写低优先级写入的值
	ctx["zoom"] = Vector2(1.2, 1.2)        # 赋 null 或留空表示不改缩放
```

使用：`AuCameraDirector.push_behavior(AuShakeZoomBehavior.new())`。
行为对象失效（区域/节点被释放）时会在每帧自动清理。

## 注意事项

- `AuCameraDirector` 必须是 Autoload 且节点名固定，否则 Rig 与 LockArea 引用不到。
- 一个场景内应只有一个 `AuCameraRig`；新 Rig 的 `_ready()` 会接管并重置关卡状态。
- `AuCameraRig` 用 `zoom` 属性的 setter 驱动 `Camera2D`，不要直接改 `Camera2D.zoom`，否则缓动与回落会不同步。
- 抖动通过修改 `camera.offset` 实现，结束后复位到 `base_offset`；若手动改过 offset 会被覆盖。
- 换关卡务必调用 `AuCameraDirector.clear()`，否则上一关的锁定区域 / 过场行为会残留。
