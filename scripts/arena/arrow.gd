class_name Arrow
extends Node3D
## 箭矢（短弓手 / 长弓手的投射物，形态见 `kind`）
##
## 命中判定用"上一帧位置 -> 本帧位置"的线段查询，避免高速穿透。
## 能被剑盾兵正面盾牌挡下：docs/bible/03_rules.md#6-盾牌挡箭判定
## 依据：docs/bible/02_entities.md、04_physics.md#3-冲量力相关

var shooter: Unit3D = null
var team: int = 0
var damage: float = 0.0
## 溅射伤害（2026-09-19 投石车）：**直击目标之外**的半径内敌人吃这个值；0 = 没有区分，全体吃 `damage`
var splash_damage: float = 0.0
var dir: Vector3 = Vector3.FORWARD
var speed: float = GameConfig.PROJECTILE_SPEED
var active: bool = true
## 2026-09-18（R2）：投射物**形态** —— `shortbow_arrow`（短弓手，2026-09-25 起是抛物线 + 预判）/
## `stone`（投石车，抛物线 + 范围伤害）/ `bolt`（弩车，直线极快）/
## `longbow_arrow`（长弓手，2026-09-25 新增：抛物线 + 落点预判的快箭）/ `arrow`（历史兜底形态）。
var kind: String = "arrow"
## 落地范围伤害半径（0 = 单体命中，见 `04_physics.md#5.3`）
var aoe_radius: float = 0.0
## 命中后施加的**击退数值**（0 = 不击退；冲量仍由 `_add_knockback()` 按目标重量缩小）
var knockback: float = 0.0
## 这次击退在"动量传递"时附带的伤害（只有弩车 > 0，见 `04_physics.md#5.1`）
var knockback_damage: float = 0.0
## 下坠加速度（石弹 > 0 = 抛物线；箭矢与弩箭 = 0 = 直线）
var gravity: float = 0.0
## 是否**无视盾牌**（2026-09-19：弩车的大型弹射物专属；剑盾兵的正面盾挡不下它）
var ignores_shield: bool = false
## **穿透额度**（2026-09-25 火枪兵新增）：还能穿过几个敌人。火枪兵 = **1** ⇒ 最多命中 **2 个**。
## 命中时扣一格并把被打中的单位记进 `_pierced`（**永久**排除出射线），扣到 0 才 `_expire()`。
## ⚠️ 与 `ignores_shield` 是**两条独立**的语义：前者管"打得到几个"，后者管"盾牌挡不挡得住"。
var pierce: int = 0
## **最大飞行距离 m**（0 = 不限，只受 `ARROW_LIFETIME_MS` 总寿命约束）。
## ⚠️ 2026-09-27 第十二轮新增，唯一用处是 Spartan 投矛的"射程 16 m"（用户口径："第一下攻击变为
## 射程为 16 m 的投矛"）—— 其余投射物走的仍是"寿命 + 打中/落地"那两条老闸门，这一格恒为 0 ⇒ 逐位不变。
var max_flight: float = 0.0
## 短弓「火矢」：这一发带着火。只改外观，点燃仍由射手的科技在命中时结算。
var ignited: bool = false
## 扇子兵「拦截」还要打中几下才会被打掉。0 = 这种投射物不吃拦截。
var intercept_left: int = 0
## 石弹落地是否眩晕。普通石弹为真；「散射」的小石子为假。
var apply_stun: bool = false
## 溅射是否也吃击退。普通石弹为真；弩车「突击模式」只击退直击的那个。
var splash_knockback: bool = true
## 长弓「爆炸箭」：落点周围这么远的敌人再打一半伤害。0 = 没有。
## 直击仍会被盾挡住，挡的那个人改吃这一圈。弹反当时不炸，弹回去射中了人才炸。
var explosive_radius: float = 0.0
var explosive_ratio: float = 0.5
## 投石车「火球」：落地后在溅射半径里留下燃烧地面。
var fireball: bool = false
var fire_damage: float = 0.0
## 「沉默弹」：这一发打中的单位沉默这么久。0 = 不沉默。
var silence_ms: int = 0
var silence_move_mult: float = 0.7
## 石弹视觉缩放。「散射」的小石子小于 1。
var stone_scale: float = 1.0
## 已经派出去、还没挥到的扇子兵人数。可用次数 = intercept_left − intercept_reserved。
var intercept_reserved: int = 0
var _born_pos: Vector3 = Vector3.ZERO
## 已经**穿过去**的单位（每帧的射线查询都把它们排除掉）——
## 不排除的话，下一帧那条线段会从同一个身体里重新起步、把同一发子弹算成两次伤害。
var _pierced: Array[RID] = []
## 这一发**是不是被偏折过**（2026-09-25 武士大师的「高级偏折」）。被偏折过的**不再被偏折**
## —— 否则两只武士大师面对面会把同一发子弹来回弹成乒乓球。
var deflected: bool = false
## **被偏折的那一点**（世界坐标，2026-09-25 第二轮）：反弹后"还能飞多远"从**这里**起算。
## ⚠️ 不是从它自己的发射点起算 —— 用户口径是"反弹的投射物最多飞行 6m"，管的是**弹回来之后**那一段。
## 未偏折过时这一格没有意义（`deflected == false` 时下面的闸门不跑）。
var _deflect_from: Vector3 = Vector3.ZERO
var _deflect_range: float = 0.0

var _born_ms: int = 0
var _vel: Vector3 = Vector3.ZERO
## 出膛时记下的**场地**引用（2026-09-25 第七条）：箭被盾牌挡下后会**改挂父节点**（挂到盾牌下），
## 那时 `get_parent()` 拿到的是盾牌、不是场地 ⇒ `_expire()` 里的 `remove_arrow()` 必须靠这个缓存，
## 否则场地的 `arrows` 数组会留下失效引用（不报错，但会慢慢堆积）。
var _arena: Node = null
## 箭尖相对**节点原点**的前伸量 m（本地 −Z 的最前端）。`_ready()` 里从网格包围盒量出来：
## 五种形态的杆长各不相同（短弓 0.62 / 长弓 1.05 / 弩箭 …），写死一个数必然对不上。
var _tip_offset: float = 0.0
## 箭尖再往盾面里扎多少 m（纯表现）：只影响"看起来插进去多深"，不参与任何判定。
const SHIELD_STICK_INSET := 0.06
## 火枪弹尾（纯表现）。沿飞行路径连成一条线；淡出从子弹停下那一刻起算。
const BULLET_SMOKE_SPACING_M := 0.8
const BULLET_SMOKE_FADE_MS := 2200
const BULLET_SMOKE_ALPHA := 0.55
const BULLET_SMOKE_HALF_M := 0.045
var _smoke_gap: float = 0.0
var _smoke_mat: StandardMaterial3D = null
var _smoke_trail: MeshInstance3D = null
var _smoke_points: PackedVector3Array = PackedVector3Array()
var _smoke_fade_from_ms: int = 0
var _smoke_fading: bool = false

