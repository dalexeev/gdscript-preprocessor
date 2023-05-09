extends SceneTree


var _preprocessor := preload("addons/gdscript_preprocessor/preprocessor.gd").new()


func _init() -> void:
	for file_name in DirAccess.get_files_at("tests/"):
		if not file_name.ends_with(".gd"):
			continue

		var gd_path := "tests/".path_join(file_name)
		var gd_file := FileAccess.open(gd_path, FileAccess.READ)
		if not gd_file.is_open():
			printerr('Failed to open "%s".' % gd_path)
			quit(1)
			return
		var gd_text := gd_file.get_as_text()
		gd_file.close()

		var txt_path := gd_path.trim_suffix(".gd") + ".txt"
		var txt_file := FileAccess.open(txt_path, FileAccess.READ)
		if not txt_file.is_open():
			printerr('Failed to open "%s".' % txt_path)
			quit(1)
			return
		var txt_text := txt_file.get_as_text()
		txt_file.close()

		var result: String

		_preprocessor.features.clear()
		_preprocessor.is_debug = false

		var params := gd_text.get_slice("\n", 0)
		if params.begins_with("# PARAMS: "):
			params = params.trim_prefix("# PARAMS: ")
			_preprocessor.features = params.get_slice(" ", 0).trim_prefix("features=").split(",")
			_preprocessor.is_debug = params.get_slice(" ", 1).trim_prefix("is_debug=") == "true"

		if _preprocessor.preprocess(gd_text):
			result = "OK\n" + _preprocessor.result
		else:
			result = "ERROR\nLine: %d\nMessage: %s\n" % [
				_preprocessor.error_line,
				_preprocessor.error_message,
			]

		if result != txt_text:
			printerr('Test "%s" failed.' % gd_path)
			printerr('The result does NOT match the ".txt" file:')
			printerr(result)
			quit(1)
			return

	print("All tests passed!")
	quit(0)
