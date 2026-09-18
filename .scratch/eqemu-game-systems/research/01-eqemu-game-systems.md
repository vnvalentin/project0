# EQEmu game-systems research for Project0

Governing issue: [Research EQEmu game systems for Project0 inspiration](https://github.com/vnvalentin/project0/issues/299)

## Executive summary

EQEmu's strongest lesson is structural, not visual: keep reusable definitions
separate from owned mutable instances, route every inventory and loot mutation
through server authority, express content as data plus bounded event handlers,
and give operators explicit reload and inspection controls.

Project0 should preserve those ideas while rejecting EQEmu's legacy-specific
slot numbering, broad mutable script globals, monolithic item schema, and any
assumption that EQEmu contains the proprietary EverQuest client UI. UI ideas
below are Project0 inferences from server-visible actions, not copied screens.

## Environment inspected

| Checkout | Revision | Role |
| --- | --- | --- |
| `/opt/eqContained` | `dae07ca655cee519b7e5e051ca47f93a362427b3` | AkkStack deployment environment |
| `/opt/eqContained/code` | `b65cf4c0810ce16fc285774fdb3351d79cad1600` | EQEmu server |
| `/opt/eqContained/server/quests` | `edc2d7f082d86c4e66845ca5fbcd6551637e959a` | ProjectEQ quest content |
| `/opt/eqContained/data/peq-editor` | `fc80011c99f53a49c41a323c6969c3b946fa356f` | PEQ content editor |

No separate PEQ database source checkout was present. Generated repository
contracts in the server source were therefore used as schema evidence.

## Items, instances, inventory, and loot

**Fact:** EQEmu separates the reusable `ItemData` definition from
`ItemInstance`. Definitions include container capacity, maximum charges,
augment sockets, attunement, stackability, and click/proc/worn effects
([item_data.h](https://github.com/EQEmu/Server/blob/b65cf4c0810ce16fc285774fdb3351d79cad1600/common/item_data.h#L356-L495)).
An instance owns mutable charges, attunement, contained items, and custom data
([item_instance.h](https://github.com/EQEmu/Server/blob/b65cf4c0810ce16fc285774fdb3351d79cad1600/common/item_instance.h#L123-L169),
[item_instance.h](https://github.com/EQEmu/Server/blob/b65cf4c0810ce16fc285774fdb3351d79cad1600/common/item_instance.h#L288-L318)).

**Fact:** Client move and loot packets enter zone-server handlers; item swaps,
container-fit checks, automatic placement, and persistence happen server-side
([client_packet.cpp](https://github.com/EQEmu/Server/blob/b65cf4c0810ce16fc285774fdb3351d79cad1600/zone/client_packet.cpp#L9516-L10089),
[inventory.cpp](https://github.com/EQEmu/Server/blob/b65cf4c0810ce16fc285774fdb3351d79cad1600/zone/inventory.cpp#L1033-L1241),
[inventory.cpp](https://github.com/EQEmu/Server/blob/b65cf4c0810ce16fc285774fdb3351d79cad1600/zone/inventory.cpp#L1540-L2019)).

**Fact:** Loot is composed rather than embedded directly in an NPC: an NPC
references a loot table, table entries reference loot drops, and drop entries
carry selection constraints. The contracts include probability, multiplier,
minimum drops, level bounds, and content flags
([base_loottable_entries_repository.h](https://github.com/EQEmu/Server/blob/b65cf4c0810ce16fc285774fdb3351d79cad1600/common/repositories/base/base_loottable_entries_repository.h#L20-L83),
[base_lootdrop_entries_repository.h](https://github.com/EQEmu/Server/blob/b65cf4c0810ce16fc285774fdb3351d79cad1600/common/repositories/base/base_lootdrop_entries_repository.h#L20-L120),
[npc.cpp](https://github.com/EQEmu/Server/blob/b65cf4c0810ce16fc285774fdb3351d79cad1600/zone/npc.cpp#L240-L260)).

**Inference for Project0:** retain a small `ItemDefinition` / `ItemInstance`
split and composable loot profiles, but model ownership and transfers as
auditable server transactions tied to Character and Canon revisions. Keep the
already-decided 14 fixed slots, free swapping, default tradeability, no
degradation, and item/class proficiency. Do not import EQEmu's expansion,
class, race, deity, or legacy slot constraints.

## Equipment, inventory, and loot experience

**Fact:** The server contracts expose the player actions the interface must
support: inspect an item, move or swap it, fit it into a container, equip or
unequip it, loot it into a valid destination, fall back to a cursor-like
holding position, and receive a rejection when validation fails. EQEmu itself
does not provide the proprietary EverQuest client UI.

**Inference for Project0:** use one coherent equipment-and-pack workspace with
fixed body slots, clear item comparison, visible proficiency/effective-effect
changes, and a nearby-loot surface that supports deliberate take and bounded
take-all. Optimistic drag feedback may be local, but ownership, fit, equip,
binding, and reward truth must reconcile to a server result. Rejections should
name the actionable reason without exposing hidden authoritative state.

## Quests and content maintenance

**Fact:** EQEmu dispatches typed NPC, Player, and Item events to both Perl and
Lua quest interfaces. Events cover speech, trade, loot, task lifecycle, item
clicks, equip/unequip, death, and zone entry
([event_codes.h](https://github.com/EQEmu/Server/blob/b65cf4c0810ce16fc285774fdb3351d79cad1600/zone/event_codes.h#L5-L64),
[lua_parser.cpp](https://github.com/EQEmu/Server/blob/b65cf4c0810ce16fc285774fdb3351d79cad1600/zone/lua_parser.cpp#L153-L219),
[lua_parser.cpp](https://github.com/EQEmu/Server/blob/b65cf4c0810ce16fc285774fdb3351d79cad1600/zone/lua_parser.cpp#L249-L458)).

**Fact:** Quest APIs can award items and experience, assign tasks, advance
activities, set timers, and store scoped globals or data buckets
([lua_client.cpp](https://github.com/EQEmu/Server/blob/b65cf4c0810ce16fc285774fdb3351d79cad1600/zone/lua_client.cpp#L928-L970),
[lua_client.cpp](https://github.com/EQEmu/Server/blob/b65cf4c0810ce16fc285774fdb3351d79cad1600/zone/lua_client.cpp#L1363-L1390),
[lua_general.cpp](https://github.com/EQEmu/Server/blob/b65cf4c0810ce16fc285774fdb3351d79cad1600/zone/lua_general.cpp#L885-L901)).
The inspected ProjectEQ checkout contains thousands of zone-scoped Lua and
Perl scripts plus global NPC, Player, and Item handlers. A representative Lua
quest combines dialogue, item turn-in, persistent flags, and return of
unaccepted items
([Aprilia Marrow quest](https://github.com/ProjectEQ/projecteqquests/blob/edc2d7f082d86c4e66845ca5fbcd6551637e959a/abysmal/%23Aprilia_Marrow.lua#L1-L38)).

**Fact:** Quest code can be reloaded locally or across zones, with configurable
timer reset and repopulation behavior
([quest_parser_collection.cpp](https://github.com/EQEmu/Server/blob/b65cf4c0810ce16fc285774fdb3351d79cad1600/zone/quest_parser_collection.cpp#L72-L87),
[zone_reload.cpp](https://github.com/EQEmu/Server/blob/b65cf4c0810ce16fc285774fdb3351d79cad1600/zone/zone_reload.cpp#L24-L43),
[console.cpp](https://github.com/EQEmu/Server/blob/b65cf4c0810ce16fc285774fdb3351d79cad1600/world/console.cpp#L864-L924)).
The PEQ editor has dedicated item, loot, NPC, merchant, quest, recipe, and task
modules in the inspected checkout.

**Inference for Project0:** adopt event-driven quest reactions and an explicit
authoring/reload workflow, but make quest definitions versioned, validated
content. Persistent progress should use typed `QuestState` and atomic Canon
mutations, not freely named globals. Scripts, if introduced at all, request
bounded commands; they do not directly award trusted outcomes or mutate Canon.
LLM-generated quest proposals remain provisional until schema validation and
canonicalization.

## Backend and operational lessons

**Fact:** EQEmu separates login, world coordination, zone simulation,
query/telemetry, and chat into distinct process directories. Shared database
and repository code supports those runtimes, while zone processes own live
gameplay and quest execution. This is useful evidence for ownership boundaries,
not a requirement that Project0 duplicate the process topology.

**Inference for Project0:** keep one authoritative gameplay boundary until
measured load or isolation needs justify another process. Separate modules and
contracts now: identity/session, Character inventory, loot resolution, quest
runtime, Canon persistence, content registry, and operator controls. Versioned
content bundles need validation, compatibility checks, staged activation,
rollback, audit records, and bounded hot reload behavior.

## Preserve, adapt, reject

| Preserve | Adapt | Reject |
| --- | --- | --- |
| Definition/instance separation | Composable loot tables into versioned loot profiles | EQ-specific class/race/deity and expansion gates |
| Server-owned move/equip/loot validation | Event-driven quests into typed commands and state transitions | Client-authored inventory or reward outcomes |
| Zone/content organization | Hot reload into staged, validated content activation | Unbounded mutable quest globals |
| Explicit authoring tools | Cursor fallback into a clear pending-placement state, if needed | Copying proprietary EverQuest UI or assets |
| Operator reload/inspection controls | Service separation into deep modules first, processes only when justified | A 200-column item record as Project0's domain model |

## Wayfinder frontiers

### Item Ownership and Loot Lifecycle

Destination: an implementation-ready specification for item definitions,
owned instances, inventory topology, loot profiles, acquisition, transfer, and
atomic persistence under server authority.

First decisions: Project0 item-instance domain model; ownership and transfer
transaction; loot-source/profile/corpse lifecycle. Fog: stack/container policy,
overflow, trading, merchants, crafting, unique-item policy, and generated loot.

### Equipment, Inventory, and Loot Experience

Destination: a validated interaction and read-model specification for managing
fixed equipment slots, carried items, comparison, proficiency effects, and
loot across desktop and controller input.

First decisions: low-fidelity workflow prototype; information disclosure and
comparison; authoritative reconciliation and rejection feedback. Fog:
accessibility, controller focus, responsive layout, batch actions, and eventual
merchant/crafting surfaces.

### Quest Content and Runtime

Destination: an implementation-ready quest domain, authoring format, runtime
event/command contract, persistent progress model, reward transaction, and
player-facing journal/dialogue flow.

First decisions: Quest/Objective/Event/Reward/QuestState vocabulary; authored
data versus bounded script policy; Canon state and reward transaction;
low-fidelity player flow. Fog: branching, party credit, repeatability,
failure/abandonment, generated quests, localization, and migration.

### Game Content Operations and Backend Boundaries

Destination: an operational specification for validating, versioning,
activating, observing, rolling back, and editing item/loot/quest content without
weakening gameplay authority or availability.

First decisions: content bundle and ownership boundary; compatibility and
activation lifecycle; operator observability/control surface. Fog: process
splits, editor scope, approvals, staging environments, audit retention, and
live migration.

## Cross-frontier constraints

- Item Ownership and Loot Lifecycle supplies domain contracts to the UX and
  quest-reward maps.
- Quest Content and Runtime supplies executable content contracts to Content
  Operations.
- UX prototypes may start immediately against fake read models, but final
  reconciliation decisions wait for the item ownership contract.
- No frontier changes the fixed equipment decisions or Project0's server,
  Character, vessel, proficiency, Canon, and LLM authority laws.
