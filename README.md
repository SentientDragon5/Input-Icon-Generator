# Gen Input Icons

A procedural approach to creating customizable icons for multiplatform games

This tool is to generate a labeled spritesheet of input icons for use in godot or unity engine with icons for keyboard, gamepad.

planned engines
- Godot
- Unity

planned platforms
- keyboard
- mouse
- gamepad
- xbox
- nintendo
- playstation
- steam

- quest
- steam frame 

outputs
- spritesheets for each platform
- outputs for each platform per engine

output format, json. with the keycode name exactly so that a lightweight script in godot or unity could decode the json and easily get the corresponding icon from the coordinates on the json correlating to spritesheet.


projects
- Gen-Input-Icons
    - a tool using godot's ui system to procedurally render the spritesheet
- Godot-Input-Tester