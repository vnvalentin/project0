extends Node
## Server-side authority for one connected Player's position, for Slice 004's
## authoritative-movement proof, extended in Slice 005 with input sequence
## tracking for client-side prediction/reconciliation, in Slice 007 with a
## peer-position-broadcast signal so the server can replicate this Player's
## authoritative position to every other connected peer, and in Slice 012
## with the first authoritative melee-strike action state machine. Holds the
## latest directional input intent reported by the owning client's
## NetworkClient RPC, integrates position at a fixed speed every physics
## tick (scaled by the current attack phase's locomotion factor), and RPCs
## the resulting authoritative position plus the latest processed input
## sequence back to that same client. See
## docs/slices/004-authoritative-player-movement.md,
## docs/slices/005-prediction-reconciliation.md,
## docs/slices/007-multi-peer-player-replication.md,
## docs/slices/012-authoritative-melee-strike.md, and docs/adr/0001 for
## scope: no persistence, and (until Slice 030) no collision. Slice 030 adds
## server-side wall/building collision to movement. The server still never
## accepts a client-supplied position or sequence-tagged position — sequence
## numbers only identify which input the client's intent came from, never
## override the server's own computed position.
##
## Slice 007 scope: `server/server_main.gd` now owns one instance of this
## node per connected peer (keyed by peer id) instead of a single shared
## instance, so exactly two concurrently connected peers each get their own
## authoritative position and input-sequence bookkeeping with no shared
## mutable state between them.
##
## Slice 012 scope: adds a per-peer melee action state machine
## (IDLE -> WINDUP -> ACTIVE -> RECOVERY -> IDLE) driven by fixed 60Hz
## simulation ticks (this node's own _physics_process calls, one per
## configured physics tick — see project settings' default 60 Hz physics
## tick rate), a monotonic action-sequence dedup/rejection path distinct from
## the movement-intent sequence above, and a deterministic vector reach/arc
## hit test against server-owned TargetDummy nodes during the ACTIVE phase.
## No damage/HP, inventory, or PvP — see
## docs/slices/012-authoritative-melee-strike.md's non-goals.

const NetworkConfigScript: Script = preload("res://shared/network_config.gd")
const CombatContractsScript: Script = preload("res://shared/combat_contracts.gd")
const PlayerCombatContractsScript: Script = preload("res://shared/player_combat_contracts.gd")

## Emitted every physics tick after this peer's authoritative position is
## computed, so server_main.gd can broadcast it to every other connected
## peer without this node needing to know about peer replication itself.
signal position_updated(peer_id: int, updated_position: Vector3)

## Emitted once per accepted ActionIntent with its ActionResolution, so
## server_main.gd can RPC the result back to the owning client without this
## node needing to know about networking itself (matching position_updated's
## separation of concerns above).
signal action_resolved(peer_id: int, resolution: Object)

## Emitted exactly once per confirmed hit during the ACTIVE phase, carrying a
## CombatContracts.CombatEvent, so server_main.gd can broadcast it to every
## connected peer for client-side visual feedback.
signal combat_event_emitted(peer_id: int, combat_event: Object)

## Slice 013: emitted once, exactly when an ActionIntent is accepted and this
## peer enters WINDUP, carrying the already-public archetype phase-timing and
## the accepted facing. Lets server_main.gd broadcast a swing-started cue to
## every connected peer (not just the owner, unlike action_resolved) so a
## remote observer's client can time its own cosmetic strike-line indicator
## without needing a trusted outcome — matching CLAUDE.md's telegraph rule
## that an authoritative action state may be replicated early for client
## presentation.
signal melee_swing_started(peer_id: int, windup_ticks: int, active_ticks: int, facing: Vector3)

## Slice 086: emitted once when this peer's selected Character is bound at world
## entry, so server_main.gd can replicate the Character's identity (display name
## + cosmetic) to every other connected peer without this node needing to know
## about peer replication itself (matching position_updated's separation).
signal character_bound(peer_id: int, display_name: String, cosmetic: Dictionary)

## Slice 094: emitted whenever this Player's authoritative HP changes (took
## monster damage, or was restored to full on the provisional defeat->respawn),
## so server_main.gd can replicate the current HP to the owning client for
## display without this node needing to know about networking itself.
signal health_changed(peer_id: int, current_hp: int, max_hp: int, server_tick: int)

## Slice 094: emitted exactly once on the tick a landed monster attack reduces
## this Player to 0 HP, before the provisional full-HP respawn is applied. The
## reposition itself replicates through the existing position_updated channel.
signal player_defeated(peer_id: int, server_tick: int)

