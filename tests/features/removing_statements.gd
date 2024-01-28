# features=pc,s3tc,linux,bptc,x86_64,template,release,template_release
# is_debug=false
# statement_removing_regex=^(?:breakpoint|assert\(|print_debug\(|print_stack\()

func test() -> void:
	print(1)
	breakpoint
	assert(randi(), "message")
	print_debug("message")
	print_debug("message",
			[1, 2, 2])
	print_debug(
		{1: 2, 3: 4},
	)
	print_stack()
	print(2)
