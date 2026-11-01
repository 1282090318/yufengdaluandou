class_name AudioManager
extends Node
## 音频层：把 `06_audio.md#3` 的**事件名清单**接到真实音频流上。
##
## 依据：`06_audio.md#1`（总线树，落在 `default_bus_layout.tres`）、`#3`（事件名与触发时机）、
## `#6`（预算：单个音效 ≤ 2.0 s）、`#7`（实现约定：**短音效走对象池化的 `AudioStreamPlayer`，禁止每次 `new`**）。
##
## 边界（R-07）：只**读**玩法层的公开状态（`type_id` / 位置 / 速度），只**听** `Events` 上的既有信号，
## **从不改任何玩法数据**；也**不新增信号** —— `06_audio.md#3` 的口径是"表现层专用信号统一走 `fx_request`，
## 事件名只是音频层内部的映射键"。
##
## ⚠️ 生命周期（**2026-09-25 改**）：由 `main.gd` 在 `_ready()` 里创建、**全程不释放**（退回主菜单时
## 别的子节点都被拆掉，只有它留着）⇒ **开始界面那一屏也有音频层**。用户口径："已引入 BGM，将其加入
## 每一个界面（之后不同界面会用不同的 BGM，但现在先共用一个）" —— 要覆盖开始界面，音频层就必须
## 活得比"一场比赛"长。⚠️ 这条**不动不变量 I-06**（Autoload 表仍是 `Events` → `GameConfig` →
## `MCPGameBridge`）：它仍是 `main` 的子节点，只是不再随比赛释放。
##
## ⚠️ 素材（用户 2026-09-25 提供，文件名已按事件名改成 snake_case 并搬进 `assets/audio/`）：
## 一个文件可能服务多个事件（"放箭"同时给 `combat_bow_release` 与 `combat_longbow_release`）。
## ⚠️ **2026-09-25 移除"受伤 / 死亡"两条音效**（用户："移除受伤和死亡音效"）：事件 `combat_hit_flesh`
## 与 `unit_die` 连同它们各自的信号接线一并删掉（两条原本共用同一个素材文件）⇒
## **`combat_hit_flesh.wav` 从此没有任何事件引用**（文件保留在磁盘上，没删 —— 只是不再播）。
## ⚠️ 阵亡 / 受击的信号本身**照旧发**（`Events.unit_was_hit` / `unit_died` 是玩法层的东西，
## 本层只是不再听），所以"删音效"没有动玩法一个字。
## ⚠️ 载具的"发射 / 移动"在原事件表里**没有对应行** ⇒ 本文件新增了三个事件名
##（`combat_catapult_launch` / `combat_ballista_launch` / `unit_vehicle_move`），待下次同步写进 `06_audio.md#3`。
##
## ⚠️ **空间化（2026-09-25 用户："音效的大小应该随镜头到音效发出的地方的距离改变，且音效能够让人识别
## 音效发出的方位"）**：本层的短音效池与载具循环**全部改成 `AudioStreamPlayer3D`**，落地 `06_audio.md#5`
## 那一张"空间化规则"表：
##   · **选手动作 / 命中 / 阵亡 / 格挡 / 发射 = 3D**，衰减 = **线性**（`06_audio.md#5` 那一档，
##     ⚠️ **Godot 4 没有线性内建档** ⇒ 见下面 `SPATIAL_*` 的说明，这条曲线是**本层自己算的**）、
##     声源位置 = 事件自带的坐标（`unit_was_hit/_died/_was_blocked` 带的**单位节点**、`fx_request` 带的
##     `world_pos`，两者都是现成的，**不需要新增信号、也不需要改玩法层**）；
##   · **听者 = 当前相机**：本层**不建 `AudioListener3D`** —— Godot 在没有 `AudioListener3D` 作 current 时
##     就用**当前 `Camera3D`** 当听者，而"哪台相机是 current"的唯一出处是 `CameraRig.camera()` ⇒
##     方位感与"随镜头距离衰减"因此自动成立（玩家用滚轮推近，声音就会跟着变响）。
## ⚠️ **与 §5 的一处偏离（要记得在同步时写进 bible）**：§5 写的是"最大距离 **30 m**"，但本作**指挥视角
## 离战场质心就有 ~42.5 m**，按 30 m 落地会**整场战斗一声不响**（那不是"随距离变化"，是"没声音"）⇒
## 这里取 **`SPATIAL_MAX_DISTANCE` = 80 m**：质心处约 −6.6 dB（听得见、但明显比凑近轻），
## 远角（~70 m）约 −15 dB。**衰减模型本身（线性）与 §5 完全一致**，改的只是那个距离刻度。
## ⚠️ **非空间化那一档**（BGM / UI / 结算 / 兴奋圈 / 环境，见 §5 表格后三行）：**2026-09-25 起有 2D 池**
##（普通 `AudioStreamPlayer`，**不塞进 3D 池** —— 塞进来会让音乐跟着镜头距离衰减）。
## 目前 2D 池里只有两个固定播放器：**BGM**（`_music`，`Music` 总线，循环）与 **UI 试听**
##（`_ui`，`SFX` 总线，给设置界面的"音效大小"滑条试听用）。结算 / 兴奋圈 / 环境仍**没有素材**，
## 将来接它们时**继续加在这个 2D 池里**。

