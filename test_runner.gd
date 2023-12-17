extends SceneTree


@warning_ignore("inferred_declaration")
const _Preprocessor = preload("./addons/gdscript_preprocessor/preprocessor.gd")

var _preprocessor: _Preprocessor = _Preprocessor.new()


func _init() -> void:
	for file_name: String in DirAccess.get_files_at("tests/"):
		if not file_name.ends_with(".gd"):
			continue

		var gd_path: String = "tests/".path_join(file_name)
		var gd_file: FileAccess = FileAccess.open(gd_path, FileAccess.READ)
		if not gd_file.is_open():
			printerr('Failed to open "%s".' % gd_path)
			quit(1)
			return
		var gd_text: String = gd_file.get_as_text()
		gd_file.close()

		var txt_path: String = gd_path.trim_suffix(".gd") + ".txt"
		var txt_file: FileAccess = FileAccess.open(txt_path, FileAccess.READ)
		if not txt_file.is_open():
			printerr('Failed to open "%s".' % txt_path)
			quit(1)
			return
		var txt_text: String = txt_file.get_as_text()
		txt_file.close()

		_preprocessor.features.clear()
		_preprocessor.is_debug = false
		_preprocessor.statement_removing_regex = null

		var i: int = 0
		while true:
			var line: String = gd_text.get_slice("\n", i)
			if line.begins_with("# features="):
				_preprocessor.features = line.trim_prefix("# features=").split(",")
			elif line.begins_with("# is_debug="):
				_preprocessor.is_debug = line.trim_prefix("# is_debug=") == "true"
			elif line.begins_with("# statement_removing_regex="):
				_preprocessor.statement_removing_regex = RegEx.create_from_string(
						line.trim_prefix("# statement_removing_regex="))
			else:
				break
			i += 1

		var result: String

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
