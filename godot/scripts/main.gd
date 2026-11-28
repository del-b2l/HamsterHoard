extends Node3D

# HamsterHoard: cozy Godot viewer for the C++ MPI + OpenMP TSP engine.
# The C++ executable performs the genetic algorithm. This script launches it,
# reads its JSON snapshots, and visualizes the best route.

const UI_BG := Color("#f8f1df")
const UI_PANEL := Color("#fffaf0")
const UI_GREEN := Color("#52775b")
const UI_GREEN_DARK := Color("#36533e")
const UI_ORANGE := Color("#e98b45")
const UI_TEXT := Color("#3b4438")
const UI_MUTED := Color("#78806e")
const CITY_COLOR := Color("#f4d36d")
const ROUTE_COLOR := Color("#e98b45")

var engine_pid: int = -1
var snapshot_path: String
var stop_path: String
var last_data: Dictionary = {}

var cities_root: Node3D
var status_label: Label
var generation_label: Label
var best_label: Label
var average_label: Label
var ranks_label: Label
var start_button: Button
var stop_button: Button
var executable_input: LineEdit
var mpi_launcher_input: LineEdit
var process_input: SpinBox
var thread_input: SpinBox
var city_input: SpinBox
var population_input: SpinBox
var generation_input: SpinBox
var speed_input: SpinBox
var delay_input: SpinBox


# Moving hamster on the route (uses the AnimatedSprite3D already in main.tscn).
var route_hamster: AnimatedSprite3D
var hamster_route: Array[Vector3] = []
var hamster_segment_index: int = 0
var hamster_segment_distance: float = 0.0
var hamster_speed: float = 3.0

# Character animations should be named like: bijou_down, bijou_up,
# bijou_left, bijou_right (and similarly for each character).
const HAMSTER_CHARACTERS: Array[String] = ["bijou", "hamtaro", "boss", "penelope"]
const HAMSTER_SHEET_SECONDS := 2.5
const HAMSTER_HEIGHT := 0.65

var hamster_character_index: int = 0
var hamster_character_clock: float = 0.0
var hamster_current_direction: String = "down"

const EXTRA_HAMSTERS := 3

class Walker:
	var sprite: AnimatedSprite3D
	var segment: int = 0
	var distance: float = 0.0
	var speed: float = 3.0
	var character: String = ""
	var direction: String = ""

var walkers: Array[Walker] = []

func _ready() -> void:
	snapshot_path = ProjectSettings.globalize_path("user://snapshot.json")
	stop_path = snapshot_path + ".stop"
	_build_world()
	_create_route_hamster()
	_spawn_walkers()
	_build_ui()
	
	var timer := Timer.new()
	timer.wait_time = 0.5
	timer.timeout.connect(_poll_snapshot)
	add_child(timer)
	timer.start()


func _process(delta: float) -> void:
	if route_hamster == null or hamster_route.size() < 2:
		return
	
	_move_walkers(delta)
	
	# Rotate through the four character animation sets.
	hamster_character_clock += delta
	if hamster_character_clock >= HAMSTER_SHEET_SECONDS:
		hamster_character_clock = 0.0
		hamster_character_index = (
			hamster_character_index + 1
		) % HAMSTER_CHARACTERS.size()
		_play_hamster_animation(hamster_current_direction)

	# Move smoothly along the current route segment.
	# hamster_segment_distance += hamster_speed * delta
	hamster_segment_distance += hamster_speed * _speed_scale() * delta
	var safety_count := 0

	while safety_count < hamster_route.size():
		var from_point := hamster_route[hamster_segment_index]
		var next_index := (hamster_segment_index + 1) % hamster_route.size()
		var to_point := hamster_route[next_index]
		var segment_length := from_point.distance_to(to_point)

		if segment_length <= 0.001:
			hamster_segment_index = next_index
			safety_count += 1
			continue

		if hamster_segment_distance >= segment_length:
			hamster_segment_distance -= segment_length
			hamster_segment_index = next_index
			safety_count += 1
		else:
			var progress := hamster_segment_distance / segment_length
			route_hamster.position = from_point.lerp(
				to_point,
				progress
			) + Vector3(0, HAMSTER_HEIGHT, 0)

			var movement := to_point - from_point
			var new_direction := _route_direction(movement)
			if new_direction != hamster_current_direction:
				hamster_current_direction = new_direction
				_play_hamster_animation(hamster_current_direction)
			break

