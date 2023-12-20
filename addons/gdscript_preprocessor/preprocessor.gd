extends RefCounted


# The signs are for fast trilean NOT.
enum _Trilean {FALSE = -1, UNKNOWN = 0, TRUE = +1}

enum _Status {
	NORMAL, # Non-conditional block.
	# Conditional block (`if`/`elif`/`else`):
	WAITING, # Replace next non-`FALSE` `elif` with `if` or `else` with `if true`.
	STARTED, # `if` was outputted (some `if`/`elif` was UNKNOWN).
	FINISHED, # `TRUE` branch was found. Next `elif`/`else` blocks must be removed.
}

class _Block extends RefCounted:
	var indent: int
	var empty: bool
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
const _BRACKET_OPEN:  int = 0x005B # "["
const _BACKSLASH:     int = 0x005C # "\\"
const _BRACKET_CLOSE: int = 0x005D # "]"
const _SMALL_R:       int = 0x0072 # "r"
const _BRACE_OPEN:    int = 0x007B # "{"
const _BRACE_CLOSE:   int = 0x007D # "}"

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

var _source: String
var _length: int
var _position: int
var _line: int

var _indent_char_str: String
var _indent_char: int
var _indent_size: int

var _root_parent: _Block # A fake parent of root.
var _block_stack: Array[_Block]
var _if_directive_stack: Array[bool]
var _output_enabled: bool = true
var _paren_stack: Array[int]

var _os_has_feature_regex: RegEx = RegEx.create_from_string(
		r"""OS\.has_feature\((["'])(\w+)\1\)""")
var _cond_regex: RegEx = RegEx.create_from_string(
		r"^(false|true|and|or|not|&&|\|\||!|\(|\)| |\t|\r|\n)+$")
var _expression: Expression = Expression.new()


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

	_root_parent = _Block.new()
	_block_stack.clear()
	_block_stack.push_back(_Block.new())
	_if_directive_stack.clear()
	_output_enabled = true
	_paren_stack.clear()

	while _position < _length:
		if _source.unicode_at(_position) == _HASH:
			_parse_comment_line()
		else:
			_parse_statement()
		if not error_message.is_empty():
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
		if block.empty:
			last_empty_block = block
	if last_empty_block and last_empty_block.state != _Trilean.FALSE:
		_append(last_empty_block.indent + _indent_size, "pass")

	return true


func _parse_comment_line() -> void:
	var from: int = _position
	while _position < _length and _source.unicode_at(_position) != _NEWLINE:
		_position += 1
	var line: String = _source.substr(from, _position - from)

	if line.begins_with("#~"):
		if line.begins_with("#~if "):
			_parse_if_directive(line.trim_prefix("#~if "))
		elif line == "#~endif" or line.begins_with("#~endif "): # Allow comment.
			_parse_endif_directive()
		else:
			error_message = 'Unknown or invalid directive "%s".' % line

	if _position < _length and _source.unicode_at(_position) == _NEWLINE:
		_position += 1
		_line += 1


func _parse_if_directive(cond: String) -> void:
	var res: _Trilean = _eval_cond(cond)
	if res == _Trilean.UNKNOWN:
		error_message = 'Invalid condition for directive "#~if".'
		return
	var state: bool = res == _Trilean.TRUE
	if not _if_directive_stack.is_empty() and not _if_directive_stack.back():
		state = false
	_if_directive_stack.push_back(state)
	_output_enabled = state


func _parse_endif_directive() -> void:
	if _if_directive_stack.is_empty():
		error_message = '"#~endif" does not have an opening counterpart.'
		return
	_if_directive_stack.pop_back()
	_output_enabled = _if_directive_stack.is_empty() or _if_directive_stack.back()


