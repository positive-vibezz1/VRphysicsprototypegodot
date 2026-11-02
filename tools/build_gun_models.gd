extends SceneTree
## Builds the gun models from CSG solids and bakes them to one mesh per moving part, one surface per material.
## Nothing here runs in the game: the scenes only load the baked .res files. After changing a model, run:
##   $GODOT --xr-mode off --path . -s res://tools/build_gun_models.gd
##
## Everything is written in the gun's own coordinates: muzzle toward -Z, right side +X, as in the gun scenes.
## Outlines are flat arrays of coordinate pairs. Most shapes are the intersection of two or three extruded views
## (side, front, top), which gives chiselled forms from short outlines. Cuts take the cutter's material on
## their walls, so a cut shows its own colour.

const MATERIALS := "res://weapons/parts/materials/"
const UNION := CSGShape3D.OPERATION_UNION
const CUT := CSGShape3D.OPERATION_SUBTRACTION
const INTERSECT := CSGShape3D.OPERATION_INTERSECTION
## The grip and mag well transforms from the gun scenes, so grips and wells line up with their collision shapes.
const RAKE_18 := Basis(Vector3(1, 0, 0), Vector3(0, 0.951057, -0.309017), Vector3(0, 0.309017, 0.951057))
const RAKE_8 := Basis(Vector3(1, 0, 0), Vector3(0, 0.990268, 0.139173), Vector3(0, -0.139173, 0.990268))

var shell: Material = load(MATERIALS + "shell.tres")
var graphite: Material = load(MATERIALS + "graphite.tres")
var rubber: Material = load(MATERIALS + "rubber.tres")
var steel: Material = load(MATERIALS + "steel.tres")
var accent: Material = load(MATERIALS + "accent.tres")
var glow: Material = load(MATERIALS + "glow.tres")
var brass: Material = load(MATERIALS + "brass.tres")

var _parent: CSGShape3D


func _initialize() -> void:
	await process_frame
	await _bake("res://weapons/pistol/models/frame.res", Vector3.ZERO, _pistol_frame)
	await _bake("res://weapons/pistol/models/slide.res", Vector3(0, 0.045, -0.03), _pistol_slide)
	await _bake("res://weapons/pistol/models/trigger.res", Vector3.ZERO, _trigger)
	await _bake("res://weapons/pistol/models/hammer.res", Vector3.ZERO, _hammer)
	await _bake("res://weapons/pistol/models/magazine.res", Vector3.ZERO, _pistol_magazine)
	await _bake("res://weapons/pistol/models/round.res", Vector3.ZERO, _round_9mm)
	_save_spring("res://weapons/pistol/models/spring.res", 0.088, 0.0045, 0.0008, 9)

	await _bake("res://weapons/ar/models/frame.res", Vector3.ZERO, _ar_frame)
	await _bake("res://weapons/ar/models/carrier.res", Vector3(0, 0.055, -0.07), _ar_carrier)
	await _bake("res://weapons/ar/models/handle.res", Vector3(0, 0.09, 0.03), _ar_handle)
	await _bake("res://weapons/ar/models/trigger.res", Vector3.ZERO, _trigger)
	await _bake("res://weapons/ar/models/selector.res", Vector3(-0.017, 0.022, -0.01), _ar_selector)
	await _bake("res://weapons/ar/models/magazine.res", Vector3.ZERO, _ar_magazine)
	await _bake("res://weapons/ar/models/round.res", Vector3.ZERO, _round_556)
	_save_spring("res://weapons/ar/models/spring.res", 0.137, 0.0052, 0.0009, 12)
	quit()


