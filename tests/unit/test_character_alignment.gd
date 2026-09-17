extends GutTest
## Slice 117 (Phase 14): public-seam tests for the Character alignment +
## disposition contract. Deterministic label derivation (with deception),
## relationship-driven disposition, lawful-under-authority restraint, and
## fail-closed parsing.

const CharacterAlignmentScript: Script = preload("res://shared/character_alignment.gd")


func _wire(morality: float, chaos: float, disposition: String, relationship: float = 0.0, declared: String = "") -> Dictionary:
	return {
		"schema_version": 1,
		"morality": morality,
		"chaos": chaos,
		"default_disposition": disposition,
		"player_relationship": relationship,
		"declared_label": declared,
	}


func test_derive_label_maps_axes_to_dnd_labels() -> void:
	assert_eq(CharacterAlignmentScript.derive_label(0.6, -0.6), "Lawful Good")
	assert_eq(CharacterAlignmentScript.derive_label(-0.8, 0.7), "Chaotic Evil")
	assert_eq(CharacterAlignmentScript.derive_label(0.0, 0.0), "True Neutral")
	assert_eq(CharacterAlignmentScript.derive_label(0.6, 0.0), "Neutral Good")
	assert_eq(CharacterAlignmentScript.derive_label(0.0, -0.6), "Lawful Neutral")


func test_perceived_label_can_deceive_while_true_label_reflects_axes() -> void:
	# A pretty knight: declares Lawful Good, is actually Lawful Evil.
	var parsed: Dictionary = CharacterAlignmentScript.from_wire_dict(
		_wire(-0.8, -0.7, "passive", 0.0, "Lawful Good")
	)
	assert_eq(parsed["outcome"], "ok")
	var a: Object = parsed["alignment"]
	assert_eq(a.perceived_label(), "Lawful Good", "observer sees the declared label")
	assert_eq(a.true_label(), "Lawful Evil", "true label reflects the real axes")


func test_perceived_label_defaults_to_true_label_without_deception() -> void:
	var parsed: Dictionary = CharacterAlignmentScript.from_wire_dict(_wire(0.6, -0.6, "neutral"))
	var a: Object = parsed["alignment"]
	assert_eq(a.perceived_label(), a.true_label())


func test_strong_relationship_overrides_alignment_conflict() -> void:
	# Opposed alignment, but a trusted relationship => passive.
	var parsed: Dictionary = CharacterAlignmentScript.from_wire_dict(_wire(-0.9, 0.9, "hostile", 75.0))
	var a: Object = parsed["alignment"]
	assert_eq(a.disposition_toward(0.9, -0.9, {}), "passive")
	# Established enmity => hostile regardless of default.
	var parsed2: Dictionary = CharacterAlignmentScript.from_wire_dict(_wire(0.5, 0.5, "passive", -80.0))
	var b: Object = parsed2["alignment"]
	assert_eq(b.disposition_toward(0.5, 0.5, {}), "hostile")


func test_alignment_conflict_turns_unknown_hostile() -> void:
	# Very opposed values, neutral relationship, no relationship built.
	var parsed: Dictionary = CharacterAlignmentScript.from_wire_dict(_wire(-0.9, 0.9, "neutral", 0.0))
	var a: Object = parsed["alignment"]
	assert_eq(a.disposition_toward(0.9, -0.9, {}), "hostile")


func test_compatible_alignment_uses_default_disposition() -> void:
	var parsed: Dictionary = CharacterAlignmentScript.from_wire_dict(_wire(0.5, -0.4, "neutral", 0.0))
	var a: Object = parsed["alignment"]
	assert_eq(a.disposition_toward(0.5, -0.4, {}), "neutral")


func test_lawful_character_is_restrained_by_authority_but_chaotic_is_not() -> void:
	# Lawful Evil, opposed to a good observer => hostile base, but restrained
	# from acting while an authority is present.
	var lawful: Object = CharacterAlignmentScript.from_wire_dict(_wire(-0.9, -0.9, "neutral", 0.0))["alignment"]
	assert_eq(lawful.disposition_toward(0.9, 0.9, {}), "hostile")
	assert_eq(lawful.disposition_toward(0.9, 0.9, {"authority_present": true}), "passive")
	assert_true(lawful.respects_authority())
	# Chaotic Evil is not restrained by authority in this slice.
	var chaotic: Object = CharacterAlignmentScript.from_wire_dict(_wire(-0.9, 0.9, "neutral", 0.0))["alignment"]
	assert_eq(chaotic.disposition_toward(0.9, -0.9, {"authority_present": true}), "hostile")
	assert_false(chaotic.respects_authority())


func test_from_wire_dict_rejects_unsupported_version() -> void:
	var wire: Dictionary = _wire(0.0, 0.0, "neutral")
	wire["schema_version"] = 999
	var result: Dictionary = CharacterAlignmentScript.from_wire_dict(wire)
	assert_eq(result["outcome"], "unsupported_version")
	assert_null(result["alignment"])


func test_from_wire_dict_rejects_out_of_bounds_axis() -> void:
	var result: Dictionary = CharacterAlignmentScript.from_wire_dict(_wire(2.0, 0.0, "neutral"))
	assert_eq(result["outcome"], "out_of_bounds")


func test_from_wire_dict_rejects_non_finite_relationship() -> void:
	var wire: Dictionary = _wire(0.0, 0.0, "neutral")
	wire["player_relationship"] = INF
	var result: Dictionary = CharacterAlignmentScript.from_wire_dict(wire)
	assert_eq(result["outcome"], "out_of_bounds")


func test_from_wire_dict_rejects_unsupported_disposition() -> void:
	var result: Dictionary = CharacterAlignmentScript.from_wire_dict(_wire(0.0, 0.0, "murderous"))
	assert_eq(result["outcome"], "unsupported_disposition")


func test_from_wire_dict_rejects_non_dictionary() -> void:
	var result: Dictionary = CharacterAlignmentScript.from_wire_dict(42)
	assert_eq(result["outcome"], "malformed")
