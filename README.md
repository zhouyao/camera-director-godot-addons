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
	├── lock_area_behavior.gd        # priority = 锁区 camera_priority（默认 10）  锁定区域
	└── shot_behavior.gd             # priority = 100  过场接管
```

**数据流**：`AuCameraDirector._process()` → 按 `priority` 升序排序所有行为 → 依次 `resolve(ctx)` 修改共享上下文 `ctx = {"target": Vector2, "zoom": Vector2|null}` → 把结果交给 `AuCameraRig` 执行。
优先级高的行为后执行，因此**可以覆盖低优先级写入的值**（锁定区域盖住跟随，过场盖住锁定区域）。

> **优先级只管 `ctx.target`**：`Camera2D.limit_*` 是行为链之后由引擎做的硬钳制，任何 `priority` 都改不了它。需要让锁区突破关卡边界时，用锁区的 `override_bounds`（见「3. 锁定区域」）。

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

放一个 `Area2D`，挂 `AuCameraLockArea` 脚本。Inspector 里按五组排列：

**① 区域 Shape & Detection**

| 导出参数 | 说明 |
| --- | --- |
| `area_size` | 触发区域宽高（默认 600×600），写入 `CollisionShape2D` 的矩形尺寸 |
| `centered` | 是否以节点原点为中心；`false` 时矩形从 `(0,0)` 向右下展开 |
| `detect_layer` | 本区域所在的物理层，写入 `Area2D.collision_layer`（默认 16 = 第 5 层）。**不**决定谁能触发本区域 |

**② 锁定 Lock**（子组：参考点 Markers / 活动范围 Ranges）

| 导出参数 | 说明 |
| --- | --- |
| `horizontal_lock_marker` | 非空则锁定相机 X 到该 Marker2D 的 X |
| `vertical_lock_marker` | 非空则锁定相机 Y 到该 Marker2D 的 Y；留空即只锁水平 |
| `horizontal_range` | 以 `horizontal_lock_marker` 的 X 为中心的 ± 可移动距离（像素）；`0` 表示钉死（默认） |
| `vertical_range` | 以 `vertical_lock_marker` 的 Y 为中心的 ± 可移动距离（像素）；`0` 表示钉死（默认） |

**③ 优先级 & 边界 Priority & Bounds**

| 导出参数 | 说明 |
| --- | --- |
| `camera_priority` | 多个锁区同时生效时的执行顺序（默认 `10`；跟随 = 0、过场接管 = 100）。数值大的后写入、覆盖前面的结果；也决定谁有权启用边界覆盖 |
| `override_bounds` | 本区域生效时允许锁定目标突破 `Camera2D.limit_*`（即关卡 `CameraBounds` 的硬边界）；离开后自动恢复。**只放宽真正配了 Marker 的那根轴** |

> **为什么需要 `override_bounds`**：`CameraBoundsRect` 换算出的 `limit_*` 是引擎对最终位置的**硬钳制**，发生在行为链之后。锁区的目标一旦落在 `limit` 之外，镜头会被直接拉回来，看起来就像"锁定没生效"。行为优先级只作用于 `ctx.target`，管不到这一步，所以必须显式放宽边界。
>
> 名字不能叫 `priority`：`Area2D` 自带同名属性（物理区域覆盖顺序），`@export` 会报「重复成员」。

**④ 镜头行为 Look**

| 导出参数 | 说明 |
| --- | --- |
| `can_look_up` / `can_look_down` | 是否允许该区域内用注视偏移推动相机 |

**⑤ 编辑器预览 Editor Preview**

| 导出参数 | 说明 |
| --- | --- |
| `show_corners_in_editor` | 在 2D 编辑器里画四角实心方框与矩形轮廓（默认开，运行时不画） |
| `fill_alpha` | **矩形内部填充不透明度，默认 `0` = 完全透明**；调大才铺淡色块。作用于 Godot 自带的 `CollisionShape2D.debug_color`（编辑器绘制专用），所以直接决定了那层绿色半透明填充是否出现 |
| `corner_color` | 四角方框与矩形轮廓的颜色，Inspector 里可配 |
| `corner_size` | 方框边长（世界单位，缩小时自动放大） |

预览时矩形**只描边、不填充**，不遮挡底下的关卡内容；引擎的 debug 形状在 alpha=0 时可能连轮廓都不画，脚本会补一条描边，保证矩形仍可辨。以上全部仅编辑器生效。

玩家进入 / 离开自动 `register_area` / `unregister_area`，无需手写信号连接。

> **碰撞层**：`detect_layer` 写入的是本 Area2D 的 `collision_layer`（供其它查询按层筛选），`_ready()` 会覆盖它，不要直接改内置的 `collision_layer`。
> 能否检测到角色取决于**本 Area2D 的 `collision_mask`** 是否包含角色所在层 —— 玩家默认在第 1 层、Area2D 默认 `mask = 1`，所以开箱即用；要换检测对象请改 `collision_mask`，而不是 `detect_layer`。

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
| `look_up()` / `look_down()` / `clear_look()` | 在**允许的区域**上偏移相机 Y，幅度 `LOOK_MAGNITUDE = 100`（负=向上） |

生效条件：角色必须处在 `AuCameraLockArea` 内，且该区域的 `can_look_up` / `can_look_down` 为 true；开放区域（不在任何锁定区域内）抬头不推动相机。

偏移在 `LOOK_TWEEN_DURATION = 0.25s` 内平滑推进到目标值，松手（`clear_look()`）同样平滑复位。

> **"按住多久才抬头推相机"属于玩法节奏，不放在本插件**：由调用方决定何时调用。玩家角色上是 `look_up` / `look_down` 状态节点的 `camera_look_delay` 导出参数（配合状态机自带的 `elapsed` 计时），达到时长才调用 `look_up()` / `look_down()`，退出时 `clear_look()`。

### 缩放与边界

| 方法 | 说明 |
| --- | --- |
| `tween_zoom(z, duration = 0.4)` | 直接缓动缩放，并把 `_base_zoom` 设为 `z` |
| `set_limits(l, t, r, b)` | 设置**关卡硬边界（基底）**。这是锁区 `override_bounds` 撤销后的回落值，不是"最后写入者赢" |
| `snap()` | 立即对齐到目标并重置平滑（切场景/传送后消除拖尾）；入场锁区由插件自动调用，见「注意事项」 |

> 边界分两层：`set_limits()` 记下**基底**，`AuCameraRig.set_center_override()` 是锁区临时叠加的**覆盖**。最终写给 `Camera2D` 的是两者按轴并集的结果，由 `_refresh_limits()` 合成，值没变就不重复写。

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
| `look_changed(offset)` | 注视偏移目标值变化（`look_up` = -100，`look_down` = +100，复位 = 0） |

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

# 抬头状态里按住够时长后推动相机；退出时复位
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
- **边界覆盖撤销不会立刻收缩**：出了 `override_bounds` 区域后，`clear_center_override()` 只是标了"待收缩"，要等**画面实际中心**（`Camera2D.get_screen_center_position()`）在**被放宽过的那根轴**上回到基底范围内，才真正收回 `limit_*`。判据刻意不用"相机目标位置"——开了位置平滑时目标已经回框、画面还滞留在上方，此时收 limit 会把画面硬钳到边界，表现为跳下平台瞬间镜头一顿。`LIMIT_SHRINK_TOLERANCE`（10px）就是这个判据的容差，也等于收缩可能造成的最大可见位移；它要盖住"目标合法地略微越界"的情形（地面玩家中心 425 vs 基底范围下沿 432）。没被放宽的轴不参与判断。发生瞬移（`teleport_to()` / 换关）时强制立刻收回。调边界时别以为改完就马上生效。
- **`set_limits()` 的语义是"基底"**：如果覆盖生效期间调用它，新值会成为新的基底，覆盖仍叠加在上面。
- **入场硬切由插件内建**：`clear()` 开启入场窗口，`AuCameraRig.teleport_to()`（换关 / 读档 / 传送的瞬移）刷新它；窗口内 `AuCameraLockArea` 由 `body_entered` 注册时，插件自动按「跟随 + 锁区」解析出的最终目标 `snap()`，避免 `Camera2D.position_smoothing` 把镜头从入口高度缓慢拉到锁定高度。窗口按 `_process` 帧递减（暂停期间不消耗，故冷启动黑场解锁后才注册也覆盖），过期后正常进出锁区恢复平滑。项目侧只需照常 `clear()` 与瞬移，不用手动补 `snap()`、也不用距离阈值，因此 dash / 转身 / 分镜推镜等连续运动不受影响。
