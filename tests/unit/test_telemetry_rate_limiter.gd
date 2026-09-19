extends GutTest
## Slice 161 (telemetry map #282, decision #284): the server-side per-peer
## telemetry rate-limiting contract (server/telemetry_rate_limiter.gd). See
## docs/slices/161-telemetry-transport-contracts.md.

const TelemetryRateLimiterScript: Script = preload("res://server/telemetry_rate_limiter.gd")


func test_a_batch_within_capacity_is_admitted() -> void:
	var limiter: TelemetryRateLimiter = TelemetryRateLimiterScript.new()
	assert_true(limiter.try_consume(7, 10, 1000.0))
	assert_eq(limiter.rate_limited_count(7), 0)


func test_a_batch_exceeding_capacity_is_rejected_and_counted() -> void:
	var limiter: TelemetryRateLimiter = TelemetryRateLimiterScript.new()
	var over_capacity: int = int(TelemetryRateLimiterScript.CAPACITY) + 1
	assert_false(limiter.try_consume(7, over_capacity, 1000.0))
	assert_eq(limiter.rate_limited_count(7), 1)


func test_a_rejected_batch_deducts_no_tokens() -> void:
	var limiter: TelemetryRateLimiter = TelemetryRateLimiterScript.new()
	var over_capacity: int = int(TelemetryRateLimiterScript.CAPACITY) + 1
	limiter.try_consume(7, over_capacity, 1000.0)
	# A small follow-up batch still succeeds — the rejected batch left the
	# bucket untouched rather than partially draining it.
	assert_true(limiter.try_consume(7, 1, 1000.0))


func test_repeated_full_capacity_batches_exhaust_the_bucket() -> void:
	var limiter: TelemetryRateLimiter = TelemetryRateLimiterScript.new()
	var capacity: int = int(TelemetryRateLimiterScript.CAPACITY)
	assert_true(limiter.try_consume(7, capacity, 1000.0), "the first full-capacity batch is admitted")
	assert_false(limiter.try_consume(7, 1, 1000.0), "no tokens remain immediately after")
	assert_eq(limiter.rate_limited_count(7), 1)


func test_tokens_refill_over_time() -> void:
	var limiter: TelemetryRateLimiter = TelemetryRateLimiterScript.new()
	var capacity: int = int(TelemetryRateLimiterScript.CAPACITY)
	limiter.try_consume(7, capacity, 1000.0)
	assert_false(limiter.try_consume(7, 1, 1000.0), "no refill has happened yet")

	var refill_seconds: float = 1.0 / TelemetryRateLimiterScript.REFILL_PER_SECOND
	assert_true(limiter.try_consume(7, 1, 1000.0 + refill_seconds), "one token has refilled after the refill interval")


func test_refill_never_exceeds_capacity() -> void:
	var limiter: TelemetryRateLimiter = TelemetryRateLimiterScript.new()
	limiter.try_consume(7, 1, 1000.0)
	# A very long idle gap must not let the bucket overflow past capacity.
	var capacity: int = int(TelemetryRateLimiterScript.CAPACITY)
	assert_true(limiter.try_consume(7, capacity, 1000.0 + 100000.0))
	assert_false(limiter.try_consume(7, 1, 1000.0 + 100000.0), "capacity was not exceeded by the long idle gap")


func test_different_peers_have_independent_buckets() -> void:
	var limiter: TelemetryRateLimiter = TelemetryRateLimiterScript.new()
	var capacity: int = int(TelemetryRateLimiterScript.CAPACITY)
	limiter.try_consume(1, capacity, 1000.0)
	assert_true(limiter.try_consume(2, capacity, 1000.0), "peer 2's bucket is unaffected by peer 1's consumption")


func test_forget_peer_clears_bucket_and_rejection_count() -> void:
	var limiter: TelemetryRateLimiter = TelemetryRateLimiterScript.new()
	var over_capacity: int = int(TelemetryRateLimiterScript.CAPACITY) + 1
	limiter.try_consume(7, over_capacity, 1000.0)
	assert_eq(limiter.rate_limited_count(7), 1)

	limiter.forget_peer(7)
	assert_eq(limiter.rate_limited_count(7), 0, "forgetting the peer resets its rejection count")
	assert_true(limiter.try_consume(7, int(TelemetryRateLimiterScript.CAPACITY), 1000.0), "forgetting the peer resets it to a fresh full bucket")
