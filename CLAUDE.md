# Project Constraints & Architecture
- **Perspective:** 3D 3/4 Isometric (Fixed tilt camera angle).
- **Engine:** Godot 4.x (Server runs `--headless` via Docker container).
- **Networking:** Server-authoritative multiplayer using Godot High-Level API.
- **World State:** Just-in-Time (JIT) world generation. Canon areas are saved to an SQLite database.
- **AI Systems:** Connects asynchronously to local Ollama API (running Llama-3-8B on Tesla P100 GPU).
- **Code Style:** Use strict GDScript 2.0 static type hints (`var score: int = 0`).

# Active Directory Map
- `/server`: Contains server-authoritative logic, database migrations, and headless execution configurations.
- `/client`: Handles player inputs, prediction, and visual interpolation.
- `/shared`: Global constants, data structures, and local LLM JSON validation rules.
- `/tests`: GUT (Godot Unit Test) suite; run via `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/unit -gexit`.
- `/addons/gut`: Vendored GUT v9.4.0 test framework (Godot 4.3/4.4 compatible).
