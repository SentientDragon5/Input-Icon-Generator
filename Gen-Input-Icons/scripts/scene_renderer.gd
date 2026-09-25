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

@onready var big_preview_rect: TextureRect = $UI/PreviewArea/VBoxContainer/PreviewsHBox/BigPreviewBox/VBoxContainer/BigPreviewPanel/BigPreviewRect
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
		var first_key = items_registry.keys()[0]
		show_preview(first_key)

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
		var theme_path = themes_dir + file_name
		var res = load(theme_path)
		if res is Theme:
			loaded_themes.append(res)
			theme_names.append(file_name.get_basename().replace("_", " ").capitalize())
	
	if loaded_themes.is_empty():
		var default_theme = Theme.new()
		loaded_themes.append(default_theme)
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
		size_slider.min_value = 16
		size_slider.max_value = 256
		size_slider.step = 1
		size_slider.value = current_size
		
		size_spin_box.min_value = 16
		size_spin_box.max_value = 256
		size_spin_box.step = 1
		size_spin_box.value = current_size
		
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
	
	# 1. Register handcrafted scenes in res://generated/
	var dir = DirAccess.open("res://generated/")
	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			if not dir.current_is_dir() and file_name.ends_with(".tscn"):
				var item_name = file_name.get_basename()
				var scene_path = "res://generated/" + file_name
				var loaded_res = load(scene_path)
				if loaded_res is PackedScene:
					var category = determine_category(item_name)
					items_registry[item_name] = {
						"type": "scene",
						"name": item_name,
						"scene": loaded_res,
						"category": category,
						"readable_name": item_name.replace("_", " ").capitalize(),
						"keycode": 0
					}
			file_name = dir.get_next()
		dir.list_dir_end()
		
	# 2. Register procedural keyboard keys
	register_procedural_keyboard_keys()
	
	print("SceneRenderer: Total items registered -> ", items_registry.size())

func determine_category(item_name: String) -> String:
	if item_name.begins_with("button_") or item_name.begins_with("dpad_") or item_name.begins_with("bumper_") or item_name.begins_with("trigger_") or item_name.begins_with("stick_") or item_name.begins_with("paddle_"):
		return "gamepad"
	elif item_name.begins_with("mouse_"):
		return "mouse"
	elif item_name.begins_with("key_"):
		return "keyboard"
	return "general"