func _pistol_frame() -> void:
	# Upper frame with a full length dust cover and a swept beavertail.
	_solid([
		_side(graphite, [-0.128, 0.0295, 0.068, 0.0295, 0.082, 0.0278, 0.091, 0.0205, 0.091, 0.0175, 0.08, 0.0135,
				0.06, 0.0115, 0.03, 0.008, -0.118, 0.008, -0.128, 0.0135], -0.02, 0.02),
		_front(graphite, [-0.0125, 0.0296, 0.0125, 0.0296, 0.0125, 0.0125, 0.0085, 0.0075, -0.0085, 0.0075,
				-0.0125, 0.0125], -0.13, 0.1),
		_top(graphite, [-0.0125, -0.13, 0.0125, -0.13, 0.0125, 0.068, 0.0075, 0.093, -0.0075, 0.093, -0.0125, 0.068],
				0.0, 0.04),
	])
	# Skeleton dust cover: the recoil spring and guide rod show through it, and a tab on the slide rides inside.
	_carve(_side(graphite, [-0.11, 0.013, -0.04, 0.013, -0.044, 0.0255, -0.114, 0.0255], -0.02, 0.02))
	_carve(_box(graphite, Vector3(0, 0.0275, -0.083), Vector3(0.006, 0.0045, 0.076)))
	# Rail teeth under the dust cover.
	for i: int in 3:
		_carve(_box(graphite, Vector3(0, 0.0072, -0.106 + i * 0.0095), Vector3(0.03, 0.005, 0.0048)))
	# Hammer slot between the wings of the beavertail.
	_carve(_box(graphite, Vector3(0, 0.0245, 0.072), Vector3(0.011, 0.016, 0.032)))

	# Square trigger guard, thin in plan like a band.
	_add(_side(graphite, [-0.083, 0.01, -0.083, -0.008, -0.0755, -0.0225, 0.0, -0.0225, 0.0, 0.01,
			-0.0735, 0.01], -0.0055, 0.0055))
	_carve(_side(accent, [-0.0755, 0.0068, -0.003, 0.0068, -0.003, -0.0183, -0.0695, -0.0183, -0.0765, -0.0065],
			-0.01, 0.01))

	# Grip, on the same 18 degree rake as its collision shape. No thicker than 30 by 42 mm, to fit the hand.
	var grip_section: Array = [-0.0148, -0.015, -0.012, -0.021, 0.012, -0.021, 0.0148, -0.015, 0.0148, 0.015,
			0.0115, 0.021, -0.0115, 0.021, -0.0148, 0.015]
	_group(Transform3D(RAKE_18, Vector3(0, -0.035, 0.018)), func() -> void:
		_solid([
			_side(graphite, [-0.021, 0.05, -0.0205, 0.034, -0.0175, 0.026, -0.0205, 0.018, -0.0175, 0.01,
					-0.0205, 0.002, -0.0175, -0.006, -0.021, -0.016, -0.021, -0.042, -0.0225, -0.0485,
					0.0225, -0.0485, 0.0212, -0.042, 0.021, 0.0, 0.0195, 0.05], -0.02, 0.02),
			_top(graphite, grip_section, -0.06, 0.06),
		])
		# An orange flared band around the mag well mouth.
		_solid([
			_side(accent, [-0.0225, -0.041, 0.0225, -0.041, 0.0225, -0.0485, -0.0225, -0.0485], -0.02, 0.02),
			_top(accent, grip_section, -0.06, 0.06),
		])
		# Shell backstrap, tying the grip to the slide's colour.
		_add(_side(shell, [0.0163, 0.05, 0.0197, 0.05, 0.0212, 0.0, 0.0212, -0.041, 0.0172, -0.041, 0.0163, 0.0], -0.0085, 0.0085))
		for side: float in [-1.0, 1.0]:
			# Rubber side panels with raised ribs.
			_carve(_box(graphite, Vector3(side * 0.0148, -0.006, 0.001), Vector3(0.0016, 0.062, 0.027)))
			_add(_box(rubber, Vector3(side * 0.0138, -0.006, 0.001), Vector3(0.0012, 0.0615, 0.0265)))
			for i: int in 8:
				_add(_box(rubber, Vector3(side * 0.0146, -0.0325 + i * 0.0076, 0.001), Vector3(0.0012, 0.0034, 0.0255)))
	)
	# The real mag well: an empty grip looks empty.
	_group(Transform3D(RAKE_18, Vector3(0, 0.012, 0.0027)), func() -> void:
		_carve(_box(graphite, Vector3(0, -0.048, 0), Vector3(0.0236, 0.12, 0.0336)))
		_carve(_box(graphite, Vector3(0, 0.014, 0.002), Vector3(0.011, 0.03, 0.03)))
	)

	# Nose block: dust cover, barrel shroud and compensator in one wedge, ported on top.
	_solid([
		_side(shell, [-0.1265, 0.0565, -0.1265, 0.008, -0.136, 0.01, -0.15, 0.0215, -0.15, 0.0525, -0.143, 0.057],
				-0.02, 0.02),
		_top(shell, [-0.0098, -0.1265, 0.0098, -0.1265, 0.0066, -0.15, -0.0066, -0.15], 0.0, 0.07),
		_front(shell, [-0.0098, 0.0505, -0.0058, 0.0572, 0.0058, 0.0572, 0.0098, 0.0505, 0.0098, 0.014, 0.0058, 0.0075,
				-0.0058, 0.0075, -0.0098, 0.014], -0.16, -0.12),
	])
	_carve(_cyl(graphite, Vector3(0, 0.045, -0.14), 0.0052, 0.03, Vector3.AXIS_Z, 12))
	for i: int in 3:
		var port: CSGShape3D = _box(accent, Vector3(0, 0.0545, -0.1335 - i * 0.0052), Vector3(0.009, 0.015, 0.0028))
		port.rotation_degrees.x = -22.0
		_carve(port)
	_carve(_box(accent, Vector3(0, 0.0245, -0.1385), Vector3(0.03, 0.006, 0.012)))

	# Barrel and hood sit in the slide's cavity and stay put when it runs back.
	_add(_lathe(steel, [0.0002, -0.128, 0.0068, -0.128, 0.0068, -0.044, 0.0002, -0.044], Vector3(0, 0.045, 0), 12))
	_add(_box(steel, Vector3(0, 0.0452, -0.027), Vector3(0.0172, 0.0172, 0.036)))
	_carve(_cyl(graphite, Vector3(0, 0.0475, -0.01), 0.0048, 0.014, Vector3.AXIS_Z, 10))
	_add(_box(graphite, Vector3(0, 0.0325, -0.03), Vector3(0.011, 0.007, 0.03)))
	_add(_cyl(steel, Vector3(0, 0.0193, -0.078), 0.0016, 0.1, Vector3.AXIS_Z, 6))

	# Controls and pins.
	_add(_box(accent, Vector3(-0.0152, -0.0035, -0.0055), Vector3(0.0034, 0.0085, 0.0085)))
	_add(_side(steel, [-0.036, 0.0225, -0.003, 0.0225, 0.005, 0.0245, 0.0075, 0.0315, -0.003, 0.0315, -0.006, 0.0265,
			-0.036, 0.0265], -0.0148, -0.0122))
	_add(_cyl(steel, Vector3(0, 0.0195, -0.03), 0.0022, 0.0265, Vector3.AXIS_X, 8))
	_add(_cyl(steel, Vector3(0, 0.0125, -0.036), 0.0019, 0.0262, Vector3.AXIS_X, 8))
	_add(_cyl(steel, Vector3(0, 0.022, 0.07), 0.0024, 0.0262, Vector3.AXIS_X, 8))