func _parse_statement() -> void:
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

	while _position < _length:
		var c: int = _source.unicode_at(_position)
		if c == _PAREN_OPEN or c == _BRACKET_OPEN or c == _BRACE_OPEN:
			_paren_stack.push_back(c)
			_position += 1
		elif c == _PAREN_CLOSE or c == _BRACKET_CLOSE or c == _BRACE_CLOSE:
			if _paren_stack.is_empty() or _PARENS[_paren_stack.pop_back()] != c:
				error_message = '"%c" does not have an opening counterpart.' % c
				return
			_position += 1
		elif c == _QUOT or c == _APOS:
			_parse_string(false)
			if not error_message.is_empty():
				return
		elif c == _SMALL_R:
			_position += 1
			if _position < _length:
				var q: int = _source.unicode_at(_position)
				if q == _QUOT or q == _APOS:
					_parse_string(true)
					if not error_message.is_empty():
						return
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
				return
		else:
			_position += 1

	string = (string + _source.substr(from, _position - from)).strip_edges()

	if string.is_empty():
		return

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
			if block.empty:
				last_empty_block = block
		current_block = _block_stack.back()
		if current_block.empty:
			last_empty_block = current_block
		if last_empty_block and last_empty_block.state != _Trilean.FALSE:
			_append(last_empty_block.indent + _indent_size, "pass")

	var parent_block: _Block
	if _block_stack.size() > 1:
		parent_block = _block_stack[-2]
	else:
		parent_block = _root_parent

	if string.begins_with("if "):
		if parent_block.state == _Trilean.FALSE:
			current_block.state = _Trilean.FALSE
			return
		current_block.state = _eval_cond(string.trim_prefix("if ").trim_suffix(":") \
				.replace("\\\n", "\n"))
		match current_block.state:
			_Trilean.FALSE:
				current_block.status = _Status.WAITING
			_Trilean.UNKNOWN:
				_append(current_block.indent, string)
				parent_block.empty = false
				current_block.status = _Status.STARTED
			_Trilean.TRUE:
				_append(current_block.indent, "if true:")
				parent_block.empty = false
				current_block.status = _Status.FINISHED
	elif string.begins_with("elif "):
		if parent_block.state == _Trilean.FALSE or current_block.status == _Status.FINISHED:
			current_block.state = _Trilean.FALSE
			return
		current_block.state = _eval_cond(string.trim_prefix("elif ").trim_suffix(":") \
				.replace("\\\n", "\n"))
		match current_block.state:
			_Trilean.UNKNOWN:
				if current_block.status == _Status.WAITING:
					_append(current_block.indent, string.trim_prefix("el"))
					parent_block.empty = false
					current_block.status = _Status.STARTED
				else:
					_append(current_block.indent, string)
			_Trilean.TRUE:
				if current_block.status == _Status.WAITING:
					_append(current_block.indent, "if true:")
					parent_block.empty = false
				else:
					_append(current_block.indent, "else:")
				current_block.status = _Status.FINISHED
	elif string.begins_with("else:"):
		if parent_block.state == _Trilean.FALSE or current_block.status == _Status.FINISHED:
			current_block.state = _Trilean.FALSE
			return
		@warning_ignore("int_as_enum_without_cast")
		current_block.state = -current_block.state # Fast trilean NOT.
		match current_block.state:
			_Trilean.UNKNOWN:
				if current_block.status == _Status.WAITING:
					_append(current_block.indent, "if true:")
					parent_block.empty = false
					current_block.status = _Status.STARTED
				else:
					_append(current_block.indent, "else:")
			_Trilean.TRUE:
				if current_block.status == _Status.WAITING:
					_append(current_block.indent, "if true:")
					parent_block.empty = false
				else:
					_append(current_block.indent, "else:")
				current_block.status = _Status.FINISHED
	else:
		if parent_block.state == _Trilean.FALSE or (statement_removing_regex
				and statement_removing_regex.search(string)):
			current_block.state = _Trilean.FALSE
			return
		_append(current_block.indent, string)
		parent_block.empty = false
		# Let's assume it's not a block (`func`, `if`, `for`, `while`, etc.).
		# Otherwise it will be corrected when allocating a nested block.
		current_block.empty = false
		current_block.state = parent_block.state
		current_block.status = _Status.NORMAL


func _parse_string(is_raw: bool) -> void:
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
				return
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
					return
			else:
				return
		else:
			_position += 1

	error_message = "Unterminated string."


func _append(indent_level: int, string: String) -> void:
	if _output_enabled:
		result += _indent_char_str.repeat(indent_level) + string + "\n"


func _eval_cond(cond: String) -> _Trilean:
	cond = cond.replace("Engine.is_editor_hint()", "false") \
			.replace("OS.is_debug_build()", "true" if is_debug else "false")

	var matches: Array[RegExMatch] = _os_has_feature_regex.search_all(cond)
	for i: int in range(matches.size() - 1, -1, -1):
		var m: RegExMatch = matches[i]
		cond = cond.left(m.get_start()) + ("true" if features.has(m.get_string(2)) else "false") \
				+ cond.substr(m.get_end())

	if _cond_regex.search(cond) == null:
		return _Trilean.UNKNOWN

	if _expression.parse(cond) != OK:
		printerr("Failed to evaluate expression.")
		return _Trilean.UNKNOWN

	return _Trilean.TRUE if _expression.execute() else _Trilean.FALSE