# ---------------------------------------------------------------- 表现参数（住脚本，不进 GameConfig）
const AUDIO_DIR := "res://assets/audio/"
## Godot **能导入**的音频格式，按优先级依次尝试（⚠️ `.m4a` / `.aac` / `.mp4` 不在其中 —— 实测导不进来）
const AUDIO_EXTENSIONS := [".wav", ".mp3", ".ogg"]
const POOL_SIZE := 16                    ## 短音效同时播放上限（池；`06_audio.md#6` 写的总上限是 24）
const BUS_COMBAT := "SFX_Combat"
const BUS_UNIT := "SFX_Unit"
## 设置界面要调的两条总线（`06_audio.md#1` 的总线树）。⚠️ 总线名的**唯一出处**在这里 ——
## 设置界面不自己写字符串，免得改总线树时漏掉一处。
##   · `Music`  —— 只挂 BGM（`_music`），"音乐"滑条调它；
##   · `SFX`    —— 是 `SFX_Combat` / `SFX_Unit` / `SFX_UI` 的**父总线**（见 `default_bus_layout.tres`）
##                ⇒ 调它一个就等于调全部音效，"音效"滑条调它（不用去逐个改三条子总线）。
const BUS_MUSIC := "Music"
const BUS_SFX := "SFX"
## 本层挂的**组名**：设置界面靠它找到本层（`AudioManager.find()`）。
## ⚠️ 为什么不走信号 / 不走 `main`：`07_file_layout.md#5` 的依赖方向里"界面层不认识 `main`"，
## 而界面 → 音频是**反向**依赖 ⇒ 用组查找（与 `unit3d.gd` 的 `units` 组同一种既有做法），
## 既不新增信号，也不让界面知道 `main` 的存在。
const GROUP := "audio"
## "音乐"滑条拉到最小时写进总线的音量（dB）。⚠️ 不能写 `linear_to_db(0)`：那是 **−inf**，
## 写进 `AudioServer` 会得到一个 NaN 音量（表现为整条总线失灵）。
const MIN_VOLUME_DB := -60.0
const VEHICLE_MOVE_EPS := 0.35           ## 载具"算在移动"的速度阈值 m/s
## 3D 空间化（`06_audio.md#5`）：`unit_size` = "这个半径以内按满音量算"，
## `max_distance` = "再远就听不见了"。
## ⚠️ **为什么不用引擎的 `attenuation_model`**：Godot 4 的 `AttenuationModel` 只有
## `INVERSE_DISTANCE` / `INVERSE_SQUARE_DISTANCE` / `LOGARITHMIC` / `DISABLED` 四档
##（引擎内实测枚举，**没有"线性"**），而 §5 明写"**线性**" ⇒ 本层把引擎那条曲线关掉
##（`ATTENUATION_DISABLED`）、**自己每帧按距离写 `volume_db`**：
##     `gain(d) = 1`（`d ≤ unit_size`）→ `1 − (d − unit_size) / (max − unit_size)`（中间线性）→ `0`（`d ≥ max`）
## ⇒ 好处是**这条曲线可以直接量**（给定距离就能算出该是多少 dB，见探针），坏处是每帧要遍历 ≤16 个播放器
##（可忽略）。⚠️ **声像（左右方位）仍然由引擎算**（`panning_strength`）—— 关掉的是"距离衰减"，
## 不是"3D 定位"；左右声道的分离度实测过（见报告）。
const SPATIAL_UNIT_SIZE := 1.0           ## 满音量半径 m
const SPATIAL_MAX_DISTANCE := 80.0       ## 衰减到静音的距离 m（⚠️ §5 原写 30，理由见文件头）
const SPATIAL_SILENT_DB := -80.0         ## 增益为 0 时写这个（`linear_to_db(0)` 是 −inf，别写进属性）
const VOLUME_LANCE_DB := -4.0            ## 轻骑兵冲锋的起手吼（`combat_lance_charge`，无音高抖动）
const VOLUME_BLOCK_DB := -6.0
const VOLUME_SHOT_DB := -5.0
const VOLUME_VEHICLE_MOVE_DB := -14.0
## BGM 的基础音量（写在**播放器**上、不写总线）：用户滑条调的是总线，总线就从 0 dB 起算，
## 这里只负责"音乐整体比音效轻一档"这一个创作口径（音乐是背景，不该压过命中 / 开火）。
const VOLUME_BGM_DB := -8.0
const PITCH_SHOT := 0.08
const PITCH_VEHICLE_LAUNCH := 0.04
## BGM 的**事件名**（= `assets/audio/` 里的文件名基名，沿用 §3 的"文件名 = 事件名"）。
## ⚠️ 现在**每个界面共用这一条**；将来"不同界面不同 BGM"就是再加常量 + 在 `_bgm_table()` 里加一行，
## 调用方换 `play_bgm(BGM_XXX)` 即可（本层按 id 幂等：同一条正在放就**不会重头开始**，
## 所以"每个界面都调一次"是安全的写法）。
const BGM_MAIN := "bgm_main"
## 设置界面"音效大小"滑条的**试听样本**：拿一条**短、无音高抖动**的既有音效来放 ——
## 不为试听新增素材，也不新增事件名（复用它本来那条事件）。
const PREVIEW_EVENT := "combat_shield_block"

