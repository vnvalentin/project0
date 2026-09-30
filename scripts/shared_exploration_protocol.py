"""Validation of redacted shared-exploration-v1 evidence."""

SCENARIO = "shared-exploration-v1"
REQUIRED_CLIENTS = frozenset(("a", "b"))


def _require(condition, reason):
    if not condition:
        raise ValueError(reason)


def validate_run_identity(correlation_id, server_build, client_build, client_ids):
    _require(bool(correlation_id and server_build and client_build), "build_identity_missing")
    _require(set(client_ids) == REQUIRED_CLIENTS, "client_identity")
    _require(client_ids["a"] != client_ids["b"], "client_identity")
    return True


def validate_client_observation(client_id, observation, correlation_id, expected_remote):
    required = {"correlation_id", "scenario_id", "client_id", "character_id",
                "authenticated", "world_entered", "remote_players"}
    missing = required - observation.keys()
    if missing:
        raise ValueError("observation_missing:" + ",".join(sorted(missing)))
    if observation["scenario_id"] != SCENARIO or observation["correlation_id"] != correlation_id:
        raise ValueError("observation_identity")
    _require(client_id in REQUIRED_CLIENTS and observation["client_id"] == client_id,
             "client_identity")
    _require(observation["authenticated"] is True and observation["world_entered"] is True,
             "client_not_authenticated")
    _require(observation["character_id"], "character_identity")
    remotes = observation["remote_players"]
    _require(isinstance(remotes, dict) and set(remotes) == {expected_remote},
             "remote_presence_count")
    _require(remotes[expected_remote].get("character_id"), "remote_character_identity")
    return True


def validate_disconnect_observation(observation):
    _require(observation.get("remote_players") == {}, "disconnect_presence_not_removed")
    return True


def validate_reconnect_observation(observation, expected_remote):
    remotes = observation.get("remote_players")
    _require(isinstance(remotes, dict) and set(remotes) == {expected_remote},
             "reconnect_presence_not_unique")
    _require(remotes[expected_remote].get("character_id"), "reconnect_character_identity")
    return True


def validate_authoritative_movement(baseline, observed, minimum_distance=0.5):
    _require(isinstance(baseline, (list, tuple)) and isinstance(observed, (list, tuple))
             and len(baseline) == 3 and len(observed) == 3, "movement_position_shape")
    distance = sum((float(current) - float(previous)) ** 2
                   for previous, current in zip(baseline, observed)) ** 0.5
    _require(distance > minimum_distance, "authoritative_movement_missing")
    return True


def validate_frontier_observation(frontier, sector_id="sector-0-1"):
    _require(isinstance(frontier, dict), "frontier_missing")
    _require(frontier.get("sector_id") == sector_id, "frontier_sector")
    _require(frontier.get("geometry_ready") is True and frontier.get("crossed") is True,
             "frontier_not_ready")
    started = frontier.get("started_at_msec")
    geometry_ready = frontier.get("geometry_ready_at_msec")
    crossed = frontier.get("crossed_at_msec")
    _require(type(started) is int and type(geometry_ready) is int and type(crossed) is int,
             "frontier_timing_shape")
    _require(started >= 0 and started <= geometry_ready <= crossed, "frontier_timing_order")
    _require(frontier.get("ready_latency_ms") == geometry_ready - started,
             "frontier_ready_timing")
    _require(frontier.get("cross_latency_ms") == crossed - started,
             "frontier_cross_timing")
    return True


def validate_server_observation(server, correlation_id, characters):
    _require(server.get("scenario_id") == SCENARIO and
             server.get("correlation_id") == correlation_id, "server_identity")
    _require(set(server.get("characters", {})) == set(characters), "server_characters")
    _require(server.get("authenticated_world_peers") == 2, "server_peer_count")
    for client_id, character_id in characters.items():
        _require(server["characters"][client_id] == character_id, "server_character_identity")
    return True
