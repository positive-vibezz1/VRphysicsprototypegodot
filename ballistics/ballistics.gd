class_name Ballistics
extends Node
## Autoload that owns the pools: bullets, casings, bullet holes and sounds. Nothing is created after startup.

const BULLET_SCENE := "res://ballistics/bullet.tscn"
const CASING_SCENE := "res://ballistics/casing.tscn"
const BULLET_COUNT := 32
const CASING_COUNT := 48
const HOLE_COUNT := 64
const SOUND_COUNT := 6

signal bullet_hit(collider: Object, energy: float)

static var pool: Ballistics

var _bullets: Array[Bullet] = []
var _casings: Array[Casing] = []
var _holes: Array[MeshInstance3D] = []
var _sounds: Array[AudioStreamPlayer3D] = []
var _next_bullet := 0
var _next_casing := 0
var _next_hole := 0
var _next_sound := 0
var _bang: AudioStreamWAV
var _click: AudioStreamWAV


func _ready() -> void:
	pool = self
	for i: int in BULLET_COUNT:
		var bullet: Bullet = (load(BULLET_SCENE) as PackedScene).instantiate()
		add_child(bullet)
		bullet.park()
		_bullets.append(bullet)
	for i: int in CASING_COUNT:
		var casing: Casing = (load(CASING_SCENE) as PackedScene).instantiate()
		add_child(casing)
		casing.park()
		_casings.append(casing)

	var hole_mesh := QuadMesh.new()
	hole_mesh.size = Vector2(0.012, 0.012)
	var hole_material := StandardMaterial3D.new()
	hole_material.albedo_color = Color(0.02, 0.02, 0.02)
	hole_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	hole_mesh.material = hole_material
	for i: int in HOLE_COUNT:
		var hole := MeshInstance3D.new()
		hole.mesh = hole_mesh
		hole.visible = false
		add_child(hole)
		_holes.append(hole)

	_bang = _make_noise_burst(0.35, 0.03)
	_click = _make_noise_burst(0.015, 0.003)
	for i: int in SOUND_COUNT:
		var sound := AudioStreamPlayer3D.new()
		sound.unit_size = 8.0
		add_child(sound)
		_sounds.append(sound)


func fire_bullet(cartridge: CartridgeSpec, from: Vector3, velocity: Vector3) -> Bullet:
	var bullet := _bullets[_next_bullet]
	_next_bullet = (_next_bullet + 1) % BULLET_COUNT
	bullet.launch(cartridge, from, velocity)
	return bullet


func eject_casing(
	cartridge: CartridgeSpec, from: Vector3, orientation: Basis, velocity: Vector3, spin: Vector3, live: bool
) -> Casing:
	var casing := _casings[_next_casing]
	_next_casing = (_next_casing + 1) % CASING_COUNT
	casing.launch(cartridge, from, orientation, velocity, spin, live)
	return casing


func on_bullet_hit(bullet: Bullet, position: Vector3, normal: Vector3, collider: Object, energy: float) -> void:
	bullet.park()
	play_click(position)
	bullet_hit.emit(collider, energy)
	# Moving targets would leave the hole floating, so only the static world keeps them.
	if collider is StaticBody3D and normal.length_squared() > 0.5:
		var hole := _holes[_next_hole]
		_next_hole = (_next_hole + 1) % HOLE_COUNT
		var up := Vector3.UP if absf(normal.y) < 0.95 else Vector3.RIGHT
		hole.global_transform = Transform3D(Basis.looking_at(-normal, up), position + normal * 0.002)
		hole.visible = true


## Louder with recoil and sharper with muzzle pressure: 5.56 cracks, 9 mm thumps.
func play_shot(position: Vector3, shot: GasSim.Shot) -> void:
	var pitch := clampf(sqrt(shot.muzzle_pressure / 6.0e7), 0.6, 1.5)
	_play(_bang, position, clampf(shot.breech_impulse / 6.5, 0.3, 1.0), pitch)


func play_click(position: Vector3) -> void:
	_play(_click, position, 0.4)


## Removes bullets, casings and holes left over from before a scene reload.
func clear() -> void:
	for bullet: Bullet in _bullets:
		bullet.park()
	for casing: Casing in _casings:
		casing.park()
	for hole: MeshInstance3D in _holes:
		hole.visible = false


func _play(stream: AudioStream, position: Vector3, volume: float, pitch := 1.0) -> void:
	var sound := _sounds[_next_sound]
	_next_sound = (_next_sound + 1) % SOUND_COUNT
	sound.stream = stream
	sound.global_position = position
	sound.volume_db = linear_to_db(volume)
	sound.pitch_scale = pitch
	sound.play()


## Decaying white noise, because the project has no audio assets yet.
func _make_noise_burst(duration: float, decay: float) -> AudioStreamWAV:
	var rate := 22050
	var samples := int(duration * rate)
	var data := PackedByteArray()
	data.resize(samples * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = samples
	var smoothed := 0.0
	for i: int in samples:
		smoothed = lerpf(smoothed, rng.randf_range(-1.0, 1.0), 0.5)
		data.encode_s16(i * 2, int(smoothed * exp(-float(i) / rate / decay) * 32000.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.data = data
	return wav
