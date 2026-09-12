extends RefCounted
class_name SectorBlueprintFixtures
## Fixture JSON strings for Slice 008's sector blueprint contract tests.
## Each fixture is the raw text that would appear as Ollama's inner
## "response" field (i.e. the model's own output text, already unwrapped from
## the Ollama envelope) — see shared/local_llm_client.gd's _parse_response().
## Used by scripts/test_sector_blueprint_contract.gd so validator/service
## behavior can be asserted without any live Ollama instance.

const VALID: String = """
{
  "schema_version": 1,
  "sector_id": "sector-0-0",
  "origin": {"x": 0, "y": 0},
  "tiles": [
    {"x": 0, "y": 0, "kind": "floor"},
    {"x": 1, "y": 0, "kind": "wall"},
    {"x": 0, "y": 1, "kind": "corridor"}
  ]
}
"""

const MALFORMED_JSON: String = """
{ this is not valid JSON at all ]
"""

const INCOMPLETE_MISSING_TILES: String = """
{
  "schema_version": 1,
  "sector_id": "sector-0-0",
  "origin": {"x": 0, "y": 0}
}
"""

const UNSUPPORTED_KIND: String = """
{
  "schema_version": 1,
  "sector_id": "sector-0-0",
  "origin": {"x": 0, "y": 0},
  "tiles": [
    {"x": 0, "y": 0, "kind": "lava_pit"}
  ]
}
"""

const WRONG_SCHEMA_VERSION: String = """
{
  "schema_version": 99,
  "sector_id": "sector-0-0",
  "origin": {"x": 0, "y": 0},
  "tiles": [
    {"x": 0, "y": 0, "kind": "floor"}
  ]
}
"""

const OUT_OF_BOUNDS_ORIGIN: String = """
{
  "schema_version": 1,
  "sector_id": "sector-0-0",
  "origin": {"x": 33, "y": 0},
  "tiles": [
    {"x": 0, "y": 0, "kind": "floor"}
  ]
}
"""

const OUT_OF_BOUNDS_TILE: String = """
{
  "schema_version": 1,
  "sector_id": "sector-0-0",
  "origin": {"x": 0, "y": 0},
  "tiles": [
    {"x": -33, "y": 0, "kind": "floor"}
  ]
}
"""
