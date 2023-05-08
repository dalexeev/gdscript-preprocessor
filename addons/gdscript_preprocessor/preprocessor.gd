extends RefCounted


enum _Trilean { TRUE, FALSE, UNKNOWN }

class _Block extends RefCounted:
	var source_indent: int
	var output_indent: int
	var conditional: bool # true - "if"/"elif"/"else", false - other.
	var parent_state := _Trilean.UNKNOWN
	var state := _Trilean.UNKNOWN
	var fired: bool # TRUE branch was found. Next "elif"/"else" blocks must be removed.
	var if_outputed: bool # "if" was outputed (some "if"/"elif" was UNKNOWN).
	var if_consumed: bool # Replace next non-FALSE "elif" with "if" or unwrap "else".
	var all_consumed: bool # All branches was removed, a "pass" is needed.

const _TAB = 0x0009 # "\t"
const _NEWLINE = 0x000A # "\n"
const _SPACE = 0x0020 # " "
const _QUOT = 0x0022 # '"'
const _HASH = 0x0023 # "#"
const _APOS = 0x0027 # "'"
const _PAREN_OPEN = 0x0028 # "("
const _PAREN_CLOSE = 0x0029 # ")"
const _BRACKET_OPEN = 0x005B # "["
const _BACKSLASH = 0x005C # "\\"
const _BRACKET_CLOSE = 0x005D # "]"
const _BRACE_OPEN = 0x007B # "{"
const _BRACE_CLOSE = 0x007D # "}"

const _PARENS = {
	_PAREN_OPEN: _PAREN_CLOSE,
	_BRACKET_OPEN: _BRACKET_CLOSE,
	_BRACE_OPEN: _BRACE_CLOSE,
}

var features: PackedStringArray
var is_debug: bool

var result: String
var error_message: String
var error_line: int

var _source: String
var _length: int
var _position: int
var _line: int

var _indent_char: int
var _paren_stack: Array[int]
var _block_stack: Array[_Block]
var _if_directive_stack: Array[bool]

var _os_has_feature_regex := RegEx.create_from_string("OS\\.has_feature\\(([\"'])(\\w+)\\1\\)")
var _cond_regex := RegEx.create_from_string(
		"^(false|true|and|or|not|&&|\\|\\||!|\\(|\\)| |\\t|\\n)+$")
var _expression := Expression.new()


func preprocess(source_code: String) -> bool:
	result = ""
	error_message = ""
	error_line = 0

	_source = source_code
	_length = _source.length()
	_position = 0
	_line = 1

	_indent_char = 0
	_paren_stack.clear()
	_block_stack.clear()
	_block_stack.push_back(_Block.new())
	_if_directive_stack.clear()

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

	var last_consumed_block: _Block = null
	while _block_stack.back().source_indent > 0:
		var block: _Block = _block_stack.pop_back()
		if block.all_consumed:
			last_consumed_block = block
	if last_consumed_block:
		_append(last_consumed_block.output_indent, "pass\n")

	return true


func _parse_comment_line() -> void:
	var from := _position
	while _mismatch(_NEWLINE):
		_advance()
	var line := _get_substr(from)
	_advance() # Consume newline.

	if not line.begins_with("#~"): # Normal comment.
		return

	if line.begins_with("#~if "):
		_parse_if_directive(line.trim_prefix("#~if "))
	elif line == "#~endif" or line.begins_with("#~endif "): # Allow comment.
		_parse_endif_directive()
	else:
		error_message = 'Unknown or invalid directive "%s".' % line


func _parse_if_directive(cond: String) -> void:
	var res := _eval_cond(cond)
	if res == _Trilean.UNKNOWN:
		error_message = 'Ivalid condition for directive "#~if".'
		return
	var state := true if res == _Trilean.TRUE else false
	if not _if_directive_stack.is_empty() and _if_directive_stack.back() == false:
		state = false
	_if_directive_stack.push_back(state)


