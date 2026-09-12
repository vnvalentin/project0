extends GutTest
## Public-seam unit tests for Slice 018's facade presenter
## (client/facade_presenter.gd). Pure UI state logic — instances the Label,
## calls show/clear directly, and asserts text/visibility. See
## docs/slices/018-facade-enter-exit.md.

const FacadePresenterScript: Script = preload("res://client/facade_presenter.gd")


func _presenter() -> Label:
	var label: Label = Label.new()
	label.set_script(FacadePresenterScript)
	return add_child_autofree(label)


func test_starts_hidden_and_empty() -> void:
	var presenter: Label = _presenter()
	assert_false(presenter.visible, "presenter starts hidden")
	assert_eq(presenter.text, "", "presenter starts with no text")


func test_show_facade_sets_line_and_visibility() -> void:
	var presenter: Label = _presenter()
	presenter.show_facade("Smithy")
	assert_true(presenter.visible, "showing a facade makes the label visible")
	assert_eq(presenter.text, "You are at the Smithy", "showing a facade sets the you-are-at line")


func test_clear_facade_clears_only_the_current_facade() -> void:
	var presenter: Label = _presenter()
	presenter.show_facade("Smithy")
	# A late exit from a DIFFERENT facade must not blank the current line.
	presenter.clear_facade("Inn")
	assert_true(presenter.visible, "a stale exit from another facade does not clear the current line")
	assert_eq(presenter.text, "You are at the Smithy", "the current facade line survives a mismatched clear")

	presenter.clear_facade("Smithy")
	assert_false(presenter.visible, "clearing the current facade hides the label")
	assert_eq(presenter.text, "", "clearing the current facade empties the text")


func test_show_then_switch_facade_updates_line() -> void:
	var presenter: Label = _presenter()
	presenter.show_facade("Smithy")
	presenter.show_facade("Inn")
	assert_eq(presenter.text, "You are at the Inn", "entering a new facade replaces the line")
	assert_true(presenter.visible, "the label stays visible across a facade switch")