## 落地扬尘的**共享网格资源**（2026-09-25 修卡顿）：在脚本加载时构造一次，
## 全部扬尘实例共用同一份 `Mesh`（只有材质是逐实例的，因为透明度要各自淡出）。
## ⚠️ 这两个常量是"预建"方案的一半：另一半是 `Arena._build_impact_dust_pool()` 预建实例池。
## 两者合起来保证**比赛中途不再新建任何网格 / 材质 / 节点**。
## ⚠️ **`TorusMesh` 的默认朝向是"躺在 XZ 平面"（平躺）** —— 引擎内实测 AABB = 2.000(Y 0.280)…
## 所以沙环**不需要任何旋转**；给它加 `rotation.x = PI/2` 会把它**转竖**（2026-09-25 的 bug 就是这个）。
## 同理 `SphereMesh` 的默认朝向无关紧要（球体对称）。
static var IMPACT_DUST_RING_MESH: TorusMesh = _make_dust_ring_mesh()
static var IMPACT_DUST_PUFF_MESH: SphereMesh = _make_dust_puff_mesh()

static func _make_dust_ring_mesh() -> TorusMesh:
	var torus := TorusMesh.new()
	torus.inner_radius = 0.72
	torus.outer_radius = 1.0
	torus.rings = 24
	torus.ring_segments = 8
	return torus

static func _make_dust_puff_mesh() -> SphereMesh:
	var sphere := SphereMesh.new()
	sphere.radius = 0.34
	sphere.height = 0.68
	sphere.radial_segments = 8
	sphere.rings = 5
	return sphere

func _ready() -> void:
	add_to_group("arrows")
	_born_ms = Time.get_ticks_msec()
	_born_pos = global_position      ## 射程闸门（`max_flight`）的起算点
	## ⚠️ 必须先播下初速：`_physics_process` 的第一帧会先减重力，
	## 若此时 `_vel` 还是零向量，石弹会只剩"竖直向下"的分量、当场落在自己脚下（修于 2026-09-18）。
	_vel = dir * speed
	intercept_left = GameConfig.fan_intercept_hits(kind)
	_build_mesh()
	## ⚠️ 必须在**改挂父节点之前**记下来 —— 被盾牌挡下的箭会被挂到盾牌下（见 `_stick_to_anchor()`）。
	_arena = get_parent()
	_measure_tip_offset()

## 量出"箭尖离节点原点多远"（本地 −Z 的最前端）。五个 `_build_*` 都是"原点在杆中、箭头在 −Z"，
## 所以只要把子树里所有网格的 AABB 合并起来取 `−box.position.z` 即可，**不必逐形态写死数字**。
func _measure_tip_offset() -> void:
	var box := AABB()
	var found := false
	for c in get_children():
		var mi := c as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var a: AABB = mi.transform * mi.mesh.get_aabb()
		box = a if not found else box.merge(a)
		found = true
	if found:
		_tip_offset = maxf(-box.position.z, 0.0)

## 出生点改到真正的出手位置。`_ready` 在 `add_child` 里就会记下当时的坐标，
## 那时候节点还在场地原点；投矛用这段距离当射程，不改的话人一离原点标枪当帧就消失。
func mark_flight_origin() -> void:
	_born_pos = global_position
	_vel = dir * speed

func _build_mesh() -> void:
	match kind:
		"stone":
			_build_stone()
		"bolt":
			_build_bolt()
		"musket_bullet":
			_build_bullet()
		"longbow_arrow":
			_build_longbow_arrow()
		"shortbow_arrow":
			_build_shortbow_arrow()
		"spear":
			_build_spear()
		_:
			_build_arrow()

## 短弓手的箭矢（**2026-09-25 重建模**，用户："短弓手箭矢重建模（应与长弓手区分）"）。
## 与长弓那支的区分靠**三层同时拉开**（单改一样在 16 m 外看不出来）：
##   · **长度**：短 = 0.62 m，长弓 = 1.05 m（长弓长 70%）；
##   · **粗度**：短 = 半径 0.026，长弓 = 0.016（短弓粗 60% ⇒ 短距离上更"看得见一根杆"）；
##   · **箭羽**：短弓是**两片 V 形斜羽**（`Fletch_a` / `Fletch_b` 各绕 Z 斜一点），
##     长弓是一整块方形羽 —— 侧对相机时一个读作"箭头"，一个读作"方块"。
## 观感意图：短弓 = **粗短沉稳的近弓**，长弓 = **细长的远弓**。
func _build_shortbow_arrow() -> void:
	var shaft := MeshInstance3D.new()
	shaft.name = "ShortShaft"
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 0.026
	cylinder.bottom_radius = 0.026
	cylinder.height = 0.62
	cylinder.radial_segments = 6
	shaft.mesh = cylinder
	shaft.rotation = Vector3(PI * 0.5, 0.0, 0.0)
	var shaft_mat := StandardMaterial3D.new()
	shaft_mat.albedo_color = Color(0.46, 0.31, 0.17)
	shaft_mat.roughness = 0.72
	shaft.material_override = shaft_mat
	add_child(shaft)

	var tip := MeshInstance3D.new()
	tip.name = "ShortTip"
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.062
	cone.height = 0.24
	cone.radial_segments = 6
	tip.mesh = cone
	tip.rotation = Vector3(-PI * 0.5, 0.0, 0.0)
	tip.position = Vector3(0.0, 0.0, -0.40)
	if ignited:
		_add_fire_tip(Vector3(0.0, 0.0, -0.52))
	var tip_mat := StandardMaterial3D.new()
	tip_mat.albedo_color = Color(0.80, 0.82, 0.86)
	tip_mat.roughness = 0.32
	tip.material_override = tip_mat
	add_child(tip)

	## 两片 V 形斜羽（长弓是单块方形羽 ⇒ 这是两者最容易分辨的一处）
	for spec in [["Fletch_a", 0.42], ["Fletch_b", -0.42]]:
		var feather := MeshInstance3D.new()
		feather.name = String(spec[0])
		var box := BoxMesh.new()
		box.size = Vector3(0.055, 0.13, 0.17)
		feather.mesh = box
		feather.position = Vector3(0.0, 0.0, 0.30)
		feather.rotation = Vector3(float(spec[1]), 0.0, 0.0)
		var feather_mat := StandardMaterial3D.new()
		feather_mat.albedo_color = Color(0.82, 0.79, 0.72)
		feather_mat.roughness = 0.85
		feather.material_override = feather_mat
		add_child(feather)

## 投出去的矛：木杆 + 金属矛头。比箭粗、比箭长，飞在半空能认出来。
func _build_spear() -> void:
	var shaft := MeshInstance3D.new()
	shaft.name = "SpearShaft"
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 0.045
	cylinder.bottom_radius = 0.045
	cylinder.height = 1.55
	cylinder.radial_segments = 8
	shaft.mesh = cylinder
	shaft.rotation = Vector3(PI * 0.5, 0.0, 0.0)
	var shaft_mat := StandardMaterial3D.new()
	shaft_mat.albedo_color = Color(0.42, 0.28, 0.14)
	shaft_mat.roughness = 0.7
	shaft.material_override = shaft_mat
	add_child(shaft)
	var head := MeshInstance3D.new()
	head.name = "SpearHead"
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.09
	cone.height = 0.38
	cone.radial_segments = 6
	head.mesh = cone
	head.rotation = Vector3(-PI * 0.5, 0.0, 0.0)
	head.position = Vector3(0.0, 0.0, -0.92)
	var head_mat := StandardMaterial3D.new()
	head_mat.albedo_color = Color(0.78, 0.80, 0.84)
	head_mat.roughness = 0.28
	head_mat.emission_enabled = true
	head_mat.emission = Color(0.45, 0.48, 0.52)
	head_mat.emission_energy_multiplier = 0.4
	head.material_override = head_mat
	add_child(head)

