extends Control
class_name InputTester

const HISTORY_ITEM_PREFAB: PackedScene = preload("res://prefabs/history_item.tscn")
const ACTIVE_ICON_PREFAB: PackedScene = preload("res://prefabs/active_icon_item.tscn")

@onready var main_icon_rect: TextureRect = $UI/MainArea/CenterCard/VBox/IconCenter/MainIconRect
@onready var input_name_label: Label = $UI/MainArea/CenterCard/VBox/InputNameLabel
@onready var event_type_label: Label = $UI/MainArea/CenterCard/VBox/EventTypeLabel
@onready var meta_label: Label = $UI/MainArea/CenterCard/VBox/MetaLabel

@onready var active_icons_container: HBoxContainer = $UI/MainArea/ActiveInputsCard/Margin/VBox/ActiveIconsHBox
@onready var history_container: VBoxContainer = $UI/Sidebar/HistoryScroll/HistoryList
@onready var status_label: Label = $UI/BottomBar/Margin/StatusLabel

@onready var device_badge_lbl: Label = $UI/TopBar/Margin/HBox/DeviceBadge/BadgeMargin/DeviceBadgeLabel
@onready var device_type_lbl: Label = $UI/Sidebar/ControlsPanel/DeviceCard/Margin/VBox/DeviceTypeLabel
@onready var device_name_lbl: Label = $UI/Sidebar/ControlsPanel/DeviceCard/Margin/VBox/DeviceNameLabel
@onready var device_id_lbl: Label = $UI/Sidebar/ControlsPanel/DeviceCard/Margin/VBox/DeviceIdLabel

@onready var left_stick_val_lbl: Label = $UI/MainArea/AnalogCard/Margin/HBox/LeftStickBox/LeftStickVal
@onready var left_stick_dir_lbl: Label = $UI/MainArea/AnalogCard/Margin/HBox/LeftStickBox/LeftStickDir
@onready var right_stick_val_lbl: Label = $UI/MainArea/AnalogCard/Margin/HBox/RightStickBox/RightStickVal
@onready var right_stick_dir_lbl: Label = $UI/MainArea/AnalogCard/Margin/HBox/RightStickBox/RightStickDir
@onready var trigger_val_lbl: Label = $UI/MainArea/AnalogCard/Margin/HBox/TriggersBox/TriggerVal
@onready var trigger_pct_lbl: Label = $UI/MainArea/AnalogCard/Margin/HBox/TriggersBox/TriggerPct

var helper: InputIconHelper = InputIconHelper.new()
var active_pressed_keys: Dictionary = {}
var using_mouse: bool = true
var active_device_id: int = -1
var raw_controller_name: String = ""
var controller_platform: String = "keyboard"

func _ready() -> void:
	Input.joy_connection_changed.connect(_on_joy_connection_changed)
	update_device_ui()
	status_label.text = "Press any key, mouse button, or gamepad button to test!"

func _process(_delta: float) -> void:
	update_analog_monitor()

