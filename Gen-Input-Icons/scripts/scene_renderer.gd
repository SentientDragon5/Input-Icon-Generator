extends Node2D
class_name SceneRenderer

@export var output_dir: String = "res://output/"
@export var default_icon_size: Vector2i = Vector2i(64, 64)
@export var themes_dir: String = "res://themes/"

@onready var sub_viewport: SubViewport = $SubViewport
@onready var to_render: Node2D = $SubViewport/ToRender

# UI Controls
@onready var theme_option_button: OptionButton = $UI/Sidebar/VBoxContainer/ParametersPanel/MarginContainer/VBoxContainer/ThemeOptionButton
@onready var size_slider: HSlider = $UI/Sidebar/VBoxContainer/ParametersPanel/MarginContainer/VBoxContainer/SizeSlider
@onready var size_spin_box: SpinBox = $UI/Sidebar/VBoxContainer/ParametersPanel/MarginContainer/VBoxContainer/SizeHeader/SizeSpinBox

@onready var exact_preview_rect: TextureRect = $UI/PreviewArea/VBoxContainer/PreviewsHBox/ExactPreviewBox/VBoxContainer/ExactPreviewPanel/CenterContainer/ExactPreviewRect
@onready var exact_title_label: Label = $UI/PreviewArea/VBoxContainer/PreviewsHBox/ExactPreviewBox/VBoxContainer/ExactTitle
@onready var selected_header_label: Label = $UI/PreviewArea/VBoxContainer/SelectedHeaderLabel

@onready var dims_label: Label = $UI/DimsLabel
@onready var status_label: Label = $UI/StatusLabel
@onready var button_list: VBoxContainer = $UI/Sidebar/VBoxContainer/ScrollContainer/ButtonList

var key_base_scene: PackedScene = preload("res://templates/key_base.tscn")
var key_wide_base_scene: PackedScene = preload("res://templates/key_wide_base.tscn")

var items_registry: Dictionary = {}
var rendered_images: Dictionary = {}

var loaded_themes: Array[Theme] = []
var theme_names: Array[String] = []
var current_theme: Theme = null
var current_theme_name: String = ""
var current_size: int = 64
var current_selected_key: String = ""

func get_output_icons_dir() -> String:
	return output_dir + "icons/"

func get_output_spritesheets_dir() -> String:
	return output_dir + "spritesheets/"

func _ready() -> void:
	create_gdignore(output_dir)
	create_gdignore(get_output_icons_dir())
	create_gdignore(get_output_spritesheets_dir())
	
	current_size = default_icon_size.x
	
	load_available_themes()
	build_items_registry()
	setup_parameters_ui()
	
	await get_tree().process_frame
	
	if "--render-icons" in OS.get_cmdline_user_args() or "--render-all" in OS.get_cmdline_args():
		await render_all()
		await generate_spritesheets()
		get_tree().quit()
		return
		
	populate_icon_buttons()
	if items_registry.size() > 0:
		show_preview(items_registry.keys()[0])

func load_available_themes() -> void:
	loaded_themes.clear()
	theme_names.clear()
	var theme_files: Array[String] = []
	var dir = DirAccess.open(themes_dir)
	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			if not dir.current_is_dir() and file_name.ends_with(".tres"):
				theme_files.append(file_name)
			file_name = dir.get_next()
		dir.list_dir_end()
	
	theme_files.sort()
	for file_name in theme_files:
		var res = load(themes_dir + file_name)
		if res is Theme:
			loaded_themes.append(res)
			theme_names.append(file_name.get_basename().replace("_", " ").capitalize())
	
	if loaded_themes.is_empty():
		loaded_themes.append(Theme.new())
		theme_names.append("Default")
		
	current_theme = loaded_themes[0]
	current_theme_name = theme_names[0]

func setup_parameters_ui() -> void:
	if theme_option_button:
		theme_option_button.clear()
		for i in range(theme_names.size()):
			theme_option_button.add_item(theme_names[i], i)
		theme_option_button.selected = 0
		theme_option_button.item_selected.connect(_on_theme_selected)
		
	if size_slider and size_spin_box:
		for control in [size_slider, size_spin_box]:
			control.min_value = 16
			control.max_value = 256
			control.step = 1
			control.value = current_size
		size_slider.value_changed.connect(_on_size_slider_changed)
		size_spin_box.value_changed.connect(_on_size_spinbox_changed)