func register_procedural_keyboard_keys() -> void:
	# A-Z letters
	for code in range(KEY_A, KEY_Z + 1):
		var char_str = String.chr(code)
		var item_name = "key_" + char_str.to_lower()
		items_registry[item_name] = {
			"type": "procedural_key",
			"name": item_name,
			"readable_name": char_str,
			"label": char_str,
			"template": key_base_scene,
			"font_size": 18,
			"category": "keyboard",
			"keycode": code
		}
		
	# 0-9 digits
	for code in range(KEY_0, KEY_9 + 1):
		var char_str = String.chr(code)
		var item_name = "key_" + char_str
		items_registry[item_name] = {
			"type": "procedural_key",
			"name": item_name,
			"readable_name": char_str,
			"label": char_str,
			"template": key_base_scene,
			"font_size": 18,
			"category": "keyboard",
			"keycode": code
		}
		
	# F1-F12 function keys
	for i in range(1, 13):
		var label_str = "F" + str(i)
		var item_name = "key_f" + str(i)
		var keycode = KEY_F1 + (i - 1)
		items_registry[item_name] = {
			"type": "procedural_key",
			"name": item_name,
			"readable_name": label_str,
			"label": label_str,
			"template": key_base_scene,
			"font_size": 14,
			"category": "keyboard",
			"keycode": keycode
		}
		
	# Symbols & punctuation
	var symbols = [
		{"name": "key_comma", "label": ",", "readable": ",", "code": KEY_COMMA, "font_size": 20},
		{"name": "key_period", "label": ".", "readable": ".", "code": KEY_PERIOD, "font_size": 20},
		{"name": "key_slash", "label": "/", "readable": "/", "code": KEY_SLASH, "font_size": 18},
		{"name": "key_backslash", "label": "\\", "readable": "\\", "code": KEY_BACKSLASH, "font_size": 18},
		{"name": "key_semicolon", "label": ";", "readable": ";", "code": KEY_SEMICOLON, "font_size": 18},
		{"name": "key_apostrophe", "label": "'", "readable": "'", "code": KEY_APOSTROPHE, "font_size": 20},
		{"name": "key_bracketleft", "label": "[", "readable": "[", "code": KEY_BRACKETLEFT, "font_size": 18},
		{"name": "key_bracketright", "label": "]", "readable": "]", "code": KEY_BRACKETRIGHT, "font_size": 18},
		{"name": "key_minus", "label": "-", "readable": "-", "code": KEY_MINUS, "font_size": 20},
		{"name": "key_equal", "label": "=", "readable": "=", "code": KEY_EQUAL, "font_size": 18},
		{"name": "key_backquote", "label": "`", "readable": "`", "code": KEY_QUOTELEFT, "font_size": 20},
		{"name": "key_exclam", "label": "!", "readable": "!", "code": KEY_EXCLAM, "font_size": 18},
		{"name": "key_question", "label": "?", "readable": "?", "code": KEY_QUESTION, "font_size": 18},
		{"name": "key_plus", "label": "+", "readable": "+", "code": KEY_PLUS, "font_size": 18},
		{"name": "key_colon", "label": ":", "readable": ":", "code": KEY_COLON, "font_size": 18},
		{"name": "key_quotedbl", "label": "\"", "readable": "\"", "code": KEY_QUOTEDBL, "font_size": 18},
		{"name": "key_less", "label": "<", "readable": "<", "code": KEY_LESS, "font_size": 18},
		{"name": "key_greater", "label": ">", "readable": ">", "code": KEY_GREATER, "font_size": 18},
		{"name": "key_underscore", "label": "_", "readable": "_", "code": KEY_UNDERSCORE, "font_size": 18},
		{"name": "key_braceleft", "label": "{", "readable": "{", "code": KEY_BRACELEFT, "font_size": 18},
		{"name": "key_braceright", "label": "}", "readable": "}", "code": KEY_BRACERIGHT, "font_size": 18},
		{"name": "key_bar", "label": "|", "readable": "|", "code": KEY_BAR, "font_size": 18},
		{"name": "key_asciitilde", "label": "~", "readable": "~", "code": KEY_ASCIITILDE, "font_size": 18},
		{"name": "key_at", "label": "@", "readable": "@", "code": KEY_AT, "font_size": 16},
		{"name": "key_hash", "label": "#", "readable": "#", "code": KEY_NUMBERSIGN, "font_size": 18},
		{"name": "key_dollar", "label": "$", "readable": "$", "code": KEY_DOLLAR, "font_size": 18},
		{"name": "key_percent", "label": "%", "readable": "%", "code": KEY_PERCENT, "font_size": 16},
		{"name": "key_ampersand", "label": "&", "readable": "&", "code": KEY_AMPERSAND, "font_size": 16},
		{"name": "key_asterisk", "label": "*", "readable": "*", "code": KEY_ASTERISK, "font_size": 20},
	]
	for sym in symbols:
		items_registry[sym["name"]] = {
			"type": "procedural_key",
			"name": sym["name"],
			"readable_name": sym["readable"],
			"label": sym["label"],
			"template": key_base_scene,
			"font_size": sym["font_size"],
			"category": "keyboard",
			"keycode": sym["code"]
		}
		
	# Numpad keys
	for i in range(10):
		var item_name = "key_kp_" + str(i)
		var label_str = "Num " + str(i)
		items_registry[item_name] = {
			"type": "procedural_key",
			"name": item_name,
			"readable_name": label_str,
			"label": label_str,
			"template": key_base_scene,
			"font_size": 11,
			"category": "keyboard",
			"keycode": KEY_KP_0 + i
		}
	var numpad_ops = [
		{"name": "key_kp_add", "label": "Num +", "code": KEY_KP_ADD},
		{"name": "key_kp_subtract", "label": "Num -", "code": KEY_KP_SUBTRACT},
		{"name": "key_kp_multiply", "label": "Num *", "code": KEY_KP_MULTIPLY},
		{"name": "key_kp_divide", "label": "Num /", "code": KEY_KP_DIVIDE},
		{"name": "key_kp_period", "label": "Num .", "code": KEY_KP_PERIOD},
		{"name": "key_kp_enter", "label": "Num Enter", "code": KEY_KP_ENTER},
	]
	for op in numpad_ops:
		items_registry[op["name"]] = {
			"type": "procedural_key",
			"name": op["name"],
			"readable_name": op["label"],
			"label": op["label"],
			"template": key_base_scene,
			"font_size": 10,
			"category": "keyboard",
			"keycode": op["code"]
		}
		
	# Navigation & special keys
	var nav_keys = [
		{"name": "key_escape", "label": "Esc", "readable": "Escape", "code": KEY_ESCAPE, "wide": false},
		{"name": "key_insert", "label": "Ins", "readable": "Insert", "code": KEY_INSERT, "wide": false},
		{"name": "key_delete", "label": "Del", "readable": "Delete", "code": KEY_DELETE, "wide": false},
		{"name": "key_home", "label": "Home", "readable": "Home", "code": KEY_HOME, "wide": false},
		{"name": "key_end", "label": "End", "readable": "End", "code": KEY_END, "wide": false},
		{"name": "key_pageup", "label": "PgUp", "readable": "Page Up", "code": KEY_PAGEUP, "wide": false},
		{"name": "key_pagedown", "label": "PgDn", "readable": "Page Down", "code": KEY_PAGEDOWN, "wide": false},
		{"name": "key_up", "label": "Up", "readable": "Up Arrow", "code": KEY_UP, "wide": false},
		{"name": "key_down", "label": "Down", "readable": "Down Arrow", "code": KEY_DOWN, "wide": false},
		{"name": "key_left", "label": "Left", "readable": "Left Arrow", "code": KEY_LEFT, "wide": false},
		{"name": "key_right", "label": "Right", "readable": "Right Arrow", "code": KEY_RIGHT, "wide": false},
		{"name": "key_capslock", "label": "Caps", "readable": "Caps Lock", "code": KEY_CAPSLOCK, "wide": true},
		{"name": "key_numlock", "label": "NumLk", "readable": "Num Lock", "code": KEY_NUMLOCK, "wide": true},
		{"name": "key_scrolllock", "label": "ScrLk", "readable": "Scroll Lock", "code": KEY_SCROLLLOCK, "wide": true},
		{"name": "key_printscreen", "label": "PrtSc", "readable": "Print Screen", "code": KEY_PRINT, "wide": true},
		{"name": "key_pause", "label": "Pause", "readable": "Pause", "code": KEY_PAUSE, "wide": false},
		{"name": "key_meta", "label": "Meta", "readable": "Win / Cmd", "code": KEY_META, "wide": true},
	]
	for nk in nav_keys:
		var tmpl = key_wide_base_scene if nk["wide"] else key_base_scene
		items_registry[nk["name"]] = {
			"type": "procedural_key",
			"name": nk["name"],
			"readable_name": nk["readable"],
			"label": nk["label"],
			"template": tmpl,
			"font_size": 12,
			"category": "keyboard",
			"keycode": nk["code"]
		}

