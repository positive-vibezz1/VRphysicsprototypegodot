extends GutTest
## The parts of the gun models that follow the simulation.

const PISTOL_SCENE: PackedScene = preload("res://weapons/pistol/pistol.tscn")
const AR_SCENE: PackedScene = preload("res://weapons/ar/ar.tscn")


func test_ammo_counter_shows_chamber_and_magazine() -> void:
	var gun: Gun = add_child_autoqfree(PISTOL_SCENE.instantiate())
	var counter: Label3D = gun.get_node("Bolt/AmmoCounter")
	counter._process(0.0)
	assert_eq(counter.text, "18", "17 in the magazine and 1 chambered")
	gun.mag_well.magazine.take_round()
	counter._process(0.0)
	assert_eq(counter.text, "17")
	gun.chamber = Gun.Chamber.EMPTY
	counter._process(0.0)
	assert_eq(counter.text, "16")


func test_ar_counter_drops_a_removed_magazine() -> void:
	var gun: Gun = add_child_autoqfree(AR_SCENE.instantiate())
	var counter: Label3D = gun.get_node("Frame/AmmoCounter")
	counter._process(0.0)
	assert_eq(counter.text, "31")
	gun.release_magazine()
	counter._process(0.0)
	assert_eq(counter.text, "1", "only the chambered round is left")


func test_spring_compresses_as_the_bolt_runs_back() -> void:
	for setup: Array in [[PISTOL_SCENE, "Frame/RecoilSpring"], [AR_SCENE, "Frame/OpRodSpring"]]:
		var gun: Gun = add_child_autoqfree((setup[0] as PackedScene).instantiate())
		var spring: MeshInstance3D = gun.get_node(setup[1])
		spring._process(0.0)
		assert_almost_eq(spring.scale.z, 1.0, 0.001, "full length at rest")
		gun.bolt.position.z += gun.bolt_travel
		spring._process(0.0)
		assert_almost_eq(spring.scale.z, 1.0 - gun.bolt_travel / spring.length, 0.001, "shortened by the bolt's travel")
		assert_gt(spring.scale.z, 0.2, "still longer than its coils are thick")
