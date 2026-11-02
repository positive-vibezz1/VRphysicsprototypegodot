class_name Sounds
extends Node
## The voices, and what a hit asks of them. Everything here runs on a physics event and not per tick: volume comes from
## the energy of the hit, take and pitch from its speed and the mass of what rings. Pooled, with the quietest voice
## giving way when they run out, so a burst of casings can't cut a gunshot short.

## A hit made a sound. Energy in J, and what it came out as where it was made.
signal played(surface: Surface, energy: float, volume: float, pitch: float)

enum Surface { CONCRETE, METAL, BRASS, WOOD, SOFT, WATER }

const SURFACE_PATHS: Array[String] = [
	"res://audio/concrete.tres", "res://audio/metal.tres", "res://audio/brass.tres", "res://audio/wood.tres",
	"res://audio/soft.tres", "res://audio/water.tres",
]
## Enough for a burst from the AR (5 shots ringing at once) with the casings and the steel over it.
const VOICE_COUNT := 16
const TAKES := 3
## A hit with this much energy is as loud as it gets: an AR dropped about 1 m.
const FULL_ENERGY := 25.0
## Loudness follows energy far more gently than sound power does, as an ear and a game's mix both do: this way a 40 mJ
## casing comes out about 19 dB under a 25 J dropped rifle, instead of the 28 dB of amplitude going as sqrt(energy).
const LOUDNESS_POWER := 1.0 / 3.0
## Distance in m below which a hit is at full volume. Inverse distance past it.
const UNIT_SIZE := 2.0
## Most sounds on their way to the ear at once. A wave takes 150 ms to get here from the far steel, so few are.
const WAITING_COUNT := 32
## Below this at the ear a sound's echo isn't worth working out: the first wall is at least 8 m away.
const QUIETEST_ECHO := 0.2
## 50 dB down at the ear isn't worth a voice.
const FAINTEST := 0.003
## At most one sound per surface in this many ticks, unless it's louder than the last.
const SURFACE_GAP := 2
const PITCH_SPREAD := 0.04
## How long everything is left to settle after a reload, in real seconds.
const SETTLE_TIME := 0.5

static var pool: Sounds

## A sound on its way to the ear.
class Waiting:
	var stream: AudioStream
	var position := Vector3.ZERO
	var level := 0.0
	var pitch := 1.0
	var unit_size := 0.0
	var shelf := 0.0
	var time_left := 0.0


var acoustics := Acoustics.new()

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
var _waiting: Array[Waiting] = []
var _waiting_count := 0


func _ready() -> void:
	pool = self
	Medium.ambient = load("res://audio/air_medium.tres")
	add_child(acoustics)
	for i: int in WAITING_COUNT:
		_waiting.append(Waiting.new())
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
		voice.bus = Acoustics.BUS
		voice.attenuation_filter_cutoff_hz = Acoustics.HIGH_BAND
		add_child(voice)
		_voices.append(voice)
	# Several full volume sounds can land on one sample, and clipping sounds far worse than a brief duck.
	AudioServer.add_bus_effect(0, AudioEffectHardLimiter.new())


## In world time, since a sound wave slows along with everything else in bullet time.
func _physics_process(delta: float) -> void:
	for i: int in range(_waiting_count - 1, -1, -1):
		var sound := _waiting[i]
		sound.time_left -= delta
		if sound.time_left <= 0.0:
			_start(sound.stream, sound.position, sound.level, sound.pitch, sound.unit_size, sound.shelf)
			_waiting_count -= 1
			_waiting[i] = _waiting[_waiting_count]
			_waiting[_waiting_count] = sound


static func loudness(energy: float) -> float:
	return clampf(pow(maxf(energy, 0.0) / FULL_ENERGY, LOUDNESS_POWER), 0.0, 1.0)


static func surface_of(collider: Object) -> Surface:
	return collider.get_meta(&"surface", Surface.CONCRETE) if collider else Surface.CONCRETE


## The baked take of a surface, for tests and tools.
func stream_of(surface: Surface, hard: bool, take: int) -> AudioStreamWAV:
	return _streams[surface * TAKES * 2 + take + (TAKES if hard else 0)]


func sound_of(surface: Surface) -> SurfaceSound:
	return _surfaces[surface]


