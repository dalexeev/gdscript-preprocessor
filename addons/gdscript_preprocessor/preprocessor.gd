extends RefCounted


# The signs are for fast trilean NOT.
enum _Trilean {FALSE = -1, UNKNOWN = 0, TRUE = +1}

enum _Status {
	NORMAL, # Non-conditional block.
	# Conditional block (`if`/`elif`/`else`)
	# ======================================
	# Nothing outputted yet.
	# Replace next non-`FALSE` `elif` with `if` or `else` with `if true`.
	WAITING,
	# `if` was outputted (some `if`/`elif` was `UNKNOWN`).
	STARTED,
	# The end is reached (a `TRUE` branch or `else` in source code).
	# Next `elif`/`else` blocks must be removed.
	FINISHED,
}

class _Block extends RefCounted:
	var indent: int
	var empty: bool
	var has_return: bool
	var state: _Trilean
	var status: _Status

const _TAB:           int = 0x0009 # "\t"
const _NEWLINE:       int = 0x000A # "\n"
const _SPACE:         int = 0x0020 # " "
const _QUOT:          int = 0x0022 # '"'
const _HASH:          int = 0x0023 # "#"
const _APOS:          int = 0x0027 # "'"
const _PAREN_OPEN:    int = 0x0028 # "("
const _PAREN_CLOSE:   int = 0x0029 # ")"
const _COLON:         int = 0x003A # ":"
const _BRACKET_OPEN:  int = 0x005B # "["
const _BACKSLASH:     int = 0x005C # "\\"
const _BRACKET_CLOSE: int = 0x005D # "]"
const _SMALL_R:       int = 0x0072 # "r"
const _BRACE_OPEN:    int = 0x007B # "{"
const _BRACE_CLOSE:   int = 0x007D # "}"

enum _Context {
	NONE,
	FUNC,
	VAR,
}

const _VARIANT_DEFAULTS: Dictionary = {
	"bool":               "false",
	"int":                "0",
	"float":              "0.0",
	"String":             '""',
	"Vector2":            "Vector2()",
	"Vector2i":           "Vector2i()",
	"Rect2":              "Rect2()",
	"Rect2i":             "Rect2i()",
	"Vector3":            "Vector3()",
	"Vector3i":           "Vector3i()",
	"Transform2D":        "Transform2D()",
	"Vector4":            "Vector4()",
	"Vector4i":           "Vector4i()",
	"Plane":              "Plane()",
	"Quaternion":         "Quaternion()",
	"AABB":               "AABB()",
	"Basis":              "Basis()",
	"Transform3D":        "Transform3D()",
	"Projection":         "Projection()",
	"Color":              "Color()",
	"StringName":         '&""',
	"NodePath":           '^""',
	"RID":                "RID()",
	"Callable":           "Callable()",
	"Signal":             "Signal()",
	"Dictionary":         "{}",
	"Array":              "[]",
	"PackedByteArray":    "PackedByteArray()",
	"PackedInt32Array":   "PackedInt32Array()",
	"PackedInt64Array":   "PackedInt64Array()",
	"PackedFloat32Array": "PackedFloat32Array()",
	"PackedFloat64Array": "PackedFloat64Array()",
	"PackedStringArray":  "PackedStringArray()",
	"PackedVector2Array": "PackedVector2Array()",
	"PackedVector3Array": "PackedVector3Array()",
	"PackedColorArray":   "PackedColorArray()",
}

const _PARENS: Dictionary = {
	_PAREN_OPEN: _PAREN_CLOSE,
	_BRACKET_OPEN: _BRACKET_CLOSE,
	_BRACE_OPEN: _BRACE_CLOSE,
}

var features: PackedStringArray
var is_debug: bool
var statement_removing_regex: RegEx

var result: String
var error_message: String
var error_line: int

var _dynamic_feature_tags: Dictionary

var _source: String
var _length: int
var _position: int
var _line: int

var _indent_char_str: String
var _indent_char: int
var _indent_size: int

var _if_directive_stack: Array[bool]
var _output_enabled: bool = true

var _root_parent: _Block # A fake parent of root.
var _block_stack: Array[_Block]

var _context: _Context = _Context.NONE
var _fake_return: String
var _var_fake_return: String

var _paren_stack: Array[int]

var _func_type_regex: RegEx = RegEx.create_from_string(
		r"""->\s*([^\s\["']+)\s*(?:\[[^\["']+\])?\s*:$""")
var _var_type_regex: RegEx = RegEx.create_from_string(
		r"""^var[^:=]+:\s*([^\s:=\["']+)""")
