extends Label
## Slice 018: shows which starting-town facade the local player is currently at.
## Cosmetic and client-only — no server authority and no exclusivity (only the
## local "Player" body ever triggers it, so two peers standing at the same
## facade each see their own local label). Joins the "facade_presenter" group so
## a FacadeProximity area instanced at runtime under SectorGeometry can find it
## without a hard-coded node path. See docs/slices/018-facade-enter-exit.md.

const GROUP_NAME: StringName = &"facade_presenter"


func _ready() -> void:
	add_to_group(GROUP_NAME)
	visible = false
	text = ""


## Shows the "you are at" line for the named facade. Called by a
## FacadeProximity area when the local player enters it.
func show_facade(display_name: String) -> void:
	text = line_for(display_name)
	visible = true


## Clears the line, but only if it is still showing the facade being left, so a
## late exit from a facade the player already walked out of cannot blank a line
## a newer facade has since set.
func clear_facade(display_name: String) -> void:
	if text == line_for(display_name):
		text = ""
		visible = false


## The exact line shown for a facade. Public so FacadeProximity's tests can
## assert the presenter state without duplicating the format string.
func line_for(display_name: String) -> String:
	return "You are at the %s" % display_name
