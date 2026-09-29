"""Validation of redacted two-client co-op combat evidence."""

SCENARIO = "coop-combat-v1"
TARGET = "target_dummy_0"
REQUIRED_CLIENTS = frozenset(("a", "b"))


def _require(condition, reason):
    if not condition:
        raise ValueError(reason)


def validate_client_evidence(client_id, evidence, correlation_id, builds):
    required = {"scenario_id", "correlation_id", "client_id", "character_id",
                "authenticated", "world_entered", "hit_event"}
    _require(required <= evidence.keys(), "client_evidence_missing")
    _require(evidence["scenario_id"] == SCENARIO and evidence["correlation_id"] == correlation_id,
             "client_identity")
    _require(evidence["client_id"] == client_id and client_id in REQUIRED_CLIENTS,
             "client_identity")
    _require(evidence["authenticated"] is True and evidence["world_entered"] is True,
             "client_not_admitted")
    _require(evidence["character_id"], "character_identity")
    _require(evidence.get("client_build") == builds["client"] and
             evidence.get("server_build") == builds["server"], "build_identity")
    hit = evidence["hit_event"]
    _require(hit.get("kind") == "HIT" and hit.get("target_id") == TARGET,
             "hit_target")
    _require(type(hit.get("server_tick")) is int and hit["server_tick"] >= 0,
             "hit_tick")
    if client_id == "a":
        resolution = evidence.get("resolution")
        _require(resolution and resolution.get("result") == "ACCEPTED" and
                 resolution.get("sequence") == 0, "accepted_resolution")
        _require(type(resolution.get("server_tick")) is int and resolution["server_tick"] >= 0,
                 "resolution_tick")
    return True


def validate_pair(evidence, correlation_id, builds):
    _require(evidence.get("scenario_id") == SCENARIO and
             evidence.get("correlation_id") == correlation_id, "pair_identity")
    clients = evidence.get("clients", {})
    _require(set(clients) == REQUIRED_CLIENTS, "client_count")
    _require(clients["a"].get("character_id") != clients["b"].get("character_id"),
             "character_identity")
    for client_id in REQUIRED_CLIENTS:
        validate_client_evidence(client_id, clients[client_id], correlation_id, builds)
    a_hit = clients["a"]["hit_event"]
    b_hit = clients["b"]["hit_event"]
    _require(a_hit["target_id"] == b_hit["target_id"] == TARGET, "hit_target_mismatch")
    _require(a_hit["server_tick"] == b_hit["server_tick"], "hit_tick_mismatch")
    _require(a_hit.get("attacker_peer_id") == b_hit.get("attacker_peer_id"), "hit_attacker_mismatch")
    server = evidence.get("server_observation", {})
    _require(server.get("authenticated_world_peers") == 2, "server_peer_count")
    _require(server.get("accepted_count") == 1 and server.get("hit_count") == 1,
             "encounter_count")
    _require(server.get("accepted_resolution", {}).get("result") == "ACCEPTED",
             "server_resolution")
    _require(server.get("hit_event", {}).get("target_id") == TARGET and
             server["hit_event"].get("server_tick") == a_hit["server_tick"],
             "server_hit_mismatch")
    return True
