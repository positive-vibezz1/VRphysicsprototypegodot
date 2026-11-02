class_name GunshotSound
extends RefCounted
## The report of one gun, worked out from the gas still pushing when the bullet leaves the muzzle. That gas lets go
## about P V / (gamma - 1) of energy into the air at once, and blast scaling turns the energy into a length: how far the
## air has to be pushed before the gas has spent it. Everything else about the sound goes by that length, so a rifle's
## report comes out bigger and lower than a pistol's without being told to. Baked once for each kind of gun.

const MIX_RATE := 32000
const TAKES := 3
const LENGTH := 0.55
const ATMOSPHERE := 101325.0
const SOUND_SPEED := 343.0
## Energy that plays at full volume, about an AR's. A blast's amplitude goes as the cube root of its energy.
const FULL_ENERGY := 4200.0
## A shot stays at full volume out to here.
const UNIT_SIZE := 8.0
const PITCH_SPREAD := 0.02
## How hard a blast overdrives the air and any ear or microphone that hears it. Recorded guns all sound this way, and
## it's most of what makes one sound heavy instead of thin.
const OVERDRIVE := 2.5
## A bullet's length as a share of its width, about what both of these are.
const BULLET_SHAPE := 3.5
## When a bullet's own shock reaches the shooter, a moment after the muzzle's.
const CRACK_AT := 0.0015
## The jet's top frequency for a 9 mm bore. It goes as speed over width, and the gas leaves at much the same speed.
const JET_TOP := 7000.0
const WIDE_BORE := 0.009

static var _baked: Dictionary[String, GunshotSound] = {}

var energy := 0.0
## The length a blast of this energy scales with, in m.
var blast_radius := 0.0
## How long a bullet's shock lasts, 0 for a subsonic one.
var crack_time := 0.0
var level := 1.0
var takes: Array[AudioStreamWAV] = []

var _muzzle_pressure := 0.0
var _bore := 0.0
var _next_take := 0
var _rng := RandomNumberGenerator.new()


## Whitham's length of the N-wave a supersonic bullet drags along, as a time at 1 m. Faster and thinner is shorter, which
## is why a rifle cracks and a pistol doesn't. 0 for a bullet slower than sound.
static func crack_duration(speed: float, bore: float) -> float:
	var mach := speed / SOUND_SPEED
	if mach <= 1.0:
		return 0.0
	return 1.82 * mach * bore / (SOUND_SPEED * pow(mach * mach - 1.0, 0.375) * pow(BULLET_SHAPE * bore, 0.25))


## Only bakes the first time, as each kind of gun is used over and over and scenes get reloaded.
static func of(cartridge: CartridgeSpec, barrel_length: float, port: GasPortSpec, bolt_mass: float) -> GunshotSound:
	var key := "%s %.3f" % [cartridge.resource_path, barrel_length]
	if not _baked.has(key):
		var shot := GasSim.Shot.new()
		GasSim.simulate(cartridge, barrel_length, shot, port, bolt_mass)
		_baked[key] = GunshotSound.new(cartridge, barrel_length, shot)
	return _baked[key]


func _init(cartridge: CartridgeSpec, barrel_length: float, shot: GasSim.Shot) -> void:
	_muzzle_pressure = shot.muzzle_pressure
	energy = shot.muzzle_pressure * cartridge.bore_area() * barrel_length / (cartridge.gas_gamma - 1.0)
	blast_radius = pow(energy / ATMOSPHERE, 1.0 / 3.0)
	_bore = sqrt(4.0 * cartridge.bore_area() / PI)
	crack_time = crack_duration(shot.muzzle_velocity, _bore)
	level = minf(pow(energy / FULL_ENERGY, 1.0 / 3.0), 1.0)
	var bake_rng := RandomNumberGenerator.new()
	bake_rng.seed = hash(energy)
	for i: int in TAKES:
		takes.append(_bake(bake_rng))


func play(position: Vector3, shot: GasSim.Shot) -> void:
	var pitch := _rng.randf_range(1.0 - PITCH_SPREAD, 1.0 + PITCH_SPREAD)
	# A weak charge is a quieter shot, by the same cube root.
	var volume := level * pow(shot.muzzle_pressure / _muzzle_pressure, 1.0 / 3.0)
	Sounds.pool.play(takes[_next_take], position, minf(volume, 1.0), pitch, UNIT_SIZE)
	_next_take = (_next_take + 1) % TAKES


## Five parts, most lasting in proportion to the blast's length:
## The shock itself, Friedlander's waveform: an instant jump up, a fall past zero and a slower climb back. That jump is
## the crack.
## The cloud of gas, which overshoots and rings like a bubble as it settles to the air's pressure, dropping in pitch as
## it grows. That's the thump.
## The jet of gas still venting after it, turbulent noise that falls from a hiss to a roar.
## What the ground and the air scatter back afterward, the low roll that follows any shot outdoors.
## The bullet's own shock, right after, a jump up and down much shorter than all the rest.
func _bake(rng: RandomNumberGenerator) -> AudioStreamWAV:
	var count := int(LENGTH * MIX_RATE)
	var mix := PackedFloat32Array()
	mix.resize(count)
	var transit := blast_radius / SOUND_SPEED
	var ring := SOUND_SPEED / (TAU * blast_radius) * rng.randf_range(0.96, 1.04)
	var ring_time := 4.0 / ring
	var jet_time := 10.0 * transit
	var roar_time := 40.0 * transit
	var roll_time := 0.25 * pow(blast_radius, 0.5)
	var dt := 1.0 / MIX_RATE
	var phase := 0.0
	var jet_stage := 0.0
	var jet := 0.0
	var jet_top := JET_TOP * WIDE_BORE / _bore
	# Two filters in a row on the noises, as one alone leaves a hiss over the top of them that sounds like static.
	var roll_stage := 0.0
	var roll := 0.0
	for i: int in count:
		var t := i * dt
		var shock := (1.0 - t / transit) * exp(-1.5 * t / transit)
		phase += TAU * ring * (0.7 + 0.9 * exp(-t * ring / 1.5)) * dt
		var cloud := sin(phase) * exp(-t / ring_time)
		var jet_cutoff := 1500.0 + jet_top * exp(-t / jet_time)
		var jet_filter := 1.0 - exp(-TAU * jet_cutoff * dt)
		jet_stage += (rng.randf_range(-1.0, 1.0) - jet_stage) * jet_filter
		jet += (jet_stage - jet) * jet_filter
		var roll_cutoff := 250.0 + 500.0 * exp(-t / roll_time)
		var roll_filter := 1.0 - exp(-TAU * roll_cutoff * dt)
		roll_stage += (rng.randf_range(-1.0, 1.0) - roll_stage) * roll_filter
		roll += (roll_stage - roll) * roll_filter
		var sample := 0.9 * shock + 0.8 * cloud + 2.6 * jet * exp(-t / roar_time)
		sample += 0.5 * roll * exp(-t / roll_time) * (1.0 - exp(-t / 0.004))
		if crack_time > 0.0 and t >= CRACK_AT and t < CRACK_AT + crack_time:
			sample += 0.9 * (1.0 - 2.0 * (t - CRACK_AT) / crack_time)
		mix[i] = sample

	var data := PackedByteArray()
	data.resize(count * 2)
	var limit := tanh(OVERDRIVE * 1.2)
	for i: int in count:
		# Fades out the last 5 ms, in case any tail is left.
		var fade := minf((count - i) * dt / 0.005, 1.0)
		data.encode_s16(i * 2, int(tanh(OVERDRIVE * mix[i]) / limit * fade * 30000.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = MIX_RATE
	wav.data = data
	return wav