var _events: Dictionary = {}             ## 事件名 → { stream, bus, volume_db, pitch_jitter }
## 短音效播放器池（禁止每次 new，见 §7）。⚠️ **2026-09-25 起是 3D 播放器**（空间化，见文件头）
var _pool: Array[AudioStreamPlayer3D] = []
var _next := 0
var _vehicle_loops: Dictionary = {}       ## 载具 → 它的循环播放器（懒建，载具走了就收）
## 非空间化 2D 池（见文件头）：BGM 与 UI 试听各一个固定播放器，**不进 3D 池**。
var _music: AudioStreamPlayer = null
var _ui: AudioStreamPlayer = null
var _bgm_table: Dictionary = {}           ## BGM id → 流（懒加载，缺素材时为 null）
var _bgm_id: String = ""                  ## 正在放的 BGM id（空 = 没在放）—— `play_bgm()` 靠它幂等

func _ready() -> void:
	## 设置界面靠这个组找到本层（`AudioManager.find()`），见 `GROUP` 的说明。
	add_to_group(GROUP)
	_build_events()
	_build_bgm_table()
	for i in POOL_SIZE:
		var player := AudioStreamPlayer3D.new()
		player.name = "SfxPlayer_%d" % i         ## §3.1：动态节点也要命名，序号写在 `_` 之后
		## ⚠️ 关掉引擎的衰减曲线：线性那一条是本层自己算的（见 `SPATIAL_*` 的说明）
		player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_DISABLED
		player.max_distance = SPATIAL_MAX_DISTANCE
		add_child(player)
		_pool.append(player)
	## 2D 池（BGM + UI 试听）：普通 `AudioStreamPlayer` ⇒ **不吃距离衰减、也没有方位**
	##（音乐是"贴着耳朵"的，跟着镜头远近变响反而不对）。
	_music = AudioStreamPlayer.new()
	_music.name = "MusicPlayer"                  ## §3.1：动态节点也要命名
	_music.bus = BUS_MUSIC                       ## `06_audio.md#1`：任何播放都必须显式指定总线
	_music.volume_db = VOLUME_BGM_DB
	add_child(_music)
	_ui = AudioStreamPlayer.new()
	_ui.name = "UiPlayer"
	_ui.bus = BUS_SFX
	add_child(_ui)
	## 只挂**既有信号**（一个信号都不用新增）。
	## ⚠️ **2026-09-25 起不再听 `unit_was_hit` / `unit_died`**（"受伤 / 死亡"两条音效已按用户要求移除）。
	Events.unit_was_blocked.connect(_on_unit_was_blocked)
	Events.fx_request.connect(_on_fx_request)