## 火矢的火头。挂在箭尖前面，加色混合，不参与碰撞。
func _add_fire_tip(at: Vector3) -> void:
	var flame := MeshInstance3D.new()
	flame.name = "FireTip"
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.09
	cone.height = 0.28
	cone.radial_segments = 6
	flame.mesh = cone
	flame.rotation = Vector3(PI * 0.5, 0.0, 0.0)
	flame.position = at
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.42, 0.08, 0.9)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.35, 0.05)
	mat.emission_energy_multiplier = 2.4
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flame.material_override = mat
	add_child(flame)

## 短弓手的箭矢：细杆 + 锥形箭头（**历史形态，2026-09-25 起不再使用**；
## 保留是因为 `kind` 的兜底分支仍指向它，且旧存档 / 旧截图对照时有用）
func _build_arrow() -> void:
	var shaft := MeshInstance3D.new()
	shaft.name = "Shaft"
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 0.018
	cylinder.bottom_radius = 0.018
	cylinder.height = 0.72
	cylinder.radial_segments = 6
	shaft.mesh = cylinder
	shaft.rotation = Vector3(PI * 0.5, 0.0, 0.0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.50, 0.34, 0.18)
	mat.roughness = 0.7
	shaft.material_override = mat
	add_child(shaft)

	var tip := MeshInstance3D.new()
	tip.name = "Tip"
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.045
	cone.height = 0.16
	cone.radial_segments = 6
	tip.mesh = cone
	tip.rotation = Vector3(-PI * 0.5, 0.0, 0.0)
	tip.position = Vector3(0.0, 0.0, -0.44)
	var tip_mat := StandardMaterial3D.new()
	tip_mat.albedo_color = Color(0.75, 0.78, 0.82)
	tip_mat.roughness = 0.35
	tip.material_override = tip_mat
	add_child(tip)

## 长弓手的箭矢（2026-09-25 新增）：比短弓手的箭**更长更细**——52 m/s 的抛物线快箭，
## 屏幕上基本只看得见一条掠过的细线 + 一点箭头反光，所以靠"长度"而不是"粗度"换取可读性
##（与弩车那条又粗又直的弩箭正好相反：弩箭要读作"重"，长弓箭要读作"快"）。
func _build_longbow_arrow() -> void:
	var shaft := MeshInstance3D.new()
	shaft.name = "LongShaft"
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 0.016
	cylinder.bottom_radius = 0.016
	cylinder.height = 1.05
	cylinder.radial_segments = 6
	shaft.mesh = cylinder
	shaft.rotation = Vector3(PI * 0.5, 0.0, 0.0)
	var shaft_mat := StandardMaterial3D.new()
	shaft_mat.albedo_color = Color(0.56, 0.42, 0.24)
	shaft_mat.roughness = 0.6
	shaft.material_override = shaft_mat
	add_child(shaft)

	var tip := MeshInstance3D.new()
	tip.name = "LongTip"
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.05
	cone.height = 0.20
	cone.radial_segments = 6
	tip.mesh = cone
	tip.rotation = Vector3(-PI * 0.5, 0.0, 0.0)
	tip.position = Vector3(0.0, 0.0, -0.62)
	var tip_mat := StandardMaterial3D.new()
	tip_mat.albedo_color = Color(0.86, 0.88, 0.92)
	tip_mat.roughness = 0.25
	tip.material_override = tip_mat
	add_child(tip)

	## 箭羽：让"这是一支箭"在掠过的两帧里也读得出来（抛物线的顶点附近速度最慢，那几帧看得最清）
	var fletching := MeshInstance3D.new()
	fletching.name = "LongFletching"
	var feather := BoxMesh.new()
	feather.size = Vector3(0.10, 0.10, 0.20)
	fletching.mesh = feather
	fletching.position = Vector3(0.0, 0.0, 0.44)
	var feather_mat := StandardMaterial3D.new()
	feather_mat.albedo_color = Color(0.88, 0.86, 0.80)
	feather_mat.roughness = 0.8
	fletching.material_override = feather_mat
	add_child(fletching)

## 投石车的石弹：一颗低饱和灰石块（体积明显，抛物线看得见）
func _build_stone() -> void:
	var rock := MeshInstance3D.new()
	rock.name = "Rock"
	var sphere := SphereMesh.new()
	sphere.radius = 0.26
	sphere.height = 0.52
	sphere.radial_segments = 8
	sphere.rings = 5
	rock.mesh = sphere
	var mat := StandardMaterial3D.new()
	if fireball:
		mat.albedo_color = Color(0.95, 0.42, 0.12)
		mat.emission_enabled = true
		mat.emission = Color(1.0, 0.45, 0.08)
		mat.emission_energy_multiplier = 1.8
		mat.roughness = 0.4
	else:
		mat.albedo_color = Color(0.46, 0.45, 0.43)
		mat.roughness = 0.95
	rock.material_override = mat
	rock.scale = Vector3.ONE * stone_scale
	add_child(rock)

## 火枪子弹（2026-09-25 火枪兵）：用户口径"**子弹为小型投射物**，速度是弩车子弹的两倍"。
## 观感意图：它比弩箭**小得多**（半径 0.07 对 0.11 的箭头）、是**一颗亮铅丸**，
## 靠"高速 + 自发光"在屏幕上被看见（360 m/s，60 Hz 下每帧 6 m ⇒ 多半只能看到一条亮痕）。
## ⚠️ 与弩箭的**辨识**靠两件事：**尺寸**（小一半）与**颜色**（暖白自发光 vs 冷灰金属）。
func _build_bullet() -> void:
	var ball := MeshInstance3D.new()
	ball.name = "BulletBall"
	var sphere := SphereMesh.new()
	sphere.radius = 0.07
	sphere.height = 0.14
	sphere.radial_segments = 8
	sphere.rings = 4
	ball.mesh = sphere
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.95, 0.92, 0.78)
	mat.roughness = 0.25
	## 自发光：高速小物件只有"自己发亮"才追得上眼睛（与弩箭的金属灰形成对比）
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.86, 0.45)
	mat.emission_energy_multiplier = 1.6
	ball.material_override = mat
	add_child(ball)

## 弩车的弩箭：粗短杆 + 大箭头（60 m/s，靠"又粗又直"在屏幕上被看见）
func _build_bolt() -> void:
	var shaft := MeshInstance3D.new()
	shaft.name = "BoltShaft"
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 0.05
	cylinder.bottom_radius = 0.05
	cylinder.height = 1.10
	cylinder.radial_segments = 6
	shaft.mesh = cylinder
	shaft.rotation = Vector3(PI * 0.5, 0.0, 0.0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.38, 0.30, 0.22)
	mat.roughness = 0.6
	shaft.material_override = mat
	add_child(shaft)

	var head := MeshInstance3D.new()
	head.name = "BoltHead"
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.11
	cone.height = 0.34
	cone.radial_segments = 6
	head.mesh = cone
	head.rotation = Vector3(-PI * 0.5, 0.0, 0.0)
	head.position = Vector3(0.0, 0.0, -0.68)
	var head_mat := StandardMaterial3D.new()
	head_mat.albedo_color = Color(0.78, 0.80, 0.84)
	head_mat.roughness = 0.3
	head.material_override = head_mat
	add_child(head)

