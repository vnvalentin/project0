extends RefCounted
class_name ServerMonsterManager
## Basic Monsters slice 03: the server-side runtime that instantiates one
## monster per town spawn point, drives each monster's state machine every tick
## against the nearest player, and respawns a defeated monster after a cooldown
## at a randomized position that is kept OUTSIDE the town boundary (user caveat,
## 2026-09-12). A RefCounted driven by server_main each physics frame, so its
## whole lifecycle is unit-testable without a SceneTree. See
## docs/slices/022-monster-spawning-and-respawn.md and
## .scratch/basic-monsters/issues/03-monster-spawn-points-from-town-schema.md
## (resolved).

const ServerMonsterStateScript: Script = preload("res://server/server_monster_state.gd")
const SectorBlueprintSchemaScript: Script = preload("res://shared/sector_blueprint_schema.gd")
const MonsterContractsScript: Script = preload("res://shared/monster_contracts.gd")

## Ticks a defeated monster waits before respawning (~3s at 60 Hz).
const RESPAWN_COOLDOWN_TICKS: int = 180
## Radius (yards) around a spawn point within which a respawn is randomized.
const RESPAWN_AREA_RADIUS_YARDS: float = 2.0
## Ground height monsters spawn at (players sit at y == 1).
const MONSTER_SPAWN_Y: float = 1.0
## Fallback/default half-extent of the town's square exclusion zone, used only
## when a caller does not derive one from an actual blueprint (or the
## blueprint has no tiles). Just outside the fixture's octagon town outline
## (StartingTownHubFixture._TOWN_RADIUS == 30), so no monster is ever
## positioned inside the village, on spawn or respawn.
const TOWN_EXCLUSION_HALF_EXTENT: float = 32.0

## Margin (yards) added beyond a blueprint's furthest tile coordinate when
## deriving an exclusion half-extent from actual town bounds (Slice 053).
const TOWN_EXCLUSION_MARGIN_YARDS: float = 2.0

## Telemetry: emitted when a monster is defeated and when one respawns. The
## server runtime forwards these to logs. Initial spawns are not signalled
## (they exist from construction); use monster_count() for that.
signal monster_died(spawn_id: String, server_tick: int)
signal monster_respawned(spawn_id: String, position: Vector3, server_tick: int)

## Slice 094: emitted when a monster's landed, telegraph-fair attack should
## damage a Player. Carries the victim peer id (the nearest player the monster
## was resolving its attack against this tick), so server_main.gd can route the
## damage to that peer's ServerPlayerState without this manager knowing about
## players or networking. Only emitted when advance_all was given peer ids.
signal player_hit(victim_peer_id: int, spawn_id: String, server_tick: int)

var _slots: Array[Dictionary] = []
var _respawn_cooldown_ticks: int
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _exclusion_half_extent: float


## Slice 053: `exclusion_half_extent` defaults to the fixed fallback constant
## so existing call sites/tests that pass only `spawn_points` (or up to
## `respawn_cooldown_ticks`) keep today's exact 32.0 behavior; callers that
## know the actual town bounds (server_main.gd, via
## town_exclusion_half_extent()) pass a derived value instead.
func _init(spawn_points: Array, rng_seed: int = 0, respawn_cooldown_ticks: int = RESPAWN_COOLDOWN_TICKS, exclusion_half_extent: float = TOWN_EXCLUSION_HALF_EXTENT) -> void:
	_respawn_cooldown_ticks = respawn_cooldown_ticks
	_exclusion_half_extent = exclusion_half_extent
	_rng.seed = rng_seed
	# Bounded by the same cap the schema enforces on spawn_points.
	var count: int = mini(spawn_points.size(), SectorBlueprintSchemaScript.MAX_SPAWN_POINT_COUNT)
	for i in count:
		var spawn_point: Dictionary = spawn_points[i]
		var spawn_id: String = String(spawn_point.get("spawn_id", "spawn_%d" % i))
		var base: Vector3 = Vector3(float(spawn_point.get("x", 0)), MONSTER_SPAWN_Y, float(spawn_point.get("y", 0)))
		_slots.append({
			"spawn_id": spawn_id,
			"base": base,
			"monster": _spawn_monster(spawn_id, base),
			"cooldown": 0,
			"target_peer_id": -1,
		})