func _process(_delta: float) -> void:
	_tick_vehicle_loops()
	_tick_spatial_volumes()

# ---------------------------------------------------------------- 距离衰减（线性，见 SPATIAL_* 的说明）
## 每帧给"正在响的"播放器写一次音量：`volume_db = 基础音量 + 线性增益(dB)`。
## ⚠️ 基础音量住在播放器的 `base_db` 元数据里（`_play()` / `_make_loop_player()` 写），
## 因为 `volume_db` 这一格每帧都被本函数覆盖 —— 不这么存就会**越跑越轻**（自己衰减自己）。
func _tick_spatial_volumes() -> void:
	var listener := _listener_position()
	for player in _pool:
		if player.playing:
			_apply_spatial_volume(player, listener)
	for player in _vehicle_loops.values():
		if is_instance_valid(player) and player.playing:
			_apply_spatial_volume(player, listener)

func _apply_spatial_volume(player: AudioStreamPlayer3D, listener: Vector3) -> void:
	var base_db := float(player.get_meta("base_db", player.volume_db))
	var dist := listener.distance_to(player.global_position)
	var gain := 0.0
	if dist <= SPATIAL_UNIT_SIZE:
		gain = 1.0
	elif dist < SPATIAL_MAX_DISTANCE:
		gain = 1.0 - (dist - SPATIAL_UNIT_SIZE) / (SPATIAL_MAX_DISTANCE - SPATIAL_UNIT_SIZE)
	player.volume_db = SPATIAL_SILENT_DB if gain <= 0.0 else base_db + linear_to_db(gain)

## 听者 = **当前相机**（`06_audio.md#5` 的"随镜头到声源的距离变化"）。
## ⚠️ 本层**不建 `AudioListener3D`**：Godot 在没有它作 current 时就用当前 `Camera3D` 当听者，
## 而"哪台相机是 current"的唯一出处是 `CameraRig.camera()` ⇒ 这里也只问视口要当前相机，不自己找节点。
func _listener_position() -> Vector3:
	var cam := get_viewport().get_camera_3d()
	return cam.global_position if cam != null else Vector3.ZERO