func _physics_process(delta: float) -> void:
	if _smoke_fading:
		_fade_bullet_smoke()
		return
	if not active:
		return
	if Time.get_ticks_msec() - _born_ms > GameConfig.ARROW_LIFETIME_MS:
		_splash_explosive_at(global_position)
		_expire()
		return
	## ⚠️ **被高级偏折弹回来的投射物只再飞 `UNIT_MASTER_DEFLECT_RANGE`（6 m）**（2026-09-25 第二轮，
	## 用户："高级偏折反弹的投射物最多飞行6m"）。与上面那条"总寿命"是**两条独立闸门**：这一条只管
	## 反弹之后的那一段，从**偏折点**起算（`_deflect_from`，在 `"deflected"` 分支里记下）。
	## ⚠️ 每帧只查一次 ⇒ 最多多飞一帧的位移（360 m/s 的火枪子弹 ≈ 6 m/帧，那是这一条能接受的过冲；
	## 要更精确就得改成"线段求交"，而那会让"射程"变成一个需要解释的新概念）。
	var deflect_limit := _deflect_range if _deflect_range > 0.0 else GameConfig.UNIT_MASTER_DEFLECT_RANGE
	if deflected and global_position.distance_to(_deflect_from) >= deflect_limit:
		_expire()
		return
	## 射程上限（2026-09-27 第十二轮：Spartan 投矛的 16 m）。`max_flight <= 0` = 不限 ⇒ 其余投射物不跑这一支。
	if max_flight > 0.0 and global_position.distance_to(_born_pos) >= max_flight:
		_splash_explosive_at(global_position)
		_expire()
		return

	## 抛物线（石弹）：每帧给速度加下坠，飞行方向随之改变——`dir` 始终等于"当前飞行方向"，
	## 盾牌判定（`blocks_from(dir)`）与线段查询都用它。
	if gravity > 0.0:
		_vel.y -= gravity * delta
	if _vel.length_squared() < 0.0001:
		_vel = dir * speed
	dir = _vel.normalized()

	var from := global_position
	var to := from + _vel * delta
	try_instant_intercept(from, to)
	if not active:
		_lay_bullet_smoke(from, global_position)
		return
	## ---- 魔法盾（2026-09-26 肉鸽第五块）：**过不去那个圆** ----
	## ⚠️ 摆在 `_resolve_segment()` **之前**：那条管"打到谁"，这条管"能不能飞到那儿"。
	## 魔法盾**没有碰撞体**（用户口径"没有碰撞体积"）⇒ 物理射线永远查不到它，只能在这里做几何判定。
	var shield_hit := _magic_shield_crossing(from, to)
	if not shield_hit.is_empty():
		_block_at_shield(shield_hit)
		return
	var result := _resolve_segment(from, to)
	if String(result.get("kind", "none")) == "none":
		global_position = to
		_lay_bullet_smoke(from, to)
		return

	var point: Vector3 = result.get("point", to)
	match String(result["kind"]):
		"blocked":
			var blocker := result["unit"] as Unit3D
			## 直击被盾挡住。溅射仍在落点炸开，挡的那个人吃这一圈。弹反之后没射中人则不炸。
			_splash_explosive_at(point)
			blocker.on_shield_block()
			## **钉在盾牌上**（2026-09-25 第七条，用户："箭矢被盾牌格挡时，箭矢应停留在盾牌上而不是空中"）：
			## 有盾就**改挂到盾牌节点下**；没有盾（理论上走不到这里）退回"钉在世界坐标"。
			var anchor: Node3D = blocker.shield_anchor()
			if anchor != null:
				_stick_to_anchor(anchor, dir)
				Events.fx_request.emit("arrow_blocked", global_position)
			else:
				_stick(point)
				Events.fx_request.emit("arrow_blocked", point)
		"deflected":
			## **高级偏折的反弹**（2026-09-25 武士大师）：用户："箭矢以**大小相同、方向相反**的速度继续飞行，
			## 并将其视为**我方投射物**"。
			##   · 方向取反、速度不变（只改 `dir` 与 `_vel`，`speed` 一个字不动）；
			##   · **归属改成偏折者那一队**（`team`）⇒ 它接下来只打原来那一方的人（友军判定自动生效）；
			##   · `shooter` 也改成偏折者 ⇒ 击杀记在它头上、击退方向也从它起算；
			##   · 打上 `deflected` 标记 ⇒ **不再被偏折**（否则两只武士大师会把同一发子弹弹成乒乓球）。
			var deflector := result["unit"] as Unit3D
			team = deflector.team
			shooter = deflector
			deflected = true
			## 弹反当时不炸。爆炸留着，等这一发再射中人才溅射。沉默弹仍在这里清掉。
			silence_ms = 0
			## 记下**偏折点**：反弹后只允许再飞 `UNIT_MASTER_DEFLECT_RANGE`（6 m），见 `_physics_process()`
			_deflect_from = point
			_deflect_range = deflector.deflect_flight_range()
			dir = -dir
			_vel = dir * speed
			## 从命中点**朝新方向**挪一点再起步：否则下一帧那条线段从偏折者体内开始，会立刻又判中它自己。
			global_position = point + dir * 0.2
			_lay_bullet_smoke(from, global_position)
			Events.fx_request.emit("arrow_blocked", point)   ## 借"格挡"那一支的表现（专属素材还没有）
		"hit":
			var victim := result["unit"] as Unit3D
			if victim != null and victim.try_sidestep():
				_pierced.append(victim.get_rid())
				global_position = point + dir * 0.05
				_lay_bullet_smoke(from, global_position)
			else:
				# shooter 可能已经在箭飞行途中阵亡并被 queue_free —— 那种情况下传 null，
				# 否则会把"已释放对象"传给 apply_hit 的 from 参数并触发类型错误。
				var source: Unit3D = shooter if (shooter != null and is_instance_valid(shooter)) else null
				if aoe_radius > 0.0:
					_explode(point, source, victim)
				else:
					victim.apply_hit(damage, source, _knock_of(dir), knockback_damage, false, false, false,
							silence_ms, silence_move_mult)
					_splash_explosive_at(point, victim, true)
					Events.fx_request.emit("arrow_hit", point)
					## 穿透（2026-09-25 火枪兵）：还有额度就**不收箭** —— 把挨了这一下的单位记进排除表、
					## 把弹体推到命中点前方一点点（免得下一帧从它体内重新起步），继续飞。
					if pierce > 0:
						pierce -= 1
						_pierced.append(victim.get_rid())
						global_position = point + dir * 0.05
						_lay_bullet_smoke(from, global_position)
					else:
						_lay_bullet_smoke(from, point)
						_expire()
		_:
			## 撞到地面/墙：范围武器**就地炸开**（这正是投石车的落点）。
			## 爆炸箭打空也在落点溅射，然后钉住。
			if aoe_radius > 0.0:
				var source2: Unit3D = shooter if (shooter != null and is_instance_valid(shooter)) else null
				_explode(point, source2)
			else:
				_splash_explosive_at(point)
				_lay_bullet_smoke(from, point)
				_stick(point)

## 是不是**小型投射物**（2026-09-25 武士大师的「高级偏折」用）：用户口径是"格挡箭矢、子弹等小型投射物"。
## 判据 = **不是大型弹射物**：本项目的"大型"是弩箭 `bolt`（`ignores_shield`、"无法被盾挡"）
## 与投石车石弹 `stone`（抛物线 + 范围伤害）。
## ⚠️ **不能拿 `ignores_shield` 当判据**：火枪子弹**也是** `ignores_shield`（它穿盾），
## 但用户明说"子弹为小型投射物" ⇒ 它必须能被偏折。所以这里按 `kind` 白名单判，一眼看清谁算小型。
func is_small_projectile() -> bool:
	return kind in ["arrow", "shortbow_arrow", "longbow_arrow", "musket_bullet"]

