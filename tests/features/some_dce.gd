func editor_only() -> void:
	if not Engine.is_editor_hint():
		return
		print("unreachable")
	# Currently, dead code elimination only works for the current block.
	print("editor-only (not removed)")

func test() -> void:
	if true:
		if true:
			print(1)
			return
			print(2)
		print(3)
		return
		print(4)
	else:
		if true:
			print(5)
			return
			print(6)
		print(7)
		return
		print(8)
	print(9)
	return
	print(10)