func _spawn_walkers() -> void:
	var frames := route_hamster.sprite_frames
	if frames == null:
		return

	# Only use characters whose animations actually exist.
	var valid: Array[String] = []
	for c in HAMSTER_CHARACTERS:
		if frames.has_animation(c + "_down"):
			valid.append(c)
	if valid.is_empty():
		push_warning("Walkers: no '<character>_down' animations in SpriteFrames.")
		return

	for i in EXTRA_HAMSTERS:
		var w := Walker.new()
		w.sprite = AnimatedSprite3D.new()
		w.sprite.sprite_frames = frames
		w.sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		w.sprite.pixel_size = route_hamster.pixel_size
		w.sprite.visible = false  # hidden until a route exists
		w.character = valid.pick_random()
		w.speed = randf_range(2.0, 4.0)
		add_child(w.sprite)
		walkers.append(w)


func _move_walkers(delta: float) -> void:
	var n := hamster_route.size()
	for w in walkers:
		if not w.sprite.visible:
			w.segment = randi() % n  # random starting spot on the route
			w.distance = 0.0
			w.sprite.visible = true

		w.segment %= n
		# w.distance += w.speed * delta
		w.distance += w.speed * _speed_scale() * delta

		for _i in n:
			var from_point := hamster_route[w.segment]
			var next_index := (w.segment + 1) % n
			var to_point := hamster_route[next_index]
			var length := from_point.distance_to(to_point)

			if length > 0.001 and w.distance < length:
				w.sprite.position = from_point.lerp(to_point, w.distance / length) + Vector3(0, HAMSTER_HEIGHT, 0)
				var dir := _route_direction(to_point - from_point)
				if dir != w.direction:
					w.direction = dir
					w.sprite.play(w.character + "_" + dir)
				break

			w.distance -= length
			w.segment = next_index

func _route_direction(movement: Vector3) -> String:
	# In this top-down world: -Z is up, +Z is down, -X left, +X right.
	if absf(movement.x) > absf(movement.z):
		return "right" if movement.x > 0.0 else "left"
	return "down" if movement.z > 0.0 else "up"


func _play_hamster_animation(direction: String) -> void:
	if route_hamster == null or route_hamster.sprite_frames == null:
		return

	var character := HAMSTER_CHARACTERS[hamster_character_index]
	var animation_name := character + "_" + direction
	var frames := route_hamster.sprite_frames

	if frames.has_animation(animation_name):
		route_hamster.play(animation_name)
	elif frames.has_animation("walk_" + direction):
		# Optional fallback if you have only one set of directional animations.
		route_hamster.play("walk_" + direction)
	elif frames.has_animation("walk"):
		route_hamster.play("walk")
	elif frames.get_animation_names().size() > 0:
		# Keep the character visible even before all animation names are set up.
		route_hamster.play(frames.get_animation_names()[0])

func _build_world() -> void:
	var environment_node := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("#dce8d3")
	environment_node.environment = environment
	add_child(environment_node)

	var camera := Camera3D.new()
	camera.position = Vector3(-2, 65, 0)
	camera.rotation_degrees = Vector3(-90, 0, 0)
	camera.fov = 45.0
	camera.current = true
	add_child(camera)

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-48, -25, 0)
	light.light_energy = 1.25
	add_child(light)

	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(36, 36)
	ground.mesh = plane
	var ground_mat := StandardMaterial3D.new()
	ground_mat.albedo_color = Color("#a9c49a")
	ground_mat.roughness = 1.0
	ground.material_override = ground_mat
	ground.position.y = -0.2
	add_child(ground)

	# A subtle circular colony pad gives the scene a friendly game-like feel.
	var pad := MeshInstance3D.new()
	var pad_mesh := CylinderMesh.new()
	pad_mesh.top_radius = 2.1
	pad_mesh.bottom_radius = 2.2
	pad_mesh.height = 0.25
	pad.mesh = pad_mesh
	pad.position = Vector3(-15.0, -0.02, 14.0)
	var pad_mat := StandardMaterial3D.new()
	pad_mat.albedo_color = Color("#e7d5a8")
	pad_mat.roughness = 1.0
	pad.material_override = pad_mat
	add_child(pad)
	_add_hamster_mascot(Vector3(-15.0, 0.25, 14.0))

	cities_root = Node3D.new()
	cities_root.name = "CitiesAndBestRoute"
	add_child(cities_root)