var _os_has_feature_regex: RegEx = RegEx.create_from_string(
		r"""OS\.has_feature\((["'])(\w+)\1\)""")
var _condition_regex: RegEx = RegEx.create_from_string(
		r"^(false|true|and|or|not|&&|\|\||!|\(|\)| |\t|\r|\n)+$")
var _expression: Expression = Expression.new()


func set_dynamic_feature_tags(tags: PackedStringArray) -> void:
	_dynamic_feature_tags.clear()
	for tag: String in tags:
		_dynamic_feature_tags[tag] = true


func preprocess(source_code: String) -> bool:
	result = ""
	error_message = ""
	error_line = 0

	_source = source_code
	_length = _source.length()
	_position = 0
	_line = 1

	_indent_char_str = ""
	_indent_char = 0
	_indent_size = 0

	_if_directive_stack.clear()
	_output_enabled = true

	_root_parent = _Block.new()
	_block_stack.clear()
	_block_stack.push_back(_Block.new())

	_context = _Context.NONE
	_fake_return = ""
	_var_fake_return = ""

	_paren_stack.clear()

	while _position < _length:
		if _source.unicode_at(_position) == _HASH:
			if not _parse_comment_line():
				error_line = _line
				return false
		else:
			if not _parse_statement():
				error_line = _line
				return false

	if not _paren_stack.is_empty():
		error_message = 'Unclosed "%c".' % _paren_stack.back()
		return false

	if not _if_directive_stack.is_empty():
		error_message = "Unclosed directive."
		return false

	var last_empty_block: _Block = null
	while not _block_stack.is_empty():
		var block: _Block = _block_stack.pop_back()

		if block.indent == 1:
			if _context == _Context.FUNC and _fake_return and not block.has_return:
				_append(block.indent, _fake_return)
				block.empty = false
		elif block.indent == 2:
			if _context == _Context.VAR and _fake_return and not block.has_return:
				_append(block.indent, _fake_return)
				block.empty = false

		if block.empty:
			last_empty_block = block

	if last_empty_block and last_empty_block.state != _Trilean.FALSE:
		_append(last_empty_block.indent + _indent_size, "pass")

	return true


func _parse_comment_line() -> bool:
	var from: int = _position
	while _position < _length and _source.unicode_at(_position) != _NEWLINE:
		_position += 1
	var line: String = _source.substr(from, _position - from)

	if line.begins_with("#~"):
		if line.begins_with("#~if "):
			if not _parse_if_directive(line.substr(len("#~if "))):
				return false
		elif line == "#~endif" or line.begins_with("#~endif "): # Allow comment.
			if not _parse_endif_directive():
				return false
		else:
			error_message = 'Unknown or invalid directive "%s".' % line
			return false

	if _position < _length and _source.unicode_at(_position) == _NEWLINE:
		_position += 1
		_line += 1

	return true


func _parse_if_directive(condition: String) -> bool:
	var res: _Trilean = _evaluate(condition)
	if res == _Trilean.UNKNOWN:
		error_message = 'Invalid or dynamic condition for directive "#~if".'
		return false
	var state: bool = res == _Trilean.TRUE
	if not _if_directive_stack.is_empty() and not _if_directive_stack.back():
		state = false
	_if_directive_stack.push_back(state)
	_output_enabled = state
	return true


func _parse_endif_directive() -> bool:
	if _if_directive_stack.is_empty():
		error_message = '"#~endif" does not have an opening counterpart.'
		return false
	_if_directive_stack.pop_back()
	_output_enabled = _if_directive_stack.is_empty() or _if_directive_stack.back()
	return true


