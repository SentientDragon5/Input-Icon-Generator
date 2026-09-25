"""
get-actions-godot.py
Scrapes and caches the exact list of input actions/enums and keycodes from Godot Engine's official documentation repository.
Extracts:
  - Key (Keyboard keys, printable characters, modifiers, function keys, navigation)
  - MouseButton (Mouse buttons and scroll wheel actions)
  - JoyButton (Gamepad buttons, D-pad, bumpers, sticks, etc.)
  - JoyAxis (Gamepad sticks and analog triggers)
Outputs structured JSON to artifacts/input_actions_list_godot.json
"""

import sys
import os
import json
import urllib.request
import xml.etree.ElementTree as ET
from datetime import datetime, timezone

DEFAULT_GODOT_VERSION = "4.7"
GODOT_XML_URL_TEMPLATE = (
    "https://raw.githubusercontent.com/godotengine/godot/{version}/doc/classes/%40GlobalScope.xml"
)
OUTPUT_FILE_PATH = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
    "artifacts",
    "input_actions_list_godot.json"
)

TARGET_ENUMS = {
    "Key": "keyboard",
    "MouseButton": "mouse",
    "JoyButton": "gamepad_button",
    "JoyAxis": "gamepad_axis",
}

# Helper to generate human-friendly readable labels
def generate_readable_name(name: str, enum_type: str) -> str:
    if enum_type == "Key":
        if name.startswith("KEY_KP_"):
            suffix = name[len("KEY_KP_"):]
            return f"Num {suffix.capitalize()}"
        elif name.startswith("KEY_"):
            raw = name[len("KEY_"):]
            special_names = {
                "ESCAPE": "Esc",
                "BACKSPACE": "Backspace",
                "ENTER": "Enter",
                "KP_ENTER": "Num Enter",
                "TAB": "Tab",
                "SPACE": "Space",
                "CAPSLOCK": "Caps Lock",
                "NUMLOCK": "Num Lock",
                "SCROLLLOCK": "Scroll Lock",
                "PRINT": "Print Screen",
                "PAUSE": "Pause",
                "PAGEUP": "Page Up",
                "PAGEDOWN": "Page Down",
                "INSERT": "Insert",
                "DELETE": "Delete",
                "HOME": "Home",
                "END": "End",
                "LEFT": "Left Arrow",
                "RIGHT": "Right Arrow",
                "UP": "Up Arrow",
                "DOWN": "Down Arrow",
                "SHIFT": "Shift",
                "CTRL": "Ctrl",
                "ALT": "Alt",
                "META": "Win / Command",
                "MENU": "Menu",
                "HYPER": "Hyper",
                "SUPER": "Super",
                "BRACKETLEFT": "[",
                "BRACKETRIGHT": "]",
                "BACKSLASH": "\\",
                "SLASH": "/",
                "SEMICOLON": ";",
                "APOSTROPHE": "'",
                "COMMA": ",",
                "PERIOD": ".",
                "MINUS": "-",
                "EQUAL": "=",
                "BACKQUOTE": "`",
            }
            if raw in special_names:
                return special_names[raw]
            if len(raw) == 1:
                return raw.upper()
            return raw.replace("_", " ").title()

    elif enum_type == "MouseButton":
        mouse_names = {
            "MOUSE_BUTTON_LEFT": "Left Click",
            "MOUSE_BUTTON_RIGHT": "Right Click",
            "MOUSE_BUTTON_MIDDLE": "Middle Click",
            "MOUSE_BUTTON_WHEEL_UP": "Scroll Up",
            "MOUSE_BUTTON_WHEEL_DOWN": "Scroll Down",
            "MOUSE_BUTTON_WHEEL_LEFT": "Scroll Left",
            "MOUSE_BUTTON_WHEEL_RIGHT": "Scroll Right",
            "MOUSE_BUTTON_XBUTTON1": "Mouse 4 (Back)",
            "MOUSE_BUTTON_XBUTTON2": "Mouse 5 (Forward)",
        }
        return mouse_names.get(name, name.replace("MOUSE_BUTTON_", "").replace("_", " ").title())

    elif enum_type == "JoyButton":
        joy_names = {
            "JOY_BUTTON_A": "A / Cross",
            "JOY_BUTTON_B": "B / Circle",
            "JOY_BUTTON_X": "X / Square",
            "JOY_BUTTON_Y": "Y / Triangle",
            "JOY_BUTTON_BACK": "Back / Select / View",
            "JOY_BUTTON_GUIDE": "Guide / Home / PS",
            "JOY_BUTTON_START": "Start / Menu / Options",
            "JOY_BUTTON_LEFT_STICK": "L3 / Left Stick Click",
            "JOY_BUTTON_RIGHT_STICK": "R3 / Right Stick Click",
            "JOY_BUTTON_LEFT_SHOULDER": "LB / L1",
            "JOY_BUTTON_RIGHT_SHOULDER": "RB / R1",
            "JOY_BUTTON_DPAD_UP": "D-Pad Up",
            "JOY_BUTTON_DPAD_DOWN": "D-Pad Down",
            "JOY_BUTTON_DPAD_LEFT": "D-Pad Left",
            "JOY_BUTTON_DPAD_RIGHT": "D-Pad Right",
            "JOY_BUTTON_MISC1": "Share / Capture",
            "JOY_BUTTON_MISC2": "Misc 2 (Switch 2 / Horipad)",
            "JOY_BUTTON_MISC3": "Misc 3",
            "JOY_BUTTON_MISC4": "Misc 4",
            "JOY_BUTTON_MISC5": "Misc 5",
            "JOY_BUTTON_MISC6": "Misc 6",
            "JOY_BUTTON_PADDLE1": "Paddle 1 (P1)",
            "JOY_BUTTON_PADDLE2": "Paddle 2 (P2)",
            "JOY_BUTTON_PADDLE3": "Paddle 3 (P3)",
            "JOY_BUTTON_PADDLE4": "Paddle 4 (P4)",
            "JOY_BUTTON_TOUCHPAD": "Touchpad Click",
        }
        return joy_names.get(name, name.replace("JOY_BUTTON_", "").replace("_", " ").title())

    elif enum_type == "JoyAxis":
        axis_names = {
            "JOY_AXIS_LEFT_X": "Left Stick X",
            "JOY_AXIS_LEFT_Y": "Left Stick Y",
            "JOY_AXIS_RIGHT_X": "Right Stick X",
            "JOY_AXIS_RIGHT_Y": "Right Stick Y",
            "JOY_AXIS_TRIGGER_LEFT": "LT / L2",
            "JOY_AXIS_TRIGGER_RIGHT": "RT / R2",
        }
        return axis_names.get(name, name.replace("JOY_AXIS_", "").replace("_", " ").title())

    return name

