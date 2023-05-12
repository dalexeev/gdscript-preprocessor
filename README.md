# gdscript-preprocessor

An export plugin for stripping comments and "conditional compilation" of GDScript.

### How to use

1. Copy the `addons/gdscript_preprocessor` folder to your project.
2. Enable the plugin in the Project Settings.
3. Export the project.
4. The original scripts will not be changed, but in PCK/ZIP the scripts will be changed. Use ZIP to check the changes.
5. If any errors occurred during the export, you will see them in the Output Log.

The following errors do not affect the export success:

```
    No loader found for resource: res://.godot/global_script_class_cache.cfg.
    editor/export/editor_export_platform.cpp:776 - Condition "res.is_null()" is true. Returning: p_path
```

### Important note

See [godotengine/godot#76990](https://github.com/godotengine/godot/issues/76990) and [godotengine/godot#76996](https://github.com/godotengine/godot/pull/76996).

Each supported platform has certain standard feature tags (plus any custom tags you specify in the export preset). However, there are some standard tags that are not known in advance.

For example, the `linuxbsd` tag corresponds to the LinuxBSD _platform_. But the exported project, in theory, can be run not only on Linux, but also on BSD. Thus, it is not known in advance whether the environment will have the `linux` or `bsd` feature tag.

If you want separate exports for these OSes, you can have separate presets for Linux and BSD, just add the `linux` and `bsd` tags respectively as **custom tags**. ~~If you don't care about this difference, then you should use the `linuxbsd` tag, not `linux`.~~ _(This is not true until [godotengine/godot#76996](https://github.com/godotengine/godot/pull/76996) is merged.)_

### Features

* Stripping comments.
* Conditional compilation directives (`#~if` and `#~endif`). They work only when exporting a project, and have no effect in the editor.
* `if`/`elif`/`else` statements if their conditions contain only `true`, `false`, `and`, `or`, `not` and the following functions calls.

### Supported functions

* `Engine.is_editor_hint()`
* `OS.is_debug_build()`
* `OS.has_feature("feature_tag_name")`

### Limitations

* Built-in scripts are not properly supported yet.
* Multiple statements on the same line (`if Engine.is_editor_hint(): return`) are not recognized.
* Your code is expected to follow the [GDScript style guide](https://docs.godotengine.org/en/stable/tutorials/scripting/gdscript/gdscript_styleguide.html). Otherwise, regular expressions and string processing used in the plugin may not work.

### Example

Original script:

```gdscript
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
```

After exporting with the `release` feature tag:

```gdscript
extends Node
var a := 1
var c := 3
func _ready() -> void:
    print(1)
    print("Release.")
    print(2)
```

After exporting with the `debug` feature tag:

```gdscript
extends Node
var a := 1
var b := 2
var c := 3
func _ready() -> void:
    print(1)
    print("Debug: b = ", b)
    print(2)
```
