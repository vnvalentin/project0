# Research 04 — External Spatial-Planning Tool vs. In-Engine Deterministic Repair

**Date:** 2026-09-13
**Ticket:** [issues/04-external-spatial-planner-research.md](../issues/04-external-spatial-planner-research.md)
(deferred half of [issues/01-spatial-validity-strategy.md](../issues/01-spatial-validity-strategy.md), decision 4)
**Method:** [research skill](../../../.agents/skills/research/SKILL.md) — primary sources only (official
GitHub repos, their READMEs/source, official docs). Each factual claim is cited to its source URL.

## Recommendation: **DROP**

None of the named servers performs non-overlapping building placement — the actual
bug. They ingest, convert, or query **real-world** geospatial data (lat/lon,
EPSG-coded CRS, OSM/CityGML), which is a category mismatch for a synthetic fantasy
tile grid. Using any of them from Godot additionally requires standing up a
separate Python/Node **bridge process** plus one or more third-party MCP servers
(some backed by a PostgreSQL/PostGIS database) and, for the OSM servers, **outbound
calls to external public APIs** — a large expansion of the trust boundary and
attack surface versus the current server-side-only, direct-HTTP-to-local-model,
strictly-schema-validated posture — for **zero** benefit on the overlap problem.
The deterministic in-engine footprint + repair path (tickets 02/03) solves
non-overlap directly at negligible architecture and security cost. Nothing found
here should block or delay tickets 02/03.

---

## 1. Do these servers exist, and what do they actually do?

### 1a. `jagan-shanmugam/open-streetmap-mcp` — real-world OSM query, MIT, Python/`uvx`

- Exists. Self-describes as "An OpenStreetMap MCP server implementation that
  enhances LLM capabilities with location-based services and geospatial data."
  Source: <https://github.com/jagan-shanmugam/open-streetmap-mcp>
- Tools are all **real-world** location services: `geocode_address`,
  `reverse_geocode`, `find_nearby_places`, `get_route_directions`,
  `search_category`, `suggest_meeting_point`, `explore_area`,
  `find_schools_nearby`, `analyze_commute`, `find_ev_charging_stations`,
  `analyze_neighborhood`, `find_parking_facilities`.
  Source: <https://github.com/jagan-shanmugam/open-streetmap-mcp> (Components → Tools)
- Runtime: Python (100% Python), launched as a stdio MCP server via
  `uvx osm-mcp-server` under an MCP host (Claude Desktop, Cursor, Windsurf).
  License: MIT. Source: <https://github.com/jagan-shanmugam/open-streetmap-mcp>
  (Installation; Languages; License)
- Emits **only real-world geodata** (geocoding real addresses/places). No
  layout/placement generation and no overlap logic. Fantasy-world fit: poor.

### 1b. `nervsystems/osmmcp` — real-world OSM query, MIT, Go, outbound external APIs

- Exists. "A Go OpenStreetMap MCP server … to enable LLMs to interact with
  geospatial data." 25 tools. Source: <https://github.com/nervsystems/osmmcp>
- Tools are real-world geospatial primitives: geocoding, reverse geocoding,
  `find_nearby_places`, `route_fetch` (OSRM), `get_route_directions`,
  `bbox_from_points`, `centroid_points`, polyline encode/decode, `osm_query_bbox`,
  `get_map_image`, etc. Source: <https://github.com/nervsystems/osmmcp>
  (Implemented Tools)
- **Depends on outbound external APIs**: "The server relies on these external
  APIs: Nominatim … Overpass API … OSRM." Source:
  <https://github.com/nervsystems/osmmcp> (API Dependencies)
- Runtime: Go 1.24 to build (or a prebuilt release binary), runs over stdio.
  License: MIT. It is explicitly derived from the jagan-shanmugam Python server.
  Source: <https://github.com/nervsystems/osmmcp> (Requirements; Acknowledgments;
  License)
- Real-world geodata only. No settlement layout / non-overlap capability.

### 1c. `ronantakizawa/gis-dataconversion-mcp` — format conversion only, MIT, Node/`npx`

- Exists. "gives LLMs access to geographic data conversion tools … convert between
  different geographic data formats, coordinate systems, and spatial references."
  Source: <https://github.com/ronantakizawa/gis-dataconversion-mcp>
- Tools are pure **format conversion** + reverse geocoding: `wkt_to_geojson`,
  `geojson_to_wkt`, `csv_to_geojson`, `geojson_to_csv`, `geojson_to_topojson`,
  `topojson_to_geojson`, `kml_to_geojson`, `geojson_to_kml`,
  `coordinates_to_location` (reverse geocoding). Source:
  <https://github.com/ronantakizawa/gis-dataconversion-mcp> (Available Tools)
- Runtime: JavaScript/Node, launched via `npx`; deps include
  `@modelcontextprotocol/sdk`, `wellknown`, `csv2geojson`, `topojson-*`,
  `@tmcw/togeojson`, `xmldom`. License: MIT. Source:
  <https://github.com/ronantakizawa/gis-dataconversion-mcp> (Installation;
  Dependencies; License)
- Converts real-world GIS files; performs **no** placement/generation. It cannot
  create a layout at all, let alone a non-overlapping one.

### 1d. `tum-gis/3dcitydb-mcp-server` — read-only queries over a real CityGML DB, Apache-2.0, Python + PostgreSQL/PostGIS

- Exists and is actively maintained (TUM Chair of Geoinformatics). "A Model
  Context Protocol (MCP) server giving AI assistants direct, natural language
  access to semantic 3D city models in CityGML managed within a 3DCityDB v5
  geodatabase." Source: <https://github.com/tum-gis/3dcitydb-mcp-server>
- It is **read-only query** over an existing database: "`run_query` enforces
  SELECT-only; writes are blocked at the application layer and the database layer
  … every pooled connection runs in a read-only transaction." Source:
  <https://github.com/tum-gis/3dcitydb-mcp-server> (Features; Available MCP Tools)
- Hard prerequisite is a populated real-world city database: "A running 3DCityDB
  v5 PostgreSQL instance with PostGIS." Data is imported from real CityGML/CityJSON
  files with real EPSG SRIDs (e.g., 25832 for Germany, 6668–6692 for Japan).
  Source: <https://github.com/tum-gis/3dcitydb-mcp-server> (Prerequisites;
  Coordinate reference system; Country-specific codelists)
- Runtime: Python 3.10+ (or Docker) plus a PostgreSQL + PostGIS + SFCGAL database.
  License: Apache-2.0. Source: <https://github.com/tum-gis/3dcitydb-mcp-server>
  (Deployment Options; License)
- Queries **existing real-world** 3D city models; it does not generate or place
  buildings and has no non-overlap function.

### 1e. `wiseman/osm-mcp` — map viewer + PostGIS query, no declared license, Python + PostgreSQL/PostGIS

- Exists. "OpenStreetMap integration for MCP, allowing users to query and
  visualize map data." Source: <https://github.com/wiseman/osm-mcp>
- Tools: `get_map_view`, `set_map_view`, `set_map_title`, `add_map_marker`,
  `add_map_line`, `add_map_polygon`, `query_osm_postgres`. The `add_map_*` tools
  draw overlays on a **Leaflet** map for display; they are not a layout solver.
  Source: <https://github.com/wiseman/osm-mcp> (MCP Tools; Features)
- Requires a PostgreSQL/PostGIS database of OSM data (`PGHOST`/`PGDB`/… env vars);
  launched via `uv run` under an MCP host. Source:
  <https://github.com/wiseman/osm-mcp> (Environment Variables; Installation)
- **No license file is declared** in the repository (the file list shows no
  `LICENSE`; the About → Resources shows only "Readme", no license), so it
  defaults to all-rights-reserved and is not safe to vendor. Source:
  <https://github.com/wiseman/osm-mcp> (repository file list; About)
- Real-world OSM only; no synthetic layout generation and no non-overlap logic.

---

## 2. Does Godot 4 + local Ollama need a separate MCP host/bridge process?

**Yes.** The current path in [shared/local_llm_client.gd](../../../shared/local_llm_client.gd)
is a GDScript `HTTPRequest` POST to Ollama's `/api/generate` with
`{"format": "json", "stream": false}` at `http://127.0.0.1:11434`. That endpoint is
plain text→JSON completion; it has **no** MCP transport and **no** tool-calling.
MCP servers speak stdio/SSE/Streamable-HTTP (not something Godot's `HTTPRequest`
speaks), and Ollama itself does not host MCP servers. Bridging the gap requires an
extra long-running process:

- **`jonigl/ollama-mcp-bridge`** — "Provides an API layer in front of the Ollama
  API, seamlessly adding tools from multiple MCP servers." It pre-loads MCP
  servers at startup and exposes an Ollama-compatible API, but tool integration
  happens **only on the `/api/chat` endpoint**: "`/api/chat` is the only endpoint
  with MCP tool integration. All other endpoints are transparently proxied."
  Runtime added: **Python ≥ 3.10.15 + FastAPI/uvicorn**, installed via
  `uvx ollama-mcp-bridge` (or pip/Docker), binding `0.0.0.0:8000` by default.
  Source: <https://github.com/jonigl/ollama-mcp-bridge> (README overview;
  Requirements; How It Works; CLI Options)
  - Consequence for this project: to use it, Godot would have to **abandon
    `/api/generate`** and adopt the `/api/chat` tool-calling message protocol, run
    a **tool-calling-capable** model, and add/operate the FastAPI bridge — a new
    network-listening service — plus each MCP server as its own child process
    (Go binary / `npx` / `uvx`, and for 3DCityDB/wiseman a PostgreSQL database).
- **`jonigl/mcp-client-for-ollama` (`ollmcp`)** — is a "modern, interactive
  terminal application (TUI)"; "a controlled terminal space where you steer, and
  the agent executes." It requires **Python 3.11+ and the UV package manager**.
  It is a **human-facing TUI**, not a library or proxy a game server can call
  programmatically — the wrong shape for Godot automation. Source:
  <https://github.com/jonigl/mcp-client-for-ollama> (Overview; Requirements)

Net: adopting any of these servers means +1 bridge runtime (Python/FastAPI, via
`uvx` or Docker), +N MCP-server processes (Go/Node/Python, some needing a
PostgreSQL/PostGIS DB), and a protocol switch to `/api/chat` tool calling — none of
which exists today.

---

## 3. Security surface vs. the project's current posture

Project posture (authoritative): the LLM is called **server-side only**, over
**direct HTTP to a local model** at `127.0.0.1:11434`, and "Ollama output is
untrusted provisional data until strict validation" — "The LLM proposes; it never
authorizes." Sources: [CLAUDE.md](../../../CLAUDE.md) (Non-Negotiable Design Laws
5; Runtime Ownership), [shared/local_llm_client.gd](../../../shared/local_llm_client.gd).

Adopting these tools would add:

- **Third-party arbitrary code execution via `uvx`/`npx`.** The OSM/GIS servers
  are launched by fetching and running community packages from PyPI/npm at
  startup (`uvx osm-mcp-server`, `npx … a11y-mcp-server`, `uvx ollama-mcp-bridge`).
  Sources: <https://github.com/jagan-shanmugam/open-streetmap-mcp> (Installation),
  <https://github.com/ronantakizawa/gis-dataconversion-mcp> (Installation),
  <https://github.com/jonigl/ollama-mcp-bridge> (Quick Start).
- **Outbound egress to external public APIs** (for the OSM servers): Nominatim,
  Overpass, OSRM, and OSM tile servers — network calls off the server host, with
  third-party availability, rate limits, and data-exfil surface. Source:
  <https://github.com/nervsystems/osmmcp> (API Dependencies).
- **New listening network service.** The bridge binds `0.0.0.0:8000` and defaults
  to `CORS_ORIGINS="*"`, which its own docs flag: "Using `CORS_ORIGINS="*"` …
  is not recommended for production." Source:
  <https://github.com/jonigl/ollama-mcp-bridge> (CLI Options; CORS Configuration).
- **A standing database** for 3DCityDB (PostgreSQL + PostGIS + SFCGAL) or wiseman
  (PostgreSQL/PostGIS) — more infrastructure and attack surface. Sources:
  <https://github.com/tum-gis/3dcitydb-mcp-server> (Prerequisites),
  <https://github.com/wiseman/osm-mcp> (Environment Variables).
- **Licensing risk** for `wiseman/osm-mcp`: no declared license (all-rights-
  reserved by default). Source: <https://github.com/wiseman/osm-mcp>.

Even under an MCP client's human-in-the-loop and "tool responses are treated as
untrusted content" model, this replaces one tightly-scoped local dependency (a
single loopback HTTP call the server already treats as untrusted) with a fleet of
third-party processes and outbound network dependencies. Source (trust model):
<https://github.com/jonigl/mcp-client-for-ollama> (Security).

---

## 4. Does any tool help with non-overlapping building placement?

**No.** This is the decisive finding. Every tool falls into one of three buckets,
none of which is settlement layout generation or overlap resolution:

- **Read real-world OSM** (geocode / route / nearby / neighborhood analysis):
  `jagan-shanmugam/open-streetmap-mcp`, `nervsystems/osmmcp`, `wiseman/osm-mcp`.
  Sources: <https://github.com/jagan-shanmugam/open-streetmap-mcp>,
  <https://github.com/nervsystems/osmmcp>, <https://github.com/wiseman/osm-mcp>.
- **Convert GIS file formats** (WKT/GeoJSON/CSV/TopoJSON/KML) + reverse geocode:
  `ronantakizawa/gis-dataconversion-mcp`. Source:
  <https://github.com/ronantakizawa/gis-dataconversion-mcp>.
- **Read-only query an existing real CityGML city database**:
  `tum-gis/3dcitydb-mcp-server`. Source:
  <https://github.com/tum-gis/3dcitydb-mcp-server>.

The bug (per [issues/01](../issues/01-spatial-validity-strategy.md)) is that the
LLM proposes **dimensionless** structures with **no footprint**, so the server
cannot even express overlap, and buildings render stacked. Solving that is a
computational-geometry **placement/repair** problem over a synthetic tile grid:
assign per-kind footprints and deterministically relocate to non-overlapping,
on-valid-tile cells. None of these tools ingests a candidate synthetic layout and
returns a de-conflicted one; they consume/emit **real-world** geographic data on a
lat/lon CRS, which does not map onto a fantasy grid. That is precisely the work
already scoped for [issues/02 (footprints)](../issues/02-structure-footprint-model.md)
and [issues/03 (deterministic repair)](../issues/03-deterministic-repair-and-placement.md),
which solve it in-engine with server authority, determinism, and no new runtime or
egress.

---

## Decisive facts (with sources)

1. Every named OSM/GIS/CityDB server operates on **real-world geodata** (OSM via
   Nominatim/Overpass/OSRM; CityGML in a 3DCityDB) — none generates synthetic
   fantasy layouts. Sources: <https://github.com/nervsystems/osmmcp> (API
   Dependencies), <https://github.com/tum-gis/3dcitydb-mcp-server> (Prerequisites).
2. **None** of the tools offers non-overlapping placement; capability is limited to
   read/convert/query. Sources: the five tool READMEs above (Tools/Features).
3. Using MCP tools from Ollama needs a **separate Python/FastAPI bridge**
   (`uvx ollama-mcp-bridge`, binds `0.0.0.0:8000`) and only injects tools on the
   `/api/chat` tool-calling endpoint — not the `/api/generate` path the project
   uses. Source: <https://github.com/jonigl/ollama-mcp-bridge> (How It Works;
   Requirements).
4. `mcp-client-for-ollama` is a **human TUI** (Python 3.11+ / UV), not a callable
   library for a game server. Source:
   <https://github.com/jonigl/mcp-client-for-ollama> (Overview; Requirements).
5. Servers are launched as **third-party `uvx`/`npx` code**, and the OSM servers
   make **outbound external-API calls** — a trust-boundary/egress expansion versus
   the current server-side-only, direct-local-HTTP posture. Sources:
   <https://github.com/jagan-shanmugam/open-streetmap-mcp> (Installation),
   <https://github.com/nervsystems/osmmcp> (API Dependencies), [CLAUDE.md](../../../CLAUDE.md).
6. `wiseman/osm-mcp` ships **no license** (all-rights-reserved by default) and needs
   a PostGIS DB. Source: <https://github.com/wiseman/osm-mcp>.

## Sources consulted

- <https://github.com/jagan-shanmugam/open-streetmap-mcp>
- <https://github.com/nervsystems/osmmcp>
- <https://github.com/ronantakizawa/gis-dataconversion-mcp>
- <https://github.com/tum-gis> and <https://github.com/tum-gis/3dcitydb-mcp-server>
- <https://github.com/wiseman/osm-mcp>
- <https://github.com/jonigl/ollama-mcp-bridge>
- <https://github.com/jonigl/mcp-client-for-ollama>
- Repo posture: [CLAUDE.md](../../../CLAUDE.md), [shared/local_llm_client.gd](../../../shared/local_llm_client.gd),
  [issues/01](../issues/01-spatial-validity-strategy.md) / [02](../issues/02-structure-footprint-model.md) / [03](../issues/03-deterministic-repair-and-placement.md)

**Sources I could not access:** none — all primary repositories listed in the ticket
were reachable and read directly. (The `tum-gis` org page was used to locate the
canonical `3dcitydb-mcp-server` repo, which was then read in full.)
