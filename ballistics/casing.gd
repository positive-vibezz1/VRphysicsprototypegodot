class_name Casing
extends RigidBody3D
## Pooled spent case, or a live round thrown out by racking. Sleeps where it lands, then recycles.

const LIFETIME := 15.0

var _age := 0.0

@onready var _collider: CollisionShape3D = $CollisionShape3D
@onready var _mesh: MeshInstance3D = $Mesh


func launch(
	cartridge: CartridgeSpec, from: Vector3, orientation: Basis, velocity: Vector3, spin: Vector3, live: bool
) -> void:
	process_mode = Node.PROCESS_MODE_INHERIT
	visible = true
	mass = cartridge.round_mass if live else cartridge.casing_mass
	_age = 0.0
	var length := cartridge.casing_length * (1.3 if live else 1.0)
	var shape: CapsuleShape3D = _collider.shape
	if shape.height != length or shape.radius != cartridge.casing_radius:
		shape.radius = cartridge.casing_radius
		shape.height = maxf(length, 2.0 * cartridge.casing_radius)
		var mesh: CylinderMesh = _mesh.mesh
		mesh.top_radius = cartridge.casing_radius
		mesh.bottom_radius = cartridge.casing_radius
		mesh.height = length
	global_transform = Transform3D(orientation, from)
	linear_velocity = velocity
	angular_velocity = spin


func park() -> void:
	process_mode = Node.PROCESS_MODE_DISABLED
	visible = false


func _physics_process(delta: float) -> void:
	_age += delta
	if _age > LIFETIME:
		park()
