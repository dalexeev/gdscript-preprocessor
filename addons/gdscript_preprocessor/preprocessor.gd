extends RefCounted


enum _Trilean { TRUE, FALSE, UNKNOWN }

class _Block extends RefCounted:
	var source_indent: int
	var output_indent: int
	var empty: bool
	var conditional: bool # true - "if"/"elif"/"else", false - other.
	var state := _Trilean.UNKNOWN
	var fired: bool # TRUE branch was found. Next "elif"/"else" blocks must be removed.
	var if_outputed: bool # "if" was outputed (some "if"/"elif" was UNKNOWN).
	var if_consumed: bool # Replace next non-FALSE "elif" with "if" or unwrap "else".

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
var _root_parent: _Block # A fake parent of root.
var _paren_stack: Array[int]
var _block_stack: Array[_Block]
var _if_directive_stack: Array[bool]

var _os_has_feature_regex := RegEx.create_from_string("OS\\.has_feature\\(([\"'])(\\w+)\\1\\)")
var _cond_regex := RegEx.create_from_string(
		"^(false|true|and|or|not|&&|\\|\\||!|\\(|\\)| |\\t|\\r|\\n)+$")
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
	_root_parent = _Block.new()
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

	var last_empty_block: _Block = null
	while _block_stack.back().source_indent > 0:
		var block: _Block = _block_stack.pop_back()
		if block.empty:
			last_empty_block = block
	if last_empty_block and last_empty_block.state == _Trilean.UNKNOWN:
		_append(last_empty_block.output_indent + 1, "pass")

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

	string = (string + _get_substr(from)).strip_edges()

	if string.is_empty():
		return

	var current_block: _Block = _block_stack.back()

	if indent_level > current_block.source_indent:
		var block := _Block.new()
		block.source_indent = indent_level
		if current_block.state == _Trilean.TRUE:
			block.output_indent = current_block.output_indent
		else:
			block.output_indent = current_block.output_indent + 1
		current_block = block
		_block_stack.push_back(block)
	elif indent_level < current_block.source_indent:
		var last_empty_block: _Block = null
		while indent_level < _block_stack.back().source_indent:
			var block: _Block = _block_stack.pop_back()
			if block.empty:
				last_empty_block = block
		current_block = _block_stack.back()
		if current_block.empty:
			last_empty_block = current_block
		if last_empty_block and last_empty_block.state == _Trilean.UNKNOWN:
			_append(last_empty_block.output_indent + 1, "pass")

	var parent_block: _Block
	if _block_stack.size() > 1:
		parent_block = _block_stack[-2]
	else:
		parent_block = _root_parent

	if string.begins_with("if "):
		var state := _eval_cond(string.trim_prefix("if ").trim_suffix(":").replace("\\\n", "\n"))
		current_block.empty = true # Until we prove otherwise.
		current_block.conditional = true
		current_block.state = _trilean_and_b(parent_block.state, state)
		current_block.fired = false
		current_block.if_outputed = false
		current_block.if_consumed = false
		match current_block.state:
			_Trilean.TRUE:
				current_block.fired = true
			_Trilean.FALSE:
				current_block.if_consumed = true
			_Trilean.UNKNOWN:
				parent_block.empty = false
				current_block.if_outputed = true
				_append(current_block.output_indent, string)
	elif string.begins_with("elif "):
		if not current_block.conditional:
			error_message = 'Unexpected "elif".'
			return
		if current_block.fired:
			current_block.state = _Trilean.FALSE
			return
		var state := _eval_cond(string.trim_prefix("elif ").trim_suffix(":").replace("\\\n", "\n"))
		current_block.empty = true # Until we prove otherwise.
		current_block.state = _trilean_and_b(parent_block.state, state)
		match current_block.state:
			_Trilean.TRUE:
				if current_block.if_outputed:
					current_block.state = _Trilean.UNKNOWN
					_append(current_block.output_indent, "else:")
				current_block.fired = true
			_Trilean.FALSE:
				pass
			_Trilean.UNKNOWN:
				parent_block.empty = false
				if current_block.if_consumed:
					current_block.if_outputed = true
					current_block.if_consumed = false
					_append(current_block.output_indent, string.trim_prefix("el"))
				else:
					_append(current_block.output_indent, string)
	elif string.begins_with("else:"):
		if not current_block.conditional:
			error_message = 'Unexpected "else".'
			return
		if current_block.fired:
			current_block.state = _Trilean.FALSE
			return
		current_block.empty = true # Until we prove otherwise.
		current_block.state = _trilean_not(current_block.state)
		match current_block.state:
			_Trilean.TRUE:
				if current_block.if_outputed:
					current_block.state = _Trilean.UNKNOWN
					_append(current_block.output_indent, "else:")
				current_block.fired = true
			_Trilean.FALSE:
				pass
			_Trilean.UNKNOWN:
				parent_block.empty = false
				if current_block.if_consumed:
					current_block.state = _Trilean.TRUE
					current_block.if_consumed = false
				else:
					_append(current_block.output_indent, string)
	else:
		parent_block.empty = false
		current_block.empty = false # Let's think so.
		current_block.conditional = false
		current_block.state = parent_block.state
		current_block.fired = false
		current_block.if_outputed = false
		current_block.if_consumed = false
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
		result += "\t".repeat(indent_level) + string + "\n"


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
