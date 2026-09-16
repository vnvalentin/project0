extends Label
## Slice 094: displays the local Player's authoritative HP from the NetworkClient
## autoload and flashes a brief cue on the provisional defeat->respawn.
## Presentation only — the server owns HP; this label never computes or asserts
## it. See docs/slices/094-player-hp-monster-damage.md.

const DEFEAT_FLASH_SECONDS: float = 1.5

var _defeat_flash_remaining: float = 0.0


func _ready() -> void:
	NetworkClient.player_health_changed.connect(_on_health_changed)
	NetworkClient.player_defeated_received.connect(_on_defeated)
	_render(NetworkClient.latest_current_hp, NetworkClient.latest_max_hp)


func _process(delta: float) -> void:
	if _defeat_flash_remaining <= 0.0:
		return
	_defeat_flash_remaining -= delta
	if _defeat_flash_remaining <= 0.0:
		_render(NetworkClient.latest_current_hp, NetworkClient.latest_max_hp)


func _on_health_changed(current_hp: int, max_hp: int) -> void:
	# Hold the defeat cue for its brief window before resuming the HP readout.
	if _defeat_flash_remaining > 0.0:
		return
	_render(current_hp, max_hp)


func _on_defeated() -> void:
	_defeat_flash_remaining = DEFEAT_FLASH_SECONDS
	text = "Defeated! Respawned."
	add_theme_color_override("font_color", Color(0.95, 0.3, 0.3, 1))


func _render(current_hp: int, max_hp: int) -> void:
	text = "HP: %d / %d" % [current_hp, max_hp]
	add_theme_color_override("font_color", _color_for(current_hp, max_hp))


func _color_for(current_hp: int, max_hp: int) -> Color:
	var ratio: float = float(current_hp) / float(max_hp) if max_hp > 0 else 0.0
	if ratio <= 0.34:
		return Color(0.95, 0.35, 0.35, 1)
	if ratio <= 0.67:
		return Color(0.95, 0.8, 0.35, 1)
	return Color(0.55, 0.9, 0.55, 1)
