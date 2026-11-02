class_name Acoustics
extends Node
## What happens to a sound between where it's made and the ear, in real equations: how long it takes, what the air and
## anything else in the way take off it, and what the surroundings throw back. A sound is traced once, when it starts,
## which costs a few rays, and one more ray each tick keeps track of the room.

const BUS := &"World"
## An ear is full of air, so this is what any sound has to match to get in.
const EAR_IMPEDANCE := 1.204 * 343.0
## The most a body's energy can radiate faster in a denser medium, as a share of power in air. In a thin gas the same
## vibration radiates in proportion to impedance, but in water it can't be 3600 times as loud on the same energy.
const MOST_RADIATION := 30.0
## How much less of the highs gets through an ear under water, in dB: it hears mostly through the skull.
const SKULL_LOSS := 20.0
## The two bands everything is worked out for. Above HIGH_BAND is what a voice's filter can cut.
const LOW_BAND := 500.0
const HIGH_BAND := 4000.0
## Nearer than this nothing is in the way: it's a hand or something else the person is touching.
const NEAREST_BLOCKED := 1.0
## A ray stops this short of the sound, which is mostly right on a surface.
const MARGIN := 0.05
## Where sound might bend around what's blocking it, nearest first, in meters from where the ray hit.
const DETOURS: Array[float] = [0.5, 1.0, 2.0, 4.0, 8.0]
const MOST_DETOUR_SEARCHES := 1
## What a barrier takes off at most, in dB, whatever its size: past this, what's left comes over it through the air.
const MOST_BARRIER_LOSS := 24.0
## How far the room is looked for, past the range's 55 m berm.
const PROBE_RANGE := 70.0
const PROBES: Array[Vector3] = [
	Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 1, 0), Vector3(0, -1, 0), Vector3(0, 0, 1), Vector3(0, 0, -1),
	Vector3(0.577, 0.577, 0.577), Vector3(-0.577, 0.577, 0.577), Vector3(0.577, 0.577, -0.577), Vector3(-0.577, 0.577, -0.577),
	Vector3(0.577, -0.577, 0.577), Vector3(-0.577, -0.577, 0.577), Vector3(0.577, -0.577, -0.577), Vector3(-0.577, -0.577, -0.577),
]
## Average round trip of Godot's reverb combs, which are Freeverb's, in seconds, and the range of their feedback.
const COMB_LOOP := 0.0316
const LEAST_FEEDBACK := 0.7
const FEEDBACK_RANGE := 0.28
## Godot's reverb is Freeverb, whose combs start to sound like a metal box past about this.
const MOST_WET := 0.3
## Distance the wet level is set for: Sounds.UNIT_SIZE, where a hit is at full volume.
const WET_DISTANCE := 1.0
## An echo this much later than the direct sound is heard as its own sound: 50 ms, the limit of the ear's precedence
## effect. Anything sooner merges with the direct sound, and the reverb stands in for it.
const SHORTEST_ECHO := 17.0
const MOST_ECHOES := 2
## Steeper than this a surface can throw a sound back level. The floor's own echo arrives within a few ms.
const MOST_ECHO_TILT := 0.7

var has_listener := false
var listener := Vector3.ZERO
var ear_medium: Medium

## What trace() found.
var delay := 0.0
var gain := 1.0
## The gain without what's blocking the way, which an echo doesn't have to come through.
var open_gain := 1.0
var shelf := 0.0
var panning := 1.0

## What find_echoes() found: where each one seems to come from, how much is left of it and when it arrives.
var echo_positions := PackedVector3Array()
var echo_levels := PackedFloat32Array()
var echo_delays := PackedFloat32Array()
var echo_shelves := PackedFloat32Array()

## What the last sweep of the room found.
var reverb_seconds := 0.0
var wet := 0.0

var _ray := RayCast3D.new()
var _reverb := AudioEffectReverb.new()
var _bus := 0
var _next_probe := 0
## Negative where the ray found nothing.
var _distances := PackedFloat32Array()
var _absorptions := PackedFloat32Array()
var _points := PackedVector3Array()
var _normals := PackedVector3Array()
var _ways := PackedVector3Array()
var _searches := 0
var _last_detour := -1.0
var _ear_share := 1.0


## Eyring's reverberation time, from a room's mean free path, the absorption of its surfaces and the speed of sound.
static func reverberation(free_path: float, absorption: float, speed: float) -> float:
	return 13.8 * free_path / (speed * -log(1.0 - minf(absorption, 0.99)))


## The reverb's room size that gives a decay of this many seconds. Below about 0.6 s its combs can't go any shorter.
static func room_size(seconds: float) -> float:
	return clampf((pow(10.0, -3.0 * COMB_LOOP / seconds) - LEAST_FEEDBACK) / FEEDBACK_RANGE, 0.0, 1.0)


