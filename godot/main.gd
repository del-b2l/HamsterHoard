extends Node3D

# Minimal integrated controller/viewer. The C++ executable performs all GA/MPI/OpenMP work.
var engine_pid: int = -1
var snapshot_path: String
var stop_path: String
var last_snapshot_mtime: int = 0
var cities_root: Node3D
var route_mesh: MeshInstance3D
var status_label: Label
var metrics_label: Label
var process_input: SpinBox
var thread_input: SpinBox
var city_input: SpinBox
var population_input: SpinBox
var generation_input: SpinBox
var executable_input: LineEdit
var mpi_launcher_input: LineEdit
var last_data: Dictionary = {}

func _ready() -> void:
    snapshot_path = ProjectSettings.globalize_path("user://snapshot.json")
    stop_path = snapshot_path + ".stop"
    _build_world()
    _build_ui()
    var timer := Timer.new()
    timer.wait_time = 0.5
    timer.timeout.connect(_poll_snapshot)
    add_child(timer)
    timer.start()

func _build_world() -> void:
    var camera := Camera3D.new()
    camera.position = Vector3(0, 28, 34)
    camera.rotation_degrees = Vector3(-38, 0, 0)
    camera.current = true
    add_child(camera)

    var light := DirectionalLight3D.new()
    light.rotation_degrees = Vector3(-55, -25, 0)
    light.light_energy = 1.2
    add_child(light)

    var ground := MeshInstance3D.new()
    var plane := PlaneMesh.new()
    plane.size = Vector2(34, 26)
    ground.mesh = plane
    var ground_mat := StandardMaterial3D.new()
    ground_mat.albedo_color = Color(0.24, 0.39, 0.27)
    ground_mat.roughness = 1.0
    ground.material_override = ground_mat
    ground.position.y = -0.15
    add_child(ground)

    cities_root = Node3D.new()
    cities_root.name = "CitiesAndRoute"
    add_child(cities_root)
    _draw_colony_markers()

func _draw_colony_markers() -> void:
    var positions := [Vector3(-12, 0.1, -8), Vector3(12, 0.1, -8),
                     Vector3(-12, 0.1, 8), Vector3(12, 0.1, 8)]
    var colors := [Color("#e5a84b"), Color("#7bb6d8"), Color("#d88a9a"), Color("#9dca82")]
    for i in range(4):
        var island := MeshInstance3D.new()
        var mesh := CylinderMesh.new()
        mesh.top_radius = 3.0
        mesh.bottom_radius = 3.2
        mesh.height = 0.45
        island.mesh = mesh
        var mat := StandardMaterial3D.new()
        mat.albedo_color = colors[i]
        island.material_override = mat
        island.position = positions[i]
        add_child(island)
        var hamster := MeshInstance3D.new()
        var body := SphereMesh.new()
        body.radius = 0.65
        body.height = 1.3
        hamster.mesh = body
        var hmat := StandardMaterial3D.new()
        hmat.albedo_color = Color("#c99468")
        hamster.material_override = hmat
        hamster.position = positions[i] + Vector3(0, 0.9, 0)
        add_child(hamster)

func _build_ui() -> void:
    var layer := CanvasLayer.new()
    add_child(layer)
    var panel := PanelContainer.new()
    panel.position = Vector2(16, 16)
    panel.size = Vector2(340, 750)
    layer.add_child(panel)
    var box := VBoxContainer.new()
    box.add_theme_constant_override("separation", 8)
    panel.add_child(box)

    var title := Label.new()
    title.text = "HAMSTERHOARD"
    title.add_theme_font_size_override("font_size", 24)
    box.add_child(title)
    var subtitle := Label.new()
    subtitle.text = "Hybrid MPI + OpenMP TSP Genetic Algorithm"
    subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    box.add_child(subtitle)

    executable_input = _add_line(box, "Engine executable", _default_engine_path())
    mpi_launcher_input = _add_line(box, "MPI launcher", "mpirun" if OS.get_name() != "Windows" else "mpiexec")
    process_input = _add_spin(box, "MPI processes", 1, 4, 1)
    thread_input = _add_spin(box, "OpenMP threads / process", 1, 4, 1)
    city_input = _add_spin(box, "Cities", 3, 10000, 80)
    population_input = _add_spin(box, "Population / island", 4, 10000, 120)
    generation_input = _add_spin(box, "Generations", 1, 100000, 200)

    var buttons := HBoxContainer.new()
    box.add_child(buttons)
    var start := Button.new()
    start.text = "Start"
    start.pressed.connect(_start_simulation)
    buttons.add_child(start)
    var stop := Button.new()
    stop.text = "Stop"
    stop.pressed.connect(_stop_simulation)
    buttons.add_child(stop)

    status_label = Label.new()
    status_label.text = "Status: Ready"
    status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    box.add_child(status_label)
    metrics_label = Label.new()
    metrics_label.text = "Waiting for first snapshot..."
    metrics_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    box.add_child(metrics_label)

    var note := Label.new()
    note.text = "Build the C++ engine first. Start with 1 process × 1 thread, then test MPI/OpenMP configurations. Snapshots update every 5 generations."
    note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    box.add_child(note)

