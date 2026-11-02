extends SceneTree
## Renders each gun from four sides into one PNG contact sheet, to check how the models look without a
## headset. Needs a window, so run without --headless:
##   $GODOT --xr-mode off --resolution 1600x1000 --path . -s res://tools/render_guns.gd -- <output dir>
## Pass "open" after the output dir to render the actions pulled back.

const SCENES := {
	"pistol": "res://weapons/pistol/pistol.tscn",
	"ar": "res://weapons/ar/ar.tscn",
}
## Camera direction per view, in the gun's frame (muzzle toward -Z, right side +X), and what fraction of the
## frame width the gun's longest axis fills.
const VIEWS: Array[Array] = [
	[Vector3(1.0, 0.15, 0.0), 0.85], [Vector3(-1.0, 0.15, 0.0), 0.85],
	[Vector3(0.8, 0.8, -1.0), 0.75], [Vector3(0.9, 0.6, 1.0), 0.75],
]


func _initialize() -> void:
	var user_args := OS.get_cmdline_user_args()
	var out_dir := user_args[0] if user_args.size() > 0 else "user://"
	var open := user_args.size() > 1 and user_args[1] == "open"
	PhysicsServer3D.set_active(false)

	var stage := Node3D.new()
	root.add_child(stage)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.55, 0.57, 0.6)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color(0.7, 0.72, 0.78)
	environment.environment.ambient_light_energy = 0.9
	environment.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	stage.add_child(environment)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-42.0, 35.0, 0.0)
	key.light_energy = 2.2
	key.shadow_enabled = true
	stage.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-20.0, -140.0, 0.0)
	fill.light_energy = 0.6
	stage.add_child(fill)
	var camera := Camera3D.new()
	camera.fov = 35.0
	camera.near = 0.01
	stage.add_child(camera)
	camera.make_current()

	for gun_name: String in SCENES:
		var gun: Gun = load(SCENES[gun_name]).instantiate()
		stage.add_child(gun)
		gun.process_mode = Node.PROCESS_MODE_DISABLED
		if open:
			for body: RigidBody3D in [gun.bolt, gun.charging_handle]:
				if body:
					body.position.z += gun.bolt_travel
		await process_frame
		var bounds := _bounds(gun)
		var aspect := float(root.size.x) / float(root.size.y)
		var half_width := tan(deg_to_rad(camera.fov * 0.5)) * aspect
		var sheet: Image = null
		for view: Array in VIEWS:
			var direction: Vector3 = view[0]
			var distance: float = bounds.get_longest_axis_size() / view[1] / (2.0 * half_width)
			camera.look_at_from_position(bounds.get_center() + direction.normalized() * distance, bounds.get_center())
			await process_frame
			await RenderingServer.frame_post_draw
			var frame_image := root.get_texture().get_image()
			if sheet == null:
				sheet = Image.create(frame_image.get_width() * 2, frame_image.get_height() * 2, false, frame_image.get_format())
			var slot := VIEWS.find(view)
			sheet.blit_rect(frame_image, Rect2i(Vector2i.ZERO, frame_image.get_size()),
					Vector2i(slot % 2 * frame_image.get_width(), slot / 2 * frame_image.get_height()))
		var path := out_dir.path_join(gun_name + ("_open" if open else "") + ".png")
		sheet.save_png(path)
		print("Saved ", path)
		stage.remove_child(gun)
		gun.free()
	quit()


static func _bounds(gun: Node) -> AABB:
	var bounds := AABB()
	var first := true
	for mesh: Node in gun.find_children("*", "MeshInstance3D"):
		if not mesh.visible or not mesh.is_inside_tree() or not (mesh as MeshInstance3D).mesh:
			continue
		var box: AABB = (mesh as MeshInstance3D).global_transform * (mesh as MeshInstance3D).get_aabb()
		bounds = box if first else bounds.merge(box)
		first = false
	return bounds
