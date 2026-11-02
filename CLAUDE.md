# CLAUDE.md

VR-only, single-player **physics sandbox prototype** in Godot. The point is gun feel: every gun part is a real moving physics part, the firing pin has to actually strike the primer, recoil comes from simulated gas pressure, and weight and handling come from physics hands. First guns: a pistol and a simple AR. Out of scope for now: multiplayer, flat-screen mode, and content beyond a test range.

## Stack

- **Engine:** Godot 4.7.2, standard build (no .NET). Editor: `D:\godot\Godot_v4.7.2-stable_win64.exe`. For command-line runs use the `_console.exe` next to it so output reaches the terminal (fall back to the main exe if it's missing).
- **Language:** GDScript only, statically typed. No C#. Native code (GDExtension) only if profiling proves a hot path needs it, and ask ruby first.
- **Physics:** Jolt (`physics/3d/physics_engine = "Jolt Physics"`).
- **XR:** OpenXR core. No vendor-specific APIs without a fallback. Dev runtime is SteamVR with the Steam Frame streamed from the PC, which is the only setup ruby tests on.
- **Renderer:** Mobile, so standalone builds stay possible. Don't rely on Forward+-only features.
- **Later targets:** Quest 3 standalone (Android export + Godot OpenXR Vendors plugin) and Steam Frame standalone. Stay within standalone performance budgets now.
- **Tests:** GUT. **Version control:** git.

## Commands

Run from the project root `D:\steamframegodotshooter`.
Git Bash: `GODOT="/d/godot/Godot_v4.7.2-stable_win64_console.exe"`. PowerShell: `$GODOT = "D:\godot\Godot_v4.7.2-stable_win64_console.exe"` and prefix calls with `&`.

| Task | Command |
|---|---|
| Open editor | `$GODOT --path . -e` |
| Import assets and refresh class cache (after adding files or editing scenes) | `$GODOT --headless --xr-mode off --path . --import` |
| Check one script for parse errors | `$GODOT --headless --xr-mode off --path . --check-only --script res://path/to/file.gd` |
| Run all tests | `$GODOT --headless --xr-mode off --fixed-fps 90 --max-fps 900 --path . -s res://addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit` |
| Run the game (SteamVR must be running) | `$GODOT --path .` |
| Rebuild gun models after editing `tools/build_gun_models.gd` (opens a window) | `$GODOT --xr-mode off --path . -s res://tools/build_gun_models.gd` |
| Render the guns to PNGs to check how they look (opens a window) | `$GODOT --xr-mode off --resolution 1600x1000 --path . -s res://tools/render_guns.gd -- <absolute out dir> [open] [zoom=x,y,z,width]` |

Always pass `--xr-mode off` to headless runs: without it Godot starts SteamVR and hangs.

The test command runs physics at 10 times real speed. About 1 run in 20 fails on a "Jolt Physics job system exceeded" warning, seen only at that speed so far: run it again.

The game prints tuning numbers to the console, one line per event (`DebugLog`): shots, recoil, hits, grabs, movement state. F9 in the game window flips it, `-- --no-log` starts it off, and it's off in headless runs. Each game run saves its whole console to `logs/session_<date>_<time>.log` as it goes, so read those for how a headset session went. Godot's own `user://logs` keeps only 5 and test runs push them out. Check `DebugLog.enabled` or `due` before building a line in per-tick code.

Claude can't see or feel anything in the headset. After any change that affects feel or handling, list exactly what ruby should check in VR.

## Controls

Buttons are game actions in `openxr_action_map.tres`, bound natively per interaction profile: Steam Frame (`valve/frame_controller_valve`), Oculus Touch, and `khr/generic_controller` as a fallback for anything else. The runtime picks the profile for the hardware. On the Frame, face buttons (A, B, X, Y) are all on the right and the left has a D-pad. A new action needs a binding in each profile and a line in the controls text in `sandbox/range.gd`.

## Layout

```
player/          XR rig, physics hands, locomotion
weapons/
  parts/         shared mechanism parts: springs, hammer, firing pin, magazine, cartridge
  pistol/
  ar/
ballistics/      gas pressure model, bullets, casings, impacts, drag and buoyancy
audio/           procedural surface sounds, the voice pool, ImpactSound, media, sound propagation
sandbox/         test range (main scene), parkour course
tests/           GUT tests, test_<thing>.gd
tools/           model builder and gun render tool, not used in the game
addons/          GUT and third-party plugins only
```

Keep each scene and its script side by side, with `snake_case` file names. Move or rename files in the editor, or move the `.uid` file together with its script.

## Physics rules

- **Real units and values:** meters, kilograms, seconds, newtons, pascals. Use real masses, dimensions, spring rates and cartridge data (for example a 9×19 mm bullet is about 7.5 to 8 g, a 5.56×45 mm bullet about 3.6 to 4 g). Comment the source or reasoning for tuned constants.
- **Tick rate:** at XR startup set `Engine.physics_ticks_per_second` to the headset refresh rate (`OpenXRInterface.display_refresh_rate`). Never assume a fixed delta.
- **Move bodies with forces, impulses and joints.** Never set a RigidBody3D's transform to move it, except to teleport or reset it. Physics code goes in `_physics_process` or `_integrate_forces`.
- **No faked mechanics.** No animations or scripted kicks standing in for physics. Recoil is the reaction to the gas pushing the bullet: the momentum given to the bullet and gas goes back into the breech, bolt or slide, and from there through joints into the frame and the hands.
- **Sub-tick events:** barrel time (about 1 ms), the firing pin strike and primer ignition are much shorter than a physics tick (about 11 ms at 90 Hz). Integrate them in GDScript with sub-steps using the real equations (spring force, pressure × bore area), then apply the result to the Jolt bodies as impulses. Momentum must be conserved; keep a GUT test for it.
- **Firing chain:** trigger → sear → hammer or striker driven by its spring → firing pin → primer. The primer fires only when the pin's impact energy is above the primer's threshold, so light strikes and duds are possible.
- **Gun parts:** frame, slide or bolt carrier, charging handle and magazine are separate RigidBody3Ds held by joints with limits. Springs are forces with real spring rates. Trigger, sear, hammer and firing pin are sub-stepped in `FireControl` instead: tested as a Jolt body at 90 Hz, a sprung hammer hits the 47 rad/s engine limit and needs 3 ticks for a 3 ms fall. The magazine follower is implied by the round count.
- **Fast stops:** Jolt only enforces a joint limit once a part is past it, so `Rail` slows a fast bolt to land on its stop, with equal and opposite impulses on the bolt and the frame. At rest the joint limit alone holds it, because the prediction can't see forces from the hands.
- **Small parts and stability:** joints between bodies with very different masses (a few-gram pin on a kilogram frame) jitter in Jolt. If a tiny part is unstable, simulate its motion with the sub-step approach above instead of raising solver iterations blindly.
- **Bullets and casings** are pooled RigidBody3Ds with real mass and `continuous_cd = true` (a rifle bullet travels about 10 m per tick). A bullet does its own drag in `_integrate_forces`, by what it flew through since the last tick. If CCD misses thin colliders, raise it with ruby before switching to shape casts.
- **Physics hands:** hands are RigidBody3Ds pulled toward the tracked controller pose by a PD controller (force and torque), never parented to the controller. A grabbed gun is attached to the hand with a joint, so its mass, inertia and recoil act on the hand. Two-handed grips: primary grip, support hand on the handguard, and the AR stock braces against a shoulder collider on the player body. Grips are `GrabPoint` markers placed in the middle of the part, with -Z along it, so they land inside the fist: `SNAP` brings the gun to the hand, `SUPPORT` brings a second hand to its spot on a held gun, and `PIN` holds a moving part where it was touched. An empty hand squeezing at the front of the belt (`MagPouch`, following the head) draws a full magazine for the gun in the other hand. Drawn magazines are pooled per cartridge: once `pool_size` are out, the oldest one at rest gets refilled and drawn again.
- **Locomotion:** smooth movement and smooth turning on the thumbsticks, left stick click toggles running until the stick is released, right stick click or flick up to jump, higher with the arms swung up. No teleport, no snap turn. (Remote grab moves objects to the hand, not the player.) The player is an 80 kg RigidBody3D with rotation locked and no friction, moved only by capped forces, so speeding up comes from `leg_force`, stopping from the stronger `brake_force`, and both from the mass. The legs are a spring on a ray under the body, which steps up small steps and soaks up landings, and the lower capsule stops it on anything taller. Turning rotates the XROrigin around the head. The capsule catching up with the person's real steps is the one direct move of the body, and it adds no momentum.
- **Climbing and grapple:** a squeeze near a climbable surface (ladders, pipes, ledge lips and rock crevices, not whole blocks) freezes the hand on it, and each arm pulls the body back to where the controller took hold, capped at `arm_force`. An empty hand shows a dot where a `Grapple` cable would catch any parkour surface, and its trigger connects it. The cable only pulls, and pulling the arm back hauls on it. Letting go of either keeps the body's speed. The legs capsule turns off while hanging, so the torso can get over a ledge, and comes back once there's room. Pressing jump while gripping a ledge mantles: it looks for somewhere to stand past the hold, then hauls the body up and over with a capped force.
- **Bullet time:** `BulletTime` sets `Engine.time_scale`, which keeps the ticks at the same real rate and shortens `delta`, so use `delta` for world time and `1.0 / Engine.physics_ticks_per_second` for what the person does themselves (turning, arm swings). The body stays in world time. Hands stay on the controllers in real time: `PhysicsHand._keep_up` hands the extra motion to everything held as a rigid change of velocity, because a force that big would throw a slide open, and the arm's PD keeps its normal strength in world time, so recoil and sag stay full size. Jolt's 47 rad/s spin limit stays at its default, since raising it tears a free gun's slide off at normal speed, so a wrist above 4.7 rad/s falls behind at a time scale of 0.1 and catches up.
- **Target damage:** a bullet reports the kinetic energy its contact took out of it through `Ballistics.bullet_hit`, and `Dummy` turns that into damage, so distance, cartridge and glancing angle all count. Its momentum reaches the target through Jolt, not through the damage code. Dummy body and head stand on sprung joints, not a rounded base: Jolt keeps a rolling roly-poly rocking forever.
- **Sound:** an `ImpactSound` child makes a rigid body ring when it hits something, and static bodies say what they are with `metadata/surface` (no metadata is concrete). The energy of a hit is half Jolt's contact impulse times the closing speed, and it sets the volume, while the ringing body's mass sets the pitch and Hertz's contact time, from the stiffness of both materials, the mass and the speed, sets how bright it is. A light hitter only gets a share of its energy into something heavy. On a contact that's still there, use how much the body really changed speed, because Jolt's closing speed includes this tick's forces. Each `SurfaceSound` holds the modes of a surface, baked into takes at startup. `Sounds` holds 16 pooled voices, and the quietest gives way when they run out. Footsteps go by distance over the ground.
- **Air and water:** `FluidDrag` finds every `RigidBody3D` as it enters the tree, apart from bullets and moving gun parts, and each tick gives the moving ones quadratic drag and buoyancy from the `Medium` density over their height. Size comes from the collision shapes, so a new body needs nothing added; `metadata/drag_coefficient` and `metadata/bulk_density` override what shapes get wrong. `physics/3d/default_linear_damp` is 0 so this is all that slows a body in flight. The engine's default angular damp stays, standing in for the rolling resistance Jolt doesn't have. To change the air, edit `audio/air_medium.tres`.
- **Sound propagation:** `Medium` holds a density, speed of sound and absorption. `Medium.ambient` is what's everywhere, and a `MediumVolume` box is anything else: read `MediumVolume.medium_at(point)` instead of keeping a density of your own. `Acoustics.trace` works out each sound once, when it starts: the delay along its path, the highs the media absorb, what crosses each boundary by impedance, and what gets past a wall by the mass law or around it by Maekawa's barrier chart, whichever is louder. Loud sounds also get echoes from mirror images behind the walls a ray finds. One ray a tick around the listener sets the reverb, with Eyring's reverberation time. A voice's only filter is its high shelf, and Godot scales it by how far the sound is from full volume, so `Sounds._start` divides that back out.
- **Collision:** primitive or convex shapes on moving bodies, never trimesh. Use collision layers and masks so parts inside one gun only collide where they need to. A body only gets pushed by layers in its own mask: bullets can't move a target whose mask leaves out the bullet layer.
- **Layers:** 1 world, 2 player, 3 hand, 4 gun frame, 5 moving gun part, 6 magazine, 7 bullet, 8 casing, 9 shoulder, 10 target, 11 climbable, 12 grapple target (both on world bodies).

## Performance

The frame budget is the headset refresh rate (11.1 ms at 90 Hz), and code should stay viable on Quest 3 standalone. No allocations in per-tick code, pool anything spawned, keep the active rigid body count low and let idle bodies sleep. Profile before optimizing.

## GDScript style

- Follow the official GDScript style guide: `snake_case` files, functions and variables, `PascalCase` classes and nodes, `CONSTANT_CASE` constants.
- Static types everywhere, including typed arrays and function signatures.
- `class_name` only for types used from other scripts.
- Tunable values are `@export` vars so they can be tweaked in the inspector. Shared data (cartridge specs, spring sets) goes in a custom `Resource`.
- When editing `.tscn` or `.tres` files by hand, keep `ext_resource` ids and `uid`s consistent, then run the import command.

## Testing and git

- GUT tests live in `tests/` and extend `GutTest`. Cover the physics math: pressure curve, muzzle velocity, momentum conservation, primer energy threshold, spring forces, drag. Use `await wait_physics_frames(n)` for tests that need the physics server.
- A change is verified when the import shows no script errors and all GUT tests pass. Feel and handling also need ruby's headset test, so call those unverified in VR until ruby confirms.
- Claude commits on its own after a change is verified: small focused commits with imperative messages. Commit `.import` and `.uid` files, never `.godot/`. Don't push unless asked (there's no remote yet).

