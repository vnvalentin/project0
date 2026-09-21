extends RefCounted
class_name WorldDirectiveValidator
## Slice 191: validates raw semantic World proposals before any deterministic
## builder can consume them. This seam has no clock, filesystem, LLM, or runtime
## dependencies; callers supply all inputs and own asynchronous scheduling.

const SCHEMA_VERSION: int = 1
const OUTCOME_ACCEPTED: String = "accepted"
const OUTCOME_FALLBACK: String = "fallback"
const OUTCOME_REJECTED: String = "rejected"
const MAX_TEXT_LENGTH: int = 1024
const MAX_VERSION_LENGTH: int = 64
const MAX_LIST_ITEMS: int = 8

const VALID_BIOMES: Array[String] = ["forest", "desert", "coast", "mountain"]
const VALID_THEMES: Array[String] = ["frontier", "ancient", "ruins"]
const VALID_PALETTE_TAGS: Array[String] = ["verdant", "arid", "maritime", "stone", "ashen"]
const VALID_ATMOSPHERE_TAGS: Array[String] = ["calm", "mist", "storm", "cinders", "moonlit"]
const VALID_POI_PREDICATES: Array[String] = ["HIGHEST_PEAK", "VALLEY", "FLAT_AREA"]

static func validate(raw: Variant, fallback: Dictionary) -> Dictionary:
	if not (raw is Dictionary):
		return _fallback("proposal_not_object", fallback)
	var proposal: Dictionary = raw
	var result: Dictionary = _validate(proposal)
	if result["outcome"] == OUTCOME_ACCEPTED:
		return result
	return _fallback(String(result["reason"]), fallback)

static func _validate(proposal: Dictionary) -> Dictionary:
	if proposal.get("schema_version") != SCHEMA_VERSION:
		return _reject("unsupported_schema_version")
	for key: String in ["directive_id", "builder_version", "tuning_version", "resource_set_version"]:
		if not _bounded_text(proposal.get(key), MAX_VERSION_LENGTH):
			return _reject("invalid_%s" % key)
	if not (proposal.get("directive_revision") is int) or int(proposal["directive_revision"]) < 1:
		return _reject("invalid_directive_revision")
	if not VALID_BIOMES.has(proposal.get("biome")) or not VALID_THEMES.has(proposal.get("theme")):
		return _reject("unsupported_vocabulary")
	if not _bounded_tags(proposal.get("palette_tags"), VALID_PALETTE_TAGS):
		return _reject("invalid_palette_tags")
	if not _bounded_tags(proposal.get("atmosphere_tags"), VALID_ATMOSPHERE_TAGS):
		return _reject("invalid_atmosphere_tags")
	for key: String in ["density_band", "threat_band"]:
		if not (proposal.get(key) is int) or int(proposal[key]) < 0 or int(proposal[key]) > 3:
			return _reject("invalid_%s" % key)
	if not _bounded_pois(proposal.get("poi_requirements")):
		return _reject("invalid_poi_requirements")
	if not _bounded_text(proposal.get("narrative", ""), MAX_TEXT_LENGTH):
		return _reject("invalid_narrative")
	if not _bounded_refs(proposal.get("context_refs", [])):
		return _reject("invalid_context_refs")
	return {
		"outcome": OUTCOME_ACCEPTED,
		"directive": {
			"schema_version": SCHEMA_VERSION,
			"directive_id": proposal["directive_id"],
			"directive_revision": proposal["directive_revision"],
			"builder_version": proposal["builder_version"],
			"tuning_version": proposal["tuning_version"],
			"resource_set_version": proposal["resource_set_version"],
			"biome": proposal["biome"],
			"theme": proposal["theme"],
			"palette_tags": proposal["palette_tags"].duplicate(),
			"atmosphere_tags": proposal["atmosphere_tags"].duplicate(),
			"density_band": proposal["density_band"],
			"threat_band": proposal["threat_band"],
			"poi_requirements": proposal["poi_requirements"].duplicate(true),
			"narrative": proposal.get("narrative", ""),
			"context_refs": proposal.get("context_refs", []).duplicate(),
		},
	}

static func _bounded_text(value: Variant, maximum: int) -> bool:
	return value is String and not String(value).strip_edges().is_empty() and String(value).length() <= maximum

static func _bounded_tags(value: Variant, vocabulary: Array[String]) -> bool:
	if not (value is Array) or value.is_empty() or value.size() > MAX_LIST_ITEMS:
		return false
	for tag: Variant in value:
		if not (tag is String) or not vocabulary.has(tag):
			return false
	return true

static func _bounded_pois(value: Variant) -> bool:
	if not (value is Array) or value.size() > MAX_LIST_ITEMS:
		return false
	for item: Variant in value:
		if not (item is Dictionary) or not _bounded_text(item.get("poi_id"), 64) or not VALID_POI_PREDICATES.has(item.get("predicate")):
			return false
	return true

static func _bounded_refs(value: Variant) -> bool:
	if not (value is Array) or value.size() > MAX_LIST_ITEMS:
		return false
	for item: Variant in value:
		if not _bounded_text(item, 64):
			return false
	return true

static func _reject(reason: String) -> Dictionary:
	return {"outcome": OUTCOME_REJECTED, "reason": reason}

static func _fallback(reason: String, fallback: Dictionary) -> Dictionary:
	return {"outcome": OUTCOME_FALLBACK, "reason": reason, "directive": fallback.duplicate(true)}