## Reverberant to direct sound at WET_DISTANCE, as an amplitude. It's Sabine's 16 pi r^2 / room constant, with the room's
## surface worked out from its mean free path as if it were a sphere.
static func reverberant_share(free_path: float, absorption: float) -> float:
	var open := minf(absorption, 0.99)
	return sqrt(7.1 * pow(WET_DISTANCE / free_path, 2.0) * (1.0 - open) / open)


## Berger's mass law for what a wall lets through, in dB. A wall's weight per area is what stops sound.
static func mass_law(frequency: float, surface_mass: float) -> float:
	return maxf(linear_to_db(frequency * surface_mass) - 47.0, 0.0)


## Maekawa's chart for sound bending over a barrier, in dB, from how much longer the way around is.
static func barrier_loss(frequency: float, detour: float, speed: float) -> float:
	return minf(linear_to_db(3.0 + 40.0 * detour * frequency / speed) * 0.5, MOST_BARRIER_LOSS)


func _ready() -> void:
	ear_medium = Medium.ambient
	_ray.enabled = false
	_ray.collision_mask = 1
	add_child(_ray)
	_ways.resize(3)
	_distances.resize(PROBES.size())
	_distances.fill(-1.0)
	_absorptions.resize(PROBES.size())
	_points.resize(PROBES.size())
	_normals.resize(PROBES.size())
	_bus = AudioServer.bus_count
	AudioServer.add_bus()
	AudioServer.set_bus_name(_bus, BUS)
	_reverb.predelay_feedback = 0.0
	_reverb.dry = 1.0
	_reverb.wet = 0.0
	AudioServer.add_bus_effect(_bus, _reverb)
	AudioServer.set_bus_effect_enabled(_bus, 0, false)


func _physics_process(_delta: float) -> void:
	_searches = 0
	var camera := get_viewport().get_camera_3d()
	has_listener = camera != null
	if not camera:
		return
	listener = camera.global_position
	ear_medium = MediumVolume.medium_at(listener)
	_ear_share = Medium.transmission(ear_medium.impedance(), EAR_IMPEDANCE)
	# The ear places a sound by the time between reaching one side and the other, which a faster medium cuts.
	panning = minf(Medium.ambient.sound_speed / ear_medium.sound_speed, 1.0)
	_probe()


func distance_to(point: Vector3) -> float:
	return listener.distance_to(point) if has_listener else 0.0


## Takes a sound made at this point to the ear.
func trace(source: Vector3) -> void:
	delay = 0.0
	gain = 1.0
	open_gain = 1.0
	shelf = 0.0
	if not has_listener:
		return
	var ambient := Medium.ambient
	var through_ambient := source.distance_to(listener)
	var distance := through_ambient
	var made_in := ambient
	for volume: MediumVolume in MediumVolume.all:
		var length := volume.path_length(source, listener)
		if length <= 0.0:
			continue
		through_ambient -= length
		delay += length / volume.medium.sound_speed
		shelf -= length * volume.medium.absorption
		if volume.contains(source):
			made_in = volume.medium
		elif not volume.contains(listener):
			# In one side and out the other: two boundaries, so one whole transmission as an amplitude.
			gain *= Medium.transmission(ambient.impedance(), volume.medium.impedance())
	delay += through_ambient / ambient.sound_speed
	shelf -= through_ambient * ambient.absorption
	if ear_medium.is_liquid:
		shelf -= SKULL_LOSS
	var radiated := minf(made_in.impedance() / EAR_IMPEDANCE, MOST_RADIATION)
	gain *= sqrt(radiated * Medium.transmission(made_in.impedance(), ear_medium.impedance()) * _ear_share)
	open_gain = gain
	if gain > 0.0 and distance > NEAREST_BLOCKED:
		_block(source, distance)


## Fills in the echoes of a sound made at this point, and returns how many. By the method of images: what a flat wall
## throws back arrives as if from a copy of the sound mirrored behind it, so it's played from there.
func find_echoes(source: Vector3) -> int:
	var ambient := Medium.ambient
	if not has_listener or ear_medium != ambient:
		return 0
	var direct := source.distance_to(listener)
	var count := 0
	echo_positions.resize(MOST_ECHOES)
	echo_levels.resize(MOST_ECHOES)
	echo_delays.resize(MOST_ECHOES)
	echo_shelves.resize(MOST_ECHOES)
	for i: int in PROBES.size():
		var normal := _normals[i]
		if _distances[i] < 0.0 or absf(normal.y) > MOST_ECHO_TILT:
			continue
		var off_wall := (source - _points[i]).dot(normal)
		if off_wall <= 0.0:
			continue
		var image := source - normal * 2.0 * off_wall
		var path := image.distance_to(listener)
		if path - direct < SHORTEST_ECHO or (count > 0 and image.distance_to(echo_positions[0]) < 1.0):
			continue
		var bounce := listener + (image - listener) * (_points[i] - listener).dot(normal) / (image - listener).dot(normal)
		var inward := (bounce - listener).normalized()
		# The ray has to hit the wall where the sound bounces, or the wall doesn't reach that far.
		if not _cast(listener, bounce + inward * 0.1) or _ray.get_collision_point().distance_to(bounce) > 0.3:
			continue
		if _cast(source, bounce + (source - bounce).normalized() * 0.1):
			continue
		echo_positions[count] = image
		echo_levels[count] = sqrt(1.0 - _absorptions[i])
		echo_delays[count] = path / ambient.sound_speed
		echo_shelves[count] = -path * ambient.absorption
		count += 1
		if count == MOST_ECHOES:
			break
	return count