func _add_hamster_mascot(center: Vector3) -> void:
	# Simple low-poly hamster made from spheres; no external assets required.
	var body := _make_sphere(0.72, Color("#c99569"))
	body.position = center + Vector3(0, 0.65, 0)
	add_child(body)

	var head := _make_sphere(0.52, Color("#d7ad80"))
	head.position = center + Vector3(0.0, 1.25, -0.28)
	add_child(head)

	for side in [-1.0, 1.0]:
		var ear := _make_sphere(0.19, Color("#c99569"))
		ear.position = center + Vector3(side * 0.34, 1.65, -0.28)
		add_child(ear)
		var inner_ear := _make_sphere(0.10, Color("#e9a5a0"))
		inner_ear.position = center + Vector3(side * 0.34, 1.67, -0.17)
		add_child(inner_ear)
		var eye := _make_sphere(0.055, Color("#3b332d"))
		eye.position = center + Vector3(side * 0.18, 1.32, -0.73)
		add_child(eye)

	var nose := _make_sphere(0.075, Color("#d78387"))
	nose.position = center + Vector3(0, 1.16, -0.78)
	add_child(nose)

func _make_sphere(radius: float, color: Color) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	node.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.9
	node.material_override = material
	return node

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 2
	add_child(layer)

	# Left control panel
	var panel := PanelContainer.new()
	panel.anchor_left = 0.0
	panel.anchor_top = 0.0
	panel.anchor_right = 0.0
	panel.anchor_bottom = 1.0
	panel.offset_left = 18
	panel.offset_top = 18
	panel.offset_right = 350
	panel.offset_bottom = -18
	panel.add_theme_stylebox_override("panel", _panel_style(UI_PANEL, 22))
	layer.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	panel.add_child(margin)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(scroll)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(box)

	var title := Label.new()
	title.text = "HAMSTERHOARD"
	title.add_theme_font_size_override("font_size", 25)
	title.add_theme_color_override("font_color", UI_GREEN_DARK)
	box.add_child(title)

	# var subtitle := Label.new()
	# subtitle.text = "A tiny colony solving a big route 🐹"
	# subtitle.add_theme_font_size_override("font_size", 13)
	# subtitle.add_theme_color_override("font_color", UI_MUTED)
	# subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# box.add_child(subtitle)
	
	
	_add_section_title(box, "ENGINE CONNECTION")
	executable_input = _add_line(box, "C++ executable", _default_engine_path())
	mpi_launcher_input = _add_line(box, "MPI launcher", "mpiexec.exe" if OS.get_name() == "Windows" else "mpirun")

	_add_section_title(box, "COLONY SETTINGS")
	process_input = _add_spin(box, "MPI ranks", 1, 4, 1)
	thread_input = _add_spin(box, "OpenMP threads / rank", 1, 4, 1)
	city_input = _add_spin(box, "Cities", 3, 10000, 300)
	population_input = _add_spin(box, "Population / rank", 4, 10000, 500)
	generation_input = _add_spin(box, "Generations", 1, 100000, 750)
	delay_input = _add_spin(box, "Delay / generation (ms)", 0, 1000, 1000)
	speed_input = _add_spin(box, "Hamster speed %", 10, 300, 50)
	
	var button_row := HBoxContainer.new()
	button_row.add_theme_constant_override("separation", 8)
	box.add_child(button_row)

	start_button = Button.new()
	start_button.text = "▶  Start run"
	start_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	start_button.custom_minimum_size = Vector2(0, 42)
	_style_button(start_button, UI_GREEN, UI_GREEN_DARK)
	start_button.pressed.connect(_start_simulation)
	button_row.add_child(start_button)

	stop_button = Button.new()
	stop_button.text = "■  Stop"
	stop_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stop_button.custom_minimum_size = Vector2(0, 42)
	_style_button(stop_button, Color("#e9d4c4"), Color("#d7b5a0"))
	stop_button.disabled = true
	stop_button.pressed.connect(_stop_simulation)
	button_row.add_child(stop_button)

	status_label = Label.new()
	status_label.text = "●  Ready to explore"
	status_label.add_theme_color_override("font_color", UI_GREEN_DARK)
	status_label.add_theme_font_size_override("font_size", 13)
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(status_label)

	var hint := Label.new()
	hint.text = "Snapshots refresh every 5 generations. Try 1 rank × 1 thread first, then explore MPI and OpenMP."
	hint.add_theme_color_override("font_color", UI_MUTED)
	hint.add_theme_font_size_override("font_size", 12)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(hint)

	# Top-right live metrics card
	var metrics_panel := PanelContainer.new()
	metrics_panel.anchor_left = 1.0
	metrics_panel.anchor_top = 0.0
	metrics_panel.anchor_right = 1.0
	metrics_panel.anchor_bottom = 0.0
	metrics_panel.offset_left = -280
	metrics_panel.offset_top = 18
	metrics_panel.offset_right = -18
	metrics_panel.offset_bottom = 220
	metrics_panel.add_theme_stylebox_override("panel", _panel_style(UI_PANEL, 20))
	layer.add_child(metrics_panel)

	var metrics_margin := MarginContainer.new()
	metrics_margin.add_theme_constant_override("margin_left", 16)
	metrics_margin.add_theme_constant_override("margin_right", 16)
	metrics_margin.add_theme_constant_override("margin_top", 12)
	metrics_margin.add_theme_constant_override("margin_bottom", 12)
	metrics_panel.add_child(metrics_margin)

	var metrics_box := VBoxContainer.new()
	metrics_box.add_theme_constant_override("separation", 6)
	metrics_margin.add_child(metrics_box)

	var metrics_title := Label.new()
	metrics_title.text = "COLONY REPORT"
	metrics_title.add_theme_font_size_override("font_size", 15)
	metrics_title.add_theme_color_override("font_color", UI_GREEN_DARK)
	metrics_box.add_child(metrics_title)

	generation_label = _add_metric(metrics_box, "Generation", "Waiting…")
	best_label = _add_metric(metrics_box, "Best route", "—")
	average_label = _add_metric(metrics_box, "Average distance", "—")
	ranks_label = _add_metric(metrics_box, "MPI ranks", "—")