# ---------------------------------------------------------------- 事件表（= 06_audio.md#3 的落地）
func _build_events() -> void:
	## ⚠️ 一个文件服务多个事件的地方都在这里写明，免得以后有人以为漏了素材
	## ⚠️ 这里写的是**不带扩展名的基名**：加载时按 `AUDIO_EXTENSIONS` 依次找
	##（`.wav` → `.mp3` → `.ogg`）⇒ 以后换素材格式**不用改代码**。
	## ⚠️ **2026-09-25 删掉两条**（用户："移除受伤和死亡音效"）：`combat_hit_flesh`（受伤）
	## 与 `unit_die`（死亡）—— 它们原本共用 `combat_hit_flesh.wav` 这一个素材。
	_events["combat_shield_block"] = _entry("combat_shield_block", "combat_shield_block", BUS_COMBAT, VOLUME_BLOCK_DB, 0.0)
	_events["combat_bow_release"] = _entry("combat_bow_release", "combat_bow_release", BUS_COMBAT, VOLUME_SHOT_DB, PITCH_SHOT)
	_events["combat_longbow_release"] = _entry("combat_longbow_release", "combat_bow_release", BUS_COMBAT, VOLUME_SHOT_DB, PITCH_SHOT)
	## ⚠️ 下面三个是**新增事件名**（原表没有载具相关的行，见文件头）
	_events["combat_catapult_launch"] = _entry("combat_catapult_launch", "combat_catapult_launch", BUS_COMBAT, VOLUME_SHOT_DB, PITCH_VEHICLE_LAUNCH)
	_events["combat_ballista_launch"] = _entry("combat_ballista_launch", "combat_ballista_launch", BUS_COMBAT, VOLUME_SHOT_DB, PITCH_VEHICLE_LAUNCH)
	_events["unit_vehicle_move"] = _entry("unit_vehicle_move", "unit_vehicle_move", BUS_UNIT, VOLUME_VEHICLE_MOVE_DB, 0.0)
	## ⚠️ **2026-09-25 新接的两条**（用户："火枪发射的音效和轻骑兵矛开始冲锋的音效已引进，请把他们加进去"）：
	## 素材由用户提供、原名是中文（`发射火枪声音效.mp3` / `轻骑兵（矛）开始冲锋音效.mp3`，且**放在项目根目录**），
	## 按 `08_naming.md#2`（资源文件 = snake_case + 类型后缀）与 `06_audio.md#3`（文件名 = 事件名、
	## 放 `assets/audio/`）**改名并搬进 `assets/audio/`** —— 与上一批中文名素材同一条既有裁决。
	## ⚠️ `combat_lance_charge` 这个**事件名早就登记在 §3 表里**（状态"待接"），所以是"接上"而不是"新开名字"；
	## 素材只有**起手**那一下（2.6 KB），持续循环 / 收尾两段仍待补（§3 与 §8 都记着）。
	_events["combat_musket_fire"] = _entry("combat_musket_fire", "combat_musket_fire", BUS_COMBAT, VOLUME_SHOT_DB, PITCH_VEHICLE_LAUNCH)
	_events["combat_lance_charge"] = _entry("combat_lance_charge", "combat_lance_charge", BUS_COMBAT, VOLUME_LANCE_DB, 0.0)

## 建一条事件映射：按 `AUDIO_EXTENSIONS` 依次找 `基名 + 扩展名`。
## ⚠️ 找不到时**必须把"磁盘上到底有什么"说清楚**，否则排查会被误导 —— 2026-09-25 就踩过一次：
## 用户把几个素材换成 `.m4a`（MP4/AAC 容器），而 **Godot 根本导不进来**（扫完连 `.import` 都不生成），
## 只报"找不到 xx.wav"会让人以为文件没放进去 ⇒ 所以这里会**扫目录**、把同名异扩展的文件列出来。
func _entry(event_name: String, base_name: String, bus: String, volume_db: float, pitch_jitter: float) -> Dictionary:
	var stream: AudioStream = null
	for extension in AUDIO_EXTENSIONS:
		var path: String = AUDIO_DIR + base_name + String(extension)
		if ResourceLoader.exists(path):
			stream = load(path)
			break
	if stream == null:
		push_warning("[AudioManager] 事件 `%s` 静音：%s%s 都取不到流；磁盘上同名的是 %s"
			% [event_name, AUDIO_DIR + base_name, str(AUDIO_EXTENSIONS), str(_sibling_files(base_name))])
	return {"stream": stream, "bus": bus, "volume_db": volume_db, "pitch_jitter": pitch_jitter}

## 建 BGM 表（id → 流）。**懒加载**：`play_bgm()` 第一次用到某条时才 `load()`，
## 免得"打开游戏"那一次就把几 MB 的音乐读进内存（虽然现在只有一条）。
func _build_bgm_table() -> void:
	_bgm_table.clear()
	## ⚠️ 以后"不同界面不同 BGM"就在这里加行（例如 `_bgm_table["bgm_sandbox"] = "bgm_sandbox"`），
	## 命名沿用 §3 的"文件名 = 事件名"。
	_bgm_table[BGM_MAIN] = BGM_MAIN

