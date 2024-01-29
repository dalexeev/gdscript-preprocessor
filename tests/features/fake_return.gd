# is_debug=true

var var_set_get: int:
	set(value):
		if OS.is_debug_build():
			prints(1, value)
		else:
			prints(2, value)
	get:
		if OS.is_debug_build():
			return 1
		else:
			return 2

var var_get_set: int:
	get:
		if OS.is_debug_build():
			return 1
		else:
			return 2
	set(value):
		if OS.is_debug_build():
			prints(1, value)
		else:
			prints(2, value)

@warning_ignore("untyped_declaration")
var var_untyped:
	get:
		if OS.is_debug_build():
			return 1
		else:
			return 2

var var_int: int:
	get:
		if OS.is_debug_build():
			return 1
		else:
			return 2

var var_array_int: Array[int]:
	get:
		if OS.is_debug_build():
			return [1]
		else:
			return [2]

var var_object: Object:
	get:
		if OS.is_debug_build():
			return Node.new()
		else:
			return Resource.new()

@warning_ignore("untyped_declaration")
func func_untyped():
	if OS.is_debug_build():
		return
	else:
		return

func func_void() -> void:
	if OS.is_debug_build():
		return
	else:
		return

func func_int() -> int:
	if OS.is_debug_build():
		return 1
	else:
		return 2

func func_array_int() -> Array[int]:
	if OS.is_debug_build():
		return [1]
	else:
		return [2]

func func_object() -> Object:
	if OS.is_debug_build():
		return Node.new()
	else:
		return Resource.new()