func _pistol_slide() -> void:
	# A chisel nosed wedge: side, front and top outlines intersected.
	_solid([
		_side(shell, [-0.125, 0.03, -0.125, 0.052, -0.112, 0.0605, 0.052, 0.0605, 0.065, 0.056, 0.065, 0.03], -0.02, 0.02),
		_front(shell, [-0.014, 0.03, 0.014, 0.03, 0.014, 0.052, 0.0085, 0.0605, -0.0085, 0.0605, -0.014, 0.052],
				-0.13, 0.07),
		_top(shell, [-0.0098, -0.125, 0.0098, -0.125, 0.014, -0.102, 0.014, 0.065, -0.014, 0.065, -0.014, -0.102],
				0.02, 0.07),
	])
	# Hollow, so the windows look onto the barrel.
	_carve(_box(graphite, Vector3(0, 0.0408, -0.053), Vector3(0.021, 0.0245, 0.13)))
	_carve(_cyl(graphite, Vector3(0, 0.045, -0.122), 0.0075, 0.012, Vector3.AXIS_Z, 12))
	# Ejection port, open over the top on the right.
	_carve(_box(accent, Vector3(0.0105, 0.051, -0.015), Vector3(0.021, 0.026, 0.05)))
	# Skeleton windows on both sides and a slot along the top.
	_carve(_side(graphite, [-0.1065, 0.0365, -0.0575, 0.0365, -0.0625, 0.0505, -0.1025, 0.0505], -0.02, 0.02))
	_carve(_side(graphite, [-0.036, 0.0365, 0.003, 0.0365, -0.002, 0.0505, -0.032, 0.0505], -0.02, 0.0))
	_carve(_box(graphite, Vector3(0, 0.058, -0.082), Vector3(0.0075, 0.012, 0.042)))
	# Bold slanted grab grooves at the rear, orange inside.
	for side: float in [-1.0, 1.0]:
		for i: int in 5:
			var groove: CSGShape3D = _box(accent, Vector3(side * 0.0145, 0.044, 0.024 + i * 0.0075), Vector3(0.0032, 0.03, 0.0032))
			groove.rotation_degrees.x = 16.0
			_carve(groove)
	# Channel for the hammer to pass under.
	_carve(_box(graphite, Vector3(0, 0.0375, 0.041), Vector3(0.0116, 0.015, 0.058)))

	# Breech face, extractor and the tab that pushes the recoil spring.
	_add(_box(steel, Vector3(0, 0.0425, 0.0115), Vector3(0.021, 0.0205, 0.002)))
	_add(_box(steel, Vector3(0.0139, 0.0495, 0.016), Vector3(0.0014, 0.004, 0.018)))
	_add(_box(steel, Vector3(0, 0.0228, -0.12), Vector3(0.0048, 0.0156, 0.004)))

	# Sights: a post with one glowing dot, a notch with two, and a graphite rib between the two.
	_add(_side(graphite, [-0.1115, 0.06, -0.104, 0.06, -0.1055, 0.0665, -0.1105, 0.0665], -0.0016, 0.0016))
	_add(_cyl(glow, Vector3(0, 0.0645, -0.1054), 0.0012, 0.0012, Vector3.AXIS_Z, 8))
	_add(_box(graphite, Vector3(0, 0.0632, 0.0555), Vector3(0.0165, 0.0066, 0.007)))
	_carve(_box(graphite, Vector3(0, 0.0655, 0.0555), Vector3(0.0038, 0.006, 0.008)))
	for side: float in [-1.0, 1.0]:
		_add(_cyl(glow, Vector3(side * 0.0052, 0.0635, 0.0592), 0.0012, 0.0012, Vector3.AXIS_Z, 8))
		_add(_box(glow, Vector3(side * 0.01405, 0.0338, -0.078), Vector3(0.0005, 0.0012, 0.044)))
	_add(_box(graphite, Vector3(0, 0.0612, 0.03), Vector3(0.0065, 0.0016, 0.042)))
	# Screen plate on the back of the slide, above the hammer.
	_add(_box(rubber, Vector3(0, 0.0522, 0.0654), Vector3(0.0165, 0.0115, 0.0012)))


func _trigger() -> void:
	# Modelled about its pivot.
	_add(_side(accent, [-0.0025, 0.005, 0.003, 0.005, 0.0035, -0.004, 0.003, -0.01, 0.001, -0.016, -0.002, -0.0205,
			-0.0045, -0.0225, -0.0065, -0.0215, -0.006, -0.0185, -0.0045, -0.013, -0.0035, -0.007, -0.0035, -0.001],
			-0.0035, 0.0035))


