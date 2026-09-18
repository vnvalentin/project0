extends Label
## Slice 127: displays the local Player's presentation-safe Character vessel
## summary from the NetworkClient autoload's replicated snapshot. Presentation
## only — the server owns the Character; this label shows derived graph state
## (kind + balanced/dominant axis), never raw stat numbers. The summary logic is
## a pure static helper so it is unit-testable without the autoload. See
## docs/slices/127-phase14-character-foundation-server.md.

const BALANCE_EPSILON: float = 0.0001


func _ready() -> void:
	NetworkClient.character_snapshot_changed.connect(_on_snapshot_changed)
	text = summarize(NetworkClient.latest_character_snapshot)


func _on_snapshot_changed(snapshot: Dictionary) -> void:
	text = summarize(snapshot)


## Pure presentation summary of a Character snapshot: "Vessel: <kind> (<axis>)"
## where axis is "balanced" for the equal baseline or the dominant node key.
static func summarize(snapshot: Dictionary) -> String:
	if snapshot.is_empty():
		return "Vessel: —"
	var kind: String = String(snapshot.get("character_kind", "?"))
	return "Vessel: %s (%s)" % [kind, dominant_axis(snapshot.get("graph_axes", {}))]


## The dominant graph axis, or "balanced" when every axis is equal (the baseline
## vessel), or "—" when there are no axes.
static func dominant_axis(axes: Dictionary) -> String:
	if axes.is_empty():
		return "—"
	var best_key: String = ""
	var best: float = -1.0
	var lowest: float = 2.0
	for key in axes:
		var value: float = float(axes[key])
		if value > best:
			best = value
			best_key = String(key)
		if value < lowest:
			lowest = value
	if best - lowest <= BALANCE_EPSILON:
		return "balanced"
	return best_key
