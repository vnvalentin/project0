extends RefCounted
## Fixture-only held-movement observation used by the real prediction harness.
## This first TDD increment deliberately preserves the legacy frame-only release
## policy. It is not the authoritative-release countermeasure or runtime proof.

const HELD_FRAME_CAP: int = 30

var _baseline: Vector3 = Vector3.ZERO
var _has_baseline: bool = false
var _latest_sequence: int = -1
var _held_sequence_floor: int = -1
var _holding: bool = false
var _observing: bool = true
var _held_progress: bool = false


func begin_hold(sequence_floor: int) -> void:
	_held_sequence_floor = sequence_floor
	_holding = true
	_held_progress = false


func observe(position: Vector3, sequence: int) -> void:
	if not _observing or sequence < -1 or sequence < _latest_sequence:
		return
	if not is_finite(position.x) or not is_finite(position.y) or not is_finite(position.z):
		return
	_latest_sequence = sequence
	if not _has_baseline:
		_baseline = position
		_has_baseline = true
		return
	if _holding and _held_sequence_floor >= 0 and sequence > _held_sequence_floor:
		_held_progress = _held_progress or position.z - _baseline.z > 0.5


func authoritative_progress_observed() -> bool:
	return _observing and _holding and _has_baseline and _held_progress


func release_ready(held_frames: int) -> bool:
	# Preserve the original harness behavior until the behavioral RED is qualified.
	return held_frames >= HELD_FRAME_CAP


func finish() -> void:
	_observing = false
	_holding = false
