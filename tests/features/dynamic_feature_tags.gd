# features=static_true_tag,dynamic_true_tag
# dynamic_feature_tags=dynamic_true_tag,dynamic_false_tag

func test() -> void:
	if OS.has_feature("static_true_tag"):
		print("static_true_tag")
	if OS.has_feature("static_false_tag"):
		print("static_false_tag")
	if OS.has_feature("dynamic_true_tag"):
		print("dynamic_true_tag")
	if OS.has_feature("dynamic_false_tag"):
		print("dynamic_false_tag")
