# PARAMS: features=pc,s3tc,linux,bptc,x86_64,template,debug,template_debug is_debug=true

var a1 := 1

#~if OS.has_feature("debug")

var a2 := 2

#~if OS.has_feature("non_existent")
var a3 := 3
#~endif # non_existent

#~if OS.has_feature("linux")
var a4 := 4
#~endif # linux

#~endif # debug

var a5 := 5

#~if OS.has_feature("non_existent")
var a6 := 6
#~if OS.has_feature("debug")
var a7 := 7
#~endif # debug
#~endif # non_existent

#~if OS.has_feature("non_existent") or OS.has_feature("linux")
var a8 := 8
#~endif # non_existent or linux

#~if OS.has_feature("non_existent") and OS.has_feature("linux")
var a9 := 9
#~endif # non_existent and linux

#~if OS.is_debug_build()
var a10 := 10
#~endif

#~if Engine.is_editor_hint()
var a11 := 11
#~endif