## 扇子兵还能不能再派一个人来打这一发。
func flight_velocity() -> Vector3:
	return _vel

var _intercept_frame_ms: int = -1

## 这一帧的飞行线段刚碰到扇子兵的 16 m 圈就结算拦截。够次数就在进圈的那一点消失。
## 同一帧只算一次：场地先算已经在飞的，刚射出的那一发在自己的物理帧里补算。
func try_instant_intercept(from: Vector3, to: Vector3) -> void:
	var now := Time.get_ticks_msec()
	if _intercept_frame_ms == now:
		return
	_intercept_frame_ms = now
	if not active or intercept_left <= 0:
		return
	var picks: Array = []
	for node in get_tree().get_nodes_in_group("units"):
		var fan := node as Unit3D
		if fan == null or not fan.alive or fan.team == team:
			continue
		if not fan.intercept_ready():
			continue
		var t := fan.intercept_segment_t(from, to)
		if t < 0.0:
			continue
		picks.append({"t": t, "fan": fan})
	if picks.is_empty():
		return
	picks.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["t"]) < float(b["t"]))
	var slots := intercept_left
	var entry_t := float(picks[0]["t"])
	for row in picks:
		if slots <= 0 or not active:
			break
		var fan := row["fan"] as Unit3D
		if fan == null or not fan.intercept_ready():
			continue
		slots -= 1
		fan.spend_intercept_swing(self, from.lerp(to, float(row["t"])))
	if not active:
		global_position = from.lerp(to, entry_t)

func intercept_open() -> bool:
	return active and intercept_left - intercept_reserved > 0

func reserve_intercept() -> bool:
	if not intercept_open():
		return false
	intercept_reserved += 1
	return true

func release_intercept() -> void:
	intercept_reserved = maxi(intercept_reserved - 1, 0)

## 这一下打中了。次数扣光就消失。
func confirm_intercept() -> bool:
	release_intercept()
	if not active or intercept_left <= 0:
		return false
	intercept_left -= 1
	if intercept_left <= 0:
		_splash_explosive_at(global_position)
		_expire()
		return true
	return false

## 击退冲量：方向 = 施加者 → 目标的水平方向（与近战同源），大小 = 每单位初速 × 击退数值
func _knock_of(_dir: Vector3) -> Vector3:
	if knockback <= 0.0 or shooter == null or not is_instance_valid(shooter):
		return Vector3.ZERO
	var push := dir
	push.y = 0.0
	if push.length_squared() < 0.0001:
		return Vector3.ZERO
	return push.normalized() * GameConfig.KNOCKBACK_SPEED * knockback

## 范围伤害（投石车落地）：对落点半径 `aoe_radius` 内的**所有敌人**各结算一次
## 「伤害 + 击退数值」。每个敌人各自走 `tap_knockback()` 闸门，与扇形攻击同一套规则。
## 2026-09-19 用户要求**直击与溅射分开**：`direct`（石弹直接撞到的那个单位）吃 `damage`（**140**），
## 半径内的**其他**人吃 `splash_damage`（**70**）；`direct` 为空（打在空地/墙上）时所有人都吃溅射值。
## ⚠️ 2026-09-19 稍后（用户："投石车直击伤害变为 160，溅射伤害为它的一半"）：两档由 140/70 改为 160/80。
## ⚠️ **2026-09-25 第五条（用户："投石车伤害变回 140，但是会对所有击中的敌人附加眩晕 1"）**：
## 两档改回 **140 / 70**，并给本循环里**每一个挨了伤害的敌人**附加 **眩晕 1**（`UNIT_STONE_STUN_MS`）。
func _explode(point: Vector3, source: Unit3D, direct: Unit3D = null) -> void:
	var arena := get_parent()
	if arena != null and arena.has_method("units_of_team"):
		for enemy in arena.units_of_team(1 - team):
			var other := enemy as Unit3D
			if other == null or not other.alive:
				continue
			## ⚠️ 2026-09-19：**潜地单位不在范围伤害的对象里**（不可锁定 + 无敌 ⇒ 连溅射都不给）
			if other.is_burrowed():
				continue
			if other.global_position.distance_to(point) > aoe_radius:
				continue
			var knock := Vector3.ZERO
			if knockback > 0.0 and (other == direct or splash_knockback):
				var push := other.global_position - point
				push.y = 0.0
				if push.length_squared() > 0.0001:
					knock = push.normalized() * GameConfig.KNOCKBACK_SPEED * knockback
			var amount: float = damage if (other == direct or splash_damage <= 0.0) else splash_damage
			other.apply_hit(amount, source, knock, knockback_damage, false, false, false,
					silence_ms, silence_move_mult)
			## **眩晕 1**（2026-09-25 第五条，用户："会对所有击中的敌人附加眩晕 1"）。
			## ⚠️ 加在**直击与溅射不分档**的位置 —— "所有击中的"就是这个循环里**每一个**挨了伤害的敌人，
			## 不是只有直击那一个（用户裁定）。打在空地上时半径内所有人吃溅射 ⇒ 也都被晕。
			## ⚠️ 伤害与眩晕是**两条独立通路**：伤害走 `apply_hit()`（可被无敌 / 潜地拦下），
			## 眩晕走 `apply_stun()`（自带 **boss 免疫**；⚠️ 它**不看**无敌 —— 无敌只挡伤害）。
			## 潜地单位在上一段就被 `continue` 跳过了，所以这里剩下的都是"站着挨了打"的，口径一致。
			## ⚠️ 连带事实：眩晕会走 `_interrupt_skill()` ⇒ 一块石头现在也能**打断骑士冲撞 / 狂战士跳跃 /
			## 火焰拳炎爆的蓄力**，以及**暂停轻骑兵（矛）的冲刺**（那是眩晕的固有语义，不是本行的副作用）。
			if apply_stun:
				other.apply_stun(GameConfig.UNIT_STONE_STUN_MS)
	## **落地扬尘**（2026-09-25 用户："投石车石头落地新增尘土特效"）：纯表现，几何见末尾的 `ImpactDust`。
	## ⚠️ **一律交给场地去播**（`Arena._show_impact_dust()`）：它维护一个**预建好的池**。
	## 本函数原来自己 `ImpactDust.new()` 现造 —— 那是"特效一出现就卡顿"的根因
	##（比赛中途新建网格 + 透明材质 ⇒ 首次渲染要编译着色器），见 `ImpactDust` 的类注释。
	## ⚠️ 也**不能**把扬尘挂在自己身上：本函数最后一句是 `_expire()`，
	## 而箭矢就是石弹自己 ⇒ 扬尘会跟着箭一起 `queue_free`、一帧都看不见。
	## 只有**石弹**会走到这里（它有 `aoe_radius`；弩箭 / 弓箭的命中在 `hit` 分支就返回了）。
	if fireball and fire_damage > 0.0 and arena != null and arena.has_method("place_fire"):
		arena.place_fire(point, aoe_radius, fire_damage, source)
	if arena != null and arena.has_method("show_impact_dust"):
		arena.show_impact_dust(point, aoe_radius)
	Events.fx_request.emit("arrow_hit", point)
	_expire()