func _hammer() -> void:
	# A ring hammer with a spur, modelled about its pivot.
	_add(_side(steel, [-0.004, -0.004, 0.004, -0.004, 0.0045, 0.006, 0.0105, 0.012, 0.0135, 0.0185, 0.011, 0.022,
			0.005, 0.0225, -0.0005, 0.0195, -0.004, 0.012], -0.0042, 0.0042))
	_carve(_cyl(accent, Vector3(0, 0.0135, 0.0055), 0.0033, 0.012, Vector3.AXIS_X, 12))


func _pistol_magazine() -> void:
	_solid([
		_side(graphite, [-0.0155, -0.004, -0.0125, -0.0005, 0.016, -0.0005, 0.016, -0.098, -0.016, -0.098], -0.02, 0.02),
		_front(graphite, [-0.0108, -0.11, 0.0108, -0.11, 0.0108, 0.0, -0.0108, 0.0], -0.02, 0.02),
	])
	_carve(_box(graphite, Vector3(0, 0.0015, 0.0), Vector3(0.0125, 0.01, 0.04)))
	for side: float in [-1.0, 1.0]:
		_add(_box(graphite, Vector3(side * 0.0085, 0.003, -0.004), Vector3(0.0032, 0.0075, 0.016)))
		for i: int in 4:
			_carve(_box(accent, Vector3(side * 0.0108, -0.024 - i * 0.017, 0.006), Vector3(0.0012, 0.0024, 0.014)))
	_solid([
		_side(accent, [-0.0175, -0.0975, 0.0195, -0.0975, 0.021, -0.1025, 0.0195, -0.106, -0.0165, -0.106, -0.0185, -0.1015],
				-0.02, 0.02),
		_front(accent, [-0.0132, -0.0975, 0.0132, -0.0975, 0.0132, -0.103, 0.0105, -0.106, -0.0105, -0.106, -0.0132, -0.103],
				-0.03, 0.03),
	])


func _round_9mm() -> void:
	_add(_lathe(brass, [0.0002, 0.0145, 0.0049, 0.0145, 0.0049, -0.0045, 0.0045, -0.0045, 0.0045, -0.009, 0.0025, -0.0135,
			0.0002, -0.0145], Vector3(0, 0.004, 0.0), 10))


func _ar_frame() -> void:
	_ar_upper()
	_ar_lower()
	_ar_stock()
	_ar_handguard()
	_ar_barrel()
	_ar_sights()


func _ar_upper() -> void:
	_solid([
		_side(shell, [-0.188, 0.036, -0.188, 0.072, -0.176, 0.083, 0.066, 0.083, 0.066, 0.036], -0.02, 0.02),
		_front(shell, [-0.0155, 0.035, 0.0155, 0.035, 0.0155, 0.07, 0.01, 0.083, -0.01, 0.083, -0.0155, 0.07], -0.19, 0.07),
		_top(shell, [-0.012, -0.188, 0.012, -0.188, 0.0155, -0.17, 0.0155, 0.066, -0.0155, 0.066, -0.0155, -0.17], 0.03, 0.09),
	])
	# Hollow, with a long port on the right and a slit on the left, so the carrier can be seen cycling.
	_carve(_box(graphite, Vector3(0, 0.0532, -0.056), Vector3(0.025, 0.0465, 0.244)))
	_carve(_side(accent, [-0.158, 0.047, -0.06, 0.047, -0.066, 0.0725, -0.152, 0.0725], 0.005, 0.02))
	_carve(_side(accent, [-0.125, 0.052, -0.045, 0.052, -0.05, 0.064, -0.12, 0.064], -0.02, -0.005))
	# Brass deflector behind the port, graphite panels and a pin line along the sides.
	_add(_side(shell, [-0.06, 0.0455, -0.046, 0.0455, -0.046, 0.0765, -0.058, 0.0765], 0.0145, 0.0195))
	for side: float in [-1.0, 1.0]:
		_add(_box(graphite, Vector3(side * 0.0155, 0.058, 0.022), Vector3(0.0012, 0.026, 0.074)))
		for i: int in 4:
			_carve(_box(accent, Vector3(side * 0.0163, 0.058, -0.002 + i * 0.016), Vector3(0.0012, 0.018, 0.0034)))
	# The track the charging handle rides in, running back along the stock's spine.
	_carve(_box(accent, Vector3(0, 0.0835, 0.09), Vector3(0.0072, 0.006, 0.31)))


