# features=pc,s3tc,linux,bptc,x86_64,template,debug,template_debug
# is_debug=true

var a1: int

#~if OS.has_feature("debug")

var a2: int

#~if OS.has_feature("non_existent")
var a3: int
#~endif # non_existent

#~if OS.has_feature("pc")
var a4: int
#~endif # pc

#~endif # debug

var a5: int

#~if OS.has_feature("non_existent")
var a6: int
#~if OS.has_feature("debug")
var a7: int
#~endif # debug
#~endif # non_existent

#~if OS.has_feature("non_existent") or OS.has_feature("pc")
var a8: int
#~endif # non_existent or pc

#~if OS.has_feature("non_existent") and OS.has_feature("pc")
var a9: int
#~endif # non_existent and pc

#~if OS.is_debug_build()
var a10: int
#~endif

#~if Engine.is_editor_hint()
var a11: int
#~endif