var owning_peer_id: int = -1
var position: Vector3 = Vector3.ZERO
## Slice 094: the spawn anchor this Player is returned to on the provisional
## defeat->respawn (ticket 05). Captured in start_for_peer from the peer's
## assigned start position; no separate respawn-point system exists yet.
var _spawn_position: Vector3 = Vector3.ZERO
## Slice 094: the Player's flat, server-owned HP pool (a Phase-12 vessel
## placeholder). Server-authoritative — the client only ever displays the
## replicated value, never sets it.
var _vitals: Object = PlayerCombatContractsScript.PlayerVitals.new()
## Forward-facing direction used for the melee arc check; defaults to -Z
## (Godot's forward) and is updated from non-zero movement input, since this
## slice has no independent look/aim input.
var facing: Vector3 = Vector3(0.0, 0.0, -1.0)
var _input_intent: Vector2 = Vector2.ZERO
var _last_processed_sequence: int = -1

## Slice 043: the selected Character this Player was instantiated as, bound on
## world entry. Identity/cosmetic only; position/combat authority is unchanged.
var character_id: String = ""
var character_display_name: String = ""
var character_cosmetic: Dictionary = {}


## Public seam (Slice 043). Binds the selected Character's identity/cosmetic to
## this Player on world entry. Does not touch position or combat state.
func bind_character(p_character_id: String, p_display_name: String, p_cosmetic: Dictionary) -> void:
	character_id = p_character_id
	character_display_name = p_display_name
	character_cosmetic = p_cosmetic
	character_bound.emit(owning_peer_id, character_display_name, character_cosmetic)


## Melee action state. archetype is fixed to the Generic Sword baseline for
## every Player in this slice — no equipping/switching exists yet.
var _archetype: Object = CombatContractsScript.generic_sword_archetype()
var _phase: String = CombatContractsScript.PHASE_IDLE
var _phase_ticks_remaining: int = 0
var _last_processed_action_sequence: int = -1
var _last_action_resolution: Object = null
var _hit_target_ids_this_swing: Dictionary = {}

## Server-owned target dummies this peer's swings can hit, injected by
## server_main.gd. Keyed by target_id (String) to any Object exposing
## `.position` (a plain Node3D for dummies today; see _monster_manager below
## for the Slice 029 RefCounted monster case). Never client-supplied — a
## client can only submit an aim direction, never name a target to strike (see
## CLAUDE.md's Kinetic destructive-output rule, which the same "server names
## the target" principle mirrors for melee).
var _target_dummies: Dictionary = {}

## Slice 030: server-side sector collision (walls + building footprints),
## injected by server_main.gd. When set, authoritative movement integration
## slides the player against solids so the town is physically solid. null in
## tests/standalone contexts means free movement (backward compatible).
var _collision_map: Object = null

## Slice 029: the server-owned monster manager this peer's hit test also
## checks against, injected by server_main.gd. Only living monsters (a fresh
## snapshot pulled every ACTIVE tick via living_targets(), never cached) are
## ever targetable, so a dead/respawning monster cannot be hit. This node
## never mutates a monster itself — it only reads `.position`/`target_id` for
## the geometric hit test and emits a target_id-keyed HIT event exactly as it
## already does for dummies; applying damage stays solely owned by
## ServerMonsterManager, reached through server_main.gd's routing of that HIT
## event (see server_main.gd's _on_player_state_combat_event_emitted).
var _monster_manager: Object = null


## Public seam: called by the server when a peer connects, to bind this state
## node to that peer and its starting position.
func start_for_peer(peer_id: int, start_position: Vector3) -> void:
	owning_peer_id = peer_id
	position = start_position
	_spawn_position = start_position
	_vitals.reset()
	_input_intent = Vector2.ZERO
	_last_processed_sequence = -1
	_phase = CombatContractsScript.PHASE_IDLE
	_phase_ticks_remaining = 0
	_last_processed_action_sequence = -1
	_last_action_resolution = null
	_hit_target_ids_this_swing.clear()


## Public seam: called by server_main.gd to register the server-owned target
## dummies this peer's melee hit tests may check against.
func set_target_dummies(target_dummies: Dictionary) -> void:
	_target_dummies = target_dummies


## Public seam: injects the server-side sector collision map used to keep the
## player out of walls and buildings during authoritative movement integration.
func set_collision_map(collision_map: Object) -> void:
	_collision_map = collision_map


## Public seam (Slice 029): called by server_main.gd to register the
## server-owned monster manager this peer's melee hit tests also check
## against, alongside the target dummies above.
func set_monster_manager(monster_manager: Object) -> void:
	_monster_manager = monster_manager