func apply_theme_to_tree(node: Node, theme_res: Theme) -> void:
	if not node or not theme_res:
		return
		
	var theme_sb: StyleBoxFlat = null
	if theme_res.has_stylebox("panel", "Panel"):
		var sb_res = theme_res.get_stylebox("panel", "Panel")
		if sb_res is StyleBoxFlat:
			theme_sb = sb_res
			
	var main_bg_color: Color = theme_sb.bg_color if theme_sb else Color(0.18, 0.18, 0.18, 1.0)
	var main_border_color: Color = theme_sb.border_color if theme_sb else Color(0.55, 0.55, 0.55, 1.0)
	var border_w: int = theme_sb.border_width_left if (theme_sb and theme_sb.border_width_left > 0) else 2
	var is_open_theme: bool = (main_bg_color.a <= 0.01)
	
	var fg_color: Color = Color(1.0, 1.0, 1.0, 1.0)
	if theme_res.has_color("font_color", "Label"):
		fg_color = theme_res.get_color("font_color", "Label")
	elif theme_res.has_color("font_color", "Button"):
		fg_color = theme_res.get_color("font_color", "Button")
		
	var inactive_fg_color: Color = Color(fg_color.r, fg_color.g, fg_color.b, 0.35)
	var secondary_bg_color: Color = main_bg_color.lerp(main_border_color, 0.2) if not is_open_theme else Color(0, 0, 0, 0)
	
	_apply_theme_recursive(node, theme_res, theme_sb, main_bg_color, main_border_color, border_w, is_open_theme, fg_color, inactive_fg_color, secondary_bg_color)

