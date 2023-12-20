# gdscript-preprocessor

An export plugin for stripping comments and "conditional compilation" of GDScript.

Compatible with Godot 4.2.

## How to use

1. Copy the `addons/gdscript_preprocessor` folder to your project.
2. Enable the plugin in the Project Settings.
3. Export the project.
4. The original scripts will not be changed, but in PCK/ZIP the scripts will be changed. Use ZIP to check the changes.
5. If any errors occurred during the export, you will see them in the Output Log.

## Important note

Each supported platform has certain standard feature tags (plus any custom tags you specify in the export preset). However, there are some standard tags that are not known in advance. See [godotengine/godot#76990](https://github.com/godotengine/godot/issues/76990) and [godotengine/godot#76996](https://github.com/godotengine/godot/pull/76996) for details.

## Features

* Stripping comments.
* Conditional compilation directives (`#~if` and `#~endif`). They work only when exporting a project, and have no effect in the editor.
* `if`/`elif`/`else` statements if their conditions contain only `true`, `false`, `and`, `or`, `not` and the following functions calls:
  * `Engine.is_editor_hint()`;
  * `OS.is_debug_build()`;
  * `OS.has_feature("feature_tag_name")`.
* Removing the following statements in release builds:
  * `assert()`;
  * `breakpoint`;
  * `print_debug()`;
  * `print_stack()`;
  * also you can specify custom regexes in `addons/gdscript_preprocessor/options.cfg`.

## Limitations

* Built-in scripts are not properly supported yet.
* Multiple statements on the same line (`if Engine.is_editor_hint(): return`) are not recognized.
* Statements inside lambdas are not processed.
* Your code is expected to follow the [GDScript style guide](https://docs.godotengine.org/en/stable/tutorials/scripting/gdscript/gdscript_styleguide.html). Otherwise, regular expressions and string processing used in the plugin may not work.

## Example

Original script:

```gdscript
extends Node


var a: int
#~if OS.has_feature("debug")
var b: int
#~endif
var c: int


## Comment.
func _ready() -> void:
    # Comment.
    print(1)
    if OS.has_feature("debug"):
        var t: int = a + b
        print("Debug: t = ", t)
    elif OS.has_feature("release"):
        print("Release.")
    else:
        print("Impossible?!")
    print(2)
```

After exporting with the `debug` feature tag:

```gdscript
extends Node
var a: int
var b: int
var c: int
func _ready() -> void:
    print(1)
    if true:
        var t: int = a + b
        print("Debug: t = ", t)
    print(2)
```

After exporting with the `release` feature tag:

```gdscript
extends Node
var a: int
var c: int
func _ready() -> void:
    print(1)
    if true:
        print("Release.")
    print(2)
```