func _input(event: InputEvent) -> void:
	var icon_name = ""
	var key_id = ""
	var is_press = false
	var desc = ""

	if event is InputEventKey:
		_set_device_kbm()
		if event.is_echo(): return
		var code = event.keycode if event.keycode != 0 else event.physical_keycode
		key_id = "key_" + str(code)
		icon_name = "key_" + OS.get_keycode_string(code).to_lower().replace(" ", "")
		if code == KEY_ASCIITILDE or code == KEY_QUOTELEFT: icon_name = "key_tilde"
		desc = "Keyboard: %s (Keycode: %d)" % [OS.get_keycode_string(code), code]
		is_press = event.pressed

	elif event is InputEventMouseButton:
		_set_device_kbm()
		key_id = "mouse_" + str(event.button_index)
		match event.button_index:
			MOUSE_BUTTON_LEFT: icon_name = "mouse_left"
			MOUSE_BUTTON_RIGHT: icon_name = "mouse_right"
			MOUSE_BUTTON_MIDDLE: icon_name = "mouse_middle"
			MOUSE_BUTTON_WHEEL_UP: icon_name = "mouse_scroll_up"
			MOUSE_BUTTON_WHEEL_DOWN: icon_name = "mouse_scroll_down"
			MOUSE_BUTTON_XBUTTON1: icon_name = "mouse_side_1"
			MOUSE_BUTTON_XBUTTON2: icon_name = "mouse_side_2"
		desc = "Mouse Button %d at %s" % [event.button_index, str(event.position)]
		is_press = event.pressed

	elif event is InputEventJoypadButton:
		_set_device_gamepad(event.device)
		key_id = "joy_btn_" + str(event.button_index)
		match event.button_index:
			JOY_BUTTON_A: icon_name = "button_a"
			JOY_BUTTON_B: icon_name = "button_b"
			JOY_BUTTON_X: icon_name = "button_x"
			JOY_BUTTON_Y: icon_name = "button_y"
			JOY_BUTTON_BACK: icon_name = "button_view"
			JOY_BUTTON_START: icon_name = "button_options"
			JOY_BUTTON_GUIDE: icon_name = "button_home"
			JOY_BUTTON_LEFT_STICK: icon_name = "stick_l3"
			JOY_BUTTON_RIGHT_STICK: icon_name = "stick_r3"
			JOY_BUTTON_LEFT_SHOULDER: icon_name = "bumper_left"
			JOY_BUTTON_RIGHT_SHOULDER: icon_name = "bumper_right"
			JOY_BUTTON_DPAD_UP: icon_name = "dpad_up"
			JOY_BUTTON_DPAD_DOWN: icon_name = "dpad_down"
			JOY_BUTTON_DPAD_LEFT: icon_name = "dpad_left"
			JOY_BUTTON_DPAD_RIGHT: icon_name = "dpad_right"
			JOY_BUTTON_MISC1: icon_name = "button_share"
			JOY_BUTTON_PADDLE1: icon_name = "paddle_p1"
			JOY_BUTTON_PADDLE2: icon_name = "paddle_p2"
			JOY_BUTTON_PADDLE3: icon_name = "paddle_p3"
			JOY_BUTTON_PADDLE4: icon_name = "paddle_p4"
			JOY_BUTTON_TOUCHPAD: icon_name = "touchpad"
		desc = "Gamepad Button %d (%s)" % [event.button_index, icon_name]
		is_press = event.pressed

	elif event is InputEventJoypadMotion:
		if abs(event.axis_value) > 0.2: _set_device_gamepad(event.device)
		if abs(event.axis_value) > 0.35:
			is_press = true
			if event.axis in [JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y]:
				icon_name = "stick_l3"
				key_id = "axis_left_stick"
				var vec = Vector2(Input.get_joy_axis(event.device, JOY_AXIS_LEFT_X), Input.get_joy_axis(event.device, JOY_AXIS_LEFT_Y))
				desc = "Left Stick: (X: %+.2f, Y: %+.2f) | %s" % [vec.x, vec.y, _get_dir_str(vec)]
			elif event.axis in [JOY_AXIS_RIGHT_X, JOY_AXIS_RIGHT_Y]:
				icon_name = "stick_r3"
				key_id = "axis_right_stick"
				var vec = Vector2(Input.get_joy_axis(event.device, JOY_AXIS_RIGHT_X), Input.get_joy_axis(event.device, JOY_AXIS_RIGHT_Y))
				desc = "Right Stick: (X: %+.2f, Y: %+.2f) | %s" % [vec.x, vec.y, _get_dir_str(vec)]
			elif event.axis == JOY_AXIS_TRIGGER_LEFT:
				icon_name = "trigger_left"
				key_id = "axis_lt"
				desc = "Left Trigger: %.2f (%d%%)" % [event.axis_value, int(round(clamp(event.axis_value, 0.0, 1.0) * 100.0))]
			elif event.axis == JOY_AXIS_TRIGGER_RIGHT:
				icon_name = "trigger_right"
				key_id = "axis_rt"
				desc = "Right Trigger: %.2f (%d%%)" % [event.axis_value, int(round(clamp(event.axis_value, 0.0, 1.0) * 100.0))]
		elif abs(event.axis_value) < 0.2:
			if event.axis in [JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y]: key_id = "axis_left_stick"
			elif event.axis in [JOY_AXIS_RIGHT_X, JOY_AXIS_RIGHT_Y]: key_id = "axis_right_stick"
			elif event.axis == JOY_AXIS_TRIGGER_LEFT: key_id = "axis_lt"
			elif event.axis == JOY_AXIS_TRIGGER_RIGHT: key_id = "axis_rt"

	if is_press and not icon_name.is_empty():
		active_pressed_keys[key_id] = icon_name
		display_pressed_input(icon_name, desc)
		update_active_icons_ui()
	elif not is_press and not key_id.is_empty() and active_pressed_keys.has(key_id):
		active_pressed_keys.erase(key_id)
		update_active_icons_ui()