## Slice 094: the Player's current authoritative HP (read-only view of _vitals).
func current_hp() -> int:
	return _vitals.current_hp


## Slice 094: the Player's maximum authoritative HP.
func max_hp() -> int:
	return _vitals.max_hp


## Public seam (Slice 094): applies a monster's authoritative, telegraph-fair
## landed attack to this Player. Only server_main.gd calls this, routing from
## the ServerMonsterManager.player_hit signal (the monster's own reach/arc test
## against its locked telegraph facing already guarantees a Player who stepped
## out during WINDUP is missed, so reaching here means the hit was fair). On the
## tick this reduces the Player to 0 HP it emits player_defeated once, then
## applies the provisional respawn placeholder (ticket 05): restore full HP and
## return to the spawn anchor, cancelling any in-progress swing. Always emits
## health_changed with the resulting HP so the owning client's HUD updates.
func receive_monster_damage(amount: int, server_tick: int) -> void:
	if owning_peer_id == -1:
		return
	var defeated: bool = _vitals.apply_damage(amount)
	if defeated:
		player_defeated.emit(owning_peer_id, server_tick)
		_vitals.reset()
		position = _spawn_position
		_phase = CombatContractsScript.PHASE_IDLE
		_phase_ticks_remaining = 0
		_hit_target_ids_this_swing.clear()
	health_changed.emit(owning_peer_id, _vitals.current_hp, _vitals.max_hp, server_tick)


## Public seam: called (as a plain in-process call, not an RPC — this node
## exists only server-side, so it is never reached over the network directly;
## see client/network_client.gd's submit_input_intent for the RPC entry
## point) with the latest directional input intent reported by the owning
## client and the client-assigned sequence number for that intent sample.
## Never a requested position — the server still owns the resulting position.
## sender_id is verified against owning_peer_id so only the bound peer's
## intent is applied. Because the intent RPC is unreliable/unordered, a
## sample is only applied if its sequence is not older than the last one
## already processed, so a late-arriving stale sample cannot overwrite a
## newer one.
func apply_input_intent(sender_id: int, intent: Vector2, sequence: int) -> void:
	if sender_id != owning_peer_id:
		return
	if sequence <= _last_processed_sequence:
		return
	_input_intent = intent
	_last_processed_sequence = sequence

	if intent.length_squared() > 0.0:
		facing = Vector3(intent.x, 0.0, intent.y).normalized()


## Public seam: called (plain in-process call, same pattern as
## apply_input_intent above) with an ActionIntent requesting a melee strike.
## Validates monotonic sequence/idempotent replay and current-state legality,
## then — if accepted — starts the WINDUP phase. Always returns (and emits
## via action_resolved) an ActionResolution; a rejected intent has no side
## effect on phase, position, or hit state, matching CLAUDE.md's Intent
## Validation And Resolution rule.
func apply_action_intent(sender_id: int, intent: Object) -> Object:
	if sender_id != owning_peer_id:
		return null

	var sequence: int = intent.sequence

	if sequence == _last_processed_action_sequence and _last_action_resolution != null:
		# Idempotent replay: return the cached resolution, never re-apply
		# effects for a duplicate/retried intent.
		return _last_action_resolution

	if sequence <= _last_processed_action_sequence:
		var resolution: Object = _make_resolution(sequence, false, CombatContractsScript.REJECTED_STALE)
		action_resolved.emit(owning_peer_id, resolution)
		return resolution

	if intent.action_kind != CombatContractsScript.ACTION_KIND_MELEE_STRIKE:
		var resolution: Object = _make_resolution(sequence, false, CombatContractsScript.REJECTED_INVALID_STATE)
		_last_processed_action_sequence = sequence
		_last_action_resolution = resolution
		action_resolved.emit(owning_peer_id, resolution)
		return resolution

	if _phase != CombatContractsScript.PHASE_IDLE:
		var reason: String = CombatContractsScript.REJECTED_BUSY if _phase != CombatContractsScript.PHASE_RECOVERY else CombatContractsScript.REJECTED_COOLDOWN
		var resolution: Object = _make_resolution(sequence, false, reason)
		_last_processed_action_sequence = sequence
		_last_action_resolution = resolution
		action_resolved.emit(owning_peer_id, resolution)
		return resolution

	if intent.aim_direction.length_squared() > 0.0:
		facing = intent.aim_direction.normalized()

	_phase = CombatContractsScript.PHASE_WINDUP
	_phase_ticks_remaining = _archetype.windup_ticks
	_hit_target_ids_this_swing.clear()

	var resolution: Object = _make_resolution(sequence, true, "")
	_last_processed_action_sequence = sequence
	_last_action_resolution = resolution
	action_resolved.emit(owning_peer_id, resolution)
	melee_swing_started.emit(owning_peer_id, _archetype.windup_ticks, _archetype.active_ticks, facing)
	return resolution