## 爆炸箭在落点炸开。直击的那个人不算在这一圈里。被盾挡住时不传这个人，所以他吃这一圈。
## 弹反之后只有射中了人（on_hit）才炸；打空、再被盾挡住、飞到头都不炸。
## 必须在改挂父节点之前调用，父节点还是场地。
func _splash_explosive_at(point: Vector3, direct: Unit3D = null, on_hit: bool = false) -> void:
	if explosive_radius <= 0.0:
		return
	if deflected and not on_hit:
		return
	var source: Unit3D = shooter if (shooter != null and is_instance_valid(shooter)) else null
	_splash_explosive(point, source, direct)

func _splash_explosive(point: Vector3, source: Unit3D, direct: Unit3D) -> void:
	var arena := get_parent()
	if arena == null or not arena.has_method("units_of_team"):
		return
	var extra := damage * explosive_ratio
	if extra <= 0.0:
		return
	for enemy in arena.units_of_team(1 - team):
		var other := enemy as Unit3D
		if other == null or not other.alive or other == direct or other.is_burrowed():
			continue
		if other.global_position.distance_to(point) > explosive_radius:
			continue
		other.apply_hit(extra, source)

## 沿飞行线段逐段查询：友军与已阵亡单位直接跳过（不消耗、不阻挡），
## 只对**敌人**结算（盾牌优先判定）。这样前排挡住射界时箭会飞向更远的敌人，
## 而不是像早期版本那样一箭一箭全打在自家前排身上（bug 2b 的真因之一）。
## ⚠️ 顺序（2026-09-25）：**先问"要不要偏折"，再问"盾牌挡不挡"** —— 偏折是主动技能（武士大师），
## 盾牌是被动装备；同一个人身上不会同时有这两样（武士大师没盾），所以顺序只影响可读性。
func _resolve_segment(from: Vector3, to: Vector3) -> Dictionary:
	var space := get_world_3d().direct_space_state
	var exclude: Array[RID] = []
	if shooter != null and is_instance_valid(shooter):
		exclude.append(shooter.get_rid())
	## 已经穿过去的单位也一并排除（火枪兵的穿透：同一发不许打同一个人两次）
	exclude.append_array(_pierced)
	var from_pos := from
	for _i in 8:
		var query := PhysicsRayQueryParameters3D.create(from_pos, to)
		query.collision_mask = 1 | (1 << 1) | (1 << 2)
		query.collide_with_areas = false
		query.exclude = exclude
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			return {"kind": "none"}
		var collider = hit.get("collider")
		var point: Vector3 = hit.get("position", to)
		var unit := collider as Unit3D
		if unit != null:
			if not unit.alive or unit.team == team:
				exclude.append(unit.get_rid())
				from_pos = point + dir * 0.05
				continue
			## 高级偏折（2026-09-25 武士大师）：**先问这一发要不要被弹回去**。
			## 判据（小型投射物 + 没被偏折过 + 对方额度/冷却都允许）全在 `Unit3D.try_deflect()` 里，
			## 箭自己只负责"飞"；反弹动作在那个分支里做（`"deflected"`）。
			if not deflected and (is_small_projectile() or kind == "spear") and unit.try_deflect(self):
				return {"kind": "deflected", "unit": unit, "point": point}
			## 弩车的大型弹射物无视盾牌（2026-09-19）：直接判命中，不给 `blocks_from()` 机会
			## ⚠️ 2026-09-27 第十二轮：种类那一道闸门收进 `Unit3D.can_block_projectile()` ——
			## 普通盾的老口径（`ignores_shield` 穿盾）**逐字保留**，两种科技盾（高级格挡 / Spartan）在那边分流。
			## 投矛：普通盾与月牙盾都不挡；只有「高级格挡」挡得住（kind 传进去由那边分流）。
			if unit.can_block_projectile(is_small_projectile(), ignores_shield, kind) and unit.blocks_from(dir):
				return {"kind": "blocked", "unit": unit, "point": point}
			return {"kind": "hit", "unit": unit, "point": point}
		return {"kind": "world", "point": point}
	return {"kind": "none"}

## 线段 `from → to` 有没有**穿过某一件敌方魔法盾的圆边界**？穿过就返回 `{point, id}`（否则空字典）。
## ⚠️ 与剑盾兵那条「盾牌挡箭」（`blocks_from()` / `try_deflect()`）是**两套完全不同**的判定：
##   · 那一条看"来箭方向落不落在盾面扇形里"，且 `ignores_shield` 的弹（弩箭 / **火枪子弹**）能穿过去；
##   · 这一条只看"**有没有跨过那个圆**"，且**不看 `ignores_shield`** —— 用户明说魔法盾"火枪无法穿透"，
##     而火枪子弹正是 `ignores_shield = true` 的那一发（它同时仍是"小型投射物"、会被武士大师偏折）。
## ⚠️ **方向无关**：从外面打进来、从圆里打出去**都算跨过边界** —— 用户原话"若敌方远程在圆圈内发动攻击，
## 攻击也无法穿过魔法盾的边"。
## ⚠️ **只挡敌方的弹**：`team` 与箭相同的盾直接跳过（自己的盾不能把自家弓手废掉）。
func _magic_shield_crossing(from: Vector3, to: Vector3) -> Dictionary:
	var arena_node: Node = _arena if (_arena != null and is_instance_valid(_arena)) else get_parent()
	if arena_node == null:
		return {}
	var blockers = arena_node.get("arrow_blockers")     ## 非场地（理论上到不了）取回 null ⇒ 直接放行
	if blockers == null:
		return {}
	for raw in blockers:
		var blocker: Dictionary = raw
		var center: Vector3 = blocker["center"]
		var radius := float(blocker["radius"])
		var owner_team := int(blocker.get("team", -1))
		var owner = blocker.get("unit", null)
		if owner != null:
			var ward_unit := owner as Unit3D
			if ward_unit == null or not is_instance_valid(ward_unit) or not ward_unit.has_ward():
				continue
			center = ward_unit.global_position
			radius = ward_unit.ward_radius()
			owner_team = ward_unit.team
		if owner_team == team:
			continue
		var point = _segment_sphere_entry(from, to, center, radius)
		if point != null:
			return {"point": point, "id": int(blocker.get("id", -1))}
	return {}

## 解 `|from + t·(to − from) − center| = radius`（t ∈ [0, 1]）取**最早**那个交点；无解回 null。
## ⚠️ 用**线段求交**而不是"端点在内 / 在外"：火枪子弹 360 m/s、60 Hz 下每帧 6 m，端点判会漏掉擦边飞过的那一发。
func _segment_sphere_entry(from: Vector3, to: Vector3, center: Vector3, radius: float):
	var d := to - from
	var f := from - center
	var a := d.dot(d)
	if a < 0.000001:
		return null                                     ## 这一帧几乎没动：按"没穿过"处理
	var b := 2.0 * f.dot(d)
	var c := f.dot(f) - radius * radius
	var disc := b * b - 4.0 * a * c
	if disc < 0.0:
		return null
	var sq := sqrt(disc)
	var t_near := (-b - sq) / (2.0 * a)
	if t_near >= 0.0 and t_near <= 1.0:
		return from + d * t_near
	var t_far := (-b + sq) / (2.0 * a)
	if t_far >= 0.0 and t_far <= 1.0:
		return from + d * t_far
	return null

