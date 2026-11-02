class_name MagPouch
extends Node3D
## A pouch at the front of the belt. An empty hand squeezing in it draws a full magazine for the gun in the other
## hand, as a real one with its weight. Drawn magazines are pooled for each cartridge: once a pool is full, the oldest
## one lying at rest somewhere is refilled and drawn again, so the count of bodies stays bounded.

## The magazines it can hand out. The one whose cartridge fits the other hand's gun is drawn.
@export var magazines: Array[PackedScene] = []
## The eyes. The pouch follows where they face, at this offset: right, up, back.
@export var head: Node3D
## Front of the belt for most people, about 0.6 m below eye level, with the hand a little out from the body.
@export var offset := Vector3(0.0, -0.6, -0.12)
@export var radius := 0.2
## Magazines of each kind drawn before the oldest is reused.
@export var pool_size := 6

var _scenes: Dictionary[CartridgeSpec, PackedScene] = {}
## Drawn magazines of each cartridge, oldest first.
var _drawn: Dictionary[CartridgeSpec, Array] = {}


func _ready() -> void:
	for scene: PackedScene in magazines:
		var state := scene.get_state()
		for i: int in state.get_node_property_count(0):
			if state.get_node_property_name(0, i) == &"cartridge":
				_scenes[state.get_node_property_value(0, i)] = scene


func _process(_delta: float) -> void:
	global_transform = spot()


## Where the pouch is, facing the way the head does. The head's right axis stays level while looking down at the belt,
## where its forward axis points at the floor.
func spot() -> Transform3D:
	var right := Vector3(head.global_basis.x.x, 0.0, head.global_basis.x.z).normalized()
	var facing := Basis(right, Vector3.UP, right.cross(Vector3.UP))
	return Transform3D(facing, head.global_position + facing * offset)


## Whether a squeeze of this hand would draw a magazine now. Cheap enough to ask every tick.
func can_draw(hand: PhysicsHand) -> bool:
	var gun := _gun_for(hand)
	return gun != null and _scenes.has(gun.mag_well.cartridge) and spot().origin.distance_to(hand.global_position) < radius


## A full magazine for the other hand's gun, at the hand for it to grab, or null if this hand can't draw one.
func draw(hand: PhysicsHand) -> GrabPoint:
	if not can_draw(hand):
		return null
	var cartridge := _gun_for(hand).mag_well.cartridge
	var mag := _take(cartridge)
	mag.refill()
	DebugLog.event("hand", "%s hand drew %s from the pouch, %d of that kind out" % ["left" if hand.is_left else "right", mag.name, _drawn[cartridge].size()])
	return mag.grab_point


func _gun_for(hand: PhysicsHand) -> Gun:
	if hand.held or not hand.other_hand or not hand.other_hand.held:
		return null
	return hand.other_hand.held.owner as Gun


## Only on a squeeze, so it may allocate.
func _take(cartridge: CartridgeSpec) -> Magazine:
	var drawn: Array = _drawn.get_or_add(cartridge, [])
	if drawn.size() >= pool_size:
		# Not one held, seated in a gun, or still moving, which could be on its way into one.
		for mag: Magazine in drawn:
			if mag.sleeping and mag.grab_point.enabled and not mag.grab_point.holder:
				drawn.erase(mag)
				drawn.append(mag)
				return mag
	var mag: Magazine = _scenes[cartridge].instantiate()
	mag.position = global_position
	# Beside the player in the world, so the range reset clears them with everything else.
	(owner.get_parent() if owner else get_parent()).add_child(mag, true)
	drawn.append(mag)
	return mag