func _add_section_title(parent: VBoxContainer, text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", UI_GREEN)
	parent.add_child(label)

func _add_metric(parent: VBoxContainer, caption: String, value: String) -> Label:
	var label := Label.new()
	label.text = caption + ": " + value
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", UI_TEXT)
	parent.add_child(label)
	return label

func _add_line(parent: VBoxContainer, caption: String, value: String) -> LineEdit:
	var label := Label.new()
	label.text = caption
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", UI_MUTED)
	parent.add_child(label)

	var edit := LineEdit.new()
	edit.text = value
	edit.custom_minimum_size = Vector2(0, 32)
	edit.add_theme_stylebox_override("normal", _panel_style(Color("#fffdf8"), 9))
	edit.add_theme_color_override("font_color", UI_TEXT)
	parent.add_child(edit)
	return edit

func _add_spin(parent: VBoxContainer, caption: String, minimum: int, maximum: int, value: int) -> SpinBox:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)

	var label := Label.new()
	label.text = caption
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", UI_TEXT)
	row.add_child(label)

	var spin := SpinBox.new()
	spin.min_value = minimum
	spin.max_value = maximum
	spin.step = 1
	spin.value = value
	spin.custom_minimum_size = Vector2(90, 30)
	spin.add_theme_color_override("font_color", UI_TEXT)
	row.add_child(spin)
	return spin