func _parse_endif_directive() -> void:
	if _if_directive_stack.is_empty():
		error_message = '"#~endif" does not have an opening counterpart.'
		return
	_if_directive_stack.pop_back()


func _parse_statement() -> void:
	var indent_level := 0
	if _indent_char:
		while _match(_indent_char):
			_advance()
			indent_level += 1
	else:
		if _match(_TAB) or _match(_SPACE):
			_indent_char = _source.unicode_at(_position)
			while _match(_indent_char):
				_advance()
				indent_level += 1

	var from := _position
	var string := ""

	while _position < _length:
		var c := _source.unicode_at(_position)
		if c == _PAREN_OPEN or c == _BRACKET_OPEN or c == _BRACE_OPEN:
			_paren_stack.push_back(c)
			_advance()
		elif c == _PAREN_CLOSE or c == _BRACKET_CLOSE or c == _BRACE_CLOSE:
			if _paren_stack.is_empty() or _PARENS[_paren_stack.pop_back()] != c:
				error_message = '"%c" does not have an opening counterpart.' % c
				return
			_advance()
		elif c == _QUOT or c == _APOS:
			_parse_string()
			if not error_message.is_empty():
				return
		elif c == _HASH:
			# Skip comment.
			string += _get_substr(from)
			while _mismatch(_NEWLINE):
				_advance()
			from = _position
		elif c == _NEWLINE:
			_advance()
			if _paren_stack.is_empty():
				break # End of statement.
		elif c == _BACKSLASH:
			_advance()
			if _match(_NEWLINE):
				_advance()
			else:
				error_message = "Expected newline after the backslash."
				return
		else:
			_advance()

	string += _get_substr(from)

	if string.strip_edges().is_empty():
		return

	var current_block: _Block = _block_stack.back()
	if indent_level > current_block.source_indent:
		var block := _Block.new()
		block.source_indent = indent_level
		if current_block.state == _Trilean.TRUE:
			block.output_indent = current_block.output_indent
		else:
			block.output_indent = current_block.output_indent + 1
		block.parent_state = current_block.state
		block.all_consumed = true # Until we prove otherwise.
		current_block = block
		_block_stack.push_back(block)
	elif indent_level < current_block.source_indent:
		var last_consumed_block: _Block = null
		while indent_level < _block_stack.back().source_indent:
			var block: _Block = _block_stack.pop_back()
			if block.all_consumed:
				last_consumed_block = block
		if last_consumed_block:
			_append(last_consumed_block.output_indent, "pass\n")
		current_block = _block_stack.back()

	if string.begins_with("if "):
		var state := _eval_cond(string.trim_prefix("if ").strip_edges().trim_suffix(":")
				.replace("\\\n", "\n"))
		current_block.conditional = true
		current_block.state = _trilean_and_b(current_block.parent_state, state)
		current_block.fired = false
		current_block.if_outputed = false
		current_block.if_consumed = false
		match current_block.state:
			_Trilean.TRUE:
				current_block.fired = true
				current_block.all_consumed = false
			_Trilean.FALSE:
				current_block.if_consumed = true
			_Trilean.UNKNOWN:
				_append(current_block.output_indent, string)
				current_block.if_outputed = true
				current_block.all_consumed = false
	elif string.begins_with("elif "):
		if not current_block.conditional:
			error_message = 'Unexpected "elif".'
			return
		if current_block.fired:
			current_block.state = _Trilean.FALSE
			return
		var state := _eval_cond(string.trim_prefix("elif ").strip_edges().trim_suffix(":")
				.replace("\\\n", "\n"))
		current_block.state = _trilean_and_b(current_block.parent_state, state)
		match current_block.state:
			_Trilean.TRUE:
				if current_block.if_outputed:
					_append(current_block.output_indent, "else:\n")
					current_block.state = _Trilean.UNKNOWN
				current_block.fired = true
				current_block.all_consumed = false
			_Trilean.FALSE:
				pass
			_Trilean.UNKNOWN:
				if current_block.if_consumed:
					_append(current_block.output_indent, string.trim_prefix("el"))
					current_block.if_outputed = true
					current_block.if_consumed = false
				else:
					_append(current_block.output_indent, string)
				current_block.all_consumed = false
	elif string.begins_with("else:"):
		if not current_block.conditional:
			error_message = 'Unexpected "else".'
			return
		if current_block.fired:
			current_block.state = _Trilean.FALSE
			return
		current_block.state = _trilean_not(current_block.state)
		match current_block.state:
			_Trilean.TRUE:
				if current_block.if_outputed:
					_append(current_block.output_indent, "else:\n")
					current_block.state = _Trilean.UNKNOWN
				current_block.fired = true
				current_block.all_consumed = false
			_Trilean.FALSE:
				pass
			_Trilean.UNKNOWN:
				if current_block.if_consumed:
					current_block.state = _Trilean.TRUE
					current_block.if_consumed = false
				else:
					_append(current_block.output_indent, string)
				current_block.all_consumed = false
	else:
		current_block.conditional = false
		current_block.state = current_block.parent_state
		current_block.fired = false
		current_block.if_outputed = false
		current_block.if_consumed = false
		current_block.all_consumed = false
		if current_block.state != _Trilean.FALSE:
			_append(current_block.output_indent, string)