def categorize_item(name: str, enum_type: str) -> str:
    if enum_type == "Key":
        if name.startswith("KEY_KP_"):
            return "numpad"
        elif name.startswith("KEY_F") and name[5:].isdigit():
            return "function"
        elif name in ("KEY_SHIFT", "KEY_CTRL", "KEY_ALT", "KEY_META", "KEY_CAPSLOCK", "KEY_NUMLOCK", "KEY_SCROLLLOCK"):
            return "modifier"
        elif name in ("KEY_ESCAPE", "KEY_TAB", "KEY_SPACE", "KEY_ENTER", "KEY_BACKSPACE", "KEY_INSERT", "KEY_DELETE",
                      "KEY_HOME", "KEY_END", "KEY_PAGEUP", "KEY_PAGEDOWN", "KEY_UP", "KEY_DOWN", "KEY_LEFT", "KEY_RIGHT"):
            return "navigation"
        elif name.startswith("KEY_MEDIA") or name.startswith("KEY_VOLUME") or name in ("KEY_MUTE", "KEY_PLAY", "KEY_STOP"):
            return "media"
        elif len(name) == 5 and name.startswith("KEY_") and name[4].isalnum():
            return "alphanumeric"
        return "general_key"
    elif enum_type == "MouseButton":
        if "WHEEL" in name:
            return "wheel"
        return "button"
    elif enum_type == "JoyButton":
        if "DPAD" in name:
            return "dpad"
        elif name in ("JOY_BUTTON_A", "JOY_BUTTON_B", "JOY_BUTTON_X", "JOY_BUTTON_Y"):
            return "face_button"
        elif "SHOULDER" in name:
            return "bumper"
        elif "STICK" in name:
            return "stick_button"
        elif "PADDLE" in name:
            return "paddle"
        return "system_button"
    elif enum_type == "JoyAxis":
        if "TRIGGER" in name:
            return "trigger"
        return "analog_stick"
    return "other"