func display_pressed_input(icon_name: String, desc: String) -> void:
	var tex = helper.get_atlas_texture(icon_name)
	var readable = helper.get_readable_name(icon_name)
	var meta = helper.data.get(icon_name, {})

	if tex:
		main_icon_rect.texture = tex
		input_name_label.text = readable
		event_type_label.text = desc
		meta_label.text = "Spritesheet Slice: [X: %d, Y: %d, %dx%d px] | Key: %s" % [
			meta.get("x", 0), meta.get("y", 0), meta.get("width", 64), meta.get("height", 64), icon_name
		]
		status_label.text = "Detected Input: " + readable
		add_to_history(tex, readable)
	else:
		input_name_label.text = readable + " (No Sprite Found)"
		event_type_label.text = desc
		meta_label.text = "Icon Key: " + icon_name

func add_to_history(tex: Texture2D, display_name: String) -> void:
	while history_container.get_child_count() >= 20:
		var old_child = history_container.get_child(history_container.get_child_count() - 1)
		history_container.remove_child(old_child)
		old_child.queue_free()

	var item = HISTORY_ITEM_PREFAB.instantiate()
	item.get_node("Icon").texture = tex
	item.get_node("NameLabel").text = display_name
	item.get_node("TimeLabel").text = Time.get_time_string_from_system()
	history_container.add_child(item)
	history_container.move_child(item, 0)

func update_active_icons_ui() -> void:
	for child in active_icons_container.get_children():
		active_icons_container.remove_child(child)
		child.queue_free()

	for key_id in active_pressed_keys.keys():
		var tex = helper.get_atlas_texture(active_pressed_keys[key_id])
		if tex:
			var item = ACTIVE_ICON_PREFAB.instantiate()
			item.texture = tex
			active_icons_container.add_child(item)

func _set_device_kbm() -> void:
	if not using_mouse:
		using_mouse = true
		active_device_id = -1
		controller_platform = "keyboard"
		update_device_ui()

func _set_device_gamepad(device: int) -> void:
	var new_name = Input.get_joy_name(device)
	if using_mouse or active_device_id != device or raw_controller_name != new_name:
		using_mouse = false
		active_device_id = device
		raw_controller_name = new_name
		var n = raw_controller_name.to_lower()
		if "nintendo" in n or "switch" in n or "joy-con" in n or "wii" in n: controller_platform = "nintendo"
		elif "ps" in n or "playstation" in n or "dualshock" in n or "dualsense" in n: controller_platform = "ps"
		elif "steam" in n: controller_platform = "steam"
		else: controller_platform = "xbox"
		update_device_ui()