## Coding Standards and Agent Behavior

### 1. Efficiency and Code Quality
- Always prefer the simplest, shortest correct implementation.
- If two solutions provide equivalent functionality, performance, readability, and maintainability, choose the one with fewer lines of code.
- Avoid overengineering, unnecessary abstractions, duplicate logic, excessive dependencies, and redundant files.
- Reuse existing functions and modules before introducing new ones.
- Prioritize actual runtime performance, memory efficiency, and algorithmic complexity over minimizing line count.
- Write concise, readable, production-quality code. Do not sacrifice correctness for brevity.

### 2. Communication and Token Efficiency
- Keep responses brief, technical, and directly relevant.
- Do not provide lengthy explanations, repetitive summaries, or unnecessary commentary.
- After making changes, briefly state what changed, whether tests passed, and any unresolved problems.
- Do not repeat information already established in the conversation or project documentation.
- Avoid unnecessary tool calls and excessive repository exploration, but never skip essential investigation or validation.

### 3. Code Preservation and Safety
- Never delete, replace, or significantly refactor code you do not understand.
- Inspect relevant implementations, dependencies, and call sites before modifying them.
- Do not remove functionality simply because it appears unused or redundant.
- Preserve existing APIs, data structures, and behavior unless changes are necessary.
- Make targeted changes rather than rewriting entire modules unnecessarily.
- Validate changes using available tests, builds, or type checks.
- Do not claim a change works unless it has been verified.

### 4. Development Workflow
- Inspect existing code before implementing changes.
- Identify the smallest safe solution that addresses the actual problem.
- Implement directly when requirements are clear.
- Avoid unrelated changes and speculative improvements.
- Maintain architectural consistency and avoid introducing new patterns without a concrete benefit.
- Prefer completing a working implementation over producing extensive planning documents
