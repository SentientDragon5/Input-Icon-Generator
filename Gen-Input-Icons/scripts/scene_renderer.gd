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

var generated_scenes: Dictionary = {}
var rendered_images: Dictionary = {}

func get_output_icons_dir() -> String:
	return output_dir + "icons/"

func get_output_spritesheets_dir() -> String:
	return output_dir + "spritesheets/"

func _ready() -> void:
	create_gdignore(output_dir)
	create_gdignore(get_output_icons_dir())
	create_gdignore(get_output_spritesheets_dir())
	
	scan_scenes()
	
	await get_tree().process_frame
	
	if "--render-icons" in OS.get_cmdline_user_args() or "--render-all" in OS.get_cmdline_args():
		await render_all()
		await generate_spritesheets()
		get_tree().quit()
		return
		
	populate_icon_buttons()
	if generated_scenes.size() > 0:
		var first_key = generated_scenes.keys()[0]
		show_preview(first_key)

func scan_scenes() -> void:
	generated_scenes.clear()
	var dir = DirAccess.open("res://generated/")
	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			if not dir.current_is_dir() and file_name.ends_with(".tscn"):
				var scene_name = file_name.get_basename()
				var scene_path = "res://generated/" + file_name
				var loaded_res = load(scene_path)
				if loaded_res is PackedScene:
					generated_scenes[scene_name] = loaded_res
			file_name = dir.get_next()
		dir.list_dir_end()
	print("SceneRenderer: Found ", generated_scenes.size(), " generated scenes.")

func populate_icon_buttons() -> void:
	for child in button_list.get_children():
		child.queue_free()
		
	var keys = generated_scenes.keys()
	keys.sort()
	for key in keys:
		var b = Button.new()
		b.text = key
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.pressed.connect(show_and_render_single.bind(key))
		button_list.add_child(b)

func show_preview(scene_name: String) -> void:
	if not generated_scenes.has(scene_name):
		return
		
	for child in to_render.get_children():
		child.queue_free()
		
	var instance = generated_scenes[scene_name].instantiate()
	to_render.add_child(instance)
	
	sub_viewport.size = default_icon_size
	if instance is Control:
		instance.size = default_icon_size
		
	dims_label.text = "Selected: " + scene_name + " (" + str(default_icon_size.x) + "x" + str(default_icon_size.y) + ")"

func show_and_render_single(scene_name: String) -> void:
	show_preview(scene_name)
	await render_scene_to_file(scene_name)

func render_scene_to_file(scene_name: String) -> String:
	show_preview(scene_name)
	
	sub_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	await get_tree().process_frame
	
	var image = sub_viewport.get_texture().get_image()
	if not image or image.is_empty():
		printerr("SceneRenderer: Empty image for ", scene_name)
		return ""
		
	var out_dir = get_output_icons_dir()
	DirAccess.make_dir_recursive_absolute(out_dir)
	var file_path = out_dir + scene_name + ".png"
	
	var err = image.save_png(file_path)
	if err == OK:
		print("SceneRenderer: Saved ", file_path)
		rendered_images[scene_name] = image
		status_label.text = "Status: Saved " + scene_name + ".png"
		return file_path
	else:
		printerr("SceneRenderer: Failed to save ", file_path)
		return ""

func render_all() -> void:
	status_label.text = "Status: Rendering all icons..."
	var keys = generated_scenes.keys()
	keys.sort()
	
	for key in keys:
		await render_scene_to_file(key)
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
		if key.begins_with("button_") or key.begins_with("dpad_") or key.begins_with("bumper_") or key.begins_with("trigger_") or key.begins_with("stick_") or key.begins_with("paddle_"):
			categories["gamepad"].append(key)
		elif key.begins_with("key_"):
			categories["keyboard"].append(key)
		elif key.begins_with("mouse_"):
			categories["mouse"].append(key)
			
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
		sheet_img.fill(Color(0, 0, 0, 0))
		
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
			
			json_data["data"][icon_key] = {
				"name": icon_key,
				"x": dest_x,
				"y": dest_y,
				"width": default_icon_size.x,
				"height": default_icon_size.y
			}
			
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