func _make_resolution(sequence: int, accepted: bool, rejection_reason: String) -> Object:
	var result: String = CombatContractsScript.RESULT_ACCEPTED if accepted else CombatContractsScript.RESULT_REJECTED
	var server_tick: int = Engine.get_physics_frames()
	return CombatContractsScript.ActionResolution.new(owning_peer_id, sequence, result, rejection_reason, server_tick)


func _physics_process(delta: float) -> void:
	if owning_peer_id == -1:
		return

	_advance_action_phase()

	var speed_factor: float = CombatContractsScript.locomotion_speed_factor_for_phase(_phase, _archetype)
	var direction: Vector3 = Vector3(_input_intent.x, 0.0, _input_intent.y)
	if direction.length_squared() > 0.0:
		direction = direction.normalized()

	var desired_position: Vector3 = position + direction * NetworkConfigScript.AUTHORITATIVE_MOVE_SPEED * speed_factor * delta
	position = _collision_map.resolve_move(position, desired_position) if _collision_map != null else desired_position

	var network_client: Node = get_tree().root.get_node_or_null("NetworkClient")
	# Requiring CONNECTION_CONNECTED guards test/standalone contexts — e.g.
	# GUT exercising this node directly with no real listening server — where
	# an rpc_id() call would otherwise error rather than no-op. Godot's
	# built-in default multiplayer_peer before any real one is attached
	# reports CONNECTION_CONNECTING, never CONNECTED, so this check is not
	# satisfied by that default. In a real running server, once
	# _start_server()'s create_server() succeeds, multiplayer_peer reports
	# CONNECTION_CONNECTED for the remainder of the process's life.
	if network_client != null and get_tree().root.multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
		network_client.rpc_id(owning_peer_id, "receive_authoritative_position", position, _last_processed_sequence)

	position_updated.emit(owning_peer_id, position)


## Advances the fixed-tick attack phase state machine by exactly one physics
## tick and performs the ACTIVE-phase hit test. Deterministic phase
## progression: WINDUP -> ACTIVE -> RECOVERY -> IDLE, counted in ticks, never
## in wall-clock time, so behavior is identical regardless of frame timing.
func _advance_action_phase() -> void:
	if _phase == CombatContractsScript.PHASE_IDLE:
		return

	if _phase == CombatContractsScript.PHASE_ACTIVE:
		_perform_hit_test()

	_phase_ticks_remaining -= 1
	if _phase_ticks_remaining > 0:
		return

	match _phase:
		CombatContractsScript.PHASE_WINDUP:
			_phase = CombatContractsScript.PHASE_ACTIVE
			_phase_ticks_remaining = _archetype.active_ticks
		CombatContractsScript.PHASE_ACTIVE:
			_phase = CombatContractsScript.PHASE_RECOVERY
			_phase_ticks_remaining = _archetype.recovery_ticks
		CombatContractsScript.PHASE_RECOVERY:
			_phase = CombatContractsScript.PHASE_IDLE
			_phase_ticks_remaining = 0


## Deterministic vector reach/arc hit test against every registered target
## dummy plus every currently living monster (Slice 029), performed once per
## ACTIVE tick. max_targets bounds how many distinct targets one swing can
## hit; a target already hit this swing is never re-emitted, so a multi-tick
## ACTIVE window cannot double-hit the same target — dummy or monster alike.
## See .scratch/melee-combat/issues/04-choose-first-target-and-hit-rule.md.
func _perform_hit_test() -> void:
	if _hit_target_ids_this_swing.size() >= _archetype.max_targets:
		return

	var targets: Dictionary = _target_dummies.duplicate()
	if _monster_manager != null:
		targets.merge(_monster_manager.living_targets())

	for target_id: String in targets.keys():
		if _hit_target_ids_this_swing.has(target_id):
			continue

		var target: Object = targets[target_id]
		if target == null:
			continue

		if not CombatContractsScript.is_within_reach_and_arc(position, facing, target.position, _archetype):
			continue

		_hit_target_ids_this_swing[target_id] = true
		var server_tick: int = Engine.get_physics_frames()
		var combat_event: Object = CombatContractsScript.CombatEvent.new(
			CombatContractsScript.COMBAT_EVENT_HIT,
			owning_peer_id,
			target_id,
			target.position,
			server_tick
		)
		combat_event_emitted.emit(owning_peer_id, combat_event)

		if _hit_target_ids_this_swing.size() >= _archetype.max_targets:
			return