func _parse_string() -> void:
	var quote_char := _source.unicode_at(_position)
	_advance()

	var is_multiline := false

	if _match_two(quote_char, quote_char):
		is_multiline = true
		_advance()
		_advance()

	while _position < _length:
		var c := _source.unicode_at(_position)
		if c == _BACKSLASH:
			# Let's assume the escape is valid.
			_advance()
			if _position >= _length:
				error_message = "Unterminated string."
				return
			_advance()
		elif c == quote_char:
			_advance()
			if is_multiline:
				if _match_two(quote_char, quote_char):
					_advance()
					_advance()
					return
			else:
				return
		else:
			_advance()

	error_message = "Unterminated string."


func _advance() -> void:
	if _position < _length:
		if _source.unicode_at(_position) == _NEWLINE:
			_line += 1
		_position += 1


func _match(c: int) -> bool:
	return _position < _length and _source.unicode_at(_position) == c


func _match_two(c0: int, c1: int) -> bool:
	return _position + 1 < _length and _source.unicode_at(_position) == c0 \
			and _source.unicode_at(_position + 1) == c1


func _mismatch(c: int) -> bool:
	return _position < _length and _source.unicode_at(_position) != c


func _get_substr(from: int) -> String:
	return _source.substr(from, _position - from)


func _append(indent_level: int, string: String) -> void:
	if (_if_directive_stack.is_empty() or _if_directive_stack.back() == true):
		result += "\t".repeat(indent_level) + string


func _eval_cond(cond: String) -> _Trilean:
	cond = cond.replace("Engine.is_editor_hint()", "false") \
			.replace("OS.is_debug_build()", "true" if is_debug else "false")

	var matches := _os_has_feature_regex.search_all(cond)
	for i in range(matches.size() - 1, -1, -1):
		var m := matches[i]
		cond = cond.left(m.get_start()) + ("true" if features.has(m.get_string(2)) else "false") \
				+ cond.substr(m.get_end())

	if _cond_regex.search(cond) == null:
		return _Trilean.UNKNOWN

	if _expression.parse(cond) != OK:
		printerr("Failed to evalute expression.")
		return _Trilean.UNKNOWN

	return _Trilean.TRUE if _expression.execute() else _Trilean.FALSE


func _trilean_not(a: _Trilean) -> _Trilean:
	if a == _Trilean.TRUE:
		return _Trilean.FALSE
	if a == _Trilean.FALSE:
		return _Trilean.TRUE
	return _Trilean.UNKNOWN


func _trilean_and_b(a: _Trilean, b: _Trilean) -> _Trilean:
	if a == _Trilean.FALSE or b == _Trilean.FALSE:
		return _Trilean.FALSE
	return b