def fetch_godot_globalscope_xml(version: str) -> str:
    url = GODOT_XML_URL_TEMPLATE.format(version=version)
    print(f"[+] Fetching Godot {version} GlobalScope XML from: {url}")
    req = urllib.request.Request(
        url,
        headers={"User-Agent": "Gen-Input-Icons-Scraper/1.0"}
    )
    with urllib.request.urlopen(req) as resp:
        return resp.read().decode("utf-8")

def parse_godot_enums(xml_content: str, version: str):
    root = ET.fromstring(xml_content)
    constants_elem = root.find("constants")
    if constants_elem is None:
        raise ValueError("Could not find <constants> element in GlobalScope XML.")

    output_data = {
        "info": {
            "engine": "godot",
            "platform_version": version,
            "source_url": GODOT_XML_URL_TEMPLATE.format(version=version),
            "generated_at": datetime.now(timezone.utc).isoformat(),
            "stats": {}
        },
        "platforms": {
            "keyboard": {},
            "mouse": {},
            "gamepad": {}
        }
    }

    counts = {"keyboard": 0, "mouse": 0, "gamepad_buttons": 0, "gamepad_axes": 0}

    for const in constants_elem.findall("constant"):
        enum_name = const.get("enum")
        if enum_name not in TARGET_ENUMS:
            continue

        item_name = const.get("name")
        item_val_str = const.get("value")
        if item_val_str is None:
            continue
        item_val = int(item_val_str)
        doc_desc = (const.text or "").strip()

        readable_name = generate_readable_name(item_name, enum_name)
        subcategory = categorize_item(item_name, enum_name)

        entry = {
            "name": item_name,
            "enum": enum_name,
            "value": item_val,
            "readable_name": readable_name,
            "category": subcategory,
            "description": doc_desc
        }

        if enum_name == "Key":
            output_data["platforms"]["keyboard"][item_name] = entry
            counts["keyboard"] += 1
        elif enum_name == "MouseButton":
            output_data["platforms"]["mouse"][item_name] = entry
            counts["mouse"] += 1
        elif enum_name == "JoyButton":
            output_data["platforms"]["gamepad"][item_name] = entry
            counts["gamepad_buttons"] += 1
        elif enum_name == "JoyAxis":
            output_data["platforms"]["gamepad"][item_name] = entry
            counts["gamepad_axes"] += 1

    output_data["info"]["stats"] = counts
    return output_data

def main():
    version = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_GODOT_VERSION
    os.makedirs(os.path.dirname(OUTPUT_FILE_PATH), exist_ok=True)

    try:
        xml_content = fetch_godot_globalscope_xml(version)
        parsed_data = parse_godot_enums(xml_content, version)

        with open(OUTPUT_FILE_PATH, "w", encoding="utf-8") as f:
            json.dump(parsed_data, f, indent=4, ensure_ascii=False)

        print(f"[OK] Successfully generated {OUTPUT_FILE_PATH}")
        print(f"    - Keyboard keys: {parsed_data['info']['stats']['keyboard']}")
        print(f"    - Mouse actions: {parsed_data['info']['stats']['mouse']}")
        print(f"    - Gamepad buttons: {parsed_data['info']['stats']['gamepad_buttons']}")
        print(f"    - Gamepad axes: {parsed_data['info']['stats']['gamepad_axes']}")

    except Exception as e:
        print(f"[ERROR] Error scraping Godot actions: {e}", file=sys.stderr)
        sys.exit(1)

if __name__ == "__main__":
    main()