## Slice 094: constructs a monster state and connects its attack_resolved
## telemetry to this manager, so a landed attack becomes a routed player_hit.
## Used for both the initial spawn and every respawn, so respawned monsters
## damage players too.
func _spawn_monster(spawn_id: String, position: Vector3) -> Object:
	var monster: Object = ServerMonsterStateScript.new(spawn_id, position)
	monster.attack_resolved.connect(_on_monster_attack_resolved)
	return monster


func monster_count() -> int:
	return _slots.size()


func living_count() -> int:
	var alive: int = 0
	for slot: Dictionary in _slots:
		if slot["monster"] != null and not (slot["monster"] as Object).is_dead():
			alive += 1
	return alive


## The live monster at a slot index, or null while that slot is respawning.
## Exposed so a player's accepted melee hit — and this slice's tests — can
## reach a monster's receive_damage.
func monster_at(index: int) -> Object:
	if index < 0 or index >= _slots.size():
		return null
	return _slots[index]["monster"]


## Every currently living monster, keyed by target_id. Rebuilt fresh on each
## call (never cached) so a caller — Slice 029's ServerPlayerState hit test —
## never sees a stale reference to a monster that has since died and been
## cleared from its slot; a dead/respawning monster is simply absent, so it
## can never be targeted.
func living_targets() -> Dictionary:
	var targets: Dictionary = {}
	for slot: Dictionary in _slots:
		var monster: Object = slot["monster"]
		if monster != null and not (monster as Object).is_dead():
			targets[slot["spawn_id"]] = monster
	return targets


## Public seam (Slice 029): applies a player's authoritative accepted melee hit
## to the living monster identified by target_id, via the monster's own
## receive_damage — this manager remains the sole owner of monster mutation, so
## ServerPlayerState never touches monster state directly. Returns true only on
## the tick this hit defeats a still-living monster (the 0-HP transition), so
## the caller can emit exactly one attacker-attributed death outcome; a no-op
## (returns false) if target_id names no living monster, matching the
## "DEAD/respawning is not targetable" invariant.
func receive_player_hit(target_id: String, attacker_peer_id: int, server_tick: int) -> bool:
	for slot: Dictionary in _slots:
		var monster: Object = slot["monster"]
		if monster == null or String(slot["spawn_id"]) != target_id:
			continue
		if (monster as Object).is_dead():
			return false
		monster.receive_damage(MonsterContractsScript.DAMAGE_PER_HIT, attacker_peer_id, server_tick)
		return (monster as Object).is_dead()
	return false


## Advances every monster one tick against the nearest connected player, and
## drives death -> cooldown -> respawn. `player_positions` may be empty (no
## connected players), in which case living monsters simply idle. Slice 094:
## `player_peer_ids` is an optional parallel array (same order/length as
## `player_positions`); when supplied, a monster whose attack lands this tick
## emits player_hit against the nearest player's peer id. When omitted (older
## call sites/tests), no player_hit is emitted — behavior is otherwise unchanged.
func advance_all(player_positions: Array, delta: float, server_tick: int, player_peer_ids: Array = []) -> void:
	for slot: Dictionary in _slots:
		var monster: Object = slot["monster"]
		if monster != null:
			if monster.is_dead():
				slot["monster"] = null
				slot["cooldown"] = _respawn_cooldown_ticks
				monster_died.emit(slot["spawn_id"], server_tick)
			elif not player_positions.is_empty():
				var nearest_index: int = _nearest_player_index(player_positions, monster.position)
				# Set the victim BEFORE advancing: the monster resolves its attack
				# (emitting attack_resolved) synchronously inside advance(), and
				# _on_monster_attack_resolved reads this slot's target_peer_id.
				slot["target_peer_id"] = int(player_peer_ids[nearest_index]) if nearest_index < player_peer_ids.size() else -1
				monster.advance(player_positions[nearest_index], delta, server_tick)
		else:
			slot["cooldown"] = int(slot["cooldown"]) - 1
			if int(slot["cooldown"]) <= 0:
				var position: Vector3 = _random_position_outside_town(slot["base"])
				slot["monster"] = _spawn_monster(slot["spawn_id"], position)
				monster_respawned.emit(slot["spawn_id"], position, server_tick)