## 取一条 BGM 的流（找不到素材时返回 null **并说明磁盘上有什么**，与 `_entry()` 同款诊断）。
func _bgm_stream(id: String) -> AudioStream:
	var base_name := String(_bgm_table.get(id, ""))
	if base_name == "":
		push_warning("[AudioManager] BGM `%s` 没登记（见 `_build_bgm_table()`）" % id)
		return null
	for extension in AUDIO_EXTENSIONS:
		var path: String = AUDIO_DIR + base_name + String(extension)
		if ResourceLoader.exists(path):
			return load(path)
	push_warning("[AudioManager] BGM `%s` 静音：%s%s 都取不到流；磁盘上同名的是 %s"
		% [id, AUDIO_DIR + base_name, str(AUDIO_EXTENSIONS), str(_sibling_files(base_name))])
	return null

## 列出 `assets/audio/` 里与 `base_name` 同名的文件（诊断用）—— 典型输出是 `["combat_shield_block.m4a"]`，
## 一眼就能看出"素材在、但格式 Godot 不认"。
func _sibling_files(base_name: String) -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(AUDIO_DIR)
	if dir == null:
		return out
	for file_name in dir.get_files():
		var name := String(file_name)
		if name.begins_with(base_name) and not name.ends_with(".import"):
			out.append(name)
	return out

# ---------------------------------------------------------------- 播放（池）
## `source_pos` = **声源的世界坐标**（3D 空间化用，见文件头）。听者 = 当前相机，不需要在这里传。
func _play(event_name: String, source_pos: Vector3) -> void:
	var entry: Dictionary = _events.get(event_name, {})
	if entry.is_empty():
		return
	var stream: AudioStream = entry["stream"]
	if stream == null:
		return
	var player := _take_player()
	player.stream = stream
	## ⚠️ `06_audio.md#1` 的规则：**任何播放都必须显式指定总线，禁止默认落到 Master**
	player.bus = String(entry["bus"])
	## 基础音量记进元数据：`volume_db` 随后被 `_tick_spatial_volumes()` 每帧按距离改写（见那里的说明）
	var base_db := float(entry["volume_db"])
	player.set_meta("base_db", base_db)
	player.volume_db = base_db
	var jitter := float(entry["pitch_jitter"])
	player.pitch_scale = 1.0 if jitter <= 0.0 else 1.0 + randf_range(-jitter, jitter)
	## ⚠️ 位置必须在 `play()` **之前**摆好：起播那一帧就要按正确的位置算声像与距离衰减
	player.global_position = source_pos
	_apply_spatial_volume(player, _listener_position())   ## 第一帧就摆好音量，别等下一次 `_process`
	player.play()

func _take_player() -> AudioStreamPlayer3D:
	for player in _pool:
		if not player.playing:
			return player
	## 池满了：轮转覆盖最早的那个（`06_audio.md#6` 的"超出按优先级剔除"是以后的事）
	var player := _pool[_next]
	_next = (_next + 1) % _pool.size()
	return player

## 声源坐标：能拿到节点就用它的位置；拿不到（已被释放）就**落在听者身上**（= 不衰减），
## 而不是掉到世界原点 —— 掉原点会让"刚死掉的单位"那一声莫名其妙地变远/变轻。
func _source_position(node: Node3D) -> Vector3:
	if node != null and is_instance_valid(node):
		return node.global_position
	var cam := get_viewport().get_camera_3d()
	return cam.global_position if cam != null else Vector3.ZERO

# ---------------------------------------------------------------- BGM（每个界面共用一个）
## 找到本层（设置界面用它改音量）。⚠️ 用组查找而不是让界面认识 `main`，见 `GROUP` 的说明。
## 返回 null 是**合法状态**（例如本层还没建起来）：调用方必须自己兜住。
static func find(tree: SceneTree) -> AudioManager:
	if tree == null:
		return null
	return tree.get_first_node_in_group(GROUP) as AudioManager