## 被魔法盾挡下：钉在**边界交点**上（与"箭被剑盾兵挡下"同一观感：留在盾上、1.2 s 后消失），
## 并把这一笔登记进场地（`Arena.arrow_blocks`）由玩法侧读走。
## ⚠️ **投射物不直接改玩法数据**：盾的血量归玩法侧所有，箭只报"我在这个点上被哪一件盾挡下了"。
func _block_at_shield(info: Dictionary) -> void:
	var point: Vector3 = info.get("point", global_position)
	_splash_explosive_at(point)
	_stick(point)
	Events.fx_request.emit("arrow_blocked", point)
	var arena_node: Node = _arena if (_arena != null and is_instance_valid(_arena)) else get_parent()
	if arena_node == null:
		return
	var blocks = arena_node.get("arrow_blocks")
	if blocks == null:
		return
	blocks.append({"id": int(info.get("id", -1)), "point": point, "damage": damage})

## 钉在**盾牌**上（2026-09-25 第七条）。与 `_stick()` 是**两套不同**的收尾：
##   · `_stick(point)`       —— 钉在**世界坐标**（地面 / 墙）：人走了它留在原地，那是对的；
##   · `_stick_to_anchor()`  —— **改挂到盾牌节点下**：人走它跟着、出手时盾牌让位也跟着。
## ⚠️ **为什么不能只把箭的原点摆到盾面**：五个 `_build_*` 的原点都在**杆中**、箭头在 −Z，
## 杆长 0.6~1.05 m ⇒ 直接摆原点会让箭有一大半穿到人身后。正解是让**箭尖**落到盾面：
##   `origin = 盾面点 − dir × (_tip_offset − SHIELD_STICK_INSET)`
## 于是杆身朝**来箭方向**支出来 —— 那才是"插在盾上"该有的样子。
## ⚠️ 朝向保留**飞行时的姿态**（`keep.basis`）：箭按来势扎进去，不跟着盾牌转正。
func _stick_to_anchor(anchor: Node3D, flight_dir: Vector3) -> void:
	active = false
	var keep := global_transform
	var old_parent := get_parent()
	if old_parent != null:
		old_parent.remove_child(self)
	anchor.add_child(self)
	var surface := anchor.global_position - flight_dir * SHIELD_STICK_INSET
	global_transform = Transform3D(keep.basis, surface - flight_dir * _tip_offset)
	_start_stick_timer()

func _stick(point: Vector3) -> void:
	active = false
	global_position = point
	# 钉在地上/墙上 1.2 秒后消失（⚠️ 盾牌走的是 `_stick_to_anchor()`，不是这里）
	_start_stick_timer()

## "钉住之后 1.2 s 消失"是两条钉法**共用**的寿命 —— 各写一遍必然漂移。
func _start_stick_timer() -> void:
	var timer := get_tree().create_timer(1.2)
	timer.timeout.connect(_expire)

func _expire() -> void:
	active = false
	if kind == "musket_bullet" and _smoke_trail != null and not _smoke_fading:
		_smoke_fading = true
		_smoke_fade_from_ms = Time.get_ticks_msec()
		_hide_bullet_body()
		return
	## ⚠️ 用**出膛时缓存**的场地引用，不用 `get_parent()` —— 钉在盾上的箭，父节点是盾牌。
	var arena: Node = _arena if (_arena != null and is_instance_valid(_arena)) else get_parent()
	if arena != null and arena.has_method("remove_arrow"):
		arena.remove_arrow(self)
	queue_free()

## 沿飞行路径接成一条白线。子弹每帧能飞数米，所以一段里要补几个点。
func _lay_bullet_smoke(from: Vector3, to: Vector3) -> void:
	if kind != "musket_bullet":
		return
	var span := to - from
	var dist := span.length()
	if dist < 0.001:
		return
	var step := span / dist
	var cursor := _smoke_gap
	if _smoke_points.is_empty():
		_smoke_points.append(from)
	while cursor < dist:
		_smoke_points.append(from + step * cursor)
		cursor += BULLET_SMOKE_SPACING_M
	_smoke_gap = cursor - dist
	_rebuild_smoke_trail()

func _ensure_smoke_trail() -> void:
	if _smoke_trail != null:
		return
	_smoke_mat = StandardMaterial3D.new()
	_smoke_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_smoke_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_smoke_mat.vertex_color_use_as_albedo = true
	_smoke_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_smoke_mat.albedo_color = Color(0.94, 0.95, 0.96, BULLET_SMOKE_ALPHA)
	_smoke_trail = MeshInstance3D.new()
	_smoke_trail.name = "BulletTrail"
	_smoke_trail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_smoke_trail.material_override = _smoke_mat
	_smoke_trail.top_level = true
	add_child(_smoke_trail)

func _rebuild_smoke_trail() -> void:
	if _smoke_points.size() < 2:
		return
	_ensure_smoke_trail()
	var verts := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	var count := _smoke_points.size()
	for i in count:
		var point := _smoke_points[i]
		var ahead := _smoke_points[mini(i + 1, count - 1)]
		var behind := _smoke_points[maxi(i - 1, 0)]
		var tangent := ahead - behind
		if tangent.length_squared() < 0.0001:
			tangent = Vector3(0.0, 0.0, -1.0)
		var side := tangent.normalized().cross(Vector3.UP)
		if side.length_squared() < 0.0001:
			side = Vector3.RIGHT
		side = side.normalized() * BULLET_SMOKE_HALF_M
		verts.append(point + side)
		verts.append(point - side)
		var tint := Color(0.94, 0.95, 0.96, BULLET_SMOKE_ALPHA)
		colors.append(tint)
		colors.append(tint)
	var steps := count - 1
	for i in steps:
		var base := i * 2
		indices.append(base)
		indices.append(base + 1)
		indices.append(base + 2)
		indices.append(base + 1)
		indices.append(base + 3)
		indices.append(base + 2)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_smoke_trail.mesh = mesh

func _hide_bullet_body() -> void:
	for child in get_children():
		if child == _smoke_trail:
			continue
		if child is Node3D:
			(child as Node3D).visible = false

func _fade_bullet_smoke() -> void:
	var t := clampf(float(Time.get_ticks_msec() - _smoke_fade_from_ms) / float(BULLET_SMOKE_FADE_MS), 0.0, 1.0)
	if _smoke_mat != null:
		var color := Color(0.94, 0.95, 0.96, BULLET_SMOKE_ALPHA * (1.0 - t))
		_smoke_mat.albedo_color = color
		_smoke_mat.emission_energy_multiplier = 0.35 * (1.0 - t)
	if t >= 1.0:
		_smoke_fading = false
		_smoke_trail = null
		_expire()

func _mcp_state() -> Dictionary:
	return {"team": team, "active": active, "damage": int(round(damage)),
		"kind": kind, "aoe": aoe_radius, "knockback": knockback}

