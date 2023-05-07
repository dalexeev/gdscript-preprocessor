extends Node


var a := 1
#~if OS.has_feature("debug")
var b := 2
#~endif
var c := 3


## Comment.
func _ready() -> void:
	print(1) # Comment.
	if OS.has_feature("debug"):
		print("Debug: b = ", b)
	# Comment.
	elif OS.has_feature("release"):
		print("Release.")
	else:
		print("Impossible?!")
	print(2)
