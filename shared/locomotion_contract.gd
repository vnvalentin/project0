extends RefCounted
class_name LocomotionContract

const MODE_NONE: String = "none"
const MODE_JUMP: String = "jump"
const MODE_DODGE: String = "dodge"
const MODE_DUCK: String = "duck"
const MODE_SLIDE: String = "slide"

const JUMP_SPEED: float = 7.0
const GRAVITY: float = -18.0
const DODGE_SPEED: float = 12.0
const DODGE_TICKS: int = 12
const SLIDE_TICKS: int = 18
const STANDING_HEIGHT: float = 1.8
const DUCKING_HEIGHT: float = 1.1
const SLIDING_HEIGHT: float = 0.8

static func valid_mode(mode: String) -> bool:
	return mode in [MODE_NONE, MODE_JUMP, MODE_DODGE, MODE_DUCK, MODE_SLIDE]

static func make_intent(direction: Vector2, mode: String) -> Dictionary:
	return {"direction": direction, "mode": mode}