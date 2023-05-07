extends RefCounted


class _IfBlock extends RefCounted:
	enum Mode { NORMAL, DEDENT, REMOVE }
	var mode: Mode
	var indent: String
	var fired: bool
	var consumed: bool = true
	var has_if: bool = true


enum _EvalResult {
	TRUE,
	FALSE,
	UNKNOWN,
	ERROR,
}

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

var _paren_stack: Array[int]
var _if_directive_stack: Array[bool]
var _if_block_stack: Array[_IfBlock]

var _os_has_feature_regex := RegEx.create_from_string("OS\\.has_feature\\(([\"'])(\\w+)\\1\\)")
var _cond_regex := RegEx.create_from_string("^(false|true|and|or|not|&&|\\|\\||!|\\(|\\)| |\\t)+$")
var _expression := Expression.new()


func preprocess(source_code: String) -> bool:
	result = ""
	error_message = ""
	error_line = 0

	_source = source_code
	_length = _source.length()
	_position = 0
	_line = 1

	_paren_stack.clear()
	_if_directive_stack.clear()
	_if_block_stack.clear()

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

	var last_removed_block: _IfBlock = null
	while not _if_block_stack.is_empty():
		last_removed_block = _if_block_stack.pop_back()
	if last_removed_block and last_removed_block.consumed:
		_append(last_removed_block.indent + "pass\n")

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
	if res == _EvalResult.ERROR or res == _EvalResult.UNKNOWN:
		error_message = 'Ivalid condition for directive "#~if".'
		return
	var state := true if res == _EvalResult.TRUE else false
	if not _if_directive_stack.is_empty() and _if_directive_stack.back() == false:
		state = false
	_if_directive_stack.push_back(state)


func _parse_endif_directive() -> void:
	if _if_directive_stack.is_empty():
		error_message = '"#~endif" does not have an opening counterpart.'
		return
	_if_directive_stack.pop_back()


func _parse_statement() -> void:
	var from := _position
	while _match(_TAB) or _match(_SPACE):
		_advance()
	var indent := _get_substr(from)

	from = _position
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

	var last_removed_block: _IfBlock = null
	while not _if_block_stack.is_empty():
		var block: _IfBlock = _if_block_stack.back()
		if indent.begins_with(block.indent) and indent.length() > block.indent.length():
			break
		last_removed_block = _if_block_stack.pop_back()

	if string.begins_with("if "):
		if last_removed_block and last_removed_block.consumed:
			_append(last_removed_block.indent + "pass\n")

		var res := _eval_cond(string.trim_prefix("if ").strip_edges().trim_suffix(":\n") \
				.replace("\\\n", "\n"))
		var block := _IfBlock.new()
		block.indent = indent
		match res:
			_EvalResult.TRUE:
				block.mode = _IfBlock.Mode.DEDENT
				block.fired = true
				block.consumed = false
			_EvalResult.FALSE:
				block.mode = _IfBlock.Mode.REMOVE
				block.has_if = false
			_EvalResult.UNKNOWN:
				_append(indent + string)
				block.mode = _IfBlock.Mode.NORMAL
				block.consumed = false
			_EvalResult.ERROR:
				error_message = "Failed to evalute expression."
				return
		_if_block_stack.append(block)
	elif string.begins_with("elif "):
		if not last_removed_block or last_removed_block.indent != indent:
			error_message = 'Unexpected "elif".'
			return
		if last_removed_block.fired:
			last_removed_block.mode = _IfBlock.Mode.REMOVE
			_if_block_stack.append(last_removed_block)
			return
		var res := _eval_cond(string.trim_prefix("elif ").trim_suffix(":\n").strip_edges() \
				.replace("\\\n", "\n"))
		match res:
			_EvalResult.TRUE:
				last_removed_block.mode = _IfBlock.Mode.DEDENT
				last_removed_block.fired = true
				last_removed_block.consumed = false
			_EvalResult.FALSE:
				last_removed_block.mode = _IfBlock.Mode.REMOVE
			_EvalResult.UNKNOWN:
				if last_removed_block.has_if:
					_append(indent + string)
				else:
					_append(indent + string.trim_prefix("el"))
					last_removed_block.has_if = true
				last_removed_block.mode = _IfBlock.Mode.NORMAL
				last_removed_block.consumed = false
			_EvalResult.ERROR:
				error_message = "Failed to evalute expression."
				return
		_if_block_stack.append(last_removed_block)
	elif string.begins_with("else:"):
		if not last_removed_block or last_removed_block.indent != indent:
			error_message = 'Unexpected "else".'
			return
		if last_removed_block.fired:
			last_removed_block.mode = _IfBlock.Mode.REMOVE
			_if_block_stack.append(last_removed_block)
			return
		match last_removed_block.mode:
			_IfBlock.Mode.NORMAL:
				_append(indent + string)
			_IfBlock.Mode.DEDENT:
				last_removed_block.mode = _IfBlock.Mode.REMOVE
			_IfBlock.Mode.REMOVE:
				last_removed_block.mode = _IfBlock.Mode.DEDENT
		last_removed_block.consumed = false
		_if_block_stack.append(last_removed_block)
	else:
		if last_removed_block and last_removed_block.consumed:
			_append(last_removed_block.indent + "pass\n")

		if _if_block_stack.is_empty():
			_append(indent + string)
		else:
			var block: _IfBlock = _if_block_stack.back()
			match block.mode:
				_IfBlock.Mode.NORMAL:
					_append(indent + string)
				_IfBlock.Mode.DEDENT:
					_append(indent.trim_prefix(block.indent) + string)
				_IfBlock.Mode.REMOVE:
					pass


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


func _append(string: String) -> void:
	if (_if_directive_stack.is_empty() or _if_directive_stack.back() == true):
		result += string


func _eval_cond(cond: String) -> _EvalResult:
	cond = cond.replace("Engine.is_editor_hint()", "false") \
			.replace("OS.is_debug_build()", "true" if is_debug else "false")

	var matches := _os_has_feature_regex.search_all(cond)
	for i in range(matches.size() - 1, -1, -1):
		var m := matches[i]
		cond = cond.left(m.get_start()) + ("true" if features.has(m.get_string(2)) else "false") \
				+ cond.substr(m.get_end())

	if _cond_regex.search(cond) == null:
		return _EvalResult.UNKNOWN

	if _expression.parse(cond) != OK:
		return _EvalResult.ERROR

	return _EvalResult.TRUE if _expression.execute() else _EvalResult.FALSE
