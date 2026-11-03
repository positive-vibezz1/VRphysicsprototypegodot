extends GutTest
## The belt pouch: an empty hand squeezing there draws a full magazine for the gun in the other hand, from a pool.

const HAND_SCENE: PackedScene = preload("res://player/physics_hand.tscn")
const PISTOL_SCENE: PackedScene = preload("res://weapons/pistol/pistol.tscn")
const AR_SCENE: PackedScene = preload("res://weapons/ar/ar.tscn")
const MAG_9MM: PackedScene = preload("res://weapons/parts/magazine_9mm.tscn")
const MAG_556: PackedScene = preload("res://weapons/parts/magazine_556.tscn")
const LEVEL_GRIP := Basis(Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(0, -1, 0))
const HEAD := Vector3(0, 101.6, 0)

var _world: Node3D
var _pouch: MagPouch
var _left: PhysicsHand
var _right: PhysicsHand


func before_each() -> void:
	_world = Node3D.new()
	add_child_autofree(_world)
	var head := Node3D.new()
	head.position = HEAD
	_world.add_child(head)
	# A floor under the belt for dropped magazines to come to rest on.
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	var slab := BoxShape3D.new()
	slab.size = Vector3(4, 0.2, 4)
	floor_shape.shape = slab
	floor_body.add_child(floor_shape)
	floor_body.position = Vector3(0, 100.4, 0)
	_world.add_child(floor_body)
	_pouch = MagPouch.new()
	_pouch.magazines = [MAG_9MM, MAG_556]
	_pouch.head = head
	_pouch.pose = Transform3D(Basis.IDENTITY, Vector3(0, -0.6, -0.12))
	_pouch.radius = 0.2
	_world.add_child(_pouch)
	_left = _hand(_pouch.spot().origin, true)
	_right = _hand(HEAD + Vector3(0.3, -0.5, -0.4), false)
	_left.other_hand = _right
	_right.other_hand = _left


func _hand(at: Vector3, left: bool) -> PhysicsHand:
	var hand: PhysicsHand = HAND_SCENE.instantiate()
	hand.is_left = left
	hand.pouch = _pouch
	_world.add_child(hand)
	hand.set_target(Transform3D(LEVEL_GRIP, at))
	return hand


func _hold_gun(scene: PackedScene) -> Gun:
	var gun: Gun = scene.instantiate()
	_world.add_child(gun)
	_right.input_grip = 1.0
	_right.grab(gun.grip)
	return gun


func _magazines() -> int:
	return _world.get_children().filter(func(node: Node) -> bool: return node is Magazine).size()


func _squeeze(hand: PhysicsHand) -> void:
	hand.input_grip = 0.0
	await wait_physics_frames(1)
	hand.input_grip = 1.0
	await wait_physics_frames(2)


func test_an_empty_hand_at_the_belt_draws_a_full_mag_for_the_pistol() -> void:
	var pistol := _hold_gun(PISTOL_SCENE)
	await wait_physics_frames(3)
	await _squeeze(_left)
	assert_not_null(_left.held, "something is in the hand")
	var mag := _left.held.owner as Magazine
	assert_not_null(mag, "and it's a magazine")
	assert_eq(mag.cartridge, pistol.mag_well.cartridge, "that fits the pistol")
	assert_eq(mag.count, mag.capacity, "full")
	assert_almost_eq(mag.mass, mag.empty_mass + mag.capacity * mag.cartridge.round_mass, 1.0e-6, "and as heavy as full")
	assert_lt(mag.grab_point.palm_transform().origin.distance_to(_left.global_position), 0.03, "in the palm")


func test_the_ar_gets_a_rifle_mag() -> void:
	var ar := _hold_gun(AR_SCENE)
	await wait_physics_frames(3)
	await _squeeze(_left)
	var mag := _left.held.owner as Magazine if _left.held else null
	assert_not_null(mag)
	assert_eq(mag.cartridge, ar.mag_well.cartridge)
	assert_eq(mag.count, 30)


func test_nothing_without_a_gun_in_the_other_hand() -> void:
	await wait_physics_frames(3)
	await _squeeze(_left)
	assert_null(_left.held)
	assert_eq(_magazines(), 0)


func test_nothing_away_from_the_belt() -> void:
	_hold_gun(PISTOL_SCENE)
	_left.set_target(Transform3D(LEVEL_GRIP, _pouch.spot().origin + Vector3(-0.35, 0.1, 0)))
	await wait_physics_frames(20)
	await _squeeze(_left)
	assert_null(_left.held)
	assert_eq(_magazines(), 0)