## What gets to the ear past whatever is in the way: through it by its weight or around it by the longer way, and the
## highs lose more on either. The louder way is the one that counts.
func _block(source: Vector3, distance: float) -> void:
	var inward := (source - listener) / distance
	var near_source := source - inward * MARGIN
	if not _cast(listener, near_source):
		return
	var front := _ray.get_collision_point()
	var blocker := _ray.get_collider()
	var thickness := front.distance_to(_ray.get_collision_point() if _cast(near_source, listener) else near_source)
	var surface_mass := maxf(thickness, MARGIN) * Sounds.pool.sound_of(Sounds.surface_of(blocker)).density
	var detour := _shortest_detour(near_source, front, inward, distance)
	var low := mass_law(LOW_BAND, surface_mass)
	var high := mass_law(HIGH_BAND, surface_mass)
	if detour >= 0.0:
		var speed := Medium.ambient.sound_speed
		low = minf(low, barrier_loss(LOW_BAND, detour, speed))
		high = minf(high, barrier_loss(HIGH_BAND, detour, speed))
	gain *= db_to_linear(-low)
	shelf -= maxf(high - low, 0.0)


## How much longer the shortest way over or around something is, or negative if there's none. Only once a tick, since
## sounds from behind the same cover tend to come in bursts: the rest go by the last one found.
func _shortest_detour(source: Vector3, front: Vector3, inward: Vector3, distance: float) -> float:
	if _searches >= MOST_DETOUR_SEARCHES:
		return _last_detour
	_searches += 1
	var side := inward.cross(Vector3.UP).normalized()
	_ways[0] = Vector3.UP
	_ways[1] = side
	_ways[2] = -side
	_last_detour = -1.0
	for offset: float in DETOURS:
		for way: Vector3 in _ways:
			var edge := front + way * offset
			if not _cast(listener, edge) and not _cast(edge, source):
				var detour := listener.distance_to(edge) + edge.distance_to(source) - distance
				_last_detour = detour if _last_detour < 0.0 else minf(_last_detour, detour)
		if _last_detour >= 0.0:
			break
	return _last_detour


## One ray a tick around the listener, about 6 times a second all the way around.
func _probe() -> void:
	var i := _next_probe
	if _cast(listener, listener + PROBES[i] * PROBE_RANGE):
		_points[i] = _ray.get_collision_point()
		_normals[i] = _ray.get_collision_normal()
		_distances[i] = listener.distance_to(_points[i])
		_absorptions[i] = Sounds.pool.sound_of(Sounds.surface_of(_ray.get_collider())).absorption
	else:
		_distances[i] = -1.0
	_next_probe = (i + 1) % PROBES.size()
	if _next_probe == 0:
		_update_room()


## A ray that finds nothing is sound that never comes back, as if it hit something that absorbs it all. Only what's
## around and above counts toward being enclosed, since the ground is under everything.
func _update_room() -> void:
	var hits := 0
	var path := 0.0
	var absorbed := 0.0
	var shortest := PROBE_RANGE
	var enclosing := 0
	var above := 0
	var surfaces := 0.0
	for i: int in PROBES.size():
		above += 1 if PROBES[i].y >= 0.0 else 0
		if _distances[i] < 0.0:
			absorbed += 1.0
			continue
		hits += 1
		path += _distances[i]
		absorbed += _absorptions[i]
		surfaces += _absorptions[i]
		shortest = minf(shortest, _distances[i])
		enclosing += 1 if PROBES[i].y >= 0.0 else 0
	var absorption := absorbed / PROBES.size()
	if hits == 0:
		wet = 0.0
		AudioServer.set_bus_effect_enabled(_bus, 0, false)
		return
	var free_path := path / hits
	var speed := ear_medium.sound_speed
	reverb_seconds = reverberation(free_path, absorption, speed)
	wet = minf(reverberant_share(free_path, absorption) * pow(float(enclosing) / above, 2.0), MOST_WET)
	_reverb.room_size = room_size(reverb_seconds)
	# Soft surfaces take the highs first.
	_reverb.damping = clampf(surfaces / hits * 2.0, 0.0, 1.0)
	_reverb.predelay_msec = clampf(2000.0 * shortest / speed, 20.0, 500.0)
	_reverb.wet = wet
	AudioServer.set_bus_effect_enabled(_bus, 0, wet > 0.02)


func _cast(from: Vector3, to: Vector3) -> bool:
	_ray.global_position = from
	_ray.target_position = to - from
	_ray.force_raycast_update()
	return _ray.is_colliding()