func _parse_statement() -> bool:
	var indent_level: int = 0
	if _indent_char:
		while _source.unicode_at(_position) == _indent_char:
			_position += 1
			indent_level += 1
	else:
		var c: int = _source.unicode_at(_position)
		if c == _TAB or c == _SPACE:
			_indent_char_str = _source[_position]
			_indent_char = _source.unicode_at(_position)
			while _position < _length and _source.unicode_at(_position) == _indent_char:
				_position += 1
				_indent_size += 1
				indent_level += 1

	var from: int = _position
	var string: String = ""
	var string_colon_pos: int = -1

	while _position < _length:
		var c: int = _source.unicode_at(_position)
		if c == _PAREN_OPEN or c == _BRACKET_OPEN or c == _BRACE_OPEN:
			_paren_stack.push_back(c)
			_position += 1
		elif c == _PAREN_CLOSE or c == _BRACKET_CLOSE or c == _BRACE_CLOSE:
			if _paren_stack.is_empty() or _PARENS[_paren_stack.pop_back()] != c:
				error_message = '"%c" does not have an opening counterpart.' % c
				return false
			_position += 1
		elif c == _QUOT or c == _APOS:
			if not _parse_string(false):
				return false
		elif c == _SMALL_R:
			_position += 1
			if _position < _length:
				var q: int = _source.unicode_at(_position)
				if q == _QUOT or q == _APOS:
					if not _parse_string(true):
						return false
		elif c == _COLON:
			if string_colon_pos < 0 and _paren_stack.is_empty():
				# This doesn't take lambdas into account, but it's unlikely
				# that anyone would use them in if/elif conditions.
				string_colon_pos = _position - from
			_position += 1
		elif c == _HASH:
			# Skip comment.
			string += _source.substr(from, _position - from)
			while _position < _length and _source.unicode_at(_position) != _NEWLINE:
				_position += 1
			from = _position
		elif c == _NEWLINE:
			_position += 1
			_line += 1
			if _paren_stack.is_empty():
				break # End of statement.
		elif c == _BACKSLASH:
			_position += 1
			if _position < _length and _source.unicode_at(_position) == _NEWLINE:
				_position += 1
				_line += 1
			else:
				error_message = "Expected newline after the backslash."
				return false
		else:
			_position += 1

	string = (string + _source.substr(from, _position - from)).strip_edges()

	if string.is_empty():
		return true

	var current_block: _Block = _block_stack.back()

	if indent_level > current_block.indent:
		current_block.empty = true # Until we prove otherwise.
		var block: _Block = _Block.new()
		block.indent = indent_level
		current_block = block
		_block_stack.push_back(block)
	elif indent_level < current_block.indent:
		var last_empty_block: _Block = null
		while indent_level < _block_stack.back().indent:
			var block: _Block = _block_stack.pop_back()

			if block.indent == 1:
				if _context == _Context.FUNC and _fake_return and not block.has_return:
					_append(block.indent, _fake_return)
					block.empty = false
			elif block.indent == 2:
				if _context == _Context.VAR and _fake_return and not block.has_return:
					_append(block.indent, _fake_return)
					block.empty = false

			if block.empty:
				last_empty_block = block

		current_block = _block_stack.back()
		if current_block.empty:
			last_empty_block = current_block

		if last_empty_block and last_empty_block.state != _Trilean.FALSE:
			_append(last_empty_block.indent + _indent_size, "pass")

	if indent_level == 0:
		_context = _Context.NONE
		_fake_return = ""
		_var_fake_return = ""

		if string.begins_with("func"):
			_context = _Context.FUNC
			var regex_match: RegExMatch = _func_type_regex.search(string)
			if regex_match:
				var type: String = regex_match.get_string(1)
				if type != "void":
					_fake_return = "return " + _VARIANT_DEFAULTS.get(type, "null")
		elif string.begins_with("var"):
			_context = _Context.VAR
			var regex_match: RegExMatch = _var_type_regex.search(string)
			if regex_match:
				_var_fake_return = "return " + _VARIANT_DEFAULTS.get(
						regex_match.get_string(1), "null")
			else:
				_var_fake_return = "return null"
	elif indent_level == 1:
		if _context == _Context.VAR:
			if string.begins_with("get:") or string.begins_with("get():"):
				_fake_return = _var_fake_return
			else:
				_fake_return = ""

	var parent_block: _Block
	if _block_stack.size() > 1:
		parent_block = _block_stack[-2]
	else:
		parent_block = _root_parent

	if string.begins_with("if "):
		if parent_block.state == _Trilean.FALSE or current_block.has_return:
			current_block.state = _Trilean.FALSE
			return true

		var condition: String = string.substr(len("if "), string_colon_pos - len("if "))
		current_block.state = _evaluate(condition.replace("\\\n", "\n"))
		match current_block.state:
			_Trilean.FALSE:
				current_block.status = _Status.WAITING
			_Trilean.UNKNOWN:
				_append(current_block.indent, string)
				parent_block.empty = false
				current_block.status = _Status.STARTED
			_Trilean.TRUE:
				_append(current_block.indent, "if true:" + string.substr(string_colon_pos + 1))
				parent_block.empty = false
				current_block.status = _Status.FINISHED

	elif string.begins_with("elif "):
		if parent_block.state == _Trilean.FALSE or current_block.has_return \
				or current_block.status == _Status.FINISHED:
			current_block.state = _Trilean.FALSE
			return true

		var condition: String = string.substr(len("elif "), string_colon_pos - len("elif "))
		current_block.state = _evaluate(condition.replace("\\\n", "\n"))
		match current_block.state:
			_Trilean.UNKNOWN:
				if current_block.status == _Status.WAITING:
					_append(current_block.indent, string.substr(len("el")))
					parent_block.empty = false
					current_block.status = _Status.STARTED
				else:
					_append(current_block.indent, string)
			_Trilean.TRUE:
				if current_block.status == _Status.WAITING:
					_append(current_block.indent, "if true:" + string.substr(string_colon_pos + 1))
					parent_block.empty = false
				else:
					_append(current_block.indent, "else:" + string.substr(string_colon_pos + 1))
				current_block.status = _Status.FINISHED

	elif string.begins_with("else:"):
		if parent_block.state == _Trilean.FALSE or current_block.has_return \
				or current_block.status == _Status.FINISHED:
			current_block.state = _Trilean.FALSE
			return true

		@warning_ignore("int_as_enum_without_cast")
		current_block.state = -current_block.state # Fast trilean NOT.
		# We don't care if it's `UNKNOWN` or `TRUE`.
		if current_block.status == _Status.WAITING:
			_append(current_block.indent, "if true:" + string.substr(string_colon_pos + 1))
			parent_block.empty = false
		else:
			_append(current_block.indent, string)
		current_block.status = _Status.FINISHED

	else:
		if parent_block.state == _Trilean.FALSE or current_block.has_return \
				or (statement_removing_regex and statement_removing_regex.search(string)):
			current_block.state = _Trilean.FALSE
			return true

		_append(current_block.indent, string)
		parent_block.empty = false
		# Let's assume it's not a block (`func`, `if`, `for`, `while`, etc.).
		# Otherwise it will be corrected when allocating a nested block.
		current_block.empty = false
		current_block.state = parent_block.state
		current_block.status = _Status.NORMAL
		if string.begins_with("return"):
			if string.length() == len("return"):
				current_block.has_return = true
				current_block.state = _Trilean.FALSE
			else:
				var c: int = string.unicode_at(len("return"))
				if c == _SPACE or c == _TAB or c == _PAREN_OPEN:
					current_block.has_return = true
					current_block.state = _Trilean.FALSE

	return true


