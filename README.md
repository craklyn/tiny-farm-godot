# Tiny Farm (Godot 4)

A cozy, 2D farming simulation prototype built with Godot 4. This is a robust port and expansion of the original Love2D prototype.

## Features
- **Farming Loop**: Clear land, till soil, plant seeds, water crops, and harvest.
- **Tools**: Hands, Axe, Pickaxe, Hoe, Watering Can, and Seeds.
- **Day/Night Cycle**: Manage your energy and sleep to progress time and grow crops.
- **Economy**: Ship crops in the shipping bin and earn gold overnight.
- **In-Situ Testing**: Includes a full headless integration test runner to simulate player actions automatically.

## Requirements
- [Godot Engine 4.4+](https://godotengine.org/)

## Running the Game
Open the `project.godot` file in the Godot 4 editor and press Play (F5).

### Running Tests
To run the automated test suite headlessly from the command line:
```bash
godot4 --headless --path . res://tools/test_runner.tscn
```
