@tool
class_name TrialGate
extends Area3D
## The start, a checkpoint or the finish of the time trial: a see-through box that feels for the player's body, with
## its name over it. Like a parkour block, it builds its shape and mesh from its size. It lights up when it's the one
## to go for next and fades once it's passed.

enum State { WAITING, NEXT, PASSED }

## Layer 2, the player's body. Hands and held guns don't count.
const PLAYER_LAYER := 2
const NEXT_COLOR := Color(1.0, 0.85, 0.2, 0.3)
const ALPHA: Array[float] = [0.12, 0.3, 0.04]

@export var size := Vector3.ONE:
	set(value):
		size = value
		_mesh.size = value
		_shape.size = value
		_label.position.y = value.y * 0.5 + 0.3
@export var title := "":
	set(value):
		title = value
		_label.text = value
@export var color := Color(0.3, 0.8, 1.0)

var _mesh := BoxMesh.new()
var _shape := BoxShape3D.new()
var _material := StandardMaterial3D.new()
var _label := Label3D.new()


func _ready() -> void:
	collision_layer = 0
	collision_mask = PLAYER_LAYER
	monitorable = false
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mesh.material = _material
	var visual := MeshInstance3D.new()
	visual.mesh = _mesh
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(visual)
	var collision := CollisionShape3D.new()
	collision.shape = _shape
	add_child(collision)
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.pixel_size = 0.004
	_label.font_size = 48
	_label.outline_size = 12
	add_child(_label)
	set_state(State.WAITING)


func set_state(state: State) -> void:
	var shade := NEXT_COLOR if state == State.NEXT else color
	shade.a = ALPHA[state]
	_material.albedo_color = shade
