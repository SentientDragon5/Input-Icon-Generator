class_name InputIconHelper

var texture: Texture2D = preload("res://spritesheets/all_spritesheet.png")
var data: Dictionary = {}

func _init() -> void:
	var file = FileAccess.open("res://spritesheets/all_spritesheet.json", FileAccess.READ)
	if file:
		var json = JSON.parse_string(file.get_as_text())
		if json and json.has("data"):
			data = json["data"]

func get_atlas_texture(icon_name: String) -> AtlasTexture:
	if not data.has(icon_name):
		return null
	var item = data[icon_name]
	var atlas = AtlasTexture.new()
	atlas.atlas = texture
	atlas.region = Rect2(item.x, item.y, item.width, item.height)
	return atlas

func get_readable_name(icon_name: String) -> String:
	return data.get(icon_name, {}).get("readable_name", icon_name.replace("_", " ").capitalize())