func _ar_lower() -> void:
	_solid([
		_side(graphite, [-0.186, 0.037, 0.066, 0.037, 0.066, 0.026, 0.038, 0.014, 0.024, 0.006, -0.012, 0.004, -0.083, 0.004,
				-0.081, -0.02, -0.1585, -0.02, -0.165, 0.012, -0.186, 0.024], -0.02, 0.02),
		_front(graphite, [-0.0152, 0.038, 0.0152, 0.038, 0.0152, -0.016, 0.0165, -0.021, -0.0165, -0.021, -0.0152, -0.016], -0.19, 0.07),
	])
	# Trigger guard.
	_add(_side(graphite, [-0.086, 0.006, -0.086, -0.0255, 0.003, -0.0255, 0.003, 0.006], -0.0055, 0.0055))
	_carve(_side(accent, [-0.0795, 0.0015, -0.002, 0.0015, -0.002, -0.0215, -0.0795, -0.0215], -0.01, 0.01))
	# Grip: at most 30 by 42 mm to fit the hand.
	var grip_section: Array = [-0.0145, -0.015, -0.012, -0.021, 0.012, -0.021, 0.0145, -0.015, 0.0145, 0.015, 0.0115, 0.021,
			-0.0115, 0.021, -0.0145, 0.015]
	_group(Transform3D(RAKE_18, Vector3(0, -0.03, 0.018)), func() -> void:
		_solid([
			_side(graphite, [-0.021, 0.05, -0.0205, 0.026, -0.018, 0.019, -0.021, 0.012, -0.021, -0.036, -0.0245, -0.045,
					0.0235, -0.045, 0.021, -0.036, 0.021, 0.05], -0.02, 0.02),
			_top(graphite, grip_section, -0.06, 0.06),
		])
		_solid([
			_side(accent, [-0.0245, -0.038, 0.0235, -0.038, 0.0235, -0.045, -0.0245, -0.045], -0.02, 0.02),
			_top(accent, grip_section, -0.06, 0.06),
		])
		_add(_side(shell, [0.0172, 0.05, 0.0212, 0.05, 0.0212, -0.038, 0.0172, -0.038], -0.0085, 0.0085))
		for side: float in [-1.0, 1.0]:
			_carve(_box(graphite, Vector3(side * 0.0145, -0.01, 0.001), Vector3(0.0016, 0.05, 0.027)))
			_add(_box(rubber, Vector3(side * 0.0135, -0.01, 0.001), Vector3(0.0012, 0.0495, 0.0265)))
			for i: int in 6:
				_add(_box(rubber, Vector3(side * 0.0143, -0.03 + i * 0.008, 0.001), Vector3(0.0012, 0.0036, 0.0255)))
	)
	# The real mag well, open into the receiver.
	_group(Transform3D(RAKE_8, Vector3(0, 0.02, -0.115)), func() -> void:
		_carve(_box(graphite, Vector3(0, -0.03, 0), Vector3(0.0256, 0.09, 0.0636)))
	)
	# Slanted grooves on the mag well, a glowing line under the port, then controls and pins.
	for side: float in [-1.0, 1.0]:
		for i: int in 4:
			var groove: CSGShape3D = _box(accent, Vector3(side * 0.0155, -0.0065, -0.148 + i * 0.017), Vector3(0.0022, 0.018, 0.0032))
			groove.rotation_degrees.x = 12.0
			_carve(groove)
		_add(_box(glow, Vector3(side * 0.0157, 0.0415, -0.11), Vector3(0.0005, 0.0012, 0.13)))
	_add(_box(accent, Vector3(0.0162, 0.02, -0.078), Vector3(0.0032, 0.0085, 0.009)))
	_add(_box(steel, Vector3(-0.0162, 0.0245, -0.077), Vector3(0.0024, 0.019, 0.011)))
	_add(_cyl(steel, Vector3(0, 0.028, -0.172), 0.0028, 0.0335, Vector3.AXIS_X, 8))
	_add(_cyl(steel, Vector3(0, 0.03, 0.052), 0.0028, 0.0335, Vector3.AXIS_X, 8))


func _ar_stock() -> void:
	# Open truss stock around the buffer tube. Its spine carries the charging handle's track.
	_solid([
		_side(shell, [0.062, 0.083, 0.293, 0.083, 0.293, -0.025, 0.266, -0.025, 0.195, 0.036, 0.062, 0.036], -0.02, 0.02),
		_top(shell, [-0.0125, 0.06, 0.0125, 0.06, 0.018, 0.235, 0.018, 0.293, -0.018, 0.293, -0.018, 0.235], -0.03, 0.09),
		_front(shell, [-0.02, -0.03, 0.02, -0.03, 0.02, 0.074, 0.012, 0.083, -0.012, 0.083, -0.02, 0.074], 0.05, 0.3),
	])
	_carve(_side(graphite, [0.085, 0.0735, 0.232, 0.0735, 0.232, 0.018, 0.2, 0.0435, 0.085, 0.0435], -0.03, 0.03))
	_carve(_side(accent, [0.253, 0.0735, 0.279, 0.0735, 0.279, -0.012, 0.253, 0.014], -0.03, 0.03))
	_carve(_box(accent, Vector3(0, 0.0835, 0.16), Vector3(0.0072, 0.006, 0.17)))
	_add(_cyl(graphite, Vector3(0, 0.055, 0.15), 0.0125, 0.172, Vector3.AXIS_Z, 12))
	_add(_lathe(accent, [0.0115, 0.066, 0.0165, 0.066, 0.0165, 0.073, 0.0115, 0.073], Vector3(0, 0.055, 0), 12))
	_add(_front(rubber, [-0.018, -0.0245, 0.018, -0.0245, 0.018, 0.08, 0.0115, 0.0845, -0.0115, 0.0845, -0.018, 0.08], 0.293, 0.305))