func _parse_string(is_raw: bool) -> bool:
	var quote_char: int = _source.unicode_at(_position)
	_position += 1

	var is_multiline: bool

	if _position + 1 < _length and _source.unicode_at(_position) == quote_char \
			and _source.unicode_at(_position + 1) == quote_char:
		is_multiline = true
		_position += 2

	while _position < _length:
		var c: int = _source.unicode_at(_position)
		if c == _NEWLINE:
			_position += 1
			_line += 1
		elif c == _BACKSLASH:
			_position += 1
			if _position >= _length:
				error_message = "Unterminated string."
				return false
			var esc: int = _source.unicode_at(_position)
			if is_raw:
				if esc == quote_char or esc == _BACKSLASH:
					_position += 1
				# else: **not** advance.
			else:
				# Let's assume the escape is valid.
				_position += 1
				if esc == _NEWLINE:
					_line += 1
		elif c == quote_char:
			_position += 1
			if is_multiline:
				if _position + 1 < _length and _source.unicode_at(_position) == quote_char \
						and _source.unicode_at(_position + 1) == quote_char:
					_position += 2
					return true
			else:
				return true
		else:
			_position += 1

	error_message = "Unterminated string."
	return false


func _append(indent_level: int, string: String) -> void:
	if _output_enabled:
		result += _indent_char_str.repeat(indent_level) + string + "\n"


func _evaluate(condition: String) -> _Trilean:
	condition = condition.replace("Engine.is_editor_hint()", "false") \
			.replace("OS.is_debug_build()", "true" if is_debug else "false")

	var matches: Array[RegExMatch] = _os_has_feature_regex.search_all(condition)
	for i: int in range(matches.size() - 1, -1, -1):
		var regex_match: RegExMatch = matches[i]
		var tag: String = regex_match.get_string(2)
		if _dynamic_feature_tags.has(tag):
			return _Trilean.UNKNOWN
		condition = condition.left(regex_match.get_start()) \
				+ ("true" if features.has(tag) else "false") \
				+ condition.substr(regex_match.get_end())

	if _condition_regex.search(condition) == null:
		return _Trilean.UNKNOWN

	if _expression.parse(condition) != OK:
		printerr("Failed to evaluate expression.")
		return _Trilean.UNKNOWN

	return _Trilean.TRUE if _expression.execute() else _Trilean.FALSE
