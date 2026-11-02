class_name Sounds
extends Node
## The voices, and what a hit asks of them. Everything here runs on a physics event and not per tick: volume comes from
## the energy of the hit, take and pitch from its speed and the mass of what rings. Pooled, with the quietest voice
## giving way when they run out, so a burst of casings can't cut a gunshot short.

## A sound got a voice. Energy in J, and what it came out as.
signal played(surface: Surface, energy: float, volume: float, pitch: float)

enum Surface { CONCRETE, METAL, BRASS, WOOD, SOFT }

const SURFACE_PATHS: Array[String] = [
	"res://audio/concrete.tres", "res://audio/metal.tres", "res://audio/brass.tres", "res://audio/wood.tres",
	"res://audio/soft.tres",
]
## Enough for a burst from the AR (5 shots ringing at once) with the casings and the steel over it.
const VOICE_COUNT := 16
const TAKES := 3
## A hit with this much energy is as loud as it gets: an AR dropped about 1 m.
const FULL_ENERGY := 25.0
## Loudness follows energy far more gently than sound power does, as an ear and a game's mix both do: this way a 40 mJ
## casing comes out about 19 dB under a 25 J dropped rifle, instead of the 28 dB of amplitude going as sqrt(energy).
const LOUDNESS_POWER := 1.0 / 3.0
## Above this the contact is short enough for the bright take.
const HARD_SPEED := 2.0
## Distance in m below which a hit is at full volume. Inverse distance past it.
const UNIT_SIZE := 2.0
## What air takes off the highs per meter, in dB: about what it does to 5 to 10 kHz. Godot's filter also dulls anything
## with a low volume, so this keeps a casing right by the ear bright while a steel plate far off still loses its edge.
const AIR_DAMPING := 0.2
## 50 dB down at the ear isn't worth a voice.
const FAINTEST := 0.003
## At most one sound per surface in this many ticks, unless it's louder than the last.
const SURFACE_GAP := 2
const PITCH_SPREAD := 0.04
## How long everything is left to settle after a reload, in real seconds.
const SETTLE_TIME := 0.5

static var pool: Sounds

var _surfaces: Array[SurfaceSound] = []
var _streams: Array[AudioStreamWAV] = []
var _next_take := PackedInt32Array()
var _voices: Array[AudioStreamPlayer3D] = []
## What each voice's sound came to at the ear when it started.
var _heard := PackedFloat32Array()
var _next_frame := PackedInt64Array()
var _last_volume := PackedFloat32Array()
var _quiet_until := 0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	pool = self
	# Seeded so every run bakes the same sounds, to tune by ear against.
	var bake_rng := RandomNumberGenerator.new()
	bake_rng.seed = 1
	for path: String in SURFACE_PATHS:
		var surface: SurfaceSound = load(path)
		_surfaces.append(surface)
		for take: int in TAKES * 2:
			_streams.append(surface.bake(take >= TAKES, bake_rng))
	_next_take.resize(_surfaces.size())
	_next_frame.resize(_surfaces.size())
	_last_volume.resize(_surfaces.size())
	_heard.resize(VOICE_COUNT)
	for i: int in VOICE_COUNT:
		var voice := AudioStreamPlayer3D.new()
		# Saves every voice a physics query per tick looking for a reverb area, and nothing uses those.
		voice.area_mask = 0
		voice.max_db = 0.0
		add_child(voice)
		_voices.append(voice)
	# Several full volume sounds can land on one sample, and clipping sounds far worse than a brief duck.
	AudioServer.add_bus_effect(0, AudioEffectHardLimiter.new())


static func loudness(energy: float) -> float:
	return clampf(pow(maxf(energy, 0.0) / FULL_ENERGY, LOUDNESS_POWER), 0.0, 1.0)


## The baked take of a surface, for tests and tools.
func stream_of(surface: Surface, hard: bool, take: int) -> AudioStreamWAV:
	return _streams[surface * TAKES * 2 + take + (TAKES if hard else 0)]


func sound_of(surface: Surface) -> SurfaceSound:
	return _surfaces[surface]


## Rings one surface. Mass is of the body ringing, or 0 for part of the world.
func impact(position: Vector3, surface: Surface, energy: float, speed: float, mass := 0.0) -> void:
	var sound := _surfaces[surface]
	var volume := loudness(energy) * sound.level
	var frame := Engine.get_physics_frames()
	if frame < _quiet_until or (frame < _next_frame[surface] and volume <= _last_volume[surface]):
		return
	var take := _next_take[surface]
	var pitch := sound.pitch_for(mass) * _rng.randf_range(1.0 - PITCH_SPREAD, 1.0 + PITCH_SPREAD)
	if not play(stream_of(surface, speed > HARD_SPEED, take), position, volume, pitch):
		return
	_next_take[surface] = (take + 1) % TAKES
	_next_frame[surface] = frame + SURFACE_GAP
	_last_volume[surface] = volume
	played.emit(surface, energy, volume, pitch)
	if DebugLog.due(&"sound", 0.1):
		DebugLog.event("sound", "%s %.3f J at %.1f m/s: %.0f dB, pitch %.2f" % [Surface.keys()[surface], energy, speed, linear_to_db(volume), pitch])


## Rings what a hitter of this mass struck. Only a share of the energy gets into it: the lighter the hitter is next to
## it, the less, so a casing doesn't shake the floor. A static surface counts as its reference mass.
func impact_on(collider: Object, position: Vector3, energy: float, speed: float, hitter_mass: float) -> void:
	var surface: Surface = collider.get_meta(&"surface", Surface.CONCRETE) if collider else Surface.CONCRETE
	var body := collider as RigidBody3D
	var struck_mass := body.mass if body else _surfaces[surface].reference_mass
	impact(position, surface, energy * hitter_mass / (hitter_mass + struck_mass), speed, body.mass if body else 0.0)


## Something padded coming down on something: a foot on the ground, or fingers closing on a gun.
func soft_hit(position: Vector3, mass: float, speed: float, on: Object) -> void:
	var energy := 0.5 * mass * speed * speed
	impact(position, Surface.SOFT, energy, speed, mass)
	impact_on(on, position, energy, speed, mass)


## Starts a sound if it's worth a voice. Returns whether it got one.
func play(stream: AudioStream, position: Vector3, volume: float, pitch := 1.0, unit_size := UNIT_SIZE) -> bool:
	var camera := get_viewport().get_camera_3d()
	var distance := camera.global_position.distance_to(position) if camera else 0.0
	var heard := volume * minf(unit_size / maxf(distance, 0.01), 1.0)
	if heard < FAINTEST:
		return false
	var index := _voice_for(heard)
	if index < 0:
		return false
	var voice := _voices[index]
	_heard[index] = heard
	voice.stream = stream
	voice.global_position = position
	voice.volume_db = linear_to_db(volume)
	voice.pitch_scale = pitch
	voice.unit_size = unit_size
	voice.attenuation_filter_db = -minf(distance * AIR_DAMPING, 24.0)
	voice.play()
	return true


## Silences impacts while a freshly loaded scene settles onto its tables.
func hush() -> void:
	_quiet_until = Engine.get_physics_frames() + int(SETTLE_TIME * Engine.physics_ticks_per_second)


## A free voice, or else the quietest one if it's quieter than this sound. -1 if this sound is the quietest of them all.
func _voice_for(heard: float) -> int:
	var quietest := -1
	var lowest := heard
	for i: int in VOICE_COUNT:
		if not _voices[i].playing:
			return i
		if _heard[i] < lowest:
			lowest = _heard[i]
			quietest = i
	return quietest
