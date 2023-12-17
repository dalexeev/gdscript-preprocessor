extends EditorExportPlugin


@warning_ignore("inferred_declaration")
const _Preprocessor = preload("./preprocessor.gd")

var _config_path: String
var _platform: EditorExportPlatform
var _features: PackedStringArray
var _preprocessor: _Preprocessor = _Preprocessor.new()


func _init() -> void:
	var script: Script = get_script()
	_config_path = ProjectSettings.globalize_path(script.resource_path) \
			.get_base_dir().path_join("options.cfg")


func _get_name() -> String:
	return "gdscript_preprocessor"


func _export_begin(
		features: PackedStringArray,
		is_debug: bool,
		_path: String,
		_flags: int,
) -> void:
	_features = features
	_preprocessor.features = features
	_preprocessor.is_debug = is_debug

	var regex: String
	var config: ConfigFile = ConfigFile.new()
	var _err: Error = config.load(_config_path)
	if is_debug:
		regex = _get_option(config, "statements", "removing_regex_debug", "")
	else:
		regex = _get_option(config, "statements", "removing_regex_release",
				r"^(?:breakpoint|assert\(|print_debug\(|print_stack\()")
	if not regex.is_empty():
		_preprocessor.statement_removing_regex = RegEx.create_from_string(regex)
		if not _preprocessor.statement_removing_regex.is_valid():
			if is_debug:
				printerr("Invalid statement removing regex for debug builds.")
			else:
				printerr("Invalid statement removing regex for release builds.")


func _begin_customize_resources(
		platform: EditorExportPlatform,
		features: PackedStringArray,
) -> bool:
	_platform = platform
	assert(_features == features)
	return true


func _get_customization_configuration_hash() -> int:
	return hash(_platform) + hash(_features)


func _customize_resource(resource: Resource, path: String) -> Resource:
	var gds: GDScript = resource as GDScript
	if not gds:
		return null

	if _preprocessor.preprocess(gds.source_code):
		var new_gds: GDScript = GDScript.new()
		new_gds.source_code = _preprocessor.result
		return new_gds
	else:
		printerr("%s:%s - %s" % [
			"<unknown>" if path.is_empty() else path,
			_preprocessor.error_line,
			_preprocessor.error_message,
		])
		return null


func _get_option(config: ConfigFile, section: String, key: String, default: Variant) -> Variant:
	var value: Variant = config.get_value(section, key, default)
	return value if typeof(value) == typeof(default) else default