func _panel_style(color: Color, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_left = radius
	style.corner_radius_bottom_right = radius
	style.border_width_left = 1
	style.border_width_right = 1
	style.border_width_top = 1
	style.border_width_bottom = 1
	style.border_color = Color("#e3dfce")
	style.shadow_color = Color(0, 0, 0, 0.08)
	style.shadow_size = 5
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	return style

func _style_button(button: Button, normal_color: Color, hover_color: Color) -> void:
	button.add_theme_stylebox_override("normal", _panel_style(normal_color, 12))
	button.add_theme_stylebox_override("hover", _panel_style(hover_color, 12))
	button.add_theme_stylebox_override("pressed", _panel_style(UI_ORANGE, 12))
	button.add_theme_color_override("font_color", Color("#fffaf0"))
	button.add_theme_color_override("font_hover_color", Color("#fffaf0"))
	button.add_theme_color_override("font_pressed_color", Color("#fffaf0"))
	button.add_theme_font_size_override("font_size", 13)

func _default_engine_path() -> String:
	if OS.get_name() == "Windows":
		return ProjectSettings.globalize_path("res://../engine/build/Release/hamsterhoard.exe")
	return ProjectSettings.globalize_path("res://../engine/build/hamsterhoard")

func _start_simulation() -> void:
	if engine_pid > 0 and OS.is_process_running(engine_pid):
		status_label.text = "●  A run is already in progress"
		return

	var engine := executable_input.text.strip_edges()
	if not FileAccess.file_exists(engine):
		status_label.text = "Engine not found. Build it and check the executable path."
		return

	# Remove previous run's files so the UI cannot display stale data.
	if FileAccess.file_exists(snapshot_path):
		DirAccess.remove_absolute(snapshot_path)
	if FileAccess.file_exists(stop_path):
		DirAccess.remove_absolute(stop_path)
	last_data.clear()

	generation_label.text = "Generation: waiting…"
	best_label.text = "Best route: —"
	average_label.text = "Average distance: —"
	ranks_label.text = "MPI ranks: —"

	var ranks := int(process_input.value)
	var threads := int(thread_input.value)
	var args: Array[String] = []
	if OS.get_name() == "Windows":
		args = ["-n", str(ranks), engine]
	else:
		args = ["-np", str(ranks), engine]

	args.append_array([
		"--cities", str(int(city_input.value)),
		"--population", str(int(population_input.value)),
		"--generations", str(int(generation_input.value)),
		"--threads", str(threads),
		"--migration-interval", "25",
		"--migration-count", "1",
		"--seed", "42",
		"--output", snapshot_path,
		"--delay-ms", str(int(delay_input.value))
	])

	var launcher := mpi_launcher_input.text.strip_edges()
	engine_pid = OS.create_process(launcher, args, false)
	if engine_pid == -1:
		status_label.text = "Could not launch MPI. Check the launcher and paths."
		start_button.disabled = false
		stop_button.disabled = true
	else:
		status_label.text = "●  Running — %d rank(s) × %d thread(s)" % [ranks, threads]
		start_button.disabled = true
		stop_button.disabled = false

func _stop_simulation() -> void:
	if engine_pid <= 0 or not OS.is_process_running(engine_pid):
		status_label.text = "●  No active run"
		engine_pid = -1
		start_button.disabled = false
		stop_button.disabled = true
		return

	var file := FileAccess.open(stop_path, FileAccess.WRITE)
	if file:
		file.store_string("stop")
		file.close()
		status_label.text = "●  Stop requested — finishing current generation"
		await get_tree().create_timer(5.0).timeout # for readability's sake
	else:
		status_label.text = "Could not create stop request file."

func _poll_snapshot() -> void:
	# Reset the process state when the MPI launcher exits.
	if engine_pid > 0 and not OS.is_process_running(engine_pid):
		engine_pid = -1
		start_button.disabled = false
		stop_button.disabled = true
		status_label.text = "●  Run finished"

	if not FileAccess.file_exists(snapshot_path):
		return

	var file := FileAccess.open(snapshot_path, FileAccess.READ)
	if file == null:
		return
	var content := file.get_as_text()
	file.close()

	var parsed = JSON.parse_string(content)
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	if parsed == last_data:
		return

	last_data = parsed
	_apply_snapshot(parsed)

	if engine_pid > 0:
		status_label.text = "●  Live snapshot — generation %s" % str(parsed.get("generation", "?"))

func _apply_snapshot(data: Dictionary) -> void:
	generation_label.text = "Generation: %d" % int(data.get("generation", 0))
	best_label.text = "Best route: %.3f" % float(data.get("best_distance", 0.0))
	average_label.text = "Average distance: %.3f" % float(data.get("average_distance", 0.0))
	ranks_label.text = "MPI ranks: %d" % int(data.get("world_size", 1))
	_draw_snapshot(data)

func _draw_snapshot(data: Dictionary) -> void:
	for child in cities_root.get_children():
		child.queue_free()

	var cities: Array = data.get("cities", [])
	var route: Array = data.get("best_route", [])
	if cities.is_empty():
		return

	var points: Array[Vector3] = []
	for city in cities:
		# Backend coordinates are generated in [0, 100] × [0, 100].
		points.append(Vector3(
			(float(city[0]) - 50.0) * 0.28,
			0.16,
			(float(city[1]) - 50.0) * 0.28
		))
	
	# Copy the current best route into the hamster's path.
	var had_route := hamster_route.size() >= 2
	hamster_route.clear()
	
	for city_index in route:
		var index := int(city_index)
	
		if index >= 0 and index < points.size():
			hamster_route.append(points[index])
	
	if hamster_route.size() >= 2:
		hamster_segment_index = (
			hamster_segment_index % hamster_route.size()
		)

		if not had_route:
			hamster_segment_index = 0
			hamster_segment_distance = 0.0

			route_hamster.position = (
				hamster_route[0] + Vector3(0, HAMSTER_HEIGHT, 0)
			)


	# MultiMesh renders hundreds or thousands of city markers efficiently.
	var marker_mesh := SphereMesh.new()
	marker_mesh.radius = 0.35
	marker_mesh.height = 0.26
	var marker_material := StandardMaterial3D.new()
	marker_material.albedo_color = CITY_COLOR
	marker_material.roughness = 0.75

	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = marker_mesh
	multimesh.instance_count = points.size()
	for i in range(points.size()):
		multimesh.set_instance_transform(i, Transform3D(Basis(), points[i]))

	var marker_instance := MultiMeshInstance3D.new()
	marker_instance.multimesh = multimesh
	marker_instance.material_override = marker_material
	cities_root.add_child(marker_instance)

	# Draw the closed tour as orange line segments.
	if route.size() >= 2:
		var route_mesh := ImmediateMesh.new()
		var route_material := StandardMaterial3D.new()
		route_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		route_material.albedo_color = ROUTE_COLOR
		route_mesh.surface_begin(Mesh.PRIMITIVE_LINES, route_material)

		for i in range(route.size()):
			var from_index := int(route[i])
			var to_index := int(route[(i + 1) % route.size()])
			if from_index < 0 or from_index >= points.size() or to_index < 0 or to_index >= points.size():
				continue
			route_mesh.surface_add_vertex(points[from_index] + Vector3(0, 0.10, 0))
			route_mesh.surface_add_vertex(points[to_index] + Vector3(0, 0.10, 0))

		route_mesh.surface_end()
		var route_instance := MeshInstance3D.new()
		route_instance.mesh = route_mesh
		cities_root.add_child(route_instance)

		# Highlight the first city in the route with a larger warm marker.
		var start_marker := _make_sphere(0.27, Color("#f08a45"))
		start_marker.position = points[int(route[0])] + Vector3(0, 0.18, 0)
		cities_root.add_child(start_marker)


func _create_route_hamster() -> void:
	# Reuse the AnimatedSprite3D node already present in main.tscn.
	route_hamster = $AnimatedSprite3D
	route_hamster.name = "RouteHamster"
	route_hamster.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	route_hamster.pixel_size = 0.05
	route_hamster.centered = true
	route_hamster.position = Vector3(0, HAMSTER_HEIGHT, 0)

	if route_hamster.sprite_frames == null:
		push_warning("Assign a SpriteFrames resource to AnimatedSprite3D in main.tscn.")
		return

	_play_hamster_animation(hamster_current_direction)

func _speed_scale() -> float:
	return speed_input.value / 100.0
