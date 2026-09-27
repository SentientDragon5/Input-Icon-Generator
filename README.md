# Gen Input Icons

A procedural system for generating customizable, high-resolution input prompt icon spritesheets and metadata for multiplatform games and applications built in Godot Engine.

## Overview

This project provides an automated pipeline using Godot's built in themes to generate labeled spritesheets and coordinate maps for keyboard, mouse, and gamepad inputs. 

Instead of relying on static raster art packs that don't scale or match your game's UI style, this tool uses Godot's UI styleboxes and UI elements to to procedurally render input icons at custom resolutions.

The repository includes both the icon generator tool and a demo implementation of realtime input identification then showing the corresponding icon.

---

## Status & Features

### Supported Inputs

- **Keyboard (Procedural & Dynamic)**:
  - Keycode-mapped directly to Godot's `KEY_*` constants.

- **Mouse**:
  - Mouse Buttons, Scroll Wheel, Side Buttons

- **Gamepad / Controller**:
  - Standard layout and paddle buttons.

### Themes

The generator applies Godot `.tres` Theme to create the icons:
- **`Simple Grey`**: Neutral dark surface with crisp border highlights.
- **`Simple Open`**: Transparent background with high-contrast outlines.
- **`Simple Light`**: Light mode keycap palette for bright UI themes.
- **`Simple Filled`**: Solid filled silhouettes.
Feel free to import your own, the project should auto detect themes from the correct folder.

### Output Format

The generator outputs transparent background PNG spritesheets and JSON coordinate maps labeled by size and theme:

#### Generated Files (`output/spritesheets/`):
- `icons_all_<theme>_<size>_spritesheet.png` / `.json`
- `icons_keyboard_<theme>_<size>_spritesheet.png` / `.json`
- `icons_gamepad_<theme>_<size>_spritesheet.png` / `.json`
- `icons_mouse_<theme>_<size>_spritesheet.png` / `.json`
- icons cached to `output/icons/<name>.png`.

#### JSON Metadata Structure:
```json
{
  "app_header": {
    "spritesheet_name": "icons_all_simple_grey_64_spritesheet.png",
    "version": "1.0",
    "platform": "godot",
    "platform_version": "4.7",
    "theme": "Simple Grey",
    "theme_slug": "simple_grey",
    "icon_size": 64,
    "cell_size": [64, 64],
    "sheet_size": [704, 704],
    "total_icons": 115
  },
  "data": {
    "key_w": {
      "name": "key_w",
      "readable_name": "W",
      "theme": "Simple Grey",
      "icon_size": 64,
      "x": 384,
      "y": 512,
      "width": 64,
      "height": 64,
      "keycode": 87
    }
}
```

---

## Runtime Integration (Godot)

Included in the tester is `InputIconHelper.gd`, which dynamically slices an `AtlasTexture` from the generated JSON:

```gdscript
var helper = InputIconHelper.new("res://spritesheets/icons_all_simple_grey_64_spritesheet.json")

# Retrieve an AtlasTexture ready for TextureRect, Sprite2D, or RichTextLabel
var texture: AtlasTexture = helper.get_atlas_texture("key_space")
var human_name: String = helper.get_readable_name("key_space")
```

---

## How to Run & Build

### Interactive Generator GUI
1. Open the `Gen-Input-Icons/` project in Godot 4.7+.
2. Run `scene_renderer.tscn` (Main Scene).
3. Adjust the theme dropdown and resolution slider (16px – 256px).
4. Click single icons to preview/render, or use "Render All & Export Spritesheets"

### Headless / CLI Batch Generation
Run the generator directly from the command line for automated build pipelines:
```bash
godot --path ./Gen-Input-Icons --headless --render-icons
```

### Interactive Tester
1. Open the `Godot-Input-Tester/` project in Godot.
2. Run `input_tester.tscn` (F5).
3. Connect gamepads, press keys, or click mouse buttons to see live input, stick/trigger values.

---

## Planned Features
If I get around to it.

- [ ] Platform-Specific Controller Glyphs:
  - PlayStation glyphs (Cross, Circle, Square, Triangle, Touchpad)
  - Nintendo Switch glyphs (A/B & X/Y layout swap, +/- buttons, D-pad split)
  - Steam Deck / Steam Controller buttons & touchpads
- [ ] Unity Support
