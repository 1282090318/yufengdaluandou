class_name RangeHint
extends Node3D
## 部署时画在地上的射程圈，以及指向「队里最多人会锁定的那一队」的箭头。
## 纯表现：没有碰撞，不进单位名单。

## 离地高度单位是米。实心圈是黑的、偏透，不进兴奋圈的 `RING_*`。
const RANGE_FILL_LIFT_M := 0.08
const RANGE_FILL_TINT := Color(0.0, 0.0, 0.0, 0.34)
const LOCK_ARROW_LIFT_M := 0.7
const LOCK_ARROW_TINT := Color(1.0, 0.38, 0.28, 0.95)

var _ring: MeshInstance3D = null
var _aim: MeshInstance3D = null
var _marked: Array = []
var _disc_mesh: CylinderMesh = null
var _disc_radius: float = -1.0


func _ready() -> void:
	_ring = MeshInstance3D.new()
	_ring.name = "RangeFill"
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ring.material_override = _fill_material()
	add_child(_ring)
	_aim = MeshInstance3D.new()
	_aim.name = "RangeAim"
	_aim.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_aim.material_override = _line_material(LOCK_ARROW_TINT)
	add_child(_aim)
	hide_hint()


func show_hint(center: Vector3, radius: float, aim_at: Vector3, has_aim: bool, owner_team: int = -1) -> void:
	visible = true
	if radius > 0.2:
		_ring.visible = true
		_ring.mesh = _disc(radius)
		_ring.position = Vector3(center.x, RANGE_FILL_LIFT_M, center.z)
	else:
		_ring.visible = false
	if has_aim:
		_aim.visible = true
		_aim.mesh = _arrow(center, aim_at)
	else:
		_aim.visible = false
		_aim.mesh = null
	_mark_inside(center, radius, owner_team)


func hide_hint() -> void:
	visible = false
	_clear_marks()
	if _aim != null:
		_aim.mesh = null


func _disc(radius: float) -> CylinderMesh:
	if _disc_mesh == null:
		_disc_mesh = CylinderMesh.new()
		_disc_mesh.height = 0.02
		_disc_mesh.radial_segments = 48
	if not is_equal_approx(_disc_radius, radius):
		_disc_radius = radius
		_disc_mesh.top_radius = radius
		_disc_mesh.bottom_radius = radius
	return _disc_mesh


func _mark_inside(center: Vector3, radius: float, owner_team: int) -> void:
	var next: Array[Unit3D] = []
	if owner_team >= 0 and radius > 0.2:
		for node in get_tree().get_nodes_in_group("units"):
			var unit := node as Unit3D
			if unit == null or not is_instance_valid(unit) or not unit.alive or unit.team == owner_team:
				continue
			if unit.is_burrowed() or unit.is_in_shadow_form():
				continue
			var flat := unit.global_position - center
			flat.y = 0.0
			var limit := radius + GameConfig.body_radius(unit.type_id)
			if flat.length() > limit:
				continue
			next.append(unit)
	var keep := {}
	for unit in next:
		keep[unit] = true
		if not _marked.has(unit):
			unit.set_range_glow(true)
	for raw in _marked:
		var old := raw as Unit3D
		if old == null or not is_instance_valid(old):
			continue
		if not keep.has(old):
			old.set_range_glow(false)
	_marked = next


func _clear_marks() -> void:
	for raw in _marked:
		var unit := raw as Unit3D
		if unit != null and is_instance_valid(unit):
			unit.set_range_glow(false)
	_marked.clear()


func _arrow(from: Vector3, to: Vector3) -> ArrayMesh:
	var start := Vector3(from.x, LOCK_ARROW_LIFT_M, from.z)
	var tip := Vector3(to.x, LOCK_ARROW_LIFT_M, to.z)
	var flat := tip - start
	flat.y = 0.0
	if flat.length_squared() < 0.36:
		return _lines(PackedVector3Array())
	var dir := flat.normalized()
	var side := Vector3(-dir.z, 0.0, dir.x)
	var head := 1.6
	var base := tip - dir * head
	var verts := PackedVector3Array()
	verts.append(start)
	verts.append(tip)
	verts.append(base + side * 0.75)
	verts.append(tip)
	verts.append(base - side * 0.75)
	return _lines(verts)


func _lines(verts: PackedVector3Array) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	if verts.size() < 2:
		return mesh
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINE_STRIP, arrays)
	return mesh


func _fill_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = RANGE_FILL_TINT
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	return mat


func _line_material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat
