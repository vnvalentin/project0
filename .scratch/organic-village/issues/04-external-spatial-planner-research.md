Type: research
Status: resolved (assigned: Copilot)
Blocked by: None

## Question

Evaluate whether an external spatial-planning tool meaningfully reduces the
burden of generating valid settlement layouts, versus the deterministic
in-engine repair path (tickets 02/03), at acceptable architecture and security
cost. This is the deferred half of strategy ticket 01 (decision 4) and closes
the loop on the user's original MCP / OSM idea.

Investigate against **primary sources** (official repos/docs, not write-ups):

- Do the specifically named servers exist and what do they actually do:
  `open-streetmap-mcp` (nervsystems/osmmcp and jagan-shanmugam),
  `gis-dataconversion-mcp` (ronantakizawa), `3dcitydb-mcp-server` (tum-gis)?
  Note license, runtime deps, and whether they emit *real-world* geodata only
  (fantasy-layout fit).
- Does Godot 4 need a separate MCP host/bridge process to use any of them
  (ollama-mcp-bridge, mcp-client-for-ollama), and what does that add on top of
  the current direct-HTTP `shared/local_llm_client.gd` path?
- Security surface: third-party code via `uvx`, outbound external-API egress
  from the server host, versus the current server-side-only,
  untrusted-LLM-output posture.
- Does any of it help **non-overlap specifically**, or only real-world data
  ingestion?

Output: a findings Markdown file under `.scratch/organic-village/research/` with
a clear recommendation (pursue / defer / drop), each claim cited to its source.

## Answer

**Recommendation: DROP.** None of the named servers addresses non-overlapping
building placement (the actual bug); they ingest/convert/query **real-world**
geodata (lat/lon, EPSG CRS, OSM/CityGML), a category mismatch for a synthetic
fantasy tile grid. Using any from Godot also requires a separate Python/FastAPI
bridge process plus third-party `uvx`/`npx` servers (some needing PostGIS) and
outbound external-API egress — a large trust-boundary expansion over the current
server-side-only, direct-HTTP-to-local-model, strictly-validated posture — for
zero non-overlap benefit. The in-engine footprint + repair path (tickets 02/03)
solves it directly, so this does not block 02/03.

Decisive facts (primary sources; full citations in the findings file):

- `nervsystems/osmmcp` calls outbound Nominatim / Overpass / OSRM APIs.
- `tum-gis/3dcitydb-mcp-server` is read-only SELECT over a required real-world
  3DCityDB PostgreSQL/PostGIS instance.
- `ronantakizawa/gis-dataconversion-mcp` is pure format conversion
  (WKT/GeoJSON/CSV/TopoJSON/KML) — it cannot generate a layout.
- `jonigl/ollama-mcp-bridge` injects tools only on `/api/chat`, not the
  `/api/generate` path this project uses; adds Python/FastAPI on 0.0.0.0:8000.
- `jonigl/mcp-client-for-ollama` is a human TUI, not a callable library.

Full findings with citations:
[research/04-external-spatial-planner.md](../research/04-external-spatial-planner.md)
