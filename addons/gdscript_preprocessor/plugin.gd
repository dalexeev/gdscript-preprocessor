@tool
extends EditorPlugin


const _ExportPlugin = preload("./export_plugin.gd")

var _export_plugin: _ExportPlugin = _ExportPlugin.new()


func _enter_tree() -> void:
	add_export_plugin(_export_plugin)


func _exit_tree() -> void:
	remove_export_plugin(_export_plugin)
