extends Node2D
class_name SceneRenderer

@export var output_dir: String = "res://output/"
@export var default_icon_size: Vector2i = Vector2i(64, 64)
@export var spritesheet_padding: int = 4
@export var themes_dir: String = "res://themes/"

@onready var sub_viewport: SubViewport = $SubViewport
@onready var to_render: Node2D = $SubViewport/ToRender

# UI Controls
@onready var theme_option_button: OptionButton = $UI/Sidebar/VBoxContainer/ParametersPanel/MarginContainer/VBoxContainer/ThemeOptionButton
@onready var size_slider: HSlider = $UI/Sidebar/VBoxContainer/ParametersPanel/MarginContainer/VBoxContainer/SizeSlider
@onready var size_spin_box: SpinBox = $UI/Sidebar/VBoxContainer/ParametersPanel/MarginContainer/VBoxContainer/SizeHeader/SizeSpinBox
@onready var padding_slider: HSlider = $UI/Sidebar/VBoxContainer/ParametersPanel/MarginContainer/VBoxContainer/PaddingSlider
@onready var padding_spin_box: SpinBox = $UI/Sidebar/VBoxContainer/ParametersPanel/MarginContainer/VBoxContainer/PaddingHeader/PaddingSpinBox

@onready var exact_preview_rect: TextureRect = $UI/PreviewArea/VBoxContainer/PreviewsHBox/ExactPreviewBox/VBoxContainer/ExactPreviewPanel/CenterContainer/ExactPreviewRect
@onready var exact_title_label: Label = $UI/PreviewArea/VBoxContainer/PreviewsHBox/ExactPreviewBox/VBoxContainer/ExactTitle
@onready var selected_header_label: Label = $UI/PreviewArea/VBoxContainer/SelectedHeaderLabel

@onready var dims_label: Label = $UI/DimsLabel
@onready var status_label: Label = $UI/StatusLabel
@onready var progress_bar: ProgressBar = $UI/ProgressBar
@onready var button_list: VBoxContainer = $UI/Sidebar/VBoxContainer/ScrollContainer/ButtonList

const MOUSE_BUTTON_MAPPINGS: Dictionary = {
	"mouse_left": MOUSE_BUTTON_LEFT,          # 1
	"mouse_right": MOUSE_BUTTON_RIGHT,        # 2
	"mouse_middle": MOUSE_BUTTON_MIDDLE,      # 3
	"mouse_scroll_up": MOUSE_BUTTON_WHEEL_UP,  # 4
	"mouse_scroll_down": MOUSE_BUTTON_WHEEL_DOWN, # 5
	"mouse_side_1": MOUSE_BUTTON_XBUTTON1,    # 8
	"mouse_side_2": MOUSE_BUTTON_XBUTTON2,    # 9
}

const JOY_BUTTON_MAPPINGS: Dictionary = {
	"button_a": JOY_BUTTON_A,                         # 0
	"button_b": JOY_BUTTON_B,                         # 1
	"button_x": JOY_BUTTON_X,                         # 2
	"button_y": JOY_BUTTON_Y,                         # 3
	"button_select": JOY_BUTTON_BACK,                 # 4
	"button_view": JOY_BUTTON_BACK,                   # 4
	"button_home": JOY_BUTTON_GUIDE,                  # 5
	"button_start": JOY_BUTTON_START,                 # 6
	"button_options": JOY_BUTTON_START,               # 6
	"stick_l3": JOY_BUTTON_LEFT_STICK,                # 7
	"stick_r3": JOY_BUTTON_RIGHT_STICK,               # 8
	"bumper_left": JOY_BUTTON_LEFT_SHOULDER,          # 9
	"bumper_right": JOY_BUTTON_RIGHT_SHOULDER,        # 10
	"dpad_up": JOY_BUTTON_DPAD_UP,                    # 11
	"dpad_down": JOY_BUTTON_DPAD_DOWN,                # 12
	"dpad_left": JOY_BUTTON_DPAD_LEFT,                # 13
	"dpad_right": JOY_BUTTON_DPAD_RIGHT,              # 14
	"button_share": JOY_BUTTON_MISC1,                 # 15
	"paddle_p1": JOY_BUTTON_PADDLE1,                  # 16
	"paddle_p2": JOY_BUTTON_PADDLE2,                  # 17
	"paddle_p3": JOY_BUTTON_PADDLE3,                  # 18
	"paddle_p4": JOY_BUTTON_PADDLE4,                  # 19
}

