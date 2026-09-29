import unittest

from scripts.shared_exploration_protocol import (
    SCENARIO,
    validate_client_observation,
    validate_authoritative_movement,
    validate_disconnect_observation,
    validate_reconnect_observation,
    validate_server_observation,
    validate_run_identity,
)


class SharedExplorationProtocolTests(unittest.TestCase):
    def setUp(self):
        validate_run_identity("run-1", "server-build", "client-build", {"a": "character-a", "b": "character-b"})

    def observation(self, remote, client_id="a"):
        character_id = "character-" + client_id
        remote_character_id = "character-" + remote
        return {"scenario_id": SCENARIO, "correlation_id": "run-1", "client_id": client_id,
                "character_id": character_id,
                "authenticated": True, "world_entered": True,
                "remote_players": {remote: {"character_id": remote_character_id}}}

    def test_two_authenticated_clients_are_correlated_and_reconnect_is_unique(self):
        validate_client_observation("a", self.observation("b"), "run-1", "b")
        validate_client_observation("b", self.observation("a", "b"), "run-1", "a")
        validate_reconnect_observation(self.observation("b"), "b")

    def test_disconnect_removes_the_stale_remote(self):
        validate_disconnect_observation({"remote_players": {}})

    def test_both_directional_movement_observations_are_nontrivial(self):
        validate_authoritative_movement([0, 0, 0], [0.6, 0, 0])
        validate_authoritative_movement([0, 0, 0], [0, 0, 0.6])

    def test_rejects_stale_or_duplicate_presence(self):
        with self.assertRaisesRegex(ValueError, "observation_identity"):
            validate_client_observation("a", self.observation("b") | {"correlation_id": "wrong"}, "run-1", "b")
        with self.assertRaisesRegex(ValueError, "remote_presence_count"):
            validate_client_observation("a", self.observation("b") | {"remote_players": {}}, "run-1", "b")

    def test_requires_distinct_authenticated_client_identities(self):
        with self.assertRaisesRegex(ValueError, "client_identity"):
            validate_run_identity("run-1", "server-build", "client-build", {"a": "same", "b": "same"})

    def test_server_requires_two_authenticated_world_peers_and_distinct_characters(self):
        validate_server_observation(
            {"scenario_id": SCENARIO, "correlation_id": "run-1",
             "authenticated_world_peers": 2,
             "characters": {"a": "character-a", "b": "character-b"}},
            "run-1", {"a": "character-a", "b": "character-b"})
        with self.assertRaisesRegex(ValueError, "server_peer_count"):
            validate_server_observation(
                {"scenario_id": SCENARIO, "correlation_id": "run-1",
                 "authenticated_world_peers": 1,
                 "characters": {"a": "character-a", "b": "character-b"}},
                "run-1", {"a": "character-a", "b": "character-b"})


if __name__ == "__main__":
    unittest.main()