func _apply_theme_recursive(
	node: Node,
	theme_res: Theme,
	theme_sb: StyleBoxFlat,
	main_bg: Color,
	main_border: Color,
	border_w: int,
	is_open: bool,
	fg: Color,
	inactive_fg: Color,
	secondary_bg: Color
) -> void:
	if not node:
		return
		
	var node_name: String = String(node.name)
	
	if node is Label:
		node.add_theme_color_override("font_color", fg)
		
	elif node is Panel:
		var current_sb = node.get_theme_stylebox("panel")
		var sb: StyleBoxFlat = null
		if current_sb is StyleBoxFlat:
			sb = current_sb.duplicate() as StyleBoxFlat
		else:
			sb = StyleBoxFlat.new()
			
		match node_name:
			"Bar1", "Bar2", "Bar3":
				sb.bg_color = fg
				sb.border_width_left = 0
				sb.border_width_top = 0
				sb.border_width_right = 0
				sb.border_width_bottom = 0
				
			"Body" when node.get_parent() and node.get_parent().name == "HomeIcon":
				sb.bg_color = fg
				sb.border_width_left = 0
				sb.border_width_top = 0
				sb.border_width_right = 0
				sb.border_width_bottom = 0
				
			"Door":
				if is_open:
					sb.bg_color = Color(0, 0, 0, 0)
					sb.border_color = fg
					sb.border_width_left = 1
					sb.border_width_top = 1
					sb.border_width_right = 1
					sb.border_width_bottom = 0
				else:
					sb.bg_color = main_bg
					sb.border_width_left = 0
					sb.border_width_top = 0
					sb.border_width_right = 0
					sb.border_width_bottom = 0
					
			"BackSquare":
				sb.bg_color = Color(0, 0, 0, 0)
				sb.border_color = fg
				sb.border_width_left = border_w
				sb.border_width_top = border_w
				sb.border_width_right = border_w
				sb.border_width_bottom = border_w
				
			"FrontSquare":
				if is_open:
					sb.bg_color = Color(0.08, 0.08, 0.1, 0.95)
				else:
					sb.bg_color = main_bg
				sb.border_color = fg
				sb.border_width_left = border_w
				sb.border_width_top = border_w
				sb.border_width_right = border_w
				sb.border_width_bottom = border_w
				
			"Tray":
				sb.bg_color = Color(0, 0, 0, 0)
				sb.border_color = fg
				sb.border_width_left = border_w
				sb.border_width_bottom = border_w
				sb.border_width_right = border_w
				sb.border_width_top = 0
				
			"LeftButton", "RightButton":
				var is_active: bool = (current_sb is StyleBoxFlat and current_sb.bg_color.v > 0.8 and current_sb.bg_color.s < 0.2)
				if is_active:
					sb.bg_color = fg
					sb.border_color = fg
					sb.border_width_left = 0
					sb.border_width_top = 0
					sb.border_width_right = 0
					sb.border_width_bottom = 0
				else:
					if is_open:
						sb.bg_color = Color(main_border.r, main_border.g, main_border.b, 0.12)
						sb.border_color = Color(main_border.r, main_border.g, main_border.b, 0.35)
						sb.border_width_left = 1
						sb.border_width_top = 1
						sb.border_width_right = 1
						sb.border_width_bottom = 1
					else:
						sb.bg_color = secondary_bg
						sb.border_width_left = 0
						sb.border_width_top = 0
						sb.border_width_right = 0
						sb.border_width_bottom = 0
						
			"ScrollWheel":
				var is_active: bool = (current_sb is StyleBoxFlat and current_sb.bg_color.v > 0.8 and current_sb.bg_color.s < 0.2)
				if is_active:
					sb.bg_color = fg
					sb.border_color = fg
					sb.border_width_left = 0
					sb.border_width_top = 0
					sb.border_width_right = 0
					sb.border_width_bottom = 0
				else:
					if is_open:
						sb.bg_color = Color(main_border.r, main_border.g, main_border.b, 0.25)
						sb.border_color = main_border
						sb.border_width_left = 1
						sb.border_width_top = 1
						sb.border_width_right = 1
						sb.border_width_bottom = 1
					else:
						sb.bg_color = secondary_bg
						sb.border_width_left = 0
						sb.border_width_top = 0
						sb.border_width_right = 0
						sb.border_width_bottom = 0
						
			"SideButton1", "SideButton2":
				if node.visible:
					sb.bg_color = fg
					sb.border_color = fg
				else:
					sb.bg_color = secondary_bg
					
			"InnerCap":
				if is_open:
					sb.bg_color = Color(0, 0, 0, 0)
				else:
					sb.bg_color = secondary_bg
				sb.border_color = main_border
				sb.border_width_left = border_w
				sb.border_width_top = border_w
				sb.border_width_right = border_w
				sb.border_width_bottom = border_w
				
			"TrackArea":
				if is_open:
					sb.bg_color = Color(0, 0, 0, 0)
					sb.border_color = Color(main_border.r, main_border.g, main_border.b, 0.4)
					sb.border_width_left = 1
					sb.border_width_top = 1
					sb.border_width_right = 1
					sb.border_width_bottom = 1
				else:
					sb.bg_color = secondary_bg
					sb.border_width_left = 0
					sb.border_width_top = 0
					sb.border_width_right = 0
					sb.border_width_bottom = 0
					
			_:
				sb.bg_color = main_bg
				sb.border_color = main_border
				if sb.border_width_left > 0 or sb.border_width_top > 0 or sb.border_width_right > 0 or sb.border_width_bottom > 0:
					sb.border_width_left = border_w
					sb.border_width_top = border_w
					sb.border_width_right = border_w
					sb.border_width_bottom = border_w
					
		node.add_theme_stylebox_override("panel", sb)
		
	elif node is Polygon2D:
		match node_name:
			"CrossShape":
				node.color = main_bg
			"ArrowUp", "ArrowDown", "ArrowLeft", "ArrowRight":
				var is_active: bool = (node.color.v > 0.8 and node.color.a > 0.8)
				node.color = fg if is_active else inactive_fg
			"Roof", "ArrowHead", "ScrollArrowUp", "ScrollArrowDown":
				node.color = fg
			_:
				node.color = fg
				
	elif node is Line2D:
		match node_name:
			"CrossOutline":
				node.default_color = main_border
				node.width = float(border_w)
			"ArrowStem":
				node.default_color = fg
				node.width = float(border_w)
			_:
				node.default_color = fg
				
	for child in node.get_children():
		_apply_theme_recursive(child, theme_res, theme_sb, main_bg, main_border, border_w, is_open, fg, inactive_fg, secondary_bg)