func _on_theme_selected(index: int) -> void:
	if index >= 0 and index < loaded_themes.size():
		current_theme = loaded_themes[index]
		current_theme_name = theme_names[index]
		status_label.text = "Theme changed to: " + current_theme_name
		if not current_selected_key.is_empty():
			show_preview(current_selected_key)

func _on_size_slider_changed(val: float) -> void:
	var int_val = int(val)
	if current_size != int_val:
		current_size = int_val
		if size_spin_box and size_spin_box.value != int_val:
			size_spin_box.set_value_no_signal(int_val)
		_apply_size_change()

func _on_size_spinbox_changed(val: float) -> void:
	var int_val = int(val)
	if current_size != int_val:
		current_size = int_val
		if size_slider and size_slider.value != int_val:
			size_slider.set_value_no_signal(int_val)
		_apply_size_change()

func _apply_size_change() -> void:
	sub_viewport.size = Vector2i(current_size, current_size)
	if not current_selected_key.is_empty():
		show_preview(current_selected_key)

func build_items_registry() -> void:
	items_registry.clear()
	
	# Handcrafted scenes
	var dir = DirAccess.open("res://generated/")
	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			if not dir.current_is_dir() and file_name.ends_with(".tscn"):
				var item_name = file_name.get_basename()
				var loaded_res = load("res://generated/" + file_name)
				if loaded_res is PackedScene:
					items_registry[item_name] = {
						"type": "scene",
						"name": item_name,
						"scene": loaded_res,
						"category": determine_category(item_name),
						"readable_name": item_name.replace("_", " ").capitalize(),
						"keycode": 0
					}
			file_name = dir.get_next()
		dir.list_dir_end()
		
	# Procedural keyboard keys
	_register_procedural_keys()

func determine_category(item_name: String) -> String:
	if item_name.begins_with("button_") or item_name.begins_with("dpad_") or item_name.begins_with("bumper_") or item_name.begins_with("trigger_") or item_name.begins_with("stick_") or item_name.begins_with("paddle_"):
		return "gamepad"
	elif item_name.begins_with("mouse_"):
		return "mouse"
	elif item_name.begins_with("key_"):
		return "keyboard"
	return "general"