## Slice 094: emits player_hit for a landed attack against the slot's current
## victim. Connected to every monster's attack_resolved (initial + respawn) via
## _spawn_monster; a miss (landed == false) or an unknown victim is a no-op.
func _on_monster_attack_resolved(target_id: String, landed: bool, server_tick: int) -> void:
	if not landed:
		return
	for slot: Dictionary in _slots:
		if String(slot["spawn_id"]) != target_id:
			continue
		var victim_peer_id: int = int(slot.get("target_peer_id", -1))
		if victim_peer_id >= 0:
			player_hit.emit(victim_peer_id, target_id, server_tick)
		return


func _nearest_player(player_positions: Array, monster_position: Vector3) -> Vector3:
	return player_positions[_nearest_player_index(player_positions, monster_position)]


func _nearest_player_index(player_positions: Array, monster_position: Vector3) -> int:
	var best_index: int = 0
	var best: float = _horizontal_distance(player_positions[0], monster_position)
	for i in range(1, player_positions.size()):
		var distance: float = _horizontal_distance(player_positions[i], monster_position)
		if distance < best:
			best = distance
			best_index = i
	return best_index


## A randomized point within RESPAWN_AREA_RADIUS_YARDS of `base`, then pushed
## back out along `base`'s dominant axis if it fell inside the town exclusion
## box — so a respawn can never land inside the town.
func _random_position_outside_town(base: Vector3) -> Vector3:
	var angle: float = _rng.randf() * TAU
	var radius: float = _rng.randf() * RESPAWN_AREA_RADIUS_YARDS
	var candidate: Vector3 = base + Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
	candidate.y = MONSTER_SPAWN_Y
	if absf(candidate.x) < _exclusion_half_extent and absf(candidate.z) < _exclusion_half_extent:
		if absf(base.x) >= absf(base.z):
			candidate.x = signf(base.x) * _exclusion_half_extent
		else:
			candidate.z = signf(base.z) * _exclusion_half_extent
	return candidate


func _horizontal_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


## Slice 053: derives a town exclusion half-extent from a validated sector
## blueprint's actual tiles — max over tiles of max(abs(x), abs(y)), plus
## TOWN_EXCLUSION_MARGIN_YARDS — instead of the hard-coded
## TOWN_EXCLUSION_HALF_EXTENT constant, so any town size (a fixture, a
## differently-sized fixture, or a future validated LLM town) keeps monsters
## just outside its actual walls. Falls back to TOWN_EXCLUSION_HALF_EXTENT when
## the blueprint has no tiles (defensive; should not occur for a validated
## blueprint). For the shipped fixture (StartingTownHubFixture._TOWN_RADIUS ==
## 30) this yields exactly 32.0, matching prior behavior.
static func town_exclusion_half_extent(blueprint: Dictionary) -> float:
	var tiles: Array = blueprint.get("tiles", [])
	if tiles.is_empty():
		return TOWN_EXCLUSION_HALF_EXTENT
	var furthest: float = 0.0
	for tile: Dictionary in tiles:
		var extent: float = maxf(absf(float(tile.get("x", 0))), absf(float(tile.get("y", 0))))
		if extent > furthest:
			furthest = extent
	return furthest + TOWN_EXCLUSION_MARGIN_YARDS