## 播放一条 BGM。**按 id 幂等**：同一条正在放就原样返回（不重头开始、也不重启）——
## 于是"每个界面都调一次 `play_bgm(BGM_MAIN)`"是安全写法（用户口径："先共用一个"）。
## ⚠️ 素材取不到时**只警告、不崩**（见 `_bgm_stream()` 的诊断），并且**不占用 `_bgm_id`** ⇒
## 以后素材补上了，下一次调用就会正常响起。
func play_bgm(id: String = BGM_MAIN) -> void:
	if _music == null:
		return
	if id == _bgm_id and _music.playing:
		return
	var stream := _bgm_stream(id)
	if stream == null:
		return
	## 循环：与载具循环同款做法（导入进来的流 `loop_begin` / `loop_end` 都是 0 ⇒ 必须自己设；
	## 光设 `loop_mode` 不生效那次教训见 `_make_loop_player()`）。
	if stream is AudioStreamWAV:
		var wav := stream as AudioStreamWAV
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = int(round(wav.get_length() * float(wav.mix_rate)))
	elif stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = true
	elif stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true
	_music.stream = stream
	_music.volume_db = VOLUME_BGM_DB      ## 基础音量住播放器，用户滑条调的是总线（见常量说明）
	_bgm_id = id
	_music.play()

func stop_bgm() -> void:
	if _music != null:
		_music.stop()
	_bgm_id = ""

## 当前正在放的 BGM id（空串 = 没在放）。探针与设置界面读它，别去翻 `_music` 内部。
func current_bgm() -> String:
	return _bgm_id

# ---------------------------------------------------------------- 音量（设置界面用）
## 音乐 / 音效的当前总线音量（dB）。⚠️ 读的是**总线**（`AudioServer`）而不是本层的成员：
## 总线音量是引擎级状态，本层被重建也不会丢（现在本层本来也不重建，见文件头）。
func music_db() -> float:
	return _bus_db(BUS_MUSIC)

func sfx_db() -> float:
	return _bus_db(BUS_SFX)

func set_music_db(db: float) -> void:
	_set_bus_db(BUS_MUSIC, db)

func set_sfx_db(db: float) -> void:
	_set_bus_db(BUS_SFX, db)

func _bus_db(bus_name: String) -> float:
	var index := AudioServer.get_bus_index(bus_name)
	return AudioServer.get_bus_volume_db(index) if index >= 0 else 0.0

func _set_bus_db(bus_name: String, db: float) -> void:
	var index := AudioServer.get_bus_index(bus_name)
	if index < 0:
		push_warning("[AudioManager] 总线 `%s` 不存在（`default_bus_layout.tres` 改过了？）" % bus_name)
		return
	## ⚠️ 下界夹到 `MIN_VOLUME_DB`：滑条拉到 0 时 `linear_to_db(0)` 是 −inf，
	## 写进 `AudioServer` 会让整条总线变成 NaN（不是"静音"，是"坏掉"）。
	AudioServer.set_bus_volume_db(index, maxf(db, MIN_VOLUME_DB))

## 放一声"试听"音（设置界面的"音效大小"滑条用）：走 2D 池的 `_ui` ⇒ **不吃距离衰减**，
## 音量由 `SFX` 总线决定（所以拖完滑条立刻能听出大小差别）。
func preview_sfx() -> void:
	if _ui == null:
		return
	var entry: Dictionary = _events.get(PREVIEW_EVENT, {})
	var stream: AudioStream = entry.get("stream", null)
	if stream == null:
		return
	_ui.stream = stream
	_ui.bus = BUS_SFX
	_ui.volume_db = float(entry.get("volume_db", 0.0))
	_ui.play()

# ---------------------------------------------------------------- 既有信号的接线
## ⚠️ 单位信号**本来就带节点**（`Events.unit_was_blocked(unit)`）—— 2026-09-25 之前这一层把它丢掉了
##（参数名叫 `_unit`），空间化正好把它用起来：**玩法层一个字都不用改**。
## ⚠️ **受伤 / 死亡两条已移除**（用户口径），所以这里只剩格挡一个单位信号 ——
## `_source_position()` 仍然要用（格挡声也要定在挨打那个单位身上）。
func _on_unit_was_blocked(unit: Unit3D) -> void:
	_play("combat_shield_block", _source_position(unit))