const JOY_AXIS_MAPPINGS: Dictionary = {
	"trigger_left": JOY_AXIS_TRIGGER_LEFT,            # 4
	"trigger_right": JOY_AXIS_TRIGGER_RIGHT,          # 5
}

const KEY_MAPPINGS: Dictionary = {
	"key_alt": KEY_ALT,
	"key_backspace": KEY_BACKSPACE,
	"key_ctrl": KEY_CTRL,
	"key_enter": KEY_ENTER,
	"key_shift": KEY_SHIFT,
	"key_space": KEY_SPACE,
	"key_tab": KEY_TAB,
}

var key_base_scene: PackedScene = preload("res://templates/key_base.tscn")
var key_wide_base_scene: PackedScene = preload("res://templates/key_wide_base.tscn")

var items_registry: Dictionary = {}
var rendered_images: Dictionary = {}

var loaded_themes: Array[Theme] = []
var theme_names: Array[String] = []
var current_theme: Theme = null
var current_theme_name: String = ""
var current_size: int = 64
var bold_font: FontVariation = null
var current_selected_key: String = ""

func get_output_icons_dir() -> String:
	return output_dir + "icons/"

func get_output_spritesheets_dir() -> String:
	return output_dir + "spritesheets/"

func _ready() -> void:
	bold_font = FontVariation.new()
	bold_font.variation_embolden = 0.65
	
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
	var default_index = 0
	for i in range(theme_files.size()):
		var file_name = theme_files[i]
		var res = load(themes_dir + file_name)
		if res is Theme:
			loaded_themes.append(res)
			var display_name = file_name.get_basename().replace("_", " ").capitalize()
			theme_names.append(display_name)
			if file_name == "simple_grey.tres":
				default_index = loaded_themes.size() - 1
	
	if loaded_themes.is_empty():
		loaded_themes.append(Theme.new())
		theme_names.append("Default")
		default_index = 0
		
	current_theme = loaded_themes[default_index]
	current_theme_name = theme_names[default_index]

func setup_parameters_ui() -> void:
	if theme_option_button:
		theme_option_button.clear()
		var default_idx = 0
		for i in range(theme_names.size()):
			theme_option_button.add_item(theme_names[i], i)
			if theme_names[i].to_lower() == "simple grey":
				default_idx = i
		theme_option_button.selected = default_idx
		theme_option_button.item_selected.connect(_on_theme_selected)
		
	if size_slider and size_spin_box:
		for control in [size_slider, size_spin_box]:
			control.min_value = 16
			control.max_value = 256
			control.step = 1
			control.value = current_size
		size_slider.value_changed.connect(_on_size_slider_changed)
		size_spin_box.value_changed.connect(_on_size_spinbox_changed)

	if padding_slider and padding_spin_box:
		for control in [padding_slider, padding_spin_box]:
			control.min_value = 0
			control.max_value = 32
			control.step = 1
			control.value = spritesheet_padding
		padding_slider.value_changed.connect(_on_padding_slider_changed)
		padding_spin_box.value_changed.connect(_on_padding_spinbox_changed)

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

func _on_padding_slider_changed(val: float) -> void:
	var int_val = int(val)
	if spritesheet_padding != int_val:
		spritesheet_padding = int_val
		if padding_spin_box and padding_spin_box.value != int_val:
			padding_spin_box.set_value_no_signal(int_val)
		status_label.text = "Spritesheet padding set to: %d px" % spritesheet_padding

func _on_padding_spinbox_changed(val: float) -> void:
	var int_val = int(val)
	if spritesheet_padding != int_val:
		spritesheet_padding = int_val
		if padding_slider and padding_slider.value != int_val:
			padding_slider.set_value_no_signal(int_val)
		status_label.text = "Spritesheet padding set to: %d px" % spritesheet_padding

func _apply_size_change() -> void:
	_update_viewport_scale()
	if not current_selected_key.is_empty():
		show_preview(current_selected_key)