func _ar_handguard() -> void:
	# A faceted shroud about 40 mm across: shell on top, graphite below.
	var profile: Array = [-0.188, 0.03, -0.188, 0.082, -0.425, 0.082, -0.44, 0.072, -0.445, 0.06, -0.445, 0.045, -0.432, 0.03]
	var plan: Array = [-0.02, -0.188, 0.02, -0.188, 0.02, -0.415, 0.012, -0.445, -0.012, -0.445, -0.02, -0.415]
	_solid([
		_side(shell, profile, -0.03, 0.03),
		_top(shell, plan, 0.0, 0.1),
		_front(shell, [-0.02, 0.0556, 0.02, 0.0556, 0.02, 0.066, 0.011, 0.0795, -0.011, 0.0795, -0.02, 0.066], -0.45, -0.18),
	])
	_solid([
		_side(graphite, profile, -0.03, 0.03),
		_top(graphite, plan, 0.0, 0.1),
		_front(graphite, [-0.02, 0.0558, 0.02, 0.0558, 0.02, 0.046, 0.011, 0.0305, -0.011, 0.0305, -0.02, 0.046], -0.45, -0.18),
	])
	_carve(_front(graphite, [-0.0175, 0.047, -0.0175, 0.0645, -0.0095, 0.0765, 0.0095, 0.0765, 0.0175, 0.0645, 0.0175, 0.047,
			0.0095, 0.0335, -0.0095, 0.0335], -0.45, -0.18))
	# Slanted vents along both sides and the top, onto the barrel, gas block and spring.
	for i: int in 5:
		var z := -0.41 + i * 0.041
		_carve(_side(accent, [z, 0.0575, z + 0.031, 0.0575, z + 0.027, 0.0685, z - 0.004, 0.0685], -0.03, 0.03))
		_carve(_top(accent, [-0.005, z + 0.002, 0.005, z + 0.002, 0.005, z + 0.029, -0.005, z + 0.029], 0.07, 0.09))
	# Rubber pads along the bottom, where the support hand goes.
	for i: int in 9:
		_add(_box(rubber, Vector3(0, 0.0303, -0.408 + i * 0.024), Vector3(0.0215, 0.0018, 0.017)))
	for side: float in [-1.0, 1.0]:
		_add(_box(glow, Vector3(side * 0.0201, 0.0556, -0.305), Vector3(0.0005, 0.0013, 0.21)))
	# An orange collar where the shroud meets the receiver.
	_add(_front(accent, [-0.0205, 0.0556, -0.0205, 0.0665, -0.0115, 0.0805, 0.0115, 0.0805, 0.0205, 0.0665, 0.0205, 0.046,
			0.0115, 0.0298, -0.0115, 0.0298, -0.0205, 0.046], -0.194, -0.188))


func _ar_barrel() -> void:
	# Barrel with cooling rings behind the gas block, then a slim run to the muzzle brake.
	var outline: Array = [0.0002, -0.165, 0.011, -0.165, 0.011, -0.2]
	for i: int in 10:
		var z := -0.204 - i * 0.012
		outline.append_array([0.0085, z, 0.0105, z, 0.0105, z - 0.006, 0.0085, z - 0.006])
	outline.append_array([0.0085, -0.45, 0.0075, -0.46, 0.0075, -0.502, 0.0002, -0.502])
	_add(_lathe(steel, outline, Vector3(0, 0.055, 0), 12))
	_add(_box(graphite, Vector3(0, 0.0615, -0.348), Vector3(0.0215, 0.031, 0.018)))
	_add(_cyl(accent, Vector3(0, 0.0695, -0.359), 0.0046, 0.004, Vector3.AXIS_Z, 10))
	# Spring stop at the receiver's front wall.
	_add(_cyl(steel, Vector3(0, 0.0695, -0.188), 0.0066, 0.004, Vector3.AXIS_Z, 10))
	# Muzzle brake: an octagon with slanted side ports.
	_solid([
		_front(graphite, [-0.0135, 0.0475, -0.0135, 0.0625, -0.0075, 0.0685, 0.0075, 0.0685, 0.0135, 0.0625, 0.0135, 0.0475,
				0.0075, 0.0415, -0.0075, 0.0415], -0.545, -0.498),
		_side(graphite, [-0.498, 0.0685, -0.54, 0.0685, -0.545, 0.0635, -0.545, 0.0465, -0.54, 0.0415, -0.498, 0.0415], -0.02, 0.02),
	])
	_carve(_cyl(graphite, Vector3(0, 0.055, -0.53), 0.0055, 0.04, Vector3.AXIS_Z, 12))
	for i: int in 3:
		var port: CSGShape3D = _box(accent, Vector3(0, 0.055, -0.509 - i * 0.0115), Vector3(0.04, 0.0105, 0.0052))
		port.rotation_degrees.y = 14.0
		_carve(port)
		_carve(_box(accent, Vector3(0, 0.067, -0.509 - i * 0.0115), Vector3(0.0065, 0.008, 0.0052)))


