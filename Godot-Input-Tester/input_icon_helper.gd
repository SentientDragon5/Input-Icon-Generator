class_name InputIconHelper

var texture: Texture2D
var data: Dictionary = {}

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

func get_atlas_texture(icon_name: String) -> AtlasTexture:
	if not data.has(icon_name) or not texture:
		return null
	var item = data[icon_name]
	var atlas = AtlasTexture.new()
	atlas.atlas = texture
	atlas.region = Rect2(item.x, item.y, item.width, item.height)
	return atlas

func get_readable_name(icon_name: String) -> String:
	return data.get(icon_name, {}).get("readable_name", icon_name.replace("_", " ").capitalize())
