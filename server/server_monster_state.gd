extends RefCounted
class_name ServerMonsterState
## Basic Monsters slice 02: the authoritative detect -> chase -> windup ->
## attack -> recovery state machine for one baseline monster. Server-owned and
## deterministic; a RefCounted (not a Node) so its full lifecycle is unit-
## testable by calling advance() directly, without a SceneTree or physics.
## The server runtime (a later slice) drives advance() each physics frame and
## relays the telemetry signals below; this slice owns only the behavior.
## See docs/slices/021-monster-ai-state-machine.md and
## .scratch/basic-monsters/issues/02-monster-state-machine-with-telegraph.md
## (resolved).
##
## Telegraph contract (CLAUDE.md Combat Reading): the attack is resolved once,
## at the WINDUP -> ATTACK transition, against the facing the monster locked in
## when it entered WINDUP. During WINDUP the monster does NOT re-track the
## player, so stepping out of its reach/arc during the telegraph makes the
## attack miss — that is the human's dodge window.
##
## No player-damage model exists yet (the player has no HP; that is a future
## concern like the vessel system), so a landed attack is authoritatively
## resolved and reported via telemetry but applies no damage in this slice.

const MonsterContractsScript: Script = preload("res://shared/monster_contracts.gd")
const CombatContractsScript: Script = preload("res://shared/combat_contracts.gd")

## Telemetry: emitted on every phase transition, every attack resolution, and
## on death. The server runtime forwards these to its telemetry sink/logs.
signal phase_changed(target_id: String, from_phase: String, to_phase: String, server_tick: int)
signal attack_resolved(target_id: String, landed: bool, server_tick: int)
signal died(target_id: String, killer_peer_id: int, position: Vector3, server_tick: int)

var target_id: String
var position: Vector3
## Unit vector on the horizontal plane the monster is facing; locked at the
## start of WINDUP for the telegraph. Seeded to a valid direction so the arc
## test is never degenerate.
var facing: Vector3 = Vector3.FORWARD
var phase: String = MonsterContractsScript.PHASE_IDLE

var _ticks_in_phase: int = 0
var _combat: Object


func _init(p_target_id: String, spawn_position: Vector3) -> void:
	target_id = p_target_id
	position = spawn_position
	_combat = MonsterContractsScript.default_monster()


func current_hp() -> int:
	return int(round(_combat.current_health))


func is_dead() -> bool:
	return phase == MonsterContractsScript.PHASE_DEAD


## Advances the machine one server tick against the player's current position.
## delta is seconds since the last tick (drives chase movement); server_tick is
## the authoritative tick stamped onto emitted telemetry.
func advance(player_position: Vector3, delta: float, server_tick: int) -> void:
	if phase == MonsterContractsScript.PHASE_IDLE:
		if _horizontal_distance_to(player_position) <= MonsterContractsScript.DETECTION_RADIUS_YARDS:
			_set_phase(MonsterContractsScript.PHASE_CHASE, server_tick)
	elif phase == MonsterContractsScript.PHASE_CHASE:
		_advance_chase(player_position, delta, server_tick)
	elif phase == MonsterContractsScript.PHASE_WINDUP:
		_advance_windup(player_position, server_tick)
	elif phase == MonsterContractsScript.PHASE_ATTACK:
		_ticks_in_phase += 1
		if _ticks_in_phase >= MonsterContractsScript.ATTACK_ACTIVE_TICKS:
			_set_phase(MonsterContractsScript.PHASE_RECOVERY, server_tick)
	elif phase == MonsterContractsScript.PHASE_RECOVERY:
		_ticks_in_phase += 1
		if _ticks_in_phase >= MonsterContractsScript.RECOVERY_TICKS:
			_set_phase(MonsterContractsScript.PHASE_IDLE, server_tick)
	# PHASE_DEAD is terminal: no movement, detection, or attack.


## Applies authoritative damage from a player's accepted hit. On the transition
## to 0 HP the monster enters DEAD and emits one death event (COMBAT_EVENT_DEATH
## is the shared kind the server runtime stamps on the replicated CombatEvent).
## Wiring a player's melee resolution to this call is a later slice.
func receive_damage(amount: int, attacker_peer_id: int, server_tick: int) -> void:
	if phase == MonsterContractsScript.PHASE_DEAD:
		return
	# Preserve the retired MonsterCombatState death semantics exactly: emit one
	# death only on the tick a still-living monster is reduced to 0.
	var was_alive: bool = not _combat.is_now_defeated()
	_combat.take_damage(float(amount))
	if was_alive and _combat.is_now_defeated():
		_set_phase(MonsterContractsScript.PHASE_DEAD, server_tick)
		died.emit(target_id, attacker_peer_id, position, server_tick)


func _advance_chase(player_position: Vector3, delta: float, server_tick: int) -> void:
	if _horizontal_distance_to(player_position) > MonsterContractsScript.DETECTION_RADIUS_YARDS:
		_set_phase(MonsterContractsScript.PHASE_IDLE, server_tick)
		return
	_face(player_position)
	if _within_attack(player_position):
		# Facing is now locked for the telegraph; do not re-track during WINDUP.
		_set_phase(MonsterContractsScript.PHASE_WINDUP, server_tick)
	else:
		_move_toward(player_position, delta)


func _advance_windup(player_position: Vector3, server_tick: int) -> void:
	_ticks_in_phase += 1
	if _ticks_in_phase < MonsterContractsScript.WINDUP_TICKS:
		return
	_set_phase(MonsterContractsScript.PHASE_ATTACK, server_tick)
	# Resolve the strike once, against the locked facing — a player who stepped
	# out of reach/arc during the telegraph is missed.
	var landed: bool = _within_attack(player_position)
	attack_resolved.emit(target_id, landed, server_tick)


func _set_phase(new_phase: String, server_tick: int) -> void:
	var previous: String = phase
	phase = new_phase
	_ticks_in_phase = 0
	phase_changed.emit(target_id, previous, new_phase, server_tick)


func _within_attack(player_position: Vector3) -> bool:
	return CombatContractsScript.is_within_reach_and_arc(
		position, facing, player_position, MonsterContractsScript.monster_attack_archetype()
	)


func _face(player_position: Vector3) -> void:
	var to_player: Vector3 = _horizontal(player_position - position)
	if to_player.length_squared() > 0.0:
		facing = to_player.normalized()


func _move_toward(player_position: Vector3, delta: float) -> void:
	var to_player: Vector3 = _horizontal(player_position - position)
	if to_player.length_squared() == 0.0:
		return
	position += to_player.normalized() * MonsterContractsScript.CHASE_SPEED_YARDS_PER_SEC * delta


func _horizontal_distance_to(player_position: Vector3) -> float:
	return _horizontal(player_position - position).length()


func _horizontal(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)
