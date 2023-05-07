extends EditorExportPlugin


var _platform: EditorExportPlatform
var _features: PackedStringArray
var _preprocessor := preload("preprocessor.gd").new()


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
	var gds := resource as GDScript
	if not gds:
		return null

	var new_gds := GDScript.new()
	if _preprocessor.preprocess(gds.source_code):
		new_gds.source_code = _preprocessor.result
	else:
		printerr("%s:%s - %s" % ["<unknown>" if path.is_empty() else path,
				_preprocessor.error_line, _preprocessor.error_message])

	return new_gds