func update_device_ui() -> void:
	var count = Input.get_connected_joypads().size()
	if using_mouse:
		if device_badge_lbl:
			device_badge_lbl.text = "⌨ Keyboard & Mouse"
			device_badge_lbl.add_theme_color_override("font_color", Color(0.6, 0.9, 0.7, 1))
		if device_type_lbl: device_type_lbl.text = "Active: Keyboard & Mouse"
		if device_name_lbl: device_name_lbl.text = "Gamepad: " + (raw_controller_name if not raw_controller_name.is_empty() else "None (Standby)")
		if device_id_lbl: device_id_lbl.text = "Device ID: -1 | Gamepads: %d" % count
	else:
		var title = "Xbox" if controller_platform == "xbox" else ("PlayStation" if controller_platform == "ps" else ("Nintendo" if controller_platform == "nintendo" else "Steam Deck"))
		if device_badge_lbl:
			device_badge_lbl.text = "🎮 %s (ID: %d)" % [title, active_device_id]
			device_badge_lbl.add_theme_color_override("font_color", Color(0.4, 0.8, 1.0, 1))
		if device_type_lbl: device_type_lbl.text = "Active: %s Gamepad" % title
		if device_name_lbl: device_name_lbl.text = "Name: " + (raw_controller_name if not raw_controller_name.is_empty() else "Generic Gamepad")
		if device_id_lbl: device_id_lbl.text = "Device ID: %d | Gamepads: %d" % [active_device_id, count]

func update_analog_monitor() -> void:
	var dev = active_device_id if active_device_id >= 0 else (Input.get_connected_joypads()[0] if not Input.get_connected_joypads().is_empty() else 0)
	var lx = Input.get_joy_axis(dev, JOY_AXIS_LEFT_X)
	var ly = Input.get_joy_axis(dev, JOY_AXIS_LEFT_Y)
	var rx = Input.get_joy_axis(dev, JOY_AXIS_RIGHT_X)
	var ry = Input.get_joy_axis(dev, JOY_AXIS_RIGHT_Y)
	var lt = Input.get_joy_axis(dev, JOY_AXIS_TRIGGER_LEFT)
	var rt = Input.get_joy_axis(dev, JOY_AXIS_TRIGGER_RIGHT)
	var l_vec = Vector2(lx, ly)
	var r_vec = Vector2(rx, ry)

	if left_stick_val_lbl: left_stick_val_lbl.text = "X: %+.2f  Y: %+.2f" % [lx, ly]
	if left_stick_dir_lbl: left_stick_dir_lbl.text = "%s (Mag: %.2f)" % [_get_dir_str(l_vec), l_vec.length()]
	if right_stick_val_lbl: right_stick_val_lbl.text = "X: %+.2f  Y: %+.2f" % [rx, ry]
	if right_stick_dir_lbl: right_stick_dir_lbl.text = "%s (Mag: %.2f)" % [_get_dir_str(r_vec), r_vec.length()]
	if trigger_val_lbl: trigger_val_lbl.text = "LT: %.2f | RT: %.2f" % [lt, rt]
	if trigger_pct_lbl: trigger_pct_lbl.text = "LT: %d%% | RT: %d%%" % [int(round(clamp(lt, 0.0, 1.0) * 100.0)), int(round(clamp(rt, 0.0, 1.0) * 100.0))]

func _get_dir_str(vec: Vector2) -> String:
	if vec.length() < 0.2: return "Neutral"
	var deg = rad_to_deg(vec.angle())
	if deg >= -22.5 and deg < 22.5: return "Right"
	elif deg >= 22.5 and deg < 67.5: return "Down-Right"
	elif deg >= 67.5 and deg < 112.5: return "Down"
	elif deg >= 112.5 and deg < 157.5: return "Down-Left"
	elif deg >= 157.5 or deg < -157.5: return "Left"
	elif deg >= -157.5 and deg < -112.5: return "Up-Left"
	elif deg >= -112.5 and deg < -67.5: return "Up"
	elif deg >= -67.5 and deg < -22.5: return "Up-Right"
	return "Neutral"

func _on_joy_connection_changed(device: int, connected: bool) -> void:
	if connected: _set_device_gamepad(device)
	else:
		if active_device_id == device:
			var joys = Input.get_connected_joypads()
			if joys.is_empty(): _set_device_kbm()
			else: _set_device_gamepad(joys[0])
	update_device_ui()
