# PARAMS: features=pc,s3tc,linuxbsd,bptc,x86_64,template,debug,template_debug is_debug=true

extends Node


func _ready() -> void:
	print("=== BASIC USAGE ===")
	if OS.is_debug_build():
		print("basic usage - debug")
		print("basic usage - more debug")
	else:
		print("basic usage - release")

	print("=== BASIC USAGE INVERTED ===")
	if not OS.is_debug_build():
		print("basic usage inverted - release")
	else:
		print("basic usage inverted - debug")
		print("basic usage inverted - more debug")

	print("=== NESTED TRUE ===")
	if randi():
		print("nested true - 1")
		if true:
			print("nested true - 2")
		print("nested true - 3")

	print("=== NESTED FALSE ===")
	if randi():
		print("nested false - 1")
		if false:
			print("nested false - 2")
		print("nested false - 3")

	print("=== NESTED UNKNOWN ===")
	if true:
		print("nested unknown - 1")
		if randi():
			print("nested unknown - 2")
		print("nested unknown - 3")

	print("=== CONSUMED BLOCKS ===")
	if randi():
		print("consumed blocks - 1")
		if false:
			if false:
				if false:
					print("consumed blocks - 2")
	if randi():
		if false:
			if false:
				if false:
					print("consumed blocks - 3")

	print("=== TRUE IF ===")
	if true:
		print("true if - 1")
	elif randi():
		print("true if - 2")
	elif false:
		print("true if - 3")
	elif true:
		print("true if - 4")
	else:
		print("true if - 5")

	print("=== FALSE IF ===")
	if false:
		print("false if - 1")
	elif randi():
		print("false if - 2")
	elif false:
		print("false if - 3")
	elif true:
		print("false if - 4")
	else:
		print("false if - 5")

	print("=== UNKNOWN IF ===")
	if randi():
		print("unknown if - 1")
	elif randi():
		print("unknown if - 2")
	elif false:
		print("unknown if - 3")
	elif true:
		print("unknown if - 4")
	else:
		print("unknown if - 5")
