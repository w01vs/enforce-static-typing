@tool
extends EditorPlugin

var file_system: EditorFileSystem
var last_errors: Array[String] = []
var editor_interface: EditorInterface

var original_run_function: Callable


func _enter_tree() -> void:
	# Access the file system and check the scripts when the plugin is loaded
	file_system = get_editor_interface().get_resource_filesystem()
	check_all_scripts()
	# Optional: add a toolbar button
	add_tool_menu_item("Check Typed Scripts", _on_check_scripts)

	resource_saved.connect(_on_resource_saved)


func _exit_tree() -> void:
	# Remove toolbar item when the plugin is unloaded
	remove_tool_menu_item("Check Typed Scripts")


func _on_resource_saved(res: Resource) -> void:
	if res is GDScript and not res.resource_path.begins_with("res://addons"):
		_check_script(res)


func _on_check_scripts() -> void:
	# Manually trigger script check (can be used from the tool menu item)
	check_all_scripts()


func check_all_scripts() -> void:
	# Start checking the scripts in the project
	var scripts = _get_all_gd_scripts("res://")  # adjust path as needed
	for script_path in scripts:
		var script: Resource = load(script_path)
		if script is GDScript:
			_check_script(script)


func _get_all_gd_scripts(folder: String) -> Array:
	# Recursively get all .gd scripts under the specified folder
	var result: Array = []
	var dir: DirAccess = DirAccess.open(folder)
	if not dir:
		return result

	dir.list_dir_begin()
	var file: String = dir.get_next()
	while file != "":
		var full_path: String = folder.path_join(file)
		if dir.current_is_dir():
			if full_path.begins_with("res://addons"):  # Skip addon directories
				file = dir.get_next()
				continue
			# Recursively process subdirectories
			result += _get_all_gd_scripts(full_path)
		elif file.ends_with(".gd"):  # Only consider .gd files
			result.append(full_path)
		file = dir.get_next()
	dir.list_dir_end()
	return result


func _check_script(script: GDScript) -> void:
	var code: String = script.source_code
	var issues: Array = []
	var lines: PackedStringArray = code.split("\n")

	var var_regex: RegEx = RegEx.new()
	var_regex.compile(r"^(?:@[\w\s]+)*\s*(var|const)\s+\w+")

	for i in lines.size():
		var line: String = lines[i].strip_edges()
		var line_number: int = i + 1

		# Skip empty lines and comments
		if line == "" or line.begins_with("#"):
			continue

		# Check for untyped functions
		if line.begins_with("func ") and (":" not in line or "->" not in line):
			issues.append("Line %d: Untyped function: %s" % [line_number, line])
			continue

		# Check for variable/constant declarations
		if var_regex.search(line):
			# Extract the type part of the line (after the colon)
			var type_str: String = ""
			var type_match: int = line.find(":")
			var equals_match: int = line.find("=")
			if type_match > -1 and equals_match > type_match:
				type_str = line.substr(type_match + 1, equals_match - type_match - 1).strip_edges()
			elif type_match < 0:
				issues.append("Line %d: Missing type: %s" % [line_number, line])
				continue

			var after_colon: String = line.substr(type_match + 1).strip_edges()
			if after_colon.begins_with("=") or after_colon == "":
				issues.append("Line %d: Missing type: %s" % [line_number, line])
				continue

			if line.contains(":="):
				issues.append("Line %d: Using disallowed type inference: %s" % [line_number, line])
				continue
			# Check if the type is valid

	if issues.size() > 0:
		push_warning("Typing issues in %s:\n  %s" % [script.resource_path, "\n  ".join(issues)])