func _add_line(parent: VBoxContainer, caption: String, value: String) -> LineEdit:
    var label := Label.new()
    label.text = caption
    parent.add_child(label)
    var edit := LineEdit.new()
    edit.text = value
    parent.add_child(edit)
    return edit

func _add_spin(parent: VBoxContainer, caption: String, minimum: int, maximum: int, value: int) -> SpinBox:
    var label := Label.new()
    label.text = caption
    parent.add_child(label)
    var spin := SpinBox.new()
    spin.min_value = minimum
    spin.max_value = maximum
    spin.step = 1
    spin.value = value
    parent.add_child(spin)
    return spin

func _default_engine_path() -> String:
    var base := ProjectSettings.globalize_path("res://../engine/build/hamsterhoard")
    if OS.get_name() == "Windows":
        return ProjectSettings.globalize_path("res://../engine/build/Release/hamsterhoard.exe")
    return base

func _start_simulation() -> void:
    if engine_pid > 0:
        status_label.text = "Status: Engine already running"
        return
    var engine := executable_input.text.strip_edges()
    if not FileAccess.file_exists(engine):
        status_label.text = "Engine not found. Build it and set the executable path."
        return
    if FileAccess.file_exists(snapshot_path):
        DirAccess.remove_absolute(snapshot_path)
    if FileAccess.file_exists(stop_path):
        DirAccess.remove_absolute(stop_path)
    var args := []
    if OS.get_name() == "Windows":
        args = ["-n", str(int(process_input.value)), engine]
    else:
        args = ["-np", str(int(process_input.value)), engine]
    args.append_array([
        "--cities", str(int(city_input.value)),
        "--population", str(int(population_input.value)),
        "--generations", str(int(generation_input.value)),
        "--threads", str(int(thread_input.value)),
        "--migration-interval", "25",
        "--migration-count", "1",
        "--seed", "42",
        "--output", snapshot_path
    ])
    var launcher := mpi_launcher_input.text.strip_edges()
    engine_pid = OS.create_process(launcher, args, false)
    if engine_pid == -1:
        status_label.text = "Could not launch MPI. Check launcher and executable paths."
    else:
        status_label.text = "Status: Running (PID %d)" % engine_pid

func _stop_simulation() -> void:
    if engine_pid <= 0:
        status_label.text = "Status: No active process"
        return
    var f := FileAccess.open(stop_path, FileAccess.WRITE)
    if f:
        f.store_string("stop")
        f.close()
        status_label.text = "Status: Stop requested; waiting for generation boundary"

func _poll_snapshot() -> void:
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
    status_label.text = "Status: Snapshot received (generation %s)" % str(parsed.get("generation", "?"))

func _apply_snapshot(data: Dictionary) -> void:
    var gen := int(data.get("generation", 0))
    var best := float(data.get("best_distance", 0.0))
    var avg := float(data.get("average_distance", 0.0))
    var ranks: Array = data.get("rank_best", [])
    metrics_label.text = "Generation: %d\nBest route: %.3f\nAverage colony distance: %.3f\nMPI ranks: %d\nRank best: %s" % [
        gen, best, avg, int(data.get("world_size", 1)), str(ranks)
    ]
    _draw_snapshot(data)

func _draw_snapshot(data: Dictionary) -> void:
    for child in cities_root.get_children():
        child.queue_free()
    var cities: Array = data.get("cities", [])
    var route: Array = data.get("best_route", [])
    if cities.is_empty():
        return
    var points: Array[Vector3] = []
    for c in cities:
        points.append(Vector3((float(c[0]) - 50.0) * 0.28, 0.12, (float(c[1]) - 50.0) * 0.28))
    for p in points:
        var marker := MeshInstance3D.new()
        var sphere := SphereMesh.new()
        sphere.radius = 0.13
        sphere.height = 0.26
        marker.mesh = sphere
        var mat := StandardMaterial3D.new()
        mat.albedo_color = Color("#f5d76e")
        marker.material_override = mat
        marker.position = p
        cities_root.add_child(marker)
    if route.size() >= 2:
        var immediate := ImmediateMesh.new()
        var material := StandardMaterial3D.new()
        material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
        material.albedo_color = Color("#f08a45")
        immediate.surface_begin(Mesh.PRIMITIVE_LINES, material)
        for i in range(route.size()):
            var a := points[int(route[i])]
            var b := points[int(route[(i + 1) % route.size()])]
            immediate.surface_add_vertex(a + Vector3(0, 0.08, 0))
            immediate.surface_add_vertex(b + Vector3(0, 0.08, 0))
        immediate.surface_end()
        route_mesh = MeshInstance3D.new()
        route_mesh.mesh = immediate
        cities_root.add_child(route_mesh)