func _register_procedural_keys() -> void:
	# A-Z
	for code in range(KEY_A, KEY_Z + 1):
		var char_str = String.chr(code)
		_add_key_entry("key_" + char_str.to_lower(), char_str, char_str, key_base_scene, 18, code)
		
	# 0-9
	for code in range(KEY_0, KEY_9 + 1):
		var char_str = String.chr(code)
		_add_key_entry("key_" + char_str, char_str, char_str, key_base_scene, 18, code)
		
	# F1-F12
	for i in range(1, 13):
		_add_key_entry("key_f" + str(i), "F" + str(i), "F" + str(i), key_base_scene, 14, KEY_F1 + (i - 1))
		
	# Symbols
	var symbols = [
		[",", "key_comma", KEY_COMMA, 20], [".", "key_period", KEY_PERIOD, 20], ["/", "key_slash", KEY_SLASH, 18],
		["\\", "key_backslash", KEY_BACKSLASH, 18], [";", "key_semicolon", KEY_SEMICOLON, 18], ["'", "key_apostrophe", KEY_APOSTROPHE, 20],
		["[", "key_bracketleft", KEY_BRACKETLEFT, 18], ["]", "key_bracketright", KEY_BRACKETRIGHT, 18], ["-", "key_minus", KEY_MINUS, 20],
		["=", "key_equal", KEY_EQUAL, 18], ["`", "key_backquote", KEY_QUOTELEFT, 20], ["!", "key_exclam", KEY_EXCLAM, 18],
		["?", "key_question", KEY_QUESTION, 18], ["+", "key_plus", KEY_PLUS, 18], [":", "key_colon", KEY_COLON, 18],
		["\"", "key_quotedbl", KEY_QUOTEDBL, 18], ["<", "key_less", KEY_LESS, 18], [">", "key_greater", KEY_GREATER, 18],
		["_", "key_underscore", KEY_UNDERSCORE, 18], ["{", "key_braceleft", KEY_BRACELEFT, 18], ["}", "key_braceright", KEY_BRACERIGHT, 18],
		["|", "key_bar", KEY_BAR, 18], ["~", "key_asciitilde", KEY_ASCIITILDE, 18], ["@", "key_at", KEY_AT, 16],
		["#", "key_hash", KEY_NUMBERSIGN, 18], ["$", "key_dollar", KEY_DOLLAR, 18], ["%", "key_percent", KEY_PERCENT, 16],
		["&", "key_ampersand", KEY_AMPERSAND, 16], ["*", "key_asterisk", KEY_ASTERISK, 20]
	]
	for sym in symbols:
		_add_key_entry(sym[1], sym[0], sym[0], key_base_scene, sym[3], sym[2])
		
	# Numpad
	for i in range(10):
		_add_key_entry("key_kp_" + str(i), "Num " + str(i), "Num " + str(i), key_base_scene, 11, KEY_KP_0 + i)
	var numpad_ops = [
		["key_kp_add", "Num +", KEY_KP_ADD], ["key_kp_subtract", "Num -", KEY_KP_SUBTRACT],
		["key_kp_multiply", "Num *", KEY_KP_MULTIPLY], ["key_kp_divide", "Num /", KEY_KP_DIVIDE],
		["key_kp_period", "Num .", KEY_KP_PERIOD], ["key_kp_enter", "Num Enter", KEY_KP_ENTER]
	]
	for op in numpad_ops:
		_add_key_entry(op[0], op[1], op[1], key_base_scene, 10, op[2])
		
	# Navigation & special keys
	var nav_keys = [
		["key_escape", "Esc", "Escape", KEY_ESCAPE, false], ["key_insert", "Ins", "Insert", KEY_INSERT, false],
		["key_delete", "Del", "Delete", KEY_DELETE, false], ["key_home", "Home", "Home", KEY_HOME, false],
		["key_end", "End", "End", KEY_END, false], ["key_pageup", "PgUp", "Page Up", KEY_PAGEUP, false],
		["key_pagedown", "PgDn", "Page Down", KEY_PAGEDOWN, false], ["key_up", "Up", "Up Arrow", KEY_UP, false],
		["key_down", "Down", "Down Arrow", KEY_DOWN, false], ["key_left", "Left", "Left Arrow", KEY_LEFT, false],
		["key_right", "Right", "Right Arrow", KEY_RIGHT, false], ["key_capslock", "Caps", "Caps Lock", KEY_CAPSLOCK, true],
		["key_numlock", "NumLk", "Num Lock", KEY_NUMLOCK, true], ["key_scrolllock", "ScrLk", "Scroll Lock", KEY_SCROLLLOCK, true],
		["key_printscreen", "PrtSc", "Print Screen", KEY_PRINT, true], ["key_pause", "Pause", "Pause", KEY_PAUSE, false],
		["key_meta", "Meta", "Win / Cmd", KEY_META, true]
	]
	for nk in nav_keys:
		_add_key_entry(nk[0], nk[1], nk[2], key_wide_base_scene if nk[4] else key_base_scene, 12, nk[3])

func _add_key_entry(id_name: String, label: String, readable: String, tmpl: PackedScene, font_size: int, code: int) -> void:
	items_registry[id_name] = {
		"type": "procedural_key",
		"name": id_name,
		"readable_name": readable,
		"label": label,
		"template": tmpl,
		"font_size": font_size,
		"category": "keyboard",
		"keycode": code
	}