func _update_viewport_scale() -> void:
	sub_viewport.size = Vector2i(current_size, current_size)
	var scale_factor = float(current_size) / float(default_icon_size.x)
	to_render.scale = Vector2(scale_factor, scale_factor)

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
					var meta_keycode: int = KEY_MAPPINGS.get(item_name, 0)
					var meta_mouse_btn: int = MOUSE_BUTTON_MAPPINGS.get(item_name, -1)
					var meta_joy_btn: int = JOY_BUTTON_MAPPINGS.get(item_name, -1)
					var meta_joy_axis: int = JOY_AXIS_MAPPINGS.get(item_name, -1)
					
					items_registry[item_name] = {
						"type": "scene",
						"name": item_name,
						"scene": loaded_res,
						"category": determine_category(item_name),
						"readable_name": item_name.replace("_", " ").capitalize(),
						"keycode": meta_keycode,
						"mouse_button": meta_mouse_btn,
						"joy_button": meta_joy_btn,
						"joy_axis": meta_joy_axis
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
		_add_key_entry("key_" + char_str.to_lower(), char_str, char_str, key_base_scene, 22, code)
		
	# 0-9
	for code in range(KEY_0, KEY_9 + 1):
		var char_str = String.chr(code)
		_add_key_entry("key_" + char_str, char_str, char_str, key_base_scene, 22, code)
		
	# F1-F12
	for i in range(1, 13):
		_add_key_entry("key_f" + str(i), "F" + str(i), "F" + str(i), key_base_scene, 15, KEY_F1 + (i - 1))
		
	# Symbols
	var symbols = [
		[",", "key_comma", KEY_COMMA, 22], [".", "key_period", KEY_PERIOD, 22], ["/", "key_slash", KEY_SLASH, 20],
		["\\", "key_backslash", KEY_BACKSLASH, 20], [";", "key_semicolon", KEY_SEMICOLON, 20], ["'", "key_apostrophe", KEY_APOSTROPHE, 22],
		["[", "key_bracketleft", KEY_BRACKETLEFT, 20], ["]", "key_bracketright", KEY_BRACKETRIGHT, 20], ["-", "key_minus", KEY_MINUS, 22],
		["=", "key_equal", KEY_EQUAL, 20], ["`", "key_backquote", KEY_QUOTELEFT, 22], ["!", "key_exclam", KEY_EXCLAM, 20],
		["?", "key_question", KEY_QUESTION, 20], ["+", "key_plus", KEY_PLUS, 20], [":", "key_colon", KEY_COLON, 20],
		["\"", "key_quotedbl", KEY_QUOTEDBL, 20], ["<", "key_less", KEY_LESS, 20], [">", "key_greater", KEY_GREATER, 20],
		["_", "key_underscore", KEY_UNDERSCORE, 20], ["{", "key_braceleft", KEY_BRACELEFT, 20], ["}", "key_braceright", KEY_BRACERIGHT, 20],
		["|", "key_bar", KEY_BAR, 20], ["~", "key_tilde", KEY_ASCIITILDE, 20], ["~", "key_asciitilde", KEY_ASCIITILDE, 20], ["@", "key_at", KEY_AT, 18],
		["#", "key_hash", KEY_NUMBERSIGN, 20], ["$", "key_dollar", KEY_DOLLAR, 20], ["%", "key_percent", KEY_PERCENT, 18],
		["&", "key_ampersand", KEY_AMPERSAND, 18], ["*", "key_asterisk", KEY_ASTERISK, 22]
	]
	for sym in symbols:
		_add_key_entry(sym[1], sym[0], sym[0], key_base_scene, sym[3], sym[2])
		
	# Numpad
	for i in range(10):
		_add_key_entry("key_kp_" + str(i), "Num " + str(i), "Num " + str(i), key_base_scene, 13, KEY_KP_0 + i)
	var numpad_ops = [
		["key_kp_add", "Num +", KEY_KP_ADD], ["key_kp_subtract", "Num -", KEY_KP_SUBTRACT],
		["key_kp_multiply", "Num *", KEY_KP_MULTIPLY], ["key_kp_divide", "Num /", KEY_KP_DIVIDE],
		["key_kp_period", "Num .", KEY_KP_PERIOD]
	]
	for op in numpad_ops:
		_add_key_entry(op[0], op[1], op[1], key_base_scene, 13, op[2])
	_add_key_entry("key_kp_enter", "Num Enter", "Num Enter", key_wide_base_scene, 11, KEY_KP_ENTER)
		
	# Navigation & special keys
	var nav_keys = [
		["key_escape", "Esc", "Escape", KEY_ESCAPE, false, 14], ["key_insert", "Ins", "Insert", KEY_INSERT, false, 14],
		["key_delete", "Del", "Delete", KEY_DELETE, false, 14], ["key_home", "Home", "Home", KEY_HOME, false, 13],
		["key_end", "End", "End", KEY_END, false, 14], ["key_pageup", "PgUp", "Page Up", KEY_PAGEUP, false, 13],
		["key_pagedown", "PgDn", "Page Down", KEY_PAGEDOWN, false, 13], ["key_up", "Up", "Up Arrow", KEY_UP, false, 14],
		["key_down", "Down", "Down Arrow", KEY_DOWN, false, 13], ["key_left", "Left", "Left Arrow", KEY_LEFT, false, 13],
		["key_right", "Right", "Right Arrow", KEY_RIGHT, false, 13], ["key_capslock", "Caps", "Caps Lock", KEY_CAPSLOCK, true, 13],
		["key_numlock", "NumLk", "Num Lock", KEY_NUMLOCK, true, 13], ["key_scrolllock", "ScrLk", "Scroll Lock", KEY_SCROLLLOCK, true, 13],
		["key_printscreen", "PrtSc", "Print Screen", KEY_PRINT, true, 13], ["key_pause", "Pause", "Pause", KEY_PAUSE, false, 13],
		["key_meta", "Meta", "Win / Cmd", KEY_META, true, 13]
	]
	for nk in nav_keys:
		_add_key_entry(nk[0], nk[1], nk[2], key_wide_base_scene if nk[4] else key_base_scene, nk[5], nk[3])

func _add_key_entry(id_name: String, label: String, readable: String, tmpl: PackedScene, font_size: int, code: int) -> void:
	items_registry[id_name] = {
		"type": "procedural_key",
		"name": id_name,
		"readable_name": readable,
		"label": label,
		"template": tmpl,
		"font_size": font_size,
		"category": "keyboard",
		"keycode": code,
		"mouse_button": -1,
		"joy_button": -1,
		"joy_axis": -1
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
		if bold_font:
			node.add_theme_font_override("font", bold_font)
	elif node is Panel:
		var current_sb = node.get_theme_stylebox("panel")
		if current_sb is StyleBoxFlat and theme_sb:
			var sb = current_sb.duplicate() as StyleBoxFlat
			if current_sb.bg_color.v > 0.8 and current_sb.bg_color.a > 0.8: # Active highlight
				sb.bg_color = fg
			else:
				sb.bg_color = theme_sb.bg_color if not is_open else Color(0, 0, 0, 0)
			sb.border_color = theme_sb.border_color
			sb.border_width_left = theme_sb.border_width_left if current_sb.border_width_left > 0 else 0
			sb.border_width_top = theme_sb.border_width_top if current_sb.border_width_top > 0 else 0
			sb.border_width_right = theme_sb.border_width_right if current_sb.border_width_right > 0 else 0
			sb.border_width_bottom = theme_sb.border_width_bottom if current_sb.border_width_bottom > 0 else 0
			node.add_theme_stylebox_override("panel", sb)
	elif node is Polygon2D:
		if node.color.v > 0.8 and node.color.a > 0.8:
			node.color = fg
		else:
			node.color = inactive_fg
	elif node is Line2D:
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
		if not label_node:
			label_node = inst.find_child("Label", true, false) as Label
		if label_node:
			label_node.text = item_data["label"]
			if bold_font:
				label_node.add_theme_font_override("font", bold_font)
			if item_data.has("font_size"):
				label_node.add_theme_font_size_override("font_size", item_data["font_size"])
	
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
	_update_viewport_scale()
	sub_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	
	if instance is Control:
		instance.custom_minimum_size = Vector2(default_icon_size.x, default_icon_size.y)
		instance.size = Vector2(default_icon_size.x, default_icon_size.y)
		instance.position = Vector2.ZERO
		
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
	sub_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	
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
	var keys = items_registry.keys()
	keys.sort()
	var total = keys.size()
	
	progress_bar.visible = true
	progress_bar.min_value = 0
	progress_bar.max_value = total
	progress_bar.value = 0
	
	for i in range(total):
		var key = keys[i]
		status_label.text = "Rendering (%d/%d): %s" % [i + 1, total, key]
		progress_bar.value = i + 1
		await render_item_to_file(key)
		await get_tree().process_frame
		
	status_label.text = "Status: Finished rendering %d icons" % total
	await get_tree().create_timer(1.2).timeout
	progress_bar.visible = false

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
	var theme_slug = theme_display_name.to_lower().replace(" ", "_")
	
	progress_bar.visible = true
	progress_bar.min_value = 0
	progress_bar.max_value = categories.size()
	progress_bar.value = 0
	var cat_idx = 0
	
	for cat_name in categories.keys():
		cat_idx += 1
		progress_bar.value = cat_idx
		var icon_keys: Array = categories[cat_name]
		if icon_keys.is_empty():
			continue
			
		icon_keys.sort()
		var p = spritesheet_padding
		var count = icon_keys.size()
		var cols = int(ceil(sqrt(count)))
		var rows = int(ceil(float(count) / float(cols)))
		var sheet_w = cols * cell_w + (cols + 1) * p
		var sheet_h = rows * cell_h + (rows + 1) * p
		
		var file_base = "icons_%s_%s_%d_spritesheet" % [cat_name, theme_slug, cell_w]
		var png_name = file_base + ".png"
		var json_name = file_base + ".json"
		
		var sheet_img = Image.create(sheet_w, sheet_h, false, Image.FORMAT_RGBA8)
		sheet_img.fill(Color(0, 0, 0, 0))
		
		var json_data = {
			"app_header": {
				"spritesheet_name": png_name,
				"version": "1.0",
				"platform": "godot",
				"platform_version": "4.7",
				"theme": theme_display_name,
				"theme_slug": theme_slug,
				"icon_size": cell_w,
				"padding": p,
				"margin": p,
				"cell_size": [cell_w, cell_h],
				"sheet_size": [sheet_w, sheet_h],
				"total_icons": count
			},
			"data": {}
		}
		
		for i in range(count):
			var icon_key = icon_keys[i]
			var img: Image = rendered_images[icon_key]
			var col = i % cols
			var row = floori(float(i) / float(cols))
			var dest_x = p + col * (cell_w + p)
			var dest_y = p + row * (cell_h + p)
			
			sheet_img.blit_rect(img, Rect2i(0, 0, img.get_width(), img.get_height()), Vector2i(dest_x, dest_y))
			
			var meta_info = items_registry.get(icon_key, {})
			var entry = {
				"name": icon_key,
				"readable_name": meta_info.get("readable_name", icon_key),
				"theme": theme_display_name,
				"icon_size": cell_w,
				"x": dest_x,
				"y": dest_y,
				"width": cell_w,
				"height": cell_h
			}
			if meta_info.get("keycode", 0) != 0:
				entry["keycode"] = meta_info["keycode"]
			if meta_info.get("mouse_button", -1) != -1:
				entry["mouse_button"] = meta_info["mouse_button"]
			if meta_info.get("joy_button", -1) != -1:
				entry["joy_button"] = meta_info["joy_button"]
			if meta_info.get("joy_axis", -1) != -1:
				entry["joy_axis"] = meta_info["joy_axis"]
			json_data["data"][icon_key] = entry
			
		sheet_img.save_png(spritesheet_dir + png_name)
		
		var json_file = FileAccess.open(spritesheet_dir + json_name, FileAccess.WRITE)
		if json_file:
			json_file.store_string(JSON.stringify(json_data, "\t"))
			json_file.close()
			
	status_label.text = "Status: Spritesheets generated successfully (%s - %dpx)" % [theme_display_name, current_size]
	await get_tree().create_timer(1.2).timeout
	progress_bar.visible = false

func create_gdignore(path: String) -> void:
	DirAccess.make_dir_recursive_absolute(path)
	var file = FileAccess.open(path + ".gdignore", FileAccess.WRITE)
	if file:
		file.close()

func open_folder() -> void:
	var path = ProjectSettings.globalize_path(output_dir)
	DirAccess.make_dir_recursive_absolute(output_dir)
	OS.shell_open(path)
