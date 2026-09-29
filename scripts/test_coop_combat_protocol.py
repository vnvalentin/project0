import unittest

from scripts.coop_combat_protocol import SCENARIO, TARGET, validate_client_evidence, validate_pair


class CoopCombatProtocolTests(unittest.TestCase):
    def setUp(self):
        self.builds = {"client": {"sha256": "client"}, "server": {"sha256": "server"}}

    def client(self, client_id, tick=42):
        value = {
            "scenario_id": SCENARIO,
            "correlation_id": "run-1",
            "client_id": client_id,
            "character_id": "character-" + client_id,
            "authenticated": True,
            "world_entered": True,
            "client_build": self.builds["client"],
            "server_build": self.builds["server"],
            "hit_event": {"kind": "HIT", "target_id": TARGET, "server_tick": tick},
        }
        if client_id == "a":
            value["resolution"] = {"sequence": 0, "result": "ACCEPTED", "server_tick": 30}
        return value

    def test_pair_requires_same_authoritative_hit_tick(self):
        evidence = {
            "scenario_id": SCENARIO,
            "correlation_id": "run-1",
            "clients": {"a": self.client("a"), "b": self.client("b")},
            "server_observation": {
                "authenticated_world_peers": 2,
                "accepted_count": 1,
                "hit_count": 1,
                "accepted_resolution": {"result": "ACCEPTED"},
                "hit_event": {"target_id": TARGET, "server_tick": 42},
            },
        }
        self.assertTrue(validate_pair(evidence, "run-1", self.builds))
        evidence["clients"]["b"]["hit_event"]["server_tick"] = 43
        with self.assertRaisesRegex(ValueError, "hit_tick_mismatch"):
            validate_pair(evidence, "run-1", self.builds)

    def test_client_b_cannot_claim_the_owner_resolution(self):
        with self.assertRaisesRegex(ValueError, "client_evidence_missing"):
            validate_client_evidence("b", {"hit_event": {}}, "run-1", self.builds)


if __name__ == "__main__":
    unittest.main()
