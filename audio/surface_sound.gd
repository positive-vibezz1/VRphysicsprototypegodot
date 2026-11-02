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
## Radius of what touches in a hit, about a corner or an edge, in m.
const CONTACT_RADIUS := 0.01
## 1 - v^2 for a Poisson's ratio v of about 0.3, which most solids are near.
const POISSON_TERM := 0.91
## Most highs a voice's filter is asked to take off a take, in dB, for a contact much longer than the take's.
const MOST_DULLING := 40.0
## When loose parts knock together after a hit, in seconds after it, and how fast each knock dies.
const RATTLE_FROM := 0.006
const RATTLE_TO := 0.04
const RATTLE_DECAY := 0.0008

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
## A thing made of many parts has clusters of modes where a single piece has one, and that's what separates a knock from
## a ring: each mode here becomes three this far apart, as a share of its frequency.
@export var mode_spread := 0.0
## Loose parts knocking together just after the hit: how many, and how loud next to the hit.
@export var rattles := 0
@export var rattle_level := 0.0
## kg/m3. What a wall of it weighs, and how much a surrounding liquid weighs it down.
@export var density := 2400.0
## Young's modulus in Pa. How stiff it is, which sets how long a hit stays in contact.
@export var stiffness := 3.0e10
## Share of the sound hitting it that doesn't come back.
@export var absorption := 0.02


## How long two things stay in contact when they hit, by Hertz. Stiffer, lighter and faster all make it shorter.
static func contact_time(a: SurfaceSound, b: SurfaceSound, mass: float, speed: float) -> float:
	var combined := 1.0 / (POISSON_TERM / a.stiffness + POISSON_TERM / b.stiffness)
	return 2.87 * pow(mass * mass / (CONTACT_RADIUS * combined * combined * maxf(speed, 0.01)), 0.2)


## A dense medium loads what's ringing in it with its own weight, which lowers the pitch. Nothing you'd notice in air.
func pitch_for(mass: float, around_density := 0.0) -> float:
	var size := 1.0 if mass <= 0.0 else clampf(pow(reference_mass / mass, 1.0 / 3.0), LOWEST_PITCH, HIGHEST_PITCH)
	return size / sqrt(1.0 + around_density / density)


## Whether a contact this long is nearer the hard take than the soft one.
func is_hard(contact: float) -> bool:
	return contact < sqrt(hard_contact * soft_contact)


## How much the highs of the nearest take must lose to sound like a contact this long, in dB at this frequency.
func dulling(contact: float, frequency: float) -> float:
	var baked := hard_contact if is_hard(contact) else soft_contact
	return minf(maxf(_contact_loss(contact, frequency) - _contact_loss(baked, frequency), 0.0), MOST_DULLING)


static func _contact_loss(contact: float, frequency: float) -> float:
	return linear_to_db(1.0 + pow(frequency * contact, 2.0))


func bake(hard: bool, rng: RandomNumberGenerator) -> AudioStreamWAV:
	var contact := hard_contact if hard else soft_contact
	var length := noise_decay
	for mode: Vector3 in modes:
		length = maxf(length, 1.0 / mode.y)
	var count := maxi(int(length * TIME_CONSTANTS * MIX_RATE), int((RATTLE_TO + RATTLE_DECAY * TIME_CONSTANTS) * MIX_RATE))
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
		for partial: int in 3 if mode_spread > 0.0 else 1:
			# No two hits land in the same spot, so each take differs a little in tuning and in which modes it excites.
			var frequency := mode.x * rng.randf_range(0.97, 1.03) * (1.0 + (partial - 1) * mode_spread)
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

	for rattle: int in rattles:
		var at := int(rng.randf_range(RATTLE_FROM, RATTLE_TO) * MIX_RATE)
		var knock := rattle_level * rng.randf_range(0.4, 1.0)
		var knock_fade := exp(-1.0 / (RATTLE_DECAY * MIX_RATE))
		var knock_filtered := 0.0
		for i: int in range(at, mini(count, at + int(RATTLE_DECAY * TIME_CONSTANTS * MIX_RATE))):
			knock_filtered += (rng.randf_range(-knock, knock) - knock_filtered) * filter
			knock *= knock_fade
			mix[i] += knock_filtered

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
