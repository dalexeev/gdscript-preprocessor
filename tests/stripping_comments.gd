extends Node

# Comment.

"Strings are NOT stripped!"

"""
Strings are NOT stripped!
"""

## This
## is
## doc comment.
func _ready() -> void: # Inline comment.
	# Comment.
	print("test")
	print(
		# Comment.
		"a", # Inline comment.
		"b",
		"c",
	)