## 发射音：`arena.gd#spawn_arrow()` 发的是 `shot_<兵种ID>`（见那里的说明 —— `fx_request` 只带
## `(event, world_pos)`，不把兵种编进事件名就分不出是谁在射）。
## ⚠️ 它的 `world_pos`（发射点）以前是**收下就扔**，现在正是这条音效的声源坐标。
func _on_fx_request(event: String, world_pos: Vector3) -> void:
	match event:
		"shot_shortbow":
			_play("combat_bow_release", world_pos)
		"shot_longbow":
			_play("combat_longbow_release", world_pos)
		"shot_catapult":
			_play("combat_catapult_launch", world_pos)
		"shot_ballista":
			_play("combat_ballista_launch", world_pos)
		"shot_musket":
			_play("combat_musket_fire", world_pos)
		"lance_charge":
			## 轻骑兵（矛）**发动冲刺那一帧**发出来的（见 `unit3d.gd#_start_lance()`）——
			## 技能没有专属信号，起手音只能挂在 `fx_request` 上（§3.4 的口径）。
			_play("combat_lance_charge", world_pos)

# ---------------------------------------------------------------- 载具移动音（循环，逐帧跟速度）
func _tick_vehicle_loops() -> void:
	var alive_vehicles := {}
	for node in get_tree().get_nodes_in_group("units"):
		var unit := node as Unit3D
		if unit == null or not is_instance_valid(unit) or not unit.alive:
			continue
		if not UnitFactory.VEHICLE_TYPES.has(unit.type_id):
			continue
		alive_vehicles[unit] = true
		var moving := unit.velocity.length() > VEHICLE_MOVE_EPS
		var player: AudioStreamPlayer3D = _vehicle_loops.get(unit)
		if moving and player == null:
			player = _make_loop_player()
			if player != null:
				_vehicle_loops[unit] = player
		if player == null:
			continue
		## ⚠️ **每帧跟着载具走**（3D 空间化必需）：循环声的声源就是这台载具，
		## 不跟的话它会一直响在"起播那一刻的位置"，车开走了声音还留在原地。
		player.global_position = unit.global_position
		if moving and not player.playing:
			player.play()                       ## 起步：起播（v1 不做淡入，见报告里的旋钮）
		elif not moving and player.playing:
			player.stop()                       ## 停下：收掉
	## 载具阵亡 / 被释放 ⇒ 循环播放器跟着收掉（否则会留下一个停不下来的引擎声）
	for unit in _vehicle_loops.keys():
		if alive_vehicles.has(unit) and is_instance_valid(unit):
			continue
		var player: AudioStreamPlayer3D = _vehicle_loops[unit]
		if is_instance_valid(player):
			player.queue_free()
		_vehicle_loops.erase(unit)

func _make_loop_player() -> AudioStreamPlayer3D:
	var entry: Dictionary = _events["unit_vehicle_move"]
	var stream: AudioStream = entry["stream"]
	if stream == null:
		return null
	## 循环：`06_audio.md#6` 的"长音效一律分段 + 循环" —— 这个流就是"持续段"
	## ⚠️ **2026-09-25 修 bug（本次实测发现）**：光设 `loop_mode` 是**不循环**的 ——
	## 导入进来的流 `loop_begin` / `loop_end` **都是 0**（实测 `combat_hit_flesh` 与 `unit_vehicle_move`
	## 两段素材皆然），而循环区间为空 ⇒ 播完就停。表现：**引擎声每 2.67 s 重起一次**
	##（`_tick_vehicle_loops()` 下一帧发现 `not playing` 又 `play()`），听感是断断续续的"突突"。
	## 修法：按 `get_length() × mix_rate` 补上循环区间（**不按 `data.size()` 推算** ——
	## 素材是 QOA 压缩的（`format == 3`），字节数与采样数不成正比）。
	if stream is AudioStreamWAV:
		var wav := stream as AudioStreamWAV
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = int(round(wav.get_length() * float(wav.mix_rate)))
	elif stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = true
	var player := AudioStreamPlayer3D.new()
	player.name = "VehicleMove_%d" % _vehicle_loops.size()
	player.bus = String(entry["bus"])
	var base_db := float(entry["volume_db"])
	player.set_meta("base_db", base_db)
	player.volume_db = base_db
	player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_DISABLED
	player.max_distance = SPATIAL_MAX_DISTANCE
	player.stream = stream
	add_child(player)
	return player
