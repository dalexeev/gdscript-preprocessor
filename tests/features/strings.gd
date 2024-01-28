func test() -> void:
	print("test
			test \n \" ' '' \\")
	print("""test
			test \n \" ' '' " "" \\""")

	# https://github.com/godotengine/godot/blob/master/
	# modules/gdscript/tests/scripts/parser/features/r_strings.gd
	print(r"test ' \' \" \\ \n \t \u2023 test")
	print(r"\n\\[\t ]*(\w+)")
	print(r"")
	print(r"\"")
	print(r"\\\"")
	print(r"\\")
	print(r"\" \\\" \\\\\"")
	print(r"\ \\ \\\ \\\\ \\\\\ \\")
	print(r'"')
	print(r'"(?:\\.|[^"])*"')
	print(r"""""")
	print(r"""test \t "test"="" " \" \\\" \ \\ \\\ test""")
	print(r'''r"""test \t "test"="" " \" \\\" \ \\ \\\ test"""''')
	print(r"\t
			\t")
	print(r"\t \
			\t")
	print(r"""\t
			\t""")
	print(r"""\t \
			\t""")

	if true:
		if false:
			print("test")
