extends Area3D
## Slice 018: a cosmetic, client-only proximity trigger on a starting-town
## structure facade. When the local player's body overlaps, it asks the facade
## presenter to show this building's name; on exit it asks the presenter to
## clear it. Purely client-observed — no server authority, no world mutation,
## and no exclusivity. Only the local WASD Player drives it, so the structure's
## own StaticBody3D, the FlatPlane, and other peers' Players are all ignored.
## See docs/slices/018-facade-enter-exit.md.

const FacadePresenterScript: Script = preload("res://client/facade_presenter.gd")

## Set per structure prefab (house/smithy/armor_shop/inn); shown as
## "You are at the <building_display_name>".
@export var building_display_name: String = "Building"


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _on_body_entered(body: Node) -> void:
	if not is_local_player(body):
		return
	var presenter: Node = _presenter()
	if presenter != null:
		presenter.show_facade(building_display_name)


func _on_body_exited(body: Node) -> void:
	if not is_local_player(body):
		return
	var presenter: Node = _presenter()
	if presenter != null:
		presenter.clear_facade(building_display_name)


## Only the local WASD Player (named "Player" in client/gameplay.tscn) drives
## the label. Public so the behavior test can assert the filter directly.
func is_local_player(body: Node) -> bool:
	return body != null and body.name == "Player"


func _presenter() -> Node:
	return get_tree().get_first_node_in_group(FacadePresenterScript.GROUP_NAME)