## Rings one surface, hit by another. A mass is of the body, or 0 for something that doesn't give, like part of the world.
func impact(position: Vector3, surface: Surface, energy: float, speed: float, mass := 0.0, against := Surface.CONCRETE, against_mass := 0.0) -> void:
	var sound := _surfaces[surface]
	var volume := loudness(energy) * sound.level
	var frame := Engine.get_physics_frames()
	if frame < _quiet_until or (frame < _next_frame[surface] and volume <= _last_volume[surface]):
		return
	var take := _next_take[surface]
	var moving := mass * against_mass / (mass + against_mass) if mass > 0.0 and against_mass > 0.0 else maxf(mass, against_mass)
	var contact := SurfaceSound.contact_time(sound, _surfaces[against], moving, speed)
	var pitch := sound.pitch_for(mass, MediumVolume.medium_at(position).density) * _rng.randf_range(1.0 - PITCH_SPREAD, 1.0 + PITCH_SPREAD)
	if not play(stream_of(surface, sound.is_hard(contact), take), position, volume, pitch, UNIT_SIZE, sound.dulling(contact, Acoustics.HIGH_BAND)):
		return
	_next_take[surface] = (take + 1) % TAKES
	_next_frame[surface] = frame + SURFACE_GAP
	_last_volume[surface] = volume
	played.emit(surface, energy, volume, pitch)
	if DebugLog.due(&"sound", 0.1):
		DebugLog.event("sound", "%s on %s %.3f J at %.1f m/s, %.2f ms contact: %.0f dB, pitch %.2f, %.0f dB and %.0f dB of highs on the way, %.0f ms late" % [
			Surface.keys()[surface], Surface.keys()[against], energy, speed, contact * 1000.0, linear_to_db(volume), pitch,
			linear_to_db(acoustics.gain), acoustics.shelf, acoustics.delay * 1000.0
		])


## Rings what a hitter of this mass struck. Only a share of the energy gets into it: the lighter the hitter is next to
## it, the less, so a casing doesn't shake the floor. A static surface counts as its reference mass.
func impact_on(collider: Object, position: Vector3, energy: float, speed: float, hitter_mass: float, hitter: Surface) -> void:
	var surface := surface_of(collider)
	var body := collider as RigidBody3D
	var struck_mass := body.mass if body else _surfaces[surface].reference_mass
	impact(position, surface, energy * hitter_mass / (hitter_mass + struck_mass), speed, body.mass if body else 0.0, hitter, hitter_mass)


## Something padded coming down on something: a foot on the ground, or fingers closing on a gun.
func soft_hit(position: Vector3, mass: float, speed: float, on: Object) -> void:
	var energy := 0.5 * mass * speed * speed
	var body := on as RigidBody3D
	impact(position, Surface.SOFT, energy, speed, mass, surface_of(on), body.mass if body else 0.0)
	impact_on(on, position, energy, speed, mass, Surface.SOFT)


## Sends a sound on its way to the ear, and its echoes if it's loud enough to have any. Returns whether any of it will
## be heard. Dull is how much of its highs to take off to start with, in dB.
func play(stream: AudioStream, position: Vector3, volume: float, pitch := 1.0, unit_size := UNIT_SIZE, dull := 0.0) -> bool:
	acoustics.trace(position)
	var heard := _send(stream, position, volume * acoustics.gain, pitch, unit_size, acoustics.delay, acoustics.shelf - dull)
	var level := volume * acoustics.open_gain
	if level >= QUIETEST_ECHO:
		for i: int in acoustics.find_echoes(position):
			var echo_position := acoustics.echo_positions[i]
			var echo := level * acoustics.echo_levels[i]
			heard = _send(stream, echo_position, echo, pitch, unit_size, acoustics.echo_delays[i], acoustics.echo_shelves[i] - dull) or heard
	return heard


## Silences everything while a freshly loaded scene settles onto its tables.
func hush() -> void:
	_quiet_until = Engine.get_physics_frames() + int(SETTLE_TIME * Engine.physics_ticks_per_second)
	_waiting_count = 0
	for voice: AudioStreamPlayer3D in _voices:
		voice.stop()


## How many sounds are still on their way.
func waiting_count() -> int:
	return _waiting_count


func _send(stream: AudioStream, position: Vector3, level: float, pitch: float, unit_size: float, delay: float, shelf: float) -> bool:
	if _heard_level(position, level, unit_size) < FAINTEST:
		return false
	if delay * Engine.physics_ticks_per_second < Engine.time_scale:
		return _start(stream, position, level, pitch, unit_size, shelf)
	if _waiting_count == WAITING_COUNT:
		return false
	var sound := _waiting[_waiting_count]
	_waiting_count += 1
	sound.stream = stream
	sound.position = position
	sound.level = level
	sound.pitch = pitch
	sound.unit_size = unit_size
	sound.shelf = shelf
	sound.time_left = delay
	return true


func _start(stream: AudioStream, position: Vector3, level: float, pitch: float, unit_size: float, shelf: float) -> bool:
	var heard := _heard_level(position, level, unit_size)
	var index := _voice_for(heard)
	if index < 0:
		return false
	var voice := _voices[index]
	_heard[index] = heard
	voice.stream = stream
	voice.global_position = position
	voice.volume_db = linear_to_db(level)
	voice.pitch_scale = pitch
	voice.unit_size = unit_size
	voice.panning_strength = acoustics.panning
	# Godot scales its filter by how far the sound is from full volume, so this is what gives the shelf asked for.
	voice.attenuation_filter_db = clampf(shelf / (1.0 - minf(heard, 0.9)), -80.0, 0.0)
	voice.play()
	return true


func _heard_level(position: Vector3, level: float, unit_size: float) -> float:
	return level * minf(unit_size / maxf(acoustics.distance_to(position), 0.01), 1.0)


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
