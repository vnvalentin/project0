extends Label
## Slice 142 (Phase 15 follow-on): displays the local Player's presentation-safe
## effective-mechanics summary from the NetworkClient autoload's replicated
## snapshot. Presentation only — the server owns the vessel + subsystems; this
## label shows the derived friction profile + dominant graph axis, never raw
## effective numbers. The summary logic is a pure static helper so it is
## unit-testable without the autoload or a Label node, mirroring the Character
## vessel label. See docs/slices/142-effective-mechanics-replication.md.

const BALANCE_EPSILON: float = 0.0001


func _ready() -> void:
	NetworkClient.effective_mechanics_changed.connect(_on_mechanics_changed)
	text = summarize(NetworkClient.latest_effective_mechanics)


func _on_mechanics_changed(snapshot: Dictionary) -> void:
	text = summarize(snapshot)


## Pure presentation summary of an EffectiveMechanicsSnapshot:
## "Mechanics: <friction_profile> (<axis>)" where axis is "balanced" for the
## equal baseline or the dominant node key, and the profile comes from the
## subsystem-safe derived map (defaulting to "—" when absent).
static func summarize(snapshot: Dictionary) -> String:
	if snapshot.is_empty():
		return "Mechanics: —"
	var derived: Dictionary = snapshot.get("derived", {})
	var profile: String = String(derived.get("friction_profile", "—"))
	return "Mechanics: %s (%s)" % [profile, dominant_axis(snapshot.get("graph_axes", {}))]


## The dominant graph axis, or "balanced" when every axis is equal (the baseline
## vessel), or "—" when there are no axes. Mirrors the Character vessel label.
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
