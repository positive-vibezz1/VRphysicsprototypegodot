class_name SurfaceSound
extends Resource
## What a surface sounds like when something hits it, by modal synthesis. A struck solid rings at a set of frequencies
## of its own, each dying away at its own rate. Baked once at startup, since a voice per sample in GDScript would never
## fit a Quest 3's budget. The rest comes from the hit: its energy sets the volume, and the struck body's mass the pitch.

const MIX_RATE := 22050
## A mode is computed down to 60 dB under its start, which takes this many time constants.
const TIME_CONSTANTS := 6.9
## Pitch goes as size for the same shape, so as the cube root of mass. Past these a stretched sound stops sounding real.
const LOWEST_PITCH := 0.5
const HIGHEST_PITCH := 2.5

## Each mode is x frequency in Hz, y decay per second, z level.
@export var modes: PackedVector3Array
## The body these frequencies are for, in kg. Also how much of a static surface a hit has to shake.
@export var reference_mass := 1.0
@export var level := 1.0
## How long a hit stays in contact, in seconds. It filters the sound: a mode much faster than the contact hardly starts
## ringing, so a hard hit (short contact) is bright and a gentle one dull.
@export var soft_contact := 0.0005
@export var hard_contact := 0.0001
## The scrape of the contact itself: white noise through the same filter.
@export var noise_level := 0.3
@export var noise_decay := 0.003


func pitch_for(mass: float) -> float:
	return 1.0 if mass <= 0.0 else clampf(pow(reference_mass / mass, 1.0 / 3.0), LOWEST_PITCH, HIGHEST_PITCH)


func bake(hard: bool, rng: RandomNumberGenerator) -> AudioStreamWAV:
	var contact := hard_contact if hard else soft_contact
	var length := noise_decay
	for mode: Vector3 in modes:
		length = maxf(length, 1.0 / mode.y)
	var count := int(length * TIME_CONSTANTS * MIX_RATE)
	var mix := PackedFloat32Array()
	mix.resize(count)

	var filter := 1.0 - exp(-TAU / (contact * MIX_RATE))
	var fade := exp(-1.0 / (noise_decay * MIX_RATE))
	var noise := noise_level
	var filtered := 0.0
	for i: int in mini(count, int(noise_decay * TIME_CONSTANTS * MIX_RATE)):
		filtered += (rng.randf_range(-noise, noise) - filtered) * filter
		noise *= fade
		mix[i] = filtered

	for mode: Vector3 in modes:
		# No two hits land in the same spot, so each take differs a little in tuning and in which modes it excites.
		var frequency := mode.x * rng.randf_range(0.97, 1.03)
		var ring := frequency * contact
		var gain := mode.z * rng.randf_range(0.7, 1.0) / (1.0 + ring * ring)
		var decay := exp(-mode.y / MIX_RATE)
		var step := TAU * frequency / MIX_RATE
		# The two term recurrence of a decaying sine, which is much cheaper than calling sin() per sample.
		var factor := 2.0 * decay * cos(step)
		var damping := decay * decay
		var before := 0.0
		var now := gain * decay * sin(step)
		for i: int in mini(count, int(TIME_CONSTANTS / mode.y * MIX_RATE)):
			mix[i] += now
			var next := factor * now - damping * before
			before = now
			now = next

	var peak := 0.0
	for sample: float in mix:
		peak = maxf(peak, absf(sample))
	var data := PackedByteArray()
	data.resize(count * 2)
	var scale := 29000.0 / peak
	for i: int in count:
		data.encode_s16(i * 2, int(mix[i] * scale))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = MIX_RATE
	wav.data = data
	return wav
