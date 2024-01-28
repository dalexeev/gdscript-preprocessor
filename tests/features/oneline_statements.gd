func test() -> void:
	if true: print(1)
	if false: print(2)
	if randi(): print(3)
	# Does not parse nested conditions.
	if true: if false: print(4)
