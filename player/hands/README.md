Hand models, finger animations and glove textures from Godot XR Tools 4.5.2
(https://github.com/GodotVR/godot-xr-tools), found on the Godot Asset Library.
By DigitalN8m4r3 (Miodrag Sejic), made with MakeHuman, released under CC0. See License.md.

Only the low poly glove hands are copied here. glove.tres and the hand scenes are our own.

The root transform of each hand scene is measured, not guessed. With the fingers at the guns' grip closure (0.45),
the tube they close around runs through (-+0.025, -0.008, -0.073) along (+-0.105, 0.988, -0.111) in the model. The
root puts that tube along the grip pose's -Z through its origin, which is how OpenXR defines the grip pose, so a grip
marker placed in the middle of a grip lands inside the fist.
