extends Label3D
## Rounds left in the gun, chambered and in the magazine, on a small screen the shooter can read while aiming.

var _shown := -1

@onready var _gun: Gun = owner


func _process(_delta: float) -> void:
	var rounds := 1 if _gun.chamber == Gun.Chamber.LIVE else 0
	if _gun.mag_well.latched:
		rounds += _gun.mag_well.magazine.count
	if rounds != _shown:
		_shown = rounds
		text = str(rounds)
