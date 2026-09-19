extends GutTest
## Slice 161 (telemetry map #282, decision #284): the client-side telemetry
## batching contract (client/telemetry_batch_queue.gd). See
## docs/slices/161-telemetry-transport-contracts.md.

const TelemetryBatchQueueScript: Script = preload("res://client/telemetry_batch_queue.gd")


func test_new_queue_has_nothing_pending() -> void:
	var queue: TelemetryBatchQueue = TelemetryBatchQueueScript.new(0)
	assert_eq(queue.pending_count(), 0)
	assert_false(queue.should_flush(1000), "an empty queue never flushes, however much time passed")


func test_enqueue_increments_pending_count() -> void:
	var queue: TelemetryBatchQueue = TelemetryBatchQueueScript.new(0)
	queue.enqueue({"event_type": "a"})
	queue.enqueue({"event_type": "b"})
	assert_eq(queue.pending_count(), 2)


func test_should_flush_false_before_interval_elapses() -> void:
	var queue: TelemetryBatchQueue = TelemetryBatchQueueScript.new(0)
	queue.enqueue({"event_type": "a"})
	assert_false(queue.should_flush(TelemetryBatchQueueScript.FLUSH_INTERVAL_MSEC - 1))


func test_should_flush_true_once_interval_elapses_with_pending_events() -> void:
	var queue: TelemetryBatchQueue = TelemetryBatchQueueScript.new(0)
	queue.enqueue({"event_type": "a"})
	assert_true(queue.should_flush(TelemetryBatchQueueScript.FLUSH_INTERVAL_MSEC))


func test_take_batch_drains_and_returns_pending_events() -> void:
	var queue: TelemetryBatchQueue = TelemetryBatchQueueScript.new(0)
	queue.enqueue({"event_type": "a"})
	queue.enqueue({"event_type": "b"})
	var batch: Array[Dictionary] = queue.take_batch(300)
	assert_eq(batch.size(), 2)
	assert_eq(queue.pending_count(), 0, "the queue is empty after draining")


func test_take_batch_resets_the_flush_clock() -> void:
	var queue: TelemetryBatchQueue = TelemetryBatchQueueScript.new(0)
	queue.enqueue({"event_type": "a"})
	queue.take_batch(300)
	queue.enqueue({"event_type": "b"})
	assert_false(queue.should_flush(300 + TelemetryBatchQueueScript.FLUSH_INTERVAL_MSEC - 1), "clock restarted from the last take_batch() call")
	assert_true(queue.should_flush(300 + TelemetryBatchQueueScript.FLUSH_INTERVAL_MSEC))
