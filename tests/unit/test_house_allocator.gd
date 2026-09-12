extends GutTest
## Public-seam unit tests for Slice 019's house allocator
## (server/house_allocator.gd). Pure and SceneTree-independent — builds the
## allocator from plain house-id arrays (and once from the real hub fixture)
## and asserts assign/release/idempotency/fail-closed behavior. See
## docs/slices/019-player-house-allocation.md.

const HouseAllocatorScript: Script = preload("res://server/house_allocator.gd")
const StartingTownHubFixtureScript: Script = preload("res://server/starting_town_hub_fixture.gd")


func _allocator(count: int) -> Object:
	var ids: Array[String] = []
	for i in count:
		ids.append("house_%02d" % (i + 1))
	return HouseAllocatorScript.new(ids)


func test_house_ids_from_hub_fixture_extracts_the_ten_houses() -> void:
	var ids: Array[String] = HouseAllocatorScript.house_ids_from_blueprint(StartingTownHubFixtureScript.blueprint())
	assert_eq(ids.size(), 10, "the hub fixture yields exactly 10 house ids")
	var unique: Dictionary = {}
	for house_id: String in ids:
		unique[house_id] = true
	assert_eq(unique.size(), 10, "all extracted house ids are unique")


func test_assign_gives_distinct_houses_to_distinct_peers() -> void:
	var allocator: Object = _allocator(10)
	var first: String = allocator.assign(101)
	var second: String = allocator.assign(102)
	assert_ne(first, "", "the first peer gets a house")
	assert_ne(second, "", "the second peer gets a house")
	assert_ne(first, second, "distinct peers receive distinct houses")


func test_assign_is_idempotent_per_peer() -> void:
	var allocator: Object = _allocator(10)
	var first: String = allocator.assign(101)
	var again: String = allocator.assign(101)
	assert_eq(again, first, "assigning the same peer twice returns the same house")
	assert_eq(allocator.available_count(), 9, "an idempotent re-assign does not consume a second slot")


func test_pool_exhaustion_returns_empty_string() -> void:
	var allocator: Object = _allocator(2)
	assert_ne(allocator.assign(1), "", "first of two houses assigns")
	assert_ne(allocator.assign(2), "", "second of two houses assigns")
	assert_eq(allocator.assign(3), "", "a third peer against a 2-house pool gets '' (fail closed)")
	assert_eq(allocator.available_count(), 0, "the pool reports zero available when exhausted")


func test_release_frees_the_slot_for_first_available_reuse() -> void:
	var allocator: Object = _allocator(3)
	var a: String = allocator.assign(1)
	allocator.assign(2)
	allocator.assign(3)
	assert_eq(allocator.available_count(), 0, "all three houses are taken")

	allocator.release(1)
	assert_eq(allocator.available_count(), 1, "releasing a peer frees exactly one slot")
	var reused: String = allocator.assign(4)
	assert_eq(reused, a, "the next peer reuses the just-freed house (first-available)")


func test_release_of_unassigned_peer_is_a_noop() -> void:
	var allocator: Object = _allocator(3)
	allocator.assign(1)
	allocator.release(999)
	assert_eq(allocator.available_count(), 2, "releasing a peer that holds no house changes nothing")


func test_assigned_house_lookup() -> void:
	var allocator: Object = _allocator(3)
	var a: String = allocator.assign(1)
	assert_eq(allocator.assigned_house(1), a, "assigned_house returns the peer's current house")
	assert_eq(allocator.assigned_house(2), "", "assigned_house returns '' for an unassigned peer")
