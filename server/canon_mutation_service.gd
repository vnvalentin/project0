extends RefCounted
class_name CanonMutationService
## Slice 096 (P-013): server-only resolver that turns an authenticated caller's
## untrusted CanonMutationIntent into a server-owned CanonMutationEvent and
## applies it through the Slice 050 CanonMutationRepository. The server — never
## the client — stamps the actor, the event identity, and the tick:
##
##  - actor_player_id comes from the authenticated Player (the caller passes it;
##    the intent itself may not carry one, enforced by CanonMutationIntent);
##  - event_id is a deterministic function of (actor, client_seq), so a
##    retransmitted intent is idempotent and two actors never collide;
##  - server_tick comes from the injected authoritative clock.
##
## Server-only per CLAUDE.md: shared/ and client/ never reference this class or
## the repository/store it drives.

const CanonMutationIntentScript: Script = preload("res://shared/canon_mutation_intent.gd")

const MAX_ACTOR_LENGTH: int = 128

const STATUS_ACCEPTED: String = "accepted"
const STATUS_REJECTED: String = "rejected"

const REASON_INVALID_ACTOR: String = "invalid_actor"
const REASON_INVALID_INTENT: String = "invalid_intent"

## Mutation-event schema the repository expects (Slice 050).
const _EVENT_SCHEMA_VERSION: int = 1

var _mutations: CanonMutationRepository = null
var _clock: Callable = Callable()


## clock is a Callable returning the authoritative server tick as an int.
func _init(mutations: CanonMutationRepository, clock: Callable) -> void:
	_mutations = mutations
	_clock = clock


## Resolves one intent from an authenticated actor into an accepted/rejected
## resolution. No partial side effect on any rejection.
func resolve_intent(actor_player_id: String, raw_intent: Variant) -> Dictionary:
	if actor_player_id.is_empty() or actor_player_id.length() > MAX_ACTOR_LENGTH:
		return _rejected(REASON_INVALID_ACTOR, -1, "")

	var parsed: Dictionary = CanonMutationIntentScript.parse(raw_intent)
	if parsed["outcome"] != CanonMutationIntentScript.OUTCOME_OK:
		return _rejected(REASON_INVALID_INTENT, _seq_of(raw_intent), "")
	var intent: Dictionary = parsed["intent"]
	var client_seq: int = intent["client_seq"]

	var event_id: String = _event_id(actor_player_id, client_seq)
	var event: Dictionary = {
		"schema_version": _EVENT_SCHEMA_VERSION,
		"event_id": event_id,
		"sector_id": intent["sector_id"],
		"target_guid": intent["target_guid"],
		"mutation_kind": intent["mutation_kind"],
		"actor_player_id": actor_player_id,
		"server_tick": int(_clock.call()),
		"expected_revision": intent["expected_revision"],
		"payload": intent["payload"],
	}

	var result: Dictionary = _mutations.apply_mutation(event)
	var outcome: String = result["outcome"]
	if outcome == CanonMutationRepository.OUTCOME_OK or outcome == CanonMutationRepository.OUTCOME_IDEMPOTENT:
		return {
			"status": STATUS_ACCEPTED,
			"reason": outcome,
			"applied_revision": int(result.get("applied_revision", -1)),
			"client_seq": client_seq,
			"event_id": event_id,
		}
	return {
		"status": STATUS_REJECTED,
		"reason": outcome,
		"applied_revision": int(result.get("applied_revision", result.get("current_revision", -1))),
		"client_seq": client_seq,
		"event_id": event_id,
	}


## Deterministic, bounded server-owned idempotency key. Distinct actors with the
## same client_seq never collide because the actor is hashed in.
func _event_id(actor_player_id: String, client_seq: int) -> String:
	var canonical: String = "%s\u0001%d" % [actor_player_id, client_seq]
	return "mut-%s" % canonical.sha256_text().substr(0, 32)


## Best-effort client_seq extraction for a rejection detail; -1 when unavailable.
func _seq_of(raw_intent: Variant) -> int:
	if raw_intent is Dictionary and (raw_intent as Dictionary).get("client_seq") is int:
		return int((raw_intent as Dictionary)["client_seq"])
	return -1


func _rejected(reason: String, client_seq: int, event_id: String) -> Dictionary:
	return {
		"status": STATUS_REJECTED,
		"reason": reason,
		"applied_revision": -1,
		"client_seq": client_seq,
		"event_id": event_id,
	}
