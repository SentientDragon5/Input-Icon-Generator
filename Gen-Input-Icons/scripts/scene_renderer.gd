extends Node2D
class_name SceneRenderer

@export var output_dir: String = "res://output/"
@export var default_icon_size: Vector2i = Vector2i(64, 64)

@onready var sub_viewport: SubViewport = $SubViewport
@onready var to_render: Node2D = $SubViewport/ToRender
@onready var preview_rect: TextureRect = $UI/PreviewRect
@onready var dims_label: Label = $UI/DimsLabel
@onready var status_label: Label = $UI/StatusLabel
@onready var button_list: VBoxContainer = $UI/Sidebar/VBoxContainer/ScrollContainer/ButtonList

var key_base_scene: PackedScene = preload("res://templates/key_base.tscn")
var key_wide_base_scene: PackedScene = preload("res://templates/key_wide_base.tscn")

var items_registry: Dictionary = {}
var rendered_images: Dictionary = {}

func get_output_icons_dir() -> String:
	return output_dir + "icons/"

func get_output_spritesheets_dir() -> String:
	return output_dir + "spritesheets/"

func _ready() -> void:
	create_gdignore(output_dir)
	create_gdignore(get_output_icons_dir())
	create_gdignore(get_output_spritesheets_dir())
	
	build_items_registry()
	
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

func build_items_registry() -> void:
	items_registry.clear()
	
	# 1. Register all handcrafted scenes in res://generated/ (Gamepads, Mouse, D-Pad, Custom)
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
		
	# 2. Procedurally generate all keyboard keys (Letters A-Z, Numbers 0-9, F1-F12, Symbols, Navigation, Numpad)
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

func instantiate_item(item_data: Dictionary) -> Node:
	if item_data["type"] == "scene":
		var sc: PackedScene = item_data["scene"]
		return sc.instantiate()
	elif item_data["type"] == "procedural_key":
		var tmpl: PackedScene = item_data["template"]
		var inst = tmpl.instantiate()
		var label_node = inst.get_node_or_null("Panel/Label") as Label
		if label_node:
			label_node.text = item_data["label"]
			if item_data.has("font_size"):
				label_node.add_theme_font_size_override("font_size", item_data["font_size"])
		return inst
	return null

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
		
	for child in to_render.get_children():
		child.queue_free()
		
	var instance = instantiate_item(items_registry[item_name])
	if not instance:
		return
		
	to_render.add_child(instance)
	
	sub_viewport.size = default_icon_size
	if instance is Control:
		instance.size = default_icon_size
		
	dims_label.text = "Selected: " + item_name + " (" + str(default_icon_size.x) + "x" + str(default_icon_size.y) + ")"

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
	
	for cat_name in categories.keys():
		var icon_keys: Array = categories[cat_name]
		if icon_keys.is_empty():
			continue
			
		icon_keys.sort()
		var count = icon_keys.size()
		var cols = int(ceil(sqrt(count)))
		var rows = int(ceil(float(count) / float(cols)))
		
		var sheet_w = cols * default_icon_size.x
		var sheet_h = rows * default_icon_size.y
		
		var sheet_img = Image.create(sheet_w, sheet_h, false, Image.FORMAT_RGBA8)
		sheet_img.fill(Color(0, 0, 0, 0)) # 100% transparent background
		
		var json_data = {
			"app_header": {
				"spritesheet_name": cat_name + "_spritesheet.png",
				"version": "1.0",
				"platform": "godot",
				"platform_version": "4.7",
				"cell_size": [default_icon_size.x, default_icon_size.y],
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
			var dest_x = col * default_icon_size.x
			var dest_y = row * default_icon_size.y
			
			sheet_img.blit_rect(img, Rect2i(0, 0, img.get_width(), img.get_height()), Vector2i(dest_x, dest_y))
			
			var meta_info = items_registry.get(icon_key, {})
			var entry = {
				"name": icon_key,
				"readable_name": meta_info.get("readable_name", icon_key),
				"x": dest_x,
				"y": dest_y,
				"width": default_icon_size.x,
				"height": default_icon_size.y
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
		
	status_label.text = "Status: Spritesheets generated successfully"

func create_gdignore(path: String) -> void:
	DirAccess.make_dir_recursive_absolute(path)
	var file = FileAccess.open(path + ".gdignore", FileAccess.WRITE)
	if file:
		file.close()

func open_folder() -> void:
	var path = ProjectSettings.globalize_path(output_dir)
	DirAccess.make_dir_recursive_absolute(output_dir)
	OS.shell_open(path)