func _ar_sights() -> void:
	# Two tall fins, each a ring with a sight line 55 mm above the bore: a glowing post in front, ticks at the rear.
	_solid([
		_side(shell, [-0.432, 0.079, -0.398, 0.079, -0.404, 0.122, -0.424, 0.124], -0.02, 0.02),
		_front(shell, [-0.012, 0.078, 0.012, 0.078, 0.012, 0.119, 0.0075, 0.125, -0.0075, 0.125, -0.012, 0.119], -0.44, -0.39),
		_top(shell, [-0.0075, -0.432, 0.0075, -0.432, 0.012, -0.418, 0.012, -0.398, -0.012, -0.398, -0.012, -0.418], 0.07, 0.13),
	])
	_carve(_cyl(accent, Vector3(0, 0.11, -0.415), 0.0082, 0.05, Vector3.AXIS_Z, 16))
	_add(_box(graphite, Vector3(0, 0.1045, -0.415), Vector3(0.0024, 0.0112, 0.0024)))
	_add(_box(glow, Vector3(0, 0.1098, -0.415), Vector3(0.0032, 0.0032, 0.0032)))

	_solid([
		_side(shell, [-0.08, 0.081, -0.045, 0.081, -0.045, 0.1245, -0.064, 0.1245], -0.02, 0.02),
		_front(shell, [-0.0145, 0.08, 0.0145, 0.08, 0.0145, 0.118, 0.009, 0.1245, -0.009, 0.1245, -0.0145, 0.118], -0.09, -0.04),
		_top(shell, [-0.0085, -0.08, 0.0085, -0.08, 0.0145, -0.06, 0.0145, -0.045, -0.0145, -0.045, -0.0145, -0.06], 0.07, 0.13),
	])
	_carve(_cyl(accent, Vector3(0, 0.11, -0.06), 0.0088, 0.05, Vector3.AXIS_Z, 16))
	_add(_box(glow, Vector3(-0.0088, 0.11, -0.0448), Vector3(0.0036, 0.0013, 0.0008)))
	_add(_box(glow, Vector3(0.0088, 0.11, -0.0448), Vector3(0.0036, 0.0013, 0.0008)))
	_add(_box(glow, Vector3(0, 0.1188, -0.0448), Vector3(0.0013, 0.0036, 0.0008)))
	# Screen plate under the ring, for the fire mode and round count.
	_add(_box(rubber, Vector3(0, 0.0925, -0.0446), Vector3(0.0272, 0.0165, 0.0012)))


func _ar_carrier() -> void:
	# Bright so it reads through the port. The op rod runs forward from it through the shroud's vents.
	_add(_box(steel, Vector3(0, 0.055, -0.07), Vector3(0.018, 0.022, 0.17)))
	_add(_lathe(graphite, [0.0002, -0.168, 0.0095, -0.168, 0.0095, -0.155, 0.0002, -0.155], Vector3(0, 0.055, 0), 12))
	_add(_box(graphite, Vector3(0, 0.0685, -0.13), Vector3(0.0085, 0.0075, 0.05)))
	_add(_cyl(accent, Vector3(0.0102, 0.058, -0.095), 0.0038, 0.003, Vector3.AXIS_X, 10))
	_add(_cyl(accent, Vector3(-0.0102, 0.058, -0.085), 0.0038, 0.003, Vector3.AXIS_X, 10))
	_add(_cyl(steel, Vector3(0, 0.0695, -0.247), 0.0024, 0.184, Vector3.AXIS_Z, 8))
	_add(_cyl(steel, Vector3(0, 0.0695, -0.329), 0.0066, 0.004, Vector3.AXIS_Z, 10))


func _ar_handle() -> void:
	# Swept orange wings on a slider in the spine's track.
	_add(_top(accent, [-0.0075, 0.017, 0.0075, 0.017, 0.025, 0.032, 0.025, 0.04, -0.025, 0.04, -0.025, 0.032], 0.0855, 0.0945))
	_carve(_box(graphite, Vector3(0, 0.0945, 0.034), Vector3(0.012, 0.002, 0.012)))
	_add(_box(graphite, Vector3(0, 0.083, 0.03), Vector3(0.0062, 0.006, 0.024)))


func _ar_selector() -> void:
	# A hub and an orange thumb lever, modelled about the pivot.
	_add(_cyl(steel, Vector3(-0.017, 0.022, -0.01), 0.0048, 0.0034, Vector3.AXIS_X, 10))
	_add(_box(accent, Vector3(-0.0178, 0.031, -0.01), Vector3(0.0034, 0.0165, 0.0055)))


func _ar_magazine() -> void:
	_solid([
		_side(graphite, [-0.031, -0.0005, 0.031, -0.0005, 0.0305, -0.09, 0.0275, -0.172, -0.0345, -0.172, -0.0325, -0.09], -0.02, 0.02),
		_front(graphite, [-0.0118, -0.18, 0.0118, -0.18, 0.0118, 0.0, -0.0118, 0.0], -0.05, 0.05),
	])
	_carve(_box(graphite, Vector3(0, 0.0015, 0.0), Vector3(0.0125, 0.01, 0.07)))
	for side: float in [-1.0, 1.0]:
		_add(_box(graphite, Vector3(side * 0.0088, 0.0025, -0.004), Vector3(0.0034, 0.0065, 0.03)))
		for i: int in 5:
			_carve(_box(accent, Vector3(side * 0.0118, -0.03 - i * 0.027, -0.002 - i * 0.0012), Vector3(0.0012, 0.0028, 0.042)))
	_solid([
		_side(accent, [-0.0365, -0.1715, 0.029, -0.1715, 0.03, -0.1765, 0.0285, -0.18, -0.0355, -0.18, -0.0375, -0.176], -0.02, 0.02),
		_front(accent, [-0.0135, -0.1715, 0.0135, -0.1715, 0.0135, -0.177, 0.011, -0.18, -0.011, -0.18, -0.0135, -0.177], -0.05, 0.05),
	])


func _round_556() -> void:
	_add(_lathe(brass, [0.0002, 0.0285, 0.0047, 0.0285, 0.0047, -0.0105, 0.0032, -0.0135, 0.0032, -0.0165, 0.0028, -0.0165,
			0.0028, -0.02, 0.0012, -0.0285, 0.0002, -0.0285], Vector3(0, 0.004, 0.0), 10))


