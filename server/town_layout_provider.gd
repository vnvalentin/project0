extends RefCounted
class_name TownLayoutProvider
## Slice 026: the LLM town-layout guarantee seam. The LLM proposes a town layout
## (untrusted data); the server validates it via SectorBlueprintSchema and
## guarantees the required structures (a 10-house pool plus a smithy, armor
## shop, and inn) are present. If the candidate is invalid or incomplete, the
## server falls back to the hand-authored hub fixture so the town is NEVER
## unusable (Organic Village map decision Q2; CLAUDE.md law 5 "the LLM proposes;
## it never authorizes"). See docs/slices/026-llm-town-generation.md.
##
## Non-blocking: request_town() is a coroutine that awaits an injected async LLM
## client (any object exposing `generate_json(prompt) -> Dictionary`, e.g.
## shared/local_llm_client.gd or a test stub) and never blocks the SceneTree.
## No persistence and no boot wiring in this slice — the reliable fixture stays
## the boot default; turning LLM generation on at boot is a separate decision
## (boot latency, Ollama availability). See the slice doc's non-goals.

const SectorBlueprintSchemaScript: Script = preload("res://shared/sector_blueprint_schema.gd")

## The required-structure contract the town must always satisfy (map Q2).
const REQUIRED_HOUSE_COUNT: int = 10
const REQUIRED_SINGLETON_KINDS: PackedStringArray = ["smithy", "armor_shop", "inn"]

## Which layout a resolution used.
const SOURCE_LLM: String = "llm"
const SOURCE_FALLBACK: String = "fallback"

## Resolution outcome codes (beyond SectorBlueprintSchema's own OUTCOME_*, which
## are surfaced verbatim when a candidate fails schema validation).
const OUTCOME_ACCEPTED: String = "accepted"
const OUTCOME_MISSING_REQUIRED_STRUCTURES: String = "missing_required_structures"
const OUTCOME_TRANSPORT_ERROR: String = "transport_error"

signal town_resolved(result: Dictionary)


## Pure guarantee. Validates `candidate` (untrusted LLM data) via the schema and
## then checks the required structures. Returns
## {"source": String, "outcome": String, "detail": String, "blueprint": Dictionary}:
## on success `source == SOURCE_LLM` with the validated candidate; otherwise
## `source == SOURCE_FALLBACK` with `fallback` and a reason. `fallback` is
## assumed already valid (the shipped hub fixture) and is returned as-is so the
## town is never unusable.
static func resolve(candidate: Variant, fallback: Dictionary) -> Dictionary:
	var validation: Dictionary = SectorBlueprintSchemaScript.validate(candidate)
	if validation["outcome"] != SectorBlueprintSchemaScript.OUTCOME_VALID:
		return _fallback_result(fallback, validation["outcome"], "LLM candidate failed schema validation: %s" % validation["detail"])

	var validated: Dictionary = validation["blueprint"]
	var required: Dictionary = meets_required_structures(validated)
	if not required["ok"]:
		return _fallback_result(fallback, OUTCOME_MISSING_REQUIRED_STRUCTURES, required["detail"])

	return {
		"source": SOURCE_LLM,
		"outcome": OUTCOME_ACCEPTED,
		"detail": "",
		"blueprint": validated,
	}


## Pure. True when `blueprint` holds at least REQUIRED_HOUSE_COUNT houses and at
## least one of each REQUIRED_SINGLETON_KINDS. Returns {"ok": bool, "detail": String}.
static func meets_required_structures(blueprint: Dictionary) -> Dictionary:
	var counts: Dictionary = {}
	for structure: Dictionary in (blueprint.get("structures", []) as Array):
		var kind: String = String(structure.get("kind", ""))
		counts[kind] = int(counts.get(kind, 0)) + 1

	var house_count: int = int(counts.get("house", 0))
	if house_count < REQUIRED_HOUSE_COUNT:
		return {"ok": false, "detail": "requires >= %d houses, found %d" % [REQUIRED_HOUSE_COUNT, house_count]}
	for kind: String in REQUIRED_SINGLETON_KINDS:
		if int(counts.get(kind, 0)) < 1:
			return {"ok": false, "detail": "missing required structure kind '%s'" % kind}
	return {"ok": true, "detail": ""}


## The prompt handed to the LLM. Documents the town contract the model must
## satisfy; the server still validates and guarantees the result regardless of
## the wording, so a lazy or adversarial model cannot produce an unusable town.
static func default_town_prompt() -> String:
	return "\n".join([
		"Return ONLY one JSON object (no prose) describing a small fantasy starting town as a sector blueprint.",
		"Required shape:",
		"- \"schema_version\": 3",
		"- \"sector_id\": \"starting_town_hub\"",
		"- \"origin\": {\"x\": 0, \"y\": 0}",
		"- \"tiles\": 1..2048 entries of {\"x\": int, \"y\": int, \"kind\": string}; x and y within -16..16;",
		"  kind is one of floor, wall, corridor, path, plaza, gate, water, grass. Enclose the town in a",
		"  \"wall\" ring with a \"gate\" opening; use \"path\"/\"plaza\" for roads and a central square,",
		"  \"grass\"/\"water\" for scenery, and \"floor\" elsewhere.",
		"- \"structures\": entries of {\"structure_id\": unique string, \"kind\": string, \"x\": int, \"y\": int,",
		"  \"facing_degrees\": number in [0,360)}; kind is one of house, smithy, armor_shop, inn, church,",
		"  item_shop, tavern, well. You MUST include at least 10 house structures and at least one each of",
		"  smithy, armor_shop, and inn. You MAY add church, item_shop, tavern, and well for flavor.",
		"  Place every structure on an interior non-wall tile within -16..16.",
		"Output valid JSON only.",
	])


## Non-blocking async request. Awaits `llm_client.generate_json(prompt)`, routes
## the raw candidate through resolve() against `fallback`, emits town_resolved,
## and returns the resolution. A transport/parse failure from the client falls
## back to `fallback`. `llm_client` is injected so this is testable without a
## live Ollama.
func request_town(llm_client: Object, fallback: Dictionary) -> Dictionary:
	var llm_result: Dictionary = await llm_client.generate_json(default_town_prompt())

	var result: Dictionary
	if not bool(llm_result.get("success", false)):
		result = _fallback_result(fallback, OUTCOME_TRANSPORT_ERROR, String(llm_result.get("error", "LLM request failed")))
	else:
		result = resolve(llm_result.get("data"), fallback)

	print("Town layout resolved: source=%s, outcome=%s." % [result["source"], result["outcome"]])
	town_resolved.emit(result)
	return result


static func _fallback_result(fallback: Dictionary, outcome: String, detail: String) -> Dictionary:
	return {
		"source": SOURCE_FALLBACK,
		"outcome": outcome,
		"detail": detail,
		"blueprint": fallback,
	}
