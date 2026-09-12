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

## Ticks a defeated monster waits before respawning (~3s at 60 Hz).
const RESPAWN_COOLDOWN_TICKS: int = 180
## Radius (meters) around a spawn point within which a respawn is randomized.
const RESPAWN_AREA_RADIUS_METERS: float = 2.0
## Ground height monsters spawn at (players sit at y == 1).
const MONSTER_SPAWN_Y: float = 1.0
## Half-extent of the town's square exclusion zone. Just outside the fixture's
## octagon town outline (StartingTownHubFixture._TOWN_RADIUS == 16), so no
## monster is ever positioned inside the town, on spawn or respawn.
const TOWN_EXCLUSION_HALF_EXTENT: float = 18.0

## Telemetry: emitted when a monster is defeated and when one respawns. The
## server runtime forwards these to logs. Initial spawns are not signalled
## (they exist from construction); use monster_count() for that.
signal monster_died(spawn_id: String, server_tick: int)
signal monster_respawned(spawn_id: String, position: Vector3, server_tick: int)

var _slots: Array[Dictionary] = []
var _respawn_cooldown_ticks: int
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _init(spawn_points: Array, rng_seed: int = 0, respawn_cooldown_ticks: int = RESPAWN_COOLDOWN_TICKS) -> void:
	_respawn_cooldown_ticks = respawn_cooldown_ticks
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
			"monster": ServerMonsterStateScript.new(spawn_id, base),
			"cooldown": 0,
		})


func monster_count() -> int:
	return _slots.size()


func living_count() -> int:
	var alive: int = 0
	for slot: Dictionary in _slots:
		if slot["monster"] != null and not (slot["monster"] as Object).is_dead():
			alive += 1
	return alive


## The live monster at a slot index, or null while that slot is respawning.
## Exposed so a player's accepted melee hit (a later slice) — and this slice's
## tests — can reach a monster's receive_damage.
func monster_at(index: int) -> Object:
	if index < 0 or index >= _slots.size():
		return null
	return _slots[index]["monster"]


## Advances every monster one tick against the nearest connected player, and
## drives death -> cooldown -> respawn. `player_positions` may be empty (no
## connected players), in which case living monsters simply idle.
func advance_all(player_positions: Array, delta: float, server_tick: int) -> void:
	for slot: Dictionary in _slots:
		var monster: Object = slot["monster"]
		if monster != null:
			if monster.is_dead():
				slot["monster"] = null
				slot["cooldown"] = _respawn_cooldown_ticks
				monster_died.emit(slot["spawn_id"], server_tick)
			elif not player_positions.is_empty():
				monster.advance(_nearest_player(player_positions, monster.position), delta, server_tick)
		else:
			slot["cooldown"] = int(slot["cooldown"]) - 1
			if int(slot["cooldown"]) <= 0:
				var position: Vector3 = _random_position_outside_town(slot["base"])
				slot["monster"] = ServerMonsterStateScript.new(slot["spawn_id"], position)
				monster_respawned.emit(slot["spawn_id"], position, server_tick)


func _nearest_player(player_positions: Array, monster_position: Vector3) -> Vector3:
	var nearest: Vector3 = player_positions[0]
	var best: float = _horizontal_distance(nearest, monster_position)
	for i in range(1, player_positions.size()):
		var candidate: Vector3 = player_positions[i]
		var distance: float = _horizontal_distance(candidate, monster_position)
		if distance < best:
			best = distance
			nearest = candidate
	return nearest


## A randomized point within RESPAWN_AREA_RADIUS_METERS of `base`, then pushed
## back out along `base`'s dominant axis if it fell inside the town exclusion
## box — so a respawn can never land inside the town.
func _random_position_outside_town(base: Vector3) -> Vector3:
	var angle: float = _rng.randf() * TAU
	var radius: float = _rng.randf() * RESPAWN_AREA_RADIUS_METERS
	var candidate: Vector3 = base + Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
	candidate.y = MONSTER_SPAWN_Y
	if absf(candidate.x) < TOWN_EXCLUSION_HALF_EXTENT and absf(candidate.z) < TOWN_EXCLUSION_HALF_EXTENT:
		if absf(base.x) >= absf(base.z):
			candidate.x = signf(base.x) * TOWN_EXCLUSION_HALF_EXTENT
		else:
			candidate.z = signf(base.z) * TOWN_EXCLUSION_HALF_EXTENT
	return candidate


func _horizontal_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