## A helix along -Z from the node's origin, scaled along Z at runtime as the bolt moves.
func _save_spring(path: String, length: float, radius: float, wire: float, turns: int) -> void:
	const STEPS_PER_TURN := 8
	const WIRE_SIDES := 4
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings := turns * STEPS_PER_TURN + 1
	for ring: int in rings:
		var angle := TAU * float(ring) / STEPS_PER_TURN
		var center := Vector3(cos(angle) * radius, sin(angle) * radius, -length * ring / float(rings - 1))
		var out := Vector3(cos(angle), sin(angle), 0.0)
		for k: int in WIRE_SIDES:
			var spoke := out.rotated(Vector3(-sin(angle), cos(angle), 0.0), TAU * k / WIRE_SIDES)
			tool.set_normal(spoke)
			tool.add_vertex(center + spoke * wire)
	for ring: int in rings - 1:
		for k: int in WIRE_SIDES:
			var a := ring * WIRE_SIDES + k
			var b := ring * WIRE_SIDES + (k + 1) % WIRE_SIDES
			var c := a + WIRE_SIDES
			var d := b + WIRE_SIDES
			for index: int in [a, b, c, b, d, c]:
				tool.add_index(index)
	tool.set_material(accent)
	_save(tool.commit(), path)


func _bake(path: String, origin: Vector3, build: Callable) -> void:
	var root := CSGCombiner3D.new()
	var model := CSGCombiner3D.new()
	model.position = -origin
	root.add_child(model)
	self.root.add_child(root)
	_parent = model
	build.call()
	await process_frame
	var mesh: ArrayMesh = root.bake_static_mesh()
	root.free()
	_save(mesh, path)


func _save(mesh: ArrayMesh, path: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var triangles := 0
	for surface: int in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface)
		var indexed: bool = arrays[Mesh.ARRAY_INDEX] != null
		triangles += (arrays[Mesh.ARRAY_INDEX] if indexed else arrays[Mesh.ARRAY_VERTEX]).size() / 3
	print("%s: %d surfaces, %d triangles" % [path, mesh.get_surface_count(), triangles])
	ResourceSaver.save(mesh, path)


func _group(xform: Transform3D, build: Callable) -> void:
	var group := CSGCombiner3D.new()
	group.transform = xform
	var outer := _parent
	outer.add_child(group)
	_parent = group
	build.call()
	_parent = outer


func _add(shape: CSGShape3D) -> void:
	shape.operation = UNION
	_parent.add_child(shape)


func _carve(shape: CSGShape3D) -> void:
	shape.operation = CUT
	_parent.add_child(shape)


## The intersection of its views.
func _solid(views: Array[CSGShape3D]) -> void:
	var group := CSGCombiner3D.new()
	for i: int in views.size():
		views[i].operation = UNION if i == 0 else INTERSECT
		group.add_child(views[i])
	_parent.add_child(group)


## Outline of (z, y) pairs seen from the right, extruded from x0 to x1.
func _side(material: Material, outline: Array, x0: float, x1: float) -> CSGPolygon3D:
	var shape := _polygon(material, outline, x1 - x0)
	shape.transform = Transform3D(Basis(Vector3(0, 0, 1), Vector3(0, 1, 0), Vector3(-1, 0, 0)), Vector3(x0, 0, 0))
	return shape


## Outline of (x, y) pairs seen from the muzzle, extruded from z0 to z1.
func _front(material: Material, outline: Array, z0: float, z1: float) -> CSGPolygon3D:
	var shape := _polygon(material, outline, z1 - z0)
	shape.position = Vector3(0, 0, z1)
	return shape


## Outline of (x, z) pairs seen from above, extruded from y0 to y1.
func _top(material: Material, outline: Array, y0: float, y1: float) -> CSGPolygon3D:
	var shape := _polygon(material, outline, y1 - y0)
	shape.transform = Transform3D(Basis(Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(0, -1, 0)), Vector3(0, y0, 0))
	return shape


func _polygon(material: Material, outline: Array, depth: float) -> CSGPolygon3D:
	var shape := CSGPolygon3D.new()
	shape.polygon = _points(outline)
	shape.depth = depth
	shape.material = material
	return shape


## Outline of (radius, z) pairs spun about a line along Z through center.
func _lathe(material: Material, outline: Array, center: Vector3, sides: int) -> CSGPolygon3D:
	var shape := CSGPolygon3D.new()
	shape.polygon = _points(outline)
	shape.mode = CSGPolygon3D.MODE_SPIN
	shape.spin_degrees = 360.0
	shape.spin_sides = sides
	shape.material = material
	shape.transform = Transform3D(Basis(Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(0, -1, 0)), center)
	return shape


func _box(material: Material, center: Vector3, size: Vector3) -> CSGBox3D:
	var shape := CSGBox3D.new()
	shape.position = center
	shape.size = size
	shape.material = material
	return shape


func _cyl(material: Material, center: Vector3, radius: float, length: float, axis: Vector3.Axis, sides: int) -> CSGCylinder3D:
	var shape := CSGCylinder3D.new()
	shape.position = center
	shape.radius = radius
	shape.height = length
	shape.sides = sides
	shape.smooth_faces = false
	shape.material = material
	shape.rotation_degrees = Vector3(90, 0, 0) if axis == Vector3.AXIS_Z else Vector3(0, 0, 90)
	return shape


static func _points(flat: Array) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i: int in range(0, flat.size(), 2):
		points.append(Vector2(flat[i], flat[i + 1]))
	return points