## 投石车石弹**落地扬尘**（2026-09-25 用户："投石车石头落地新增尘土特效"）。
## 纯**表现**层，**不带任何碰撞体、不参与判定**（溅射伤害仍由 `Arrow._explode()` 结算）。
## 外形 = **贴地沙环 + 五团上浮的尘团**：
##   · 沙环用 `TorusMesh` **躺平**（绕 X 转 90°），从中心撑到 `UNIT_STONE_AOE_RADIUS`
##     ⇒ **观感边界 = 判定边界**（与炎爆火池 / 沙虫震地同一条规矩）；
##   · 尘团复用沙虫那套观感语言（低饱和沙色 + 自发光渐隐），但**更矮更散**（`DUST_RISE` = 0.95 m），
##     读起来是"砸起一片土"而不是"窜起一根柱"。
##
## ⚠️ **它是"预建 + 复用"的，不要改回"每次现造"**（2026-09-25 用户："投石车特效出现时会有卡顿"）：
## 原来的写法是每次落地 `ImpactDust.new()` → 现场 6 个 `MeshInstance3D` + 6 个
## `TRANSPARENCY_ALPHA` 材质 ⇒ 那是**比赛中途新建"网格 + 透明材质"组合**，
## 首次渲染要为它编译着色器 / 走一遍渲染管线初始化 ⇒ 那一帧就是肉眼可见的卡顿。
## 现在由 `Arena` 在 `_ready()` 里**预建一小池**（`_build_impact_dust_pool()`），
## 播放时只改 `visible` 与几个标量；三种外形变体（环半径 / 尘团大小与朝向）也是预建的
## ⇒ **运行期零资源分配**。
class ImpactDust:
	extends Node3D

	## 整段时长 ms：沙环扩散完 + 尘团浮起再淡掉（比沙虫震地的 420 ms 略长，石头更"沉"）
	const DUST_MS := 620
	## 尘团上升高度 m（沙虫震地是 1.35 的"炸起来"，这里刻意压低成"扬起来"）
	const DUST_RISE := 0.95
	const PUFF_COUNT := 5

	var _playing: bool = false
	var _born_ms: int = 0
	var _radius: float = 4.0
	var _ring: MeshInstance3D = null
	var _puffs: Array[MeshInstance3D] = []
	var _puff_dirs: Array[Vector2] = []
	var _mats: Array[StandardMaterial3D] = []
	## 各尘团**这一趟的起始大小**（由 `play()` 的变体决定）：`_process` 只在这个基数上收小，
	## 所以"变体差异"与"逐帧缩小"不会互相覆盖。
	var _base_scale: PackedFloat32Array = PackedFloat32Array()

	func _ready() -> void:
		visible = false
		## 沙环：**必须平躺**（`TorusMesh` 的**默认朝向就是躺在 XZ 平面**上 —— 引擎内实测
		## AABB = 2.000 × 0.280 × 2.000，Y 最薄 ⇒ 平躺）。
		## ⚠️ **2026-09-25 修 bug（用户："投石车的沙尘特效的圆圈方向错了，不应该是竖着的"）**：
		## 上一版这里多写了一句 `rotation = Vector3(PI * 0.5, 0, 0)`，把**本来就平躺**的环转成了**竖着的立环**
		##（实测变换后 AABB = 2.000 × 2.000 × 0.280，Z 最薄 ⇒ 立起来）。
		## 现在**不旋转**（保持默认平躺）。⚠️ 以后动它之前先在引擎里量一次 AABB，别照抄其它节点的 `PI/2`。
		_ring = MeshInstance3D.new()
		_ring.name = "DustRing"
		_ring.mesh = Arrow.IMPACT_DUST_RING_MESH
		_ring.position = Vector3(0.0, 0.06, 0.0)
		var ring_mat := _new_dust_material(0.44, 0.38, 0.29)
		_ring.material_override = ring_mat
		_mats.append(ring_mat)
		add_child(_ring)
		## 尘团：沿圆周均匀铺开、各自错相位（"此起彼伏"而不是五团一起跳）
		for i in PUFF_COUNT:
			var angle := TAU * float(i) / float(PUFF_COUNT)
			_puff_dirs.append(Vector2(cos(angle), sin(angle)))
			var puff := MeshInstance3D.new()
			puff.name = "DustPuff_%d" % i
			puff.mesh = Arrow.IMPACT_DUST_PUFF_MESH
			var puff_mat := _new_dust_material(0.52, 0.45, 0.35)
			puff.material_override = puff_mat
			_mats.append(puff_mat)
			_puffs.append(puff)
			add_child(puff)

	## 材质**每个实例独立一份**（因为有透明度 / 自发光要逐帧改），但网格是 4 个实例共享的常量资源。
	## ⚠️ 只在 `_ready()` 里建一次（池预建），**播放时不新建任何东西**。
	func _new_dust_material(r: float, g: float, b: float) -> StandardMaterial3D:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(r, g, b, 0.85)
		mat.roughness = 1.0
		mat.emission_enabled = true
		mat.emission = Color(r, g, b)
		mat.emission_energy_multiplier = 0.35
		## ⚠️ 最后设 `transparency` 并同时给 alpha：只设 alpha 不设 transparency 会**完全不透明**；
		## 只设 transparency 而不给 alpha<1 会跳过透明队列、`cull_mode` 之类的设置也拿不到默认值。
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		return mat

	## 播一次（由 `Arena._show_impact_dust()` 调用）。`variant` 只改**预建几何的尺寸 / 朝向**，
	## 不新建节点 ⇒ 连续两发石头不会长得一模一样。
	func play(at: Vector3, radius: float, variant: int) -> void:
		_radius = maxf(radius, 0.5)
		_born_ms = Time.get_ticks_msec()
		_playing = true
		visible = true
		global_position = Vector3(at.x, 0.02, at.z)
		rotation.y = float(variant) * 0.9          ## 只转整体朝向：换个"撒开的角度"就够了
		var bulk := 0.85 + 0.12 * float(variant % 3)
		if _ring != null:
			_ring.scale = Vector3.ONE * 0.3
		_base_scale.resize(_puffs.size())
		for i in _puffs.size():
			var spread := bulk * (0.75 + 0.18 * float((i + variant) % 3))
			_base_scale[i] = spread
			_puffs[i].scale = Vector3.ONE * spread
			_puffs[i].position = Vector3(_puff_dirs[i].x * 0.3 * spread, 0.22,
				_puff_dirs[i].y * 0.3 * spread)
		set_process(true)

	func stop() -> void:
		_playing = false
		visible = false
		set_process(false)

	func is_playing() -> bool:
		return _playing

	func _process(_delta: float) -> void:
		if not _playing:
			return
		var u := float(Time.get_ticks_msec() - _born_ms) / float(DUST_MS)
		if u >= 1.0:
			stop()
			return
		## 沙环：前 45% 冲到判定半径，之后只淡出
		if _ring != null:
			var open := clampf(u / 0.45, 0.0, 1.0)
			var r := lerpf(0.3, _radius * 0.92, ease(open, 0.35))
			_ring.scale = Vector3(r, 1.0, r)
		## 尘团：一路往外 + 往上飘，同时缩小
		for i in _puffs.size():
			var phase := clampf((u - float(i) * 0.06) / 0.72, 0.0, 1.0)
			var reach := _radius * 0.55 * ease(phase, 0.4)
			_puffs[i].position = Vector3(_puff_dirs[i].x * reach, 0.22 + DUST_RISE * ease(phase, 0.4),
				_puff_dirs[i].y * reach)
			## 起始大小由 `play()` 的变体决定（`_base_scale`），这里只在它基础上收干净
			_puffs[i].scale = Vector3.ONE * _base_scale[i] * lerpf(1.0, 0.35, phase)
		## 整段一起淡出（与沙虫震地同一手法：自发光 + alpha 一起收）
		var fade := 1.0 - clampf((u - 0.35) / 0.65, 0.0, 1.0)
		for mat in _mats:
			mat.emission_energy_multiplier = 0.35 + 0.9 * fade
			var col := mat.albedo_color
			col.a = 0.85 * fade
			mat.albedo_color = col
