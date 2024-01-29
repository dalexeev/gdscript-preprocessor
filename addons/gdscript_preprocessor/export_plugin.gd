extends EditorExportPlugin


@warning_ignore("inferred_declaration")
const _Preprocessor = preload("./preprocessor.gd")

var _preprocessor: _Preprocessor = _Preprocessor.new()


func _get_name() -> String:
	return "gdscript_preprocessor"


func _get_export_options(_platform: EditorExportPlatform) -> Array[Dictionary]:
	return [
		{
			option = {
				name = "gdscript_preprocessor/statement_removing_regex_debug",
				type = TYPE_STRING,
			},
			default_value = "",
		},
		{
			option = {
				name = "gdscript_preprocessor/statement_removing_regex_release",
				type = TYPE_STRING,
			},
			default_value = r"^(?:@tool|breakpoint|assert\(|print_debug\(|print_stack\()",
		},
		{
			option = {
				name = "gdscript_preprocessor/dynamic_feature_tags",
				type = TYPE_STRING,
			},
			default_value = "arm,arm32,arm64,arm64-v8a,armeabi,armeabi-v7a,bsd,freebsd" \
					+ ",linux,linuxbsd,movie,netbsd,openbsd,system_fonts,web_android" \
					+ ",web_ios,web_linuxbsd,web_macos,web_windows",
		},
	]


func _export_begin(
		features: PackedStringArray,
		is_debug: bool,
		_path: String,
		_flags: int,
) -> void:
	_preprocessor.features = features
	_preprocessor.is_debug = is_debug

	var regex: String
	if is_debug:
		regex = get_option(&"gdscript_preprocessor/statement_removing_regex_debug")
	else:
		regex = get_option(&"gdscript_preprocessor/statement_removing_regex_release")

	if regex.is_empty():
		_preprocessor.statement_removing_regex = null
	else:
		_preprocessor.statement_removing_regex = RegEx.create_from_string(regex)
		if not _preprocessor.statement_removing_regex.is_valid():
			if is_debug:
				printerr("Invalid statement removing regex for debug builds.")
			else:
				printerr("Invalid statement removing regex for release builds.")

	var tags: String = get_option(&"gdscript_preprocessor/dynamic_feature_tags")
	_preprocessor.set_dynamic_feature_tags(tags.split(","))


func _export_file(path: String, type: String, _features: PackedStringArray) -> void:
	if type != "GDScript":
		return

	if _preprocessor.preprocess(FileAccess.get_file_as_string(path)):
		skip()
		add_file(path, _preprocessor.result.to_utf8_buffer(), false)
	else:
		printerr("%s:%s - %s" % [
			"<unknown>" if path.is_empty() else path,
			_preprocessor.error_line,
			_preprocessor.error_message,
		])