func instantiate_item(item_data: Dictionary) -> Node:
	var inst: Node = null
	if item_data["type"] == "scene":
		var sc: PackedScene = item_data["scene"]
		inst = sc.instantiate()
	elif item_data["type"] == "procedural_key":
		var tmpl: PackedScene = item_data["template"]
		inst = tmpl.instantiate()
		var label_node = inst.get_node_or_null("Panel/Label") as Label
		if label_node:
			label_node.text = item_data["label"]
			if item_data.has("font_size"):
				var scale_factor = float(current_size) / 64.0
				var scaled_font_size = max(8, int(round(float(item_data["font_size"]) * scale_factor)))
				label_node.add_theme_font_size_override("font_size", scaled_font_size)
	
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
	
	var target_size = Vector2i(current_size, current_size)
	sub_viewport.size = target_size
	
	if instance is Control:
		instance.custom_minimum_size = Vector2(current_size, current_size)
		instance.size = Vector2(current_size, current_size)
		if instance is ColorRect:
			instance.position = Vector2.ZERO
		
	var theme_display_name = current_theme_name if not current_theme_name.is_empty() else "Default"
	if selected_header_label:
		selected_header_label.text = "Selected: " + item_name + " | Size: " + str(current_size) + "x" + str(current_size) + " | Theme: " + theme_display_name
	if dims_label:
		dims_label.text = "Dimensions: " + str(current_size) + "x" + str(current_size) + " px (" + theme_display_name + ")"
	if exact_title_label:
		exact_title_label.text = "Exact 1:1 Pixel Size (" + str(current_size) + "x" + str(current_size) + ")"
		
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
		printerr("SceneRenderer: Empty image for ", item_name)
		return ""
		
	var out_dir = get_output_icons_dir()
	DirAccess.make_dir_recursive_absolute(out_dir)
	var file_path = out_dir + item_name + ".png"
	
	var err = image.save_png(file_path)
	if err == OK:
		rendered_images[item_name] = image
		status_label.text = "Status: Saved " + item_name + ".png"
		return file_path
	else:
		printerr("SceneRenderer: Failed to save ", file_path)
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
	
	var categories = {
		"gamepad": [],
		"keyboard": [],
		"mouse": [],
		"all": []
	}
	
	for key in rendered_images.keys():
		categories["all"].append(key)
		var cat = items_registry[key]["category"] if items_registry.has(key) else determine_category(key)
		if categories.has(cat):
			categories[cat].append(key)
			
	var spritesheet_dir = get_output_spritesheets_dir()
	DirAccess.make_dir_recursive_absolute(spritesheet_dir)
	
	var cell_w = current_size
	var cell_h = current_size
	
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
		sheet_img.fill(Color(0, 0, 0, 0)) # 100% transparent background
		
		var theme_display_name = current_theme_name if not current_theme_name.is_empty() else "Default"
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
			var col = i % cols
			var row = floori(float(i) / float(cols))
			var dest_x = col * cell_w
			var dest_y = row * cell_h
			
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
			
		var png_path = spritesheet_dir + cat_name + "_spritesheet.png"
		var json_path = spritesheet_dir + cat_name + "_spritesheet.json"
		
		sheet_img.save_png(png_path)
		
		var json_file = FileAccess.open(json_path, FileAccess.WRITE)
		if json_file:
			json_file.store_string(JSON.stringify(json_data, "\t"))
			json_file.close()
			
		print("SceneRenderer: Generated spritesheet -> ", png_path, " & ", json_path)
		
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
