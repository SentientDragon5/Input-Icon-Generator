class_name InputIconHelper

var texture: Texture2D
var data: Dictionary = {}
var keycodes: Dictionary = {}
var mouse_buttons: Dictionary = {}
var joy_buttons: Dictionary = {}
var joy_axes: Dictionary = {}

func _init(spritesheet_path: String = "") -> void:
	var json_path = spritesheet_path
	if json_path.is_empty():
		var dir = DirAccess.open("res://spritesheets/")
		if dir:
			for f in dir.get_files():
				if f.ends_with(".json") and ("icons_all" in f or "all" in f):
					json_path = "res://spritesheets/" + f
					break
		if json_path.is_empty():
			json_path = "res://spritesheets/all_spritesheet.json"
			
	var png_path = json_path.replace(".json", ".png")
	if ResourceLoader.exists(png_path):
		texture = load(png_path)
		
	var file = FileAccess.open(json_path, FileAccess.READ)
	if file:
		var json = JSON.parse_string(file.get_as_text())
		if json and json.has("data"):
			data = json["data"]
			for k in data:
				var item = data[k]
				if item.has("keycode") and int(item["keycode"]) != 0:
					keycodes[int(item["keycode"])] = k
				if item.has("mouse_button") and int(item["mouse_button"]) != -1:
					mouse_buttons[int(item["mouse_button"])] = k
				if item.has("joy_button") and int(item["joy_button"]) != -1:
					joy_buttons[int(item["joy_button"])] = k
				if item.has("joy_axis") and int(item["joy_axis"]) != -1:
					joy_axes[int(item["joy_axis"])] = k

func get_atlas_texture(icon_name: String) -> AtlasTexture:
	if not data.has(icon_name) or not texture:
		return null
	var item = data[icon_name]
	var atlas = AtlasTexture.new()
	atlas.atlas = texture
	atlas.region = Rect2(item.x, item.y, item.width, item.height)
	return atlas

func get_icon_name_for_event(event: InputEvent) -> String:
	if event is InputEventKey:
		var code = event.physical_keycode if event.physical_keycode != 0 else event.keycode
		if keycodes.has(code):
			return keycodes[code]
		if event.keycode != 0 and keycodes.has(event.keycode):
			return keycodes[event.keycode]
	elif event is InputEventMouseButton:
		return mouse_buttons.get(event.button_index, "")
	elif event is InputEventJoypadButton:
		return joy_buttons.get(event.button_index, "")
	elif event is InputEventJoypadMotion:
		if abs(event.axis_value) > 0.5:
			return joy_axes.get(event.axis, "")
	return ""

func get_atlas_texture_for_event(event: InputEvent) -> AtlasTexture:
	var icon_name = get_icon_name_for_event(event)
	if not icon_name.is_empty():
		return get_atlas_texture(icon_name)
	return null

func get_readable_name(icon_name: String) -> String:
	return data.get(icon_name, {}).get("readable_name", icon_name.replace("_", " ").capitalize())