func apply_theme_to_tree(node: Node, theme_res: Theme) -> void:
	if not node or not theme_res:
		return
		
	var theme_sb = theme_res.get_stylebox("panel", "Panel") as StyleBoxFlat
	var fg = theme_res.get_color("font_color", "Label") if theme_res.has_color("font_color", "Label") else Color.WHITE
	var inactive_fg = Color(fg.r, fg.g, fg.b, 0.35)
	var is_open = (theme_sb != null and theme_sb.bg_color.a <= 0.01)

	_apply_theme_node(node, theme_sb, fg, inactive_fg, is_open)

func _apply_theme_node(node: Node, theme_sb: StyleBoxFlat, fg: Color, inactive_fg: Color, is_open: bool) -> void:
	if node is Label:
		node.add_theme_color_override("font_color", fg)
	elif node is Panel:
		var current_sb = node.get_theme_stylebox("panel")
		if current_sb is StyleBoxFlat and theme_sb:
			var sb = current_sb.duplicate() as StyleBoxFlat
			if current_sb.bg_color.v > 0.8 and current_sb.bg_color.a > 0.8: # Active highlight
				sb.bg_color = fg
			else:
				sb.bg_color = theme_sb.bg_color if not is_open else Color(0, 0, 0, 0)
			sb.border_color = theme_sb.border_color
			node.add_theme_stylebox_override("panel", sb)
	elif node is Polygon2D:
		if node.name == "CrossShape":
			node.color = theme_sb.bg_color if (theme_sb and not is_open) else Color(0, 0, 0, 0)
		elif node.color.v > 0.8 and node.color.a > 0.8:
			node.color = fg
		else:
			node.color = inactive_fg
	elif node is Line2D:
		if node.name == "CrossOutline":
			node.default_color = theme_sb.border_color if theme_sb else fg
		else:
			node.default_color = fg
			
	for child in node.get_children():
		_apply_theme_node(child, theme_sb, fg, inactive_fg, is_open)

func instantiate_item(item_data: Dictionary) -> Node:
	var inst: Node = null
	if item_data["type"] == "scene":
		inst = item_data["scene"].instantiate()
	elif item_data["type"] == "procedural_key":
		inst = item_data["template"].instantiate()
		var label_node = inst.get_node_or_null("Panel/Label") as Label
		if label_node:
			label_node.text = item_data["label"]
			if item_data.has("font_size"):
				var scale_factor = float(current_size) / 64.0
				label_node.add_theme_font_size_override("font_size", max(8, int(round(float(item_data["font_size"]) * scale_factor))))
	
	if inst and current_theme:
		apply_theme_to_tree(inst, current_theme)
		
	return inst

func populate_icon_buttons() -> void:
	for child in button_list.get_children():
		child.queue_free()
		
	var keys = items_registry.keys()
	keys.sort()
	for key in keys:
		var b = Button.new()
		b.text = key
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.pressed.connect(show_and_render_single.bind(key))
		button_list.add_child(b)

func show_preview(item_name: String) -> void:
	if not items_registry.has(item_name):
		return
		
	current_selected_key = item_name
	
	for child in to_render.get_children():
		child.queue_free()
		
	var instance = instantiate_item(items_registry[item_name])
	if not instance:
		return
		
	to_render.add_child(instance)
	sub_viewport.size = Vector2i(current_size, current_size)
	
	if instance is Control:
		instance.custom_minimum_size = Vector2(current_size, current_size)
		instance.size = Vector2(current_size, current_size)
		
	var theme_display_name = current_theme_name if not current_theme_name.is_empty() else "Default"
	if selected_header_label:
		selected_header_label.text = "Selected: %s | Size: %dx%d | Theme: %s" % [item_name, current_size, current_size, theme_display_name]
	if dims_label:
		dims_label.text = "Dimensions: %dx%d px (%s)" % [current_size, current_size, theme_display_name]
	if exact_title_label:
		exact_title_label.text = "Exact 1:1 Pixel Size (%dx%d)" % [current_size, current_size]
	if exact_preview_rect:
		exact_preview_rect.custom_minimum_size = Vector2(current_size, current_size)

func show_and_render_single(item_name: String) -> void:
	show_preview(item_name)
	await render_item_to_file(item_name)

