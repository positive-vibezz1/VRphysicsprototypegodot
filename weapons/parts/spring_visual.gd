extends MeshInstance3D
## A spring you can see working. Its rear end is fixed to the frame and its front end follows the bolt, so it
## compresses as the bolt runs back. Purely visual: the spring force itself comes from Rail.

## The mesh's length along -Z when the bolt is home.
@export var length := 0.1

var _rest := 0.0

@onready var _frame: Node3D = get_parent()
@onready var _bolt: Node3D = owner.get_node("Bolt")


func _ready() -> void:
	_rest = _frame.to_local(_bolt.global_position).z


func _process(_delta: float) -> void:
	scale.z = 1.0 - (_frame.to_local(_bolt.global_position).z - _rest) / length