func test_the_pouch_stays_put_while_the_head_looks_around_and_comes_round_when_it_turns_far() -> void:
	var head := _pouch.head
	var ahead := HEAD + Vector3(0, -0.6, -0.12)
	assert_almost_eq(_pouch.spot().origin, ahead, Vector3.ONE * 1.0e-4)
	# Looking down and a little to the left, as at the belt, leaves it where it is.
	head.basis = Basis(Vector3.UP, 0.4) * Basis(Vector3.RIGHT, -1.2)
	assert_almost_eq(_pouch.spot().origin, ahead, Vector3.ONE * 1.0e-4)
	# Turned a quarter to the left, the torso has to come round to within the neck's twist.
	head.basis = Basis(Vector3.UP, PI * 0.5)
	var turned := Basis(Vector3.UP, PI * 0.5 - _pouch.max_twist)
	assert_almost_eq(_pouch.spot().origin, HEAD + turned * Vector3(0, -0.6, -0.12), Vector3.ONE * 1.0e-4)


func test_a_stick_turn_turns_the_pouch_with_the_view() -> void:
	var head := _pouch.head
	# A stick turn rotates what the head is in, not the head in it.
	var origin := Node3D.new()
	_world.add_child(origin)
	head.reparent(origin)
	origin.rotate_y(PI)
	assert_almost_eq(_pouch.spot().origin, origin.global_basis * HEAD + Vector3(0, -0.6, 0.12), Vector3.ONE * 1.0e-4)


func test_a_full_pool_reuses_the_oldest_mag_at_rest_and_refills_it() -> void:
	_pouch.pool_size = 2
	_hold_gun(PISTOL_SCENE)
	await wait_physics_frames(3)
	var first := _pouch.draw(_left).owner as Magazine
	var second := _pouch.draw(_left).owner as Magazine
	assert_ne(first, second)
	first.take_round()
	# Drawn without a hand to take them, so they drop to the floor and settle.
	await wait_physics_frames(240)
	assert_true(first.sleeping and second.sleeping, "both at rest")
	await _squeeze(_left)
	var third := _left.held.owner as Magazine if _left.held else null
	assert_eq(third, first, "the oldest comes back")
	assert_eq(third.count, third.capacity, "full again")
	assert_lt(third.grab_point.palm_transform().origin.distance_to(_left.global_position), 0.03, "into the palm, from wherever it lay")
	assert_eq(_magazines(), 2, "no new body")


func test_a_mag_in_a_hand_or_still_moving_is_never_taken_back() -> void:
	_pouch.pool_size = 1
	_hold_gun(PISTOL_SCENE)
	await wait_physics_frames(3)
	await _squeeze(_left)
	var held := _left.held.owner as Magazine
	# A third hand, also next to the pistol's hand.
	var other := _hand(_pouch.spot().origin, false)
	other.other_hand = _right
	await wait_physics_frames(2)
	var fresh := _pouch.draw(other).owner as Magazine
	assert_ne(fresh, held, "the one in a hand stays there")
	assert_eq(_magazines(), 2)
	_left.input_grip = 0.0
	await wait_physics_frames(1)
	var again := _pouch.draw(other).owner as Magazine
	assert_ne(again, held, "and one just dropped could be on its way into a gun")
	assert_eq(_magazines(), 3)


func test_the_player_has_a_pouch_for_both_hands_and_mags_land_in_the_range() -> void:
	var range_scene: Node = (load(ProjectSettings.get_setting("application/run/main_scene")) as PackedScene).instantiate()
	add_child_autofree(range_scene)
	var pouch: MagPouch = range_scene.get_node("Player/MagPouch")
	var left: PhysicsHand = range_scene.get_node("Player/LeftHand")
	var right: PhysicsHand = range_scene.get_node("Player/RightHand")
	assert_eq(left.pouch, pouch)
	assert_eq(right.pouch, pouch)
	await wait_physics_frames(2)
	right.grab((range_scene.get_node("Pistol") as Gun).grip)
	left.global_position = pouch.spot().origin
	var drawn := pouch.draw(left)
	assert_not_null(drawn, "draws with the pistol in the right hand")
	assert_eq(drawn.owner.get_parent(), range_scene, "into the range, so a reset clears it")
	right.release()
