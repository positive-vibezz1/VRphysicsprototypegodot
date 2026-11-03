# Physics Shooter Sandbox

A single-player VR prototype in Godot where the guns are simulated, not animated. The firing pin has to hit the primer
hard enough to set it off, the recoil is the reaction to simulated powder gas pushing the bullet, and the weight and
handling come from physics hands holding real rigid bodies. Everything else in the sandbox (the player's body, climbing,
the grapple, sound, air and water) follows the same rule: real units, real equations, forces instead of scripted motion.

**Status:** an early prototype and test range, not a game. VR only, single-player, one level. Developed and played on a
Steam Frame streamed from a Windows PC through SteamVR.

---

## Contents

- [What's in the demo](#whats-in-the-demo)
- [Technology](#technology)
- [How it works](#how-it-works)
- [Requirements](#requirements)
- [Getting started](#getting-started)
- [Controls](#controls)
- [Debug log and session logs](#debug-log-and-session-logs)
- [Tests](#tests)
- [Tools](#tools)
- [Project structure](#project-structure)
- [Known limitations](#known-limitations)
- [Credits and license](#credits-and-license)

---

## What's in the demo

The main scene is the test range, `sandbox/range.tscn`.

| | |
|---|---|
| **Pistol** | 9×19 mm, short recoil, 114 mm barrel, 17-round magazine, semi-auto. Hammer-fired. |
| **AR** | 5.56×45 mm, direct-impingement gas system, 368 mm barrel, 30-round magazine. Semi, 3-round burst, full auto and safe. Two-handed, with a stock that braces on your shoulder. |
| **Targets** | Steel plates at 5, 10, 25 and 50 m, a damageable dummy, a paper board, and crates and cans to knock around. |
| **Shot readout** | A panel on the table shows the last shot's muzzle velocity, peak chamber pressure, time in the bore, recoil impulse and firing-pin energy, or why it misfired. |
| **Media boxes** | A box of water and a box of thin air, to hear and feel what they do to sound, drag and buoyancy. |
| **Movement** | A parkour course and a block course, plus an 11-section timed movement trial west of the range (sprint, slalom, steps, jumps, swing jump, ladder and bars, rock wall, grapple swing, grapple haul, drop, wade). |
| **Gear on your body** | Holsters at both hips and behind both shoulders, and a magazine pouch at the belt buckle. |
| **Bullet time** | Slows the world to 10% on a rechargeable meter. |

The guns are stylized sci-fi models built from CSG in code (see [Tools](#tools)).

## Technology

| | |
|---|---|
| **Engine** | [Godot](https://godotengine.org/) 4.7.2, standard build (no .NET) |
| **Language** | GDScript only, statically typed (untyped declarations are errors) |
| **Physics** | Jolt Physics (built into Godot 4.4+), 90 Hz default, retuned to the headset's refresh rate at startup |
| **XR** | OpenXR core, no vendor-specific APIs. Action map with native bindings for the Steam Frame controllers, Oculus Touch and the Khronos generic controller |
| **Renderer** | Mobile (Vulkan), 2× MSAA, ETC2/ASTC texture compression, so a standalone build stays possible |
| **Audio** | Procedural: modal synthesis and a sound propagation model, no recorded samples |
| **Tests** | [GUT](https://github.com/bitwes/Gut) 9.7.1, run headless |

## How it works

Everything uses SI units (meters, kilograms, seconds, newtons, pascals) and real data: cartridge dimensions and
masses, spring rates, material densities. Tuned constants carry a comment with their source or reasoning.

### Firing chain

`weapons/parts/fire_control.gd`

Trigger → sear → hammer driven by its mainspring → firing pin → primer. These parts weigh grams and move in about a
millisecond, far shorter than one 11 ms physics tick, so they are integrated in GDScript in 50 µs sub-steps with the real
spring torque. The pin strike is an elastic collision between hammer and pin. The primer only fires when the pin's
impact energy is above the cartridge's ball-drop sensitivity threshold (a linear chance between its no-fire and
all-fire energies), so light strikes and duds happen. A misfire is cleared by racking the gun.

### Interior ballistics and recoil

`ballistics/gas_sim.gd`, `weapons/parts/cartridge_spec.gd`

When the primer fires, `GasSim` integrates the shot in 5 µs sub-steps:

- Powder burns by **Vieille's law**; **Résal's energy balance** with the **Noble-Abel equation of state** gives the mean
  gas pressure, and the **Lagrange gradient** splits it into base and breech pressure.
- After the bullet leaves, the barrel blows down isentropically through the muzzle with **choked flow**.
- On the AR, gas tapped at the **gas port** pushes the bolt carrier through its key until the vents uncover.

The result is a muzzle velocity, a pressure curve and a **breech impulse**, which always equals the bullet's momentum
plus the gas's (a test checks this). That impulse goes into the slide or bolt and the frame. Everything after that
comes out of Jolt: the recoil spring, the stops, the joints, the hand holding the frame. There is no scripted kick.
Tests hold the numbers to published data: about 340–390 m/s and 170–240 MPa for 9 mm, 850–930 m/s, 350–440 MPa and
about 6 N·s of free recoil for 5.56 mm.

### Guns as rigid bodies

`weapons/gun.gd`, `weapons/parts/`

Frame, slide or bolt carrier, charging handle and magazine are separate `RigidBody3D`s held by joints with limits.
Springs are forces with real rates. `Rail` handles fast stops: Jolt only enforces a joint limit once a part is past it,
so a bolt arriving at 8 m/s is slowed to land on its stop with equal and opposite impulses on bolt and frame, which is
what makes the frame kick. The cycle (extract, eject, strip a round, feed, lock back on empty) runs off the bolt's
actual travel. A magazine's mass follows its round count, so a full one is heavier.

### Bullets, casings and damage

`ballistics/`

Bullets and casings are pooled `RigidBody3D`s (32 bullets, 48 casings, 64 bullet holes, nothing spawned after startup)
with real mass and continuous collision detection, since a rifle bullet covers about 10 m per tick. A bullet does its
own quadratic drag for whatever it flew through since the last tick. On a hit, Jolt hands its momentum to the target,
and the kinetic energy the contact took out of it becomes damage (`Ballistics.bullet_hit` → `Dummy`), so distance,
cartridge and glancing angle all matter. The dummy stands on sprung joints, so it falls over and gets back up through
physics.

### Physics hands

`player/physics_hand.gd`, `player/grab_point.gd`

Hands are `RigidBody3D`s pulled toward the tracked controller pose by a PD controller with capped force and torque,
never parented to the controller. Damping follows the carried mass and stiffness is capped to what the tick rate can
integrate, so the hand is stable from an empty palm to a loaded rifle. A grabbed object hangs on a joint, so its weight
sags the hand and its recoil throws it.

- `GrabPoint` markers define where a hand can hold: `SNAP` (firing grips, loose magazines), `SUPPORT` (a second hand
  on a held gun, like the AR's handguard) and `PIN` (a moving part held where it was touched, like a slide).
- Two-handed: the AR stock braces against a shoulder collider, which only collides while the gun points within 60° of
  your view, so a rifle swung over the shoulder passes through.
- Remote grab: point at a gun or magazine up to 1.5 m away and grip to pull it to your hand.
- Hand models are the CC0 gloves from Godot XR Tools (see [Credits](#credits-and-license)).

### Player body and movement

`player/player.gd`, `player/grapple.gd`

The player is an 80 kg `RigidBody3D` with rotation locked, moved only by capped forces. Speeding up comes from the leg
force, stopping from a stronger brake force, and both from the mass, so you have momentum. The legs are a spring on a
ray that steps up small steps and soaks up landings. Smooth movement and smooth turning only (turning rotates the play
space around your head), no teleport or snap turn.

- **Jump** higher by swinging your arms up as you jump.
- **Climb**: grip a ladder, pipe, red ledge lip or rock crevice and the hand freezes there; each arm pulls the body
  back toward where you took hold.
- **Mantle**: jump while gripping a ledge to be hauled up and over.
- **Grapple**: an empty hand shows a dot where the cable would catch; pull the trigger to fire it. The cable only
  pulls, you swing on it under your own weight, and pulling your arm back hauls you in. Letting go keeps your speed.

### Holsters and magazine pouch

`player/body_spot.gd`, `player/holster.gd`, `player/mag_pouch.gd`

Nothing tracks the torso, so body spots follow the head's yaw lazily, within a neck's twist. Let go of a gun's grip at
either hip or behind either shoulder and it holsters (frozen and carried with you until you grab it again). Squeeze an
empty hand at the belt buckle to draw a full magazine that fits the gun in your other hand. Drawn magazines are pooled
per cartridge, so the body count stays bounded. Spots exist on both sides, so the setup works left- or right-handed.

### Air, water and drag

`audio/medium.gd`, `audio/medium_volume.gd`, `ballistics/fluid_drag.gd`

A `Medium` resource holds density, speed of sound and absorption. `Medium.ambient` is the air everywhere
(`audio/air_medium.tres`), and a `MediumVolume` box is anything else, such as the water and thin air boxes. It's the one
source of truth: `MediumVolume.medium_at(point)` answers what's at any point. `FluidDrag` gives every moving rigid body
quadratic drag and buoyancy from that density, sized from its collision shapes. Engine linear damping is off, so this is
the only thing slowing a body in flight.

### Sound

`audio/`

All sound is generated from the physics event that caused it.

- **Impacts** (`ImpactSound`, `SurfaceSound`): a hit's energy (half the contact impulse times the closing speed) sets
  the volume, the ringing body's mass sets the pitch, and the Hertzian contact time from both materials' stiffness sets
  how bright it is. Surfaces ring by modal synthesis, baked into takes at startup: thin metal plates, heavy fixed steel
  bars, guns (damped clusters with loose parts rattling), brass, wood, concrete, water, soft and hand.
- **Gunshots** (`GunshotSound`): each gun's report is baked from the energy of its muzzle gas by blast scaling and its
  bullet's Mach number, so the rifle comes out bigger and lower than the pistol without being told to.
- **Propagation** (`Acoustics`): each sound is traced once when it starts: travel delay, high-frequency absorption by
  the media, transmission across boundaries by acoustic impedance, through walls by the mass law or around them by
  Maekawa's barrier chart, and mirror-image echoes for loud sounds. One ray per tick around the listener sets the
  reverb from Eyring's reverberation time.
- **Voices** (`Sounds`): 16 pooled voices, and the quietest gives way when they run out.

### Bullet time

`player/bullet_time.gd`

Sets `Engine.time_scale`, which keeps ticks at the same real rate with a shorter `delta`, so the physics gets finer
rather than choppier and every equation still runs on its own time step. A bullet still leaves at full speed; you just
see more of it. Your hands stay on the controllers in real time and hand their extra motion to whatever they hold as a
rigid velocity change, so recoil and weight stay full size. Sound slows down to 30% at most.

### Collision layers

| Layer | Use | Layer | Use |
|---|---|---|---|
| 1 | World | 7 | Bullet |
| 2 | Player | 8 | Casing |
| 3 | Hand | 9 | Shoulder |
| 4 | Gun frame | 10 | Target |
| 5 | Moving gun part | 11 | Climbable |
| 6 | Magazine | 12 | Grapple target |

## Requirements

- **Godot 4.7.2**, standard build (not .NET). On Windows, also keep the `_console.exe` next to the editor for
  command-line runs.
- **A PC VR setup with an OpenXR runtime.** Developed on **SteamVR** with a **Steam Frame** streamed from the PC. SteamVR
  must be running and set as the active OpenXR runtime.
- **Quest 3 over Link, Air Link or Steam Link** should work through the Oculus Touch bindings but hasn't been tested.
- A Vulkan-capable GPU.
- Windows is the only platform it has been run on.

There's no flat-screen mode: the game needs a headset.

## Getting started

```sh
git clone https://github.com/positive-vibezz1/VRphysicsprototypegodot.git
cd VRphysicsprototypegodot
```

Set `GODOT` to your Godot console executable, for example:

```sh
# Git Bash
GODOT="/d/godot/Godot_v4.7.2-stable_win64_console.exe"
```

```powershell
# PowerShell (prefix each call below with &)
$GODOT = "D:\godot\Godot_v4.7.2-stable_win64_console.exe"
```

**Import once after cloning or pulling.** The `.godot/` cache isn't committed, and scripts that use a `class_name` from
another script won't parse until it's rebuilt:

```sh
$GODOT --headless --xr-mode off --path . --import
```

Then, with SteamVR running and the headset connected:

| Task | Command |
|---|---|
| Run the game | `$GODOT --path .` |
| Run without the debug log | `$GODOT --path . -- --no-log` |
| Open the editor | `$GODOT --path . -e` (then F5 to play) |
| Check one script for parse errors | `$GODOT --headless --xr-mode off --path . --check-only --script res://path/to/file.gd` |

Always pass `--xr-mode off` to headless runs, or Godot starts SteamVR and hangs.

## Controls

The controls for the controller you're holding are shown on the table at the range.

**Both controllers**

| Action | Input |
|---|---|
| Grab, climb | Grip |
| Remote grab | Point at a gun or mag within 1.5 m, then grip |
| Fire | Trigger on a held gun |
| Rack | Free hand on the slide or charging handle |
| Draw a magazine | Gun in one hand, grip the other at your belt buckle |
| Holster | Let go of a gun at either hip or behind either shoulder |
| Mantle | Jump while gripping a ledge |
| Grapple | Trigger on an empty hand when the dot shows, pull your arm back to haul |

**Steam Frame** (face buttons A, B, X, Y are all on the right controller; the left has a D-pad)

| Action | Input |
|---|---|
| Move / run | Left stick; L3 or L1 toggles running |
| Turn / jump | Right stick; R3, R1 or flick up to jump |
| Drop magazine | A or D-pad down |
| Fire mode | B or D-pad right |
| Bolt release | X or D-pad left |
| Bullet time | Y or D-pad up (the bar on your left hand is the meter) |
| Reset the range | Menu |
| Adjust where your hands sit | Hold View with an empty left hand |

**Oculus Touch**

| Action | Input |
|---|---|
| Move / run | Left stick; click toggles running |
| Turn / jump | Right stick; click or flick up to jump |
| Drop magazine | A or X |
| Fire mode, or bolt release when locked back | B or Y |
| Bullet time | Y |
| Reset the range | Menu |
| Adjust where your hands sit | Hold Y with an empty left hand |

Bindings live in `openxr_action_map.tres`, one per interaction profile. A new action needs a binding in each profile
and a line in the controls text in `sandbox/range.gd`.

## Debug log and session logs

`sandbox/debug_log.gd`, `sandbox/console_file.gd`

The game prints tuning numbers to the console, one line per event (never per tick), tagged by channel: `gun`, `recoil`,
`hit`, `hand`, `player`, `grapple`, `dummy`, `sound`, `time`, `trial` and `game`. Each line starts with real seconds
since startup, and lines printed in bullet time show the time scale.

- **F9** in the game window turns it on and off. `-- --no-log` starts it off. It's always off in headless runs.
- **Every game run saves its whole console** to `logs/session_<date>_<time>.log` in the project folder (the folder is
  gitignored). An exported build writes to `user://session_logs/` instead. The file is written as it goes, so it's whole
  even if the game is killed.
- **Time trial:** the `trial` channel logs the movement tuning a run starts with, a split per checkpoint with how the
  body got through it, and a `csv` line per finished run, so runs before and after a movement change can be compared.
  Best times are kept in `user://time_trial.cfg`. Times are world time, so bullet time doesn't cost you on the clock.

## Tests

GUT tests live in `tests/` (`test_<thing>.gd`) and cover the physics: gas sim against published cartridge data, momentum
conservation, primer threshold, the gun cycle and fire control, drag and buoyancy, acoustics and sound, hands, holsters
and mag pouch, player movement, bullet time, the dummy, and the range and time trial scenes.

```sh
$GODOT --headless --xr-mode off --fixed-fps 90 --max-fps 900 --path . -s res://addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit
```

This runs physics at about 10× real speed and takes well under a minute. About 1 run in 20 fails on a "Jolt Physics job
system exceeded" warning, seen only at that speed; run it again (or run that test file alone) to confirm.

A change counts as verified when the import shows no script errors and all tests pass. Anything that changes feel or
handling also needs a headset test.

## Tools

Scripts in `tools/` aren't used by the game. Both need a window, so run them without `--headless`.

| Task | Command |
|---|---|
| Rebuild the gun models after editing `tools/build_gun_models.gd` | `$GODOT --xr-mode off --path . -s res://tools/build_gun_models.gd` |
| Render the guns to a PNG contact sheet | `$GODOT --xr-mode off --resolution 1600x1000 --path . -s res://tools/render_guns.gd -- <absolute out dir> [open] [zoom=x,y,z,width]` |

`build_gun_models.gd` builds each gun from CSG solids and bakes one mesh per moving part to `.res` files. `open` in the
render tool shows the actions pulled back; `zoom=` sets the close-up.

## Project structure

```
player/          XR rig: player body and movement, physics hands, grapple, grab points,
                 holsters and mag pouch, bullet time, hand models
weapons/
  gun.gd         one firearm: frame, bolt, fire control, magazine, cycle
  parts/         fire control, rail, mag well, magazines, cartridge specs, materials
  pistol/        pistol scene and baked models
  ar/            AR scene and baked models
ballistics/      gas sim, bullets, casings, pools, fluid drag
audio/           surface sounds, impact and gunshot sound, voice pool, media, acoustics
sandbox/         test range (main scene), parkour and block courses, time trial, dummy,
                 debug log
enemies/         alien and crawler models (not placed in the range yet)
tests/           GUT tests
tools/           gun model builder and render tool
addons/gut/      GUT test framework
openxr_action_map.tres   controller bindings
CLAUDE.md        engineering rules and conventions for this project
```

Conventions (full list in [CLAUDE.md](CLAUDE.md)): each scene sits next to its script with `snake_case` names; static
types everywhere; tunables are `@export` vars; shared data such as cartridge specs are custom `Resource`s; rigid bodies
are moved only by forces, impulses and joints; nothing is allocated in per-tick code; anything spawned is pooled.

## Known limitations

- **VR only, single-player, one test range.** No flat-screen mode, multiplayer, menus or game loop yet.
- **Tested only on a Steam Frame streamed through SteamVR on Windows.** Quest 3 and Steam Frame standalone builds are
  planned (Android export with the Godot OpenXR Vendors plugin) but not set up, and there are no export presets in the
  repo.
- **Feel needs a headset.** Tests cover the math, but handling and recoil feel have only been judged by playtesting.
- **On Oculus Touch, the left Y button is shared** by bullet time and the left hand's fire mode / bolt release, so with
  a gun in the left hand one press does both.
- **Jolt's 47 rad/s spin limit** stays at its default (raising it tears a free gun's slide off), so in bullet time a
  very fast wrist falls behind the controller and then catches up.
- **Continuous collision may miss very thin colliders** at rifle speeds.
- **A pooled casing keeps the size of its first cartridge** for drag and buoyancy, which only shows in water.
- **Test flake:** the Jolt job-system warning above fails about 1 full test run in 20.
- **Enemies** exist only as models.

## Credits and license

- Hand models, finger animations and glove textures: from [Godot XR Tools](https://github.com/GodotVR/godot-xr-tools)
  4.5.2, by DigitalN8m4r3 (Miodrag Sejic), made with MakeHuman, released under **CC0**. See
  `player/hands/README.md` and `player/hands/License.md`.
- [GUT](https://github.com/bitwes/Gut) by Butch Wesley, MIT license, in `addons/gut/`.
- Built with [Godot Engine](https://godotengine.org/) (MIT) and Jolt Physics (MIT).

No license has been chosen for the rest of the project yet.