func render_item_to_file(item_name: String) -> String:
	show_preview(item_name)
	
	sub_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	await get_tree().process_frame
	
	var image = sub_viewport.get_texture().get_image()
	if not image or image.is_empty():
		return ""
		
	var out_dir = get_output_icons_dir()
	DirAccess.make_dir_recursive_absolute(out_dir)
	var file_path = out_dir + item_name + ".png"
	
	if image.save_png(file_path) == OK:
		rendered_images[item_name] = image
		status_label.text = "Status: Saved " + item_name + ".png"
		return file_path
	return ""

func render_all() -> void:
	status_label.text = "Status: Rendering all icons..."
	var keys = items_registry.keys()
	keys.sort()
	for key in keys:
		await render_item_to_file(key)
		await get_tree().process_frame
	status_label.text = "Status: Finished rendering " + str(keys.size()) + " icons"

func generate_spritesheets() -> void:
	if rendered_images.is_empty():
		await render_all()
		
	status_label.text = "Status: Packing spritesheets..."
	
	var categories = {"gamepad": [], "keyboard": [], "mouse": [], "all": []}
	for key in rendered_images.keys():
		categories["all"].append(key)
		var cat = items_registry[key]["category"] if items_registry.has(key) else determine_category(key)
		if categories.has(cat):
			categories[cat].append(key)
			
	var spritesheet_dir = get_output_spritesheets_dir()
	DirAccess.make_dir_recursive_absolute(spritesheet_dir)
	
	var cell_w = current_size
	var cell_h = current_size
	var theme_display_name = current_theme_name if not current_theme_name.is_empty() else "Default"
	
	for cat_name in categories.keys():
		var icon_keys: Array = categories[cat_name]
		if icon_keys.is_empty():
			continue
			
		icon_keys.sort()
		var count = icon_keys.size()
		var cols = int(ceil(sqrt(count)))
		var rows = int(ceil(float(count) / float(cols)))
		var sheet_w = cols * cell_w
		var sheet_h = rows * cell_h
		
		var sheet_img = Image.create(sheet_w, sheet_h, false, Image.FORMAT_RGBA8)
		sheet_img.fill(Color(0, 0, 0, 0))
		
		var json_data = {
			"app_header": {
				"spritesheet_name": cat_name + "_spritesheet.png",
				"version": "1.0",
				"platform": "godot",
				"platform_version": "4.7",
				"theme": theme_display_name,
				"cell_size": [cell_w, cell_h],
				"sheet_size": [sheet_w, sheet_h],
				"total_icons": count
			},
			"data": {}
		}
		
		for i in range(count):
			var icon_key = icon_keys[i]
			var img: Image = rendered_images[icon_key]
			var dest_x = (i % cols) * cell_w
			var dest_y = floori(float(i) / float(cols)) * cell_h
			
			sheet_img.blit_rect(img, Rect2i(0, 0, img.get_width(), img.get_height()), Vector2i(dest_x, dest_y))
			
			var meta_info = items_registry.get(icon_key, {})
			var entry = {
				"name": icon_key,
				"readable_name": meta_info.get("readable_name", icon_key),
				"x": dest_x,
				"y": dest_y,
				"width": cell_w,
				"height": cell_h
			}
			if meta_info.has("keycode") and meta_info["keycode"] != 0:
				entry["keycode"] = meta_info["keycode"]
			json_data["data"][icon_key] = entry
			
		sheet_img.save_png(spritesheet_dir + cat_name + "_spritesheet.png")
		
		var json_file = FileAccess.open(spritesheet_dir + cat_name + "_spritesheet.json", FileAccess.WRITE)
		if json_file:
			json_file.store_string(JSON.stringify(json_data, "\t"))
			json_file.close()
			
	status_label.text = "Status: Spritesheets generated successfully (" + current_theme_name + ")"

func create_gdignore(path: String) -> void:
	DirAccess.make_dir_recursive_absolute(path)
	var file = FileAccess.open(path + ".gdignore", FileAccess.WRITE)
	if file:
		file.close()

func open_folder() -> void:
	var path = ProjectSettings.globalize_path(output_dir)
	DirAccess.make_dir_recursive_absolute(output_dir)
	OS.shell_open(path)
