# MMO Party Membership, Reward, and Cooperation Models

Research for [#320](https://github.com/vnvalentin/project0/issues/320), governed
by [#319, the Party Coordination and Shared Encounter Design
Map](https://github.com/vnvalentin/project0/issues/319).

## Scope and evidence labels

This note compares Party lifecycle, eligibility, rewards, coordination, and
read models. It is research, not an implementation design or balance contract.

- **Fact:** directly supported by a cited primary source.
- **Unknown:** the inspected source does not establish the behavior.
- **Project0 Inference:** a bounded conclusion for later map decisions, derived
  from facts plus Project0's accepted constraints. It is not an external fact.

No client assets or screenshots are reproduced. Exact formulas remain source
facts only where needed to understand precedent; this note does not select a
Project0 formula.

## Governing Project0 constraints

**Fact (Project0):** [#319](https://github.com/vnvalentin/project0/issues/319)
settles a Party cap of five Characters; durable Party identity distinct from
roster and live Player sessions; leader-managed invitations and removals;
member leave; disconnect grace and leader succession; active participation plus
bounded proximity for shared eligibility; and no conventional XP pool.

**Fact (Project0):** [CONTEXT.md](../../../../CONTEXT.md) distinguishes the
persistent Character from its in-world Player and makes Character state
server-owned. [ADR 0002](../../../../docs/adr/0002-authoritative-mechanics-and-progression.md)
and the [systems specification](../../../../docs/SYSTEMS-SPECIFICATION.md) make
the server authoritative for action outcomes and progression evidence; clients
submit intent and render replicated results.

**Fact (Project0):** [ADR 0007](../../../../docs/adr/0007-unified-character-and-npc-generalization.md)
says mastered Characters may teach a willing learner the practice sequence,
not stats or mastery. Failure teaches, but proficiency and mastery are
Character-specific.

**Project0 Inference:** Party membership may broaden encounter, quest, and loot
eligibility, but it must never copy one Character's embodied training evidence
to an idle member. Opt-out observation may unlock or begin basics only;
personal practice remains necessary for proficiency and mastery. Coordination
history may belong to the durable Party while combined-technique readiness must
remain roster-aware.

## Source and revision inventory

| System | Primary source | Revision or retrieval identity |
| --- | --- | --- |
| EQEmu | [EQEmu/Server](https://github.com/EQEmu/Server) inspected directly at `/opt/eqContained/code` over `ssh -o BatchMode=yes okami` | `b65cf4c0810ce16fc285774fdb3351d79cad1600`; `origin` verified as `https://github.com/EQEmu/Server.git` |
| Guild Wars 2 | ArenaNet-hosted official wiki: [Party](https://wiki.guildwars2.com/index.php?title=Party&oldid=2872026), [Squad](https://wiki.guildwars2.com/index.php?title=Squad&oldid=3187588), [Loot](https://wiki.guildwars2.com/index.php?title=Loot&oldid=3137934), [Dynamic level adjustment](https://wiki.guildwars2.com/index.php?title=Dynamic_level_adjustment&oldid=3190391) | Permanent wiki revisions shown in each link |
| Final Fantasy XIV | Square Enix official UI Guide pages linked below | Live official pages retrieved 2026-09-18; no immutable revision URL exposed |
| AzerothCore | [azerothcore/azerothcore-wotlk](https://github.com/azerothcore/azerothcore-wotlk) | `24adf9bfed23f490f1fe46549e579cf3e4b82f80`, resolved from repository HEAD during research |
| Project0 | Issues #319-#325, local context, systems specification, ADR 0002, ADR 0007 | Worktree HEAD `d24b0d22cb32ee2653784b7d08b4efdc60cb59d1` |

The Guild Wars 2 wiki is hosted and linked by ArenaNet and identifies ArenaNet
in its footer. Claims below avoid entries marked by that wiki as needing
verification. Square Enix pages are first-party but mutable, so their lack of
revision pinning is a limitation.

## EQEmu at the pinned revision

### Identity, capacity, and state

**Fact:** EQEmu represents a group with a numeric group ID, a leader pointer,
six member pointers, six member names, and member roles. Member names remain in
the array when a member is outside the zone; only members in the current zone
have non-null `Mob*` pointers. See
[`groups.cpp` lines 32-64](https://github.com/EQEmu/Server/blob/b65cf4c0810ce16fc285774fdb3351d79cad1600/zone/groups.cpp#L32-L64)
and
[`groups.h` lines 35-52 and 158-179](https://github.com/EQEmu/Server/blob/b65cf4c0810ce16fc285774fdb3351d79cad1600/zone/groups.h#L35-L52).
The arrays and all capacity loops use `MAX_GROUP_MEMBERS`; the client protocol
defines that constant as six, for example in
[`rof2_structs.h` lines 130-136](https://github.com/EQEmu/Server/blob/b65cf4c0810ce16fc285774fdb3351d79cad1600/common/patches/rof2_structs.h#L130-L136).

**Fact:** a new runtime group starts with the leader in slot zero. A group
reconstructed from an existing ID loads members from the database. See
[`groups.cpp` lines 41-103](https://github.com/EQEmu/Server/blob/b65cf4c0810ce16fc285774fdb3351d79cad1600/zone/groups.cpp#L41-L103).
At client entry, EQEmu reads the Character's group ID, reuses an in-zone group
or constructs one from that ID, and clears the Character's group ID if
reconstruction fails. It also restores leader, role, marker, leadership-AA,
and mentor metadata. See
[`client_packet.cpp` lines 1497-1555](https://github.com/EQEmu/Server/blob/b65cf4c0810ce16fc285774fdb3351d79cad1600/zone/client_packet.cpp#L1497-L1555).

**Fact:** database queries map member name to group ID and persist leader and
leadership metadata in `group_id` and `group_leaders`. See
[`database.cpp` lines 1600-1669](https://github.com/EQEmu/Server/blob/b65cf4c0810ce16fc285774fdb3351d79cad1600/common/database.cpp#L1600-L1669).

**Project0 Inference:** EQEmu demonstrates that roster identity can survive
zone-local entity absence, but its group ID is still coupled to current
membership. Project0's settled durable Party identity must be modeled as more
than a reconstructed transient roster.

### Invite, accept, membership, leave, kick, disband, and leader

**Fact:** invite packets are validated for packet size and self-invite. A local
eligible invitee receives a server-forwarded invite packet; a remote-zone
invite is forwarded through the world server. See
[`client_packet.cpp` lines 6940-7001](https://github.com/EQEmu/Server/blob/b65cf4c0810ce16fc285774fdb3351d79cad1600/zone/client_packet.cpp#L6940-L7001).

**Fact:** acceptance is the `GroupFollow` path. It validates packet size,
handles a same-zone inviter locally, and routes an out-of-zone acceptance
through the world server. See
[`client_packet.cpp` lines 6892-6937](https://github.com/EQEmu/Server/blob/b65cf4c0810ce16fc285774fdb3351d79cad1600/zone/client_packet.cpp#L6892-L6937).

**Unknown:** the inspected EQEmu handlers do not expose a distinct authoritative
decline mutation; not accepting is observable at the protocol/UI boundary, but
decline expiry and durable audit semantics are not established here.

**Fact:** `AddMember` rejects a full group and duplicate names, accepts either
an in-zone entity or out-of-zone identity, updates group packets and profile
member lists, marks in-zone members grouped, and persists the group ID. See
[`groups.cpp` lines 208-255](https://github.com/EQEmu/Server/blob/b65cf4c0810ce16fc285774fdb3351d79cad1600/zone/groups.cpp#L208-L255)
and
[`groups.cpp` lines 258-364](https://github.com/EQEmu/Server/blob/b65cf4c0810ce16fc285774fdb3351d79cad1600/zone/groups.cpp#L258-L364).

**Fact:** the disband handler enforces that only the leader may remove another
member; non-leaders remove themselves. Groups smaller than three are disbanded
when a member leaves. See
[`client_packet.cpp` lines 6775-6889](https://github.com/EQEmu/Server/blob/b65cf4c0810ce16fc285774fdb3351d79cad1600/zone/client_packet.cpp#L6775-L6889).

**Fact:** the ordinary `DelMember` path currently disbands the whole group when
the current leader leaves, despite later unreachable-looking leader-shuffle
code and a TODO for out-of-zone leader transfer. See
[`groups.cpp` lines 607-640](https://github.com/EQEmu/Server/blob/b65cf4c0810ce16fc285774fdb3351d79cad1600/zone/groups.cpp#L607-L640)
and
[`groups.cpp` lines 642-704](https://github.com/EQEmu/Server/blob/b65cf4c0810ce16fc285774fdb3351d79cad1600/zone/groups.cpp#L642-L704).
Explicit leader transfer is leader-authorized, updates the database, and
notifies members. See
[`client_packet.cpp` lines 7004-7022](https://github.com/EQEmu/Server/blob/b65cf4c0810ce16fc285774fdb3351d79cad1600/zone/client_packet.cpp#L7004-L7022)
and
[`groups.cpp` lines 2327-2357](https://github.com/EQEmu/Server/blob/b65cf4c0810ce16fc285774fdb3351d79cad1600/zone/groups.cpp#L2327-L2357).

**Fact:** full disband clears each member's persisted group ID, grouped state,
and runtime slot; informs clients and the world server; clears database group
records; and removes the leader. See
[`groups.cpp` lines 945-1015](https://github.com/EQEmu/Server/blob/b65cf4c0810ce16fc285774fdb3351d79cad1600/zone/groups.cpp#L945-L1015).

**Project0 Inference:** preserve explicit transition validation and server-side
leader checks. Reject EQEmu's effective leader-leave disband behavior for
Project0 because #319 requires reconnect grace and leader succession.

### Zoning and disconnect

**Fact:** EQEmu distinguishes zoning from logout. Zoning calls `MemberZoned`,
leaves the member name in the group, nulls zone-local presence, and announces
that the member left the zone. A non-zoning logout calls `LeaveGroup`. See
[`client_process.cpp` lines 620-671](https://github.com/EQEmu/Server/blob/b65cf4c0810ce16fc285774fdb3351d79cad1600/zone/client_process.cpp#L620-L671).
Client destruction also forces leave only when not zoning. See
[`client.cpp` lines 433-453](https://github.com/EQEmu/Server/blob/b65cf4c0810ce16fc285774fdb3351d79cad1600/zone/client.cpp#L433-L453).

**Fact:** a link-dead transition announces link-dead and removes the member;
hard disconnect and link-dead timeout also call `LeaveGroup`. See
[`client.cpp` lines 3385-3409](https://github.com/EQEmu/Server/blob/b65cf4c0810ce16fc285774fdb3351d79cad1600/zone/client.cpp#L3385-L3409)
and
[`client_process.cpp` lines 170-200 and 690-705](https://github.com/EQEmu/Server/blob/b65cf4c0810ce16fc285774fdb3351d79cad1600/zone/client_process.cpp#L170-L200).

**Fact:** group-wide zone moves iterate only current in-zone client pointers;
ordinary zone reconstruction later restores membership from the database. See
[`zoning.cpp` lines 529-541 and 576-588](https://github.com/EQEmu/Server/blob/b65cf4c0810ce16fc285774fdb3351d79cad1600/zone/zoning.cpp#L529-L541).

**Project0 Inference:** retain explicit member connection/presence state and
sector transition semantics. Do not equate a transport disconnect with consent
to leave; Project0 needs the grace state already settled by #319.

### `Group::SplitExp` and kill credit

**Fact:** `SplitExp` rejects merchants and client-owned NPCs. It counts only
non-null in-zone member pointers, finds the maximum member level, applies a
group-size modifier (including a distinct six-member value), rejects a gray
con target relative to the maximum level, divides the adjusted pool by the
in-zone member count, caps each award, and grants only to client members within
the allowed level difference. See
[`exp.cpp` lines 1014-1068](https://github.com/EQEmu/Server/blob/b65cf4c0810ce16fc285774fdb3351d79cad1600/zone/exp.cpp#L1014-L1068).

**Fact:** this function does not inspect position, contribution, or alive state.
Its effective same-zone constraint is structural: only members with non-null
zone-local pointers enter the count and award loops. Therefore this pinned
path supports same-zone and level eligibility, but not a proximity, alive, or
participation requirement.

**Fact:** the NPC death path attributes the kill through the top damage entry
or killer and resolves player ownership before selecting group or raid reward
handling. See
[`attack.cpp` lines 2262-2313](https://github.com/EQEmu/Server/blob/b65cf4c0810ce16fc285774fdb3351d79cad1600/zone/attack.cpp#L2262-L2313).

**Fact:** after grouped XP, every non-null in-zone client member receives
`EVENT_KILLED_MERIT`, optional merit-based faction handling, mod merit, and
task kill update. These loops do not independently test contribution,
distance, alive state, or level. See
[`attack.cpp` lines 2362-2409](https://github.com/EQEmu/Server/blob/b65cf4c0810ce16fc285774fdb3351d79cad1600/zone/attack.cpp#L2362-L2409).

**Unknown:** `EVENT_KILLED_MERIT` may drive quest scripts, but the inspected
group/death path does not prove which quests consume it or their own guards.
Task kill credit is directly verified; general quest credit remains unknown.

**Project0 Inference:** reject roster-only merit and task credit. Project0 has
no conventional XP, and membership cannot substitute for active,
server-observed participation plus bounded proximity. Level-weighted split
math is not transferable to embodied training evidence.

### Loot rights and messages

**Fact:** when a grouped client earns an NPC corpse, EQEmu puts every non-null
group member into the corpse's allowed-looter slots. See
[`attack.cpp` lines 2454-2499](https://github.com/EQEmu/Server/blob/b65cf4c0810ce16fc285774fdb3351d79cad1600/zone/attack.cpp#L2454-L2499).
`AllowPlayerLoot` stores Character IDs in a server-side allowlist, and
`CanPlayerLoot` checks that allowlist. See
[`corpse.cpp` lines 877-898](https://github.com/EQEmu/Server/blob/b65cf4c0810ce16fc285774fdb3351d79cad1600/zone/corpse.cpp#L877-L898).

**Fact:** after a successful non-player-corpse loot, the looter gets an item
message and other group members receive a group loot message naming the looter
and item. See
[`corpse.cpp` lines 1341-1363](https://github.com/EQEmu/Server/blob/b65cf4c0810ce16fc285774fdb3351d79cad1600/zone/corpse.cpp#L1341-L1363).

**Project0 Inference:** preserve explicit, authoritative encounter loot
eligibility and transparent allocation messages. Reject in-zone roster alone
as sufficient eligibility and defer allocation modes to the Item Ownership and
Loot Lifecycle map.

### Mentorship, coordination, and authority

**Fact:** EQEmu has a feature named group mentor. Its packet handler stores a
named mentoree and percentage; group state persists those fields and restores
them on entry. See
[`client_packet.cpp` lines 7025-7058](https://github.com/EQEmu/Server/blob/b65cf4c0810ce16fc285774fdb3351d79cad1600/zone/client_packet.cpp#L7025-L7058),
[`groups.cpp` lines 1971-1993](https://github.com/EQEmu/Server/blob/b65cf4c0810ce16fc285774fdb3351d79cad1600/zone/groups.cpp#L1971-L1993),
and
[`database.cpp` lines 1667-1723](https://github.com/EQEmu/Server/blob/b65cf4c0810ce16fc285774fdb3351d79cad1600/common/database.cpp#L1667-L1723).

**Unknown:** a pinned repository-wide search found setters, clearers,
persistence, and getters for `mentoree` and `mentor_percent`, but no consumer in
the inspected XP, task, technique, or skill progression paths. The name does
not establish observational learning, teaching, or evidence transfer.

**Unknown:** bounded searches for `combined technique`, `combined_technique`,
and coordination progression found no Party-level practiced-combination
system. This is not proof that no unrelated cooperative combat exists.

**Fact:** authority is split between zone server objects, world-server routing,
and database records. Clients submit invite, follow, disband, and leader-change
packets; server handlers validate and mutate group state; reward and corpse
code calculate outcomes and rights. The cited handler, group, XP, attack, and
corpse paths do not accept client-authored reward outcomes.

## Guild Wars 2 official model

**Fact:** a Party supports up to five players. Players may invite or join via
the panel, chat, LFG, or context menu; a player cannot be in two parties.
Members may leave, offline members are automatically removed, and kicking uses
a majority vote. The Party panel shows profession, level or mastery, health,
effects, and a distinct representation for members in another map instance.
See the permanent [Party revision](https://wiki.guildwars2.com/index.php?title=Party&oldid=2872026).

**Fact:** Party tools include called targets, shared map waypoints, compass
pings/drawing, and Party chat. Entering an instance prompts other members;
members attempt to join the same map instance and may use `Join In` when
capacity permits. See the same [Party
revision](https://wiki.guildwars2.com/index.php?title=Party&oldid=2872026).

**Fact:** Party membership does not itself multiply ordinary rewards. The
official wiki says solo and Party rewards are the same, while Party members
need less individual damage to tag an enemy when their Party or subgroup also
attacked. Personal loot remains unique per eligible participant. Supporting
actions can contribute to eligibility, but boon-aura support still requires
active attacking to discourage AFK reward collection. See the permanent
[Party revision](https://wiki.guildwars2.com/index.php?title=Party&oldid=2872026)
and [Loot revision](https://wiki.guildwars2.com/index.php?title=Loot&oldid=3137934).

**Fact:** dynamic level adjustment reduces effective level and attributes by
area to prevent high-level Characters trivializing enemies and depriving lower
level Characters of rewards. It retains skills/equipment and does not prove
teaching. See the permanent [Dynamic level adjustment
revision](https://wiki.guildwars2.com/index.php?title=Dynamic_level_adjustment&oldid=3190391).

**Fact:** squads are separate, larger transient formations: ten players, or
fifty when commander-created. Their read model includes same/different
instance, health, downed/defeated, offline, role and ready status. Commander
tools include markers, broadcasts, subgroup organization, and ready checks.
See the permanent [Squad revision](https://wiki.guildwars2.com/index.php?title=Squad&oldid=3187588).

**Fact:** WvW shared participation is an explicit exception, limited to one
recipient per five squad members and assigned by commander or lieutenant. It
replaces the recipient's own participation with squad-member activity; the
official page describes scouts as the normal use. This is reward delegation,
not mentorship. See the [Squad
revision](https://wiki.guildwars2.com/index.php?title=Squad&oldid=3187588).

**Unknown:** the inspected official pages do not establish a durable Party
identity, Party-level progression, observational learning, or practiced
combined-technique progression.

**Project0 Inference:** preserve the five-member scale, explicit remote/offline
read state, support actions as valid participation signals, personal loot
eligibility, and anti-idle requirement. Adapt target/marker/ready tools only if
later Party-map decisions require them. Reject broad shared participation as a
training precedent and reject automatic offline removal because Project0 has a
durable identity and grace period.

## Final Fantasy XIV official model

**Fact:** Square Enix documents direct Party invitation from a Character or
name in chat, friend, Free Company, or Linkshell lists. See [Inviting Players
to Party](https://na.finalfantasyxiv.com/uiguide/party/party-how/party_invite.html).
The accessible page does not specify accept/decline timing or invitation expiry.

**Fact:** only the leader can disband the Party; an individual member can
leave. See [Disbanding
Party](https://na.finalfantasyxiv.com/uiguide/party/party-how/party_dissolution.html).

**Fact:** an offline duty member remains represented long enough for the Party
to vote-dismiss them; after agreement, the leader may search for a replacement
when the duty was randomly matched. See [When Duty Becomes Difficult due to a
Party Member Going Offline](https://na.finalfantasyxiv.com/uiguide/party/party-how/party_dismiss.html).

**Fact:** ready check asks every Party or alliance member and reports all
statuses; a timeout is shown as not ready. See [How to Initiate a Ready
Check](https://na.finalfantasyxiv.com/uiguide/party/party-how/party_readycheck.html).
The Party list can be sorted by Tank, Healer, and DPS by default and customized
within roles. See [Sorting Party
List](https://na.finalfantasyxiv.com/uiguide/party/party-how/party_partylist.html).

**Fact:** ordinary supported duties synchronize Character level to the
recommended level. Unrestricted Party disables level sync and permits bypassing
role or minimum-size requirements, but enemies then yield no EXP and gear gains
no spiritbond; the leader's setting controls the Party. See [Entering a Duty
with Your Current Character
Level](https://na.finalfantasyxiv.com/uiguide/party/party-how/party_usparty.html).

**Fact:** leaving a matched duty early can incur a penalty. See [Leaving a
Duty](https://na.finalfantasyxiv.com/uiguide/party/party-how/party_exit.html).

**Fact:** Hall of the Novice is NPC-authored role training, not member-to-member
mentorship. It provides Tank, Healer, and DPS exercises and completion rewards.
See [Training for Party
Combat](https://na.finalfantasyxiv.com/uiguide/party/party-how/party_practice.html).

**Unknown:** the accessible cited pages do not state the general Party cap,
light/full Party sizes, leader succession, zoning behavior, ordinary shared XP
formula, quest credit, loot allocation, contribution/proximity rules, durable
Party identity, observational learning, or Party-level combined-technique
progression. Those cells remain unknown rather than relying on common knowledge.

**Project0 Inference:** preserve explicit ready/offline state and the principle
that removing normal constraints also removes progression rewards. Do not treat
level sync or NPC role training as mentorship. Project0 has no level XP and
must use direct participation evidence instead.

## AzerothCore at the pinned revision

**Fact:** AzerothCore defines `MAX_GROUP_SIZE` as five and raid size separately
as forty. See
[`Group.h` lines 45-55](https://github.com/azerothcore/azerothcore-wotlk/blob/24adf9bfed23f490f1fe46549e579cf3e4b82f80/src/server/game/Groups/Group.h#L45-L55).

**Fact:** the server-side group stores a GUID, leader identity, member slots,
subgroups, type, difficulty, loot method, threshold, and master-looter identity.
See
[`Group.h` lines 100-220](https://github.com/azerothcore/azerothcore-wotlk/blob/24adf9bfed23f490f1fe46549e579cf3e4b82f80/src/server/game/Groups/Group.h#L100-L220).
The inspected source establishes runtime creation and destruction, not a
durable Party identity independent of roster.

**Fact:** server packet handlers validate target, existing membership,
capacity, and caller permissions before creating or mutating groups. See
[`GroupHandler.cpp` lines 45-230](https://github.com/azerothcore/azerothcore-wotlk/blob/24adf9bfed23f490f1fe46549e579cf3e4b82f80/src/server/game/Handlers/GroupHandler.cpp#L45-L230).
Removal, disband, and leader change are server group mutations with successor
selection and handler authority checks. See
[`Group.cpp` lines 250-430](https://github.com/azerothcore/azerothcore-wotlk/blob/24adf9bfed23f490f1fe46549e579cf3e4b82f80/src/server/game/Groups/Group.cpp#L250-L430)
and
[`GroupHandler.cpp` lines 230-360](https://github.com/azerothcore/azerothcore-wotlk/blob/24adf9bfed23f490f1fe46549e579cf3e4b82f80/src/server/game/Handlers/GroupHandler.cpp#L230-L360).

**Fact:** the group sends clients a server-generated member read model including
leader, subgroup, online/state, role/flags, and location-related member data.
See
[`Group.cpp` lines 500-690](https://github.com/azerothcore/azerothcore-wotlk/blob/24adf9bfed23f490f1fe46549e579cf3e4b82f80/src/server/game/Groups/Group.cpp#L500-L690).
The inspected group code does not make zoning an automatic disband.

**Fact:** grouped kill rewards filter by server-side membership and
reward-distance/map conditions and weight XP by level rather than sharing it
equally. The same area coordinates group-aware kill and quest reward calls.
See
[`Group.cpp` lines 690-850](https://github.com/azerothcore/azerothcore-wotlk/blob/24adf9bfed23f490f1fe46549e579cf3e4b82f80/src/server/game/Groups/Group.cpp#L690-L850).

**Unknown:** this bounded inspection does not establish a universal alive/dead
or contribution threshold for all reward types, nor a separate shared-quest
abstraction. Eligibility delegated to Player reward routines remains outside
the claim.

**Fact:** group state supports free-for-all, round-robin, master loot, group
loot, and need-before-greed, plus threshold and master-looter authority. See
[`Group.h` lines 130-180](https://github.com/azerothcore/azerothcore-wotlk/blob/24adf9bfed23f490f1fe46549e579cf3e4b82f80/src/server/game/Groups/Group.h#L130-L180)
and
[`Group.cpp` lines 850-980](https://github.com/azerothcore/azerothcore-wotlk/blob/24adf9bfed23f490f1fe46549e579cf3e4b82f80/src/server/game/Groups/Group.cpp#L850-L980).

**Unknown:** a repository-wide search at the pinned revision found no feature
identified by `mentor`, `mentorship`, `teach`, `observation`, `combined
technique`, or `coordination progression`. That bounded result does not rule
out cooperative actions under unrelated names.

**Project0 Inference:** preserve server-validated lifecycle, five-member scale,
reward-distance/map eligibility, explicit loot authority, and replicated member
state. Reject conventional level-weighted XP and transient-only identity.

## Comparison matrix

`Unknown` means the cited source set did not establish the value.

| Dimension | EQEmu pinned source | Guild Wars 2 official wiki | Final Fantasy XIV official guide | AzerothCore pinned source | Project0 constraint |
| --- | --- | --- | --- | --- | --- |
| Cap | 6 | Party 5; squad 10/50 | Unknown | Party 5; raid 40 | Party 5 |
| Identity | DB-backed current group ID and roster | Transient; offline Party members removed | Unknown; duty offline member persists until action | Runtime server group GUID | Durable Party ID, mutable roster |
| Invite/accept | Invite plus `GroupFollow` acceptance; cross-zone routed | Invite or join through multiple surfaces | Invite documented; accept/decline details unknown | Server-validated invite/accept handlers | Consent and idempotent transitions required |
| Leave/kick/disband | Member self-leave; leader kick; small group/leader leave can disband | Self-leave; majority vote-kick | Self-leave; leader disband; duty vote-dismiss | Server removal, disband, leader checks | Leave, leader removal, explicit disband |
| Leader succession | Manual transfer; leader leave effectively disbands in cited path | Party leader not established; squad takeover documented | Unknown | Server successor selection | Grace plus succession required |
| Disconnect | Link-dead/logout removes member | Offline removes Party member | Offline duty member can be vote-dismissed/replaced | Offline state replicated; no automatic zoning disband in inspected group path | Grace state; transport loss is not leave |
| Zoning/instance | Names survive zone-local pointer loss; DB reconstruction | Cross-instance state and join-in | Unknown | Map/location-aware state; no zoning disband found | Explicit cross-Sector policy remains open |
| Shared XP/reward | Level-gated, size-adjusted conventional XP; roster-based merit/task for in-zone clients | Same ordinary reward as solo; easier Party tag; personal eligibility | Level sync; unrestricted mode removes EXP | Level-weighted XP with reward distance/map checks | No conventional XP; eligibility is not evidence copying |
| Eligibility | In-zone pointer and level for XP; merit/task lacks proximity/contribution checks | Damage/support participation; active attack anti-AFK | Most ordinary eligibility details unknown | Reward distance/map; other guards partly delegated | Active participation plus bounded proximity |
| Quest/task credit | Task kill update to all in-zone client members; general quest unknown | Renown-heart progress visible; exact sharing unknown | Unknown | Group-aware reward calls; exact shared quest contract unknown | Shared objective eligibility, later quest-map ownership |
| Loot | Server corpse allowlist for in-zone members; group loot messages | Personal loot after participation | Unknown | Multiple server-owned allocation modes | Eligibility here; allocation elsewhere |
| Anti-idle/power-level | Level/gray checks; no contribution/proximity in cited group loop | Active attack required despite support; downscaling | Unrestricted duty removes EXP/spiritbond; early-leave penalty | Reward distance/map checks | Participation, proximity, replay and collusion controls |
| Member read model | Names, in-zone pointers, roles, targets, packets | Profession, level/mastery, health, effects, instance | Role-sorted list, offline state, ready status | Leader, subgroup, online/state, role/location | Replicated eligibility and connection state; hidden authority stays server-side |
| Cooperative semantics | Roles/targets; no verified practiced combined technique | Targets, pings, markers, ready checks, proximity-prioritized subgroup support | Role training and ready check | Roles and group coordination; no verified practiced combined technique | Roster-aware coordination and practiced combined techniques |
| Mentorship | Named mentoree/percent metadata; no verified learning consumer | No verified observational learning | NPC role training only | No identified feature in bounded search | Opt-out basics by observation; own practice for mastery |
| Party progression | None verified | None verified | None verified | None verified | Durable coordination history, roster-aware readiness |

## Mentorship and Party-level progression finding

**Fact:** none of the four inspected systems provides verified evidence for the
specific Project0 destination: consent-based observation of a mastered Party
member that unlocks only introductory technique knowledge while requiring the
learner's own embodied practice, or durable Party-level coordination history
that gates roster-aware combined techniques.

**Fact:** superficially similar mechanics are not equivalent:

- EQEmu's named mentor fields have no verified learning consumer in the pinned
  paths.
- Guild Wars 2 level adjustment changes effective power; it does not transfer
  knowledge.
- Guild Wars 2 target calls, combo-adjacent combat, boons, and squad tools are
  cooperative actions, not evidence of Party-level progression.
- Final Fantasy XIV Hall of the Novice is NPC-authored role instruction, not
  observation of a Party member.
- AzerothCore's group rewards and roles do not establish teaching or practiced
  combined-technique progression.

**Project0 Inference:** #323 and #324 are novel design decisions rather than
adaptations of a verified reference model. They require explicit consent,
participation, roster, repetition, interruption, and anti-idle evidence. No
external source supports sharing one Character's embodied training evidence
with idle members.

## Preserve, adapt, or reject

| Pattern | Disposition | Reason for Project0 |
| --- | --- | --- |
| Server validates membership and leadership transitions | Preserve | Matches ADR 0002 and prevents client-authored roster state |
| Five-member Party scale | Preserve | Already settled by #319 and supported by GW2/AzerothCore precedent |
| Explicit remote, offline, defeated, and ready member state | Preserve | Makes eligibility and coordination legible without exposing hidden calculations |
| Server-owned loot eligibility/allocation with visible result messages | Preserve | Separates trusted eligibility from client presentation |
| Support actions count toward participation | Adapt | Valid only when server-observed, bounded, encounter-relevant, and resistant to passive aura idling |
| Reward distance/map or zone checks | Adapt | Project0 needs proximity plus active contribution, not location alone |
| Cross-zone roster reconstruction | Adapt | Useful precedent, but Project0 Party identity must survive roster mutation independently |
| Vote-dismiss and explicit replacement flow | Adapt | Useful for disputed removal/offline UX; exact authority remains #321 scope |
| Ready checks, targets, markers, and pings | Adapt or defer | Useful coordination tools, but not proof of coordination progression |
| Personal loot per eligible participant | Adapt | Eligibility belongs here; allocation modes remain another map's decision |
| Conventional XP pool, group bonus, or level-weighted split | Reject | Project0 progression is embodied and action-evidenced |
| Roster-only kill merit/task credit | Reject | Violates active participation and proximity requirements |
| Automatic offline removal | Reject | Conflicts with durable identity and disconnect grace |
| Leader departure automatically destroys Party | Reject | Conflicts with succession and durable Party identity |
| Level sync treated as mentorship | Reject | Power normalization does not demonstrate learning |
| Generic combo/proximity buff treated as Party progression | Reject | Cooperation alone does not prove durable, practiced coordination |
| Copying performer training evidence to observers | Reject | Contradicts personal embodied progression and enables idling/power-leveling |

## Security and exploit lessons

1. **Authority must be explicit.** EQEmu and AzerothCore route client requests
   into server validation and mutation. Project0 must reject client-authored
   membership, eligibility, loot, observation, timing, and progression results.
2. **Roster membership is insufficient evidence.** EQEmu's in-zone roster loops
   show how merit/task/loot can over-credit non-contributors. Presence must not
   substitute for active, encounter-relevant action.
3. **Support needs anti-idle proof.** Guild Wars 2 recognizes healing, revival,
   boon, condition-removal, and control contribution but still requires active
   attacking against passive aura AFK behavior. Project0 needs analogous
   server-observed activity without mandating one specific combat role.
4. **Distance alone is insufficient.** Reward radius reduces remote leeching
   but does not prove contribution, consent, attention, or correct encounter
   membership.
5. **Connection loss is not intent.** Logout, link-dead, zoning, and explicit
   leave need separate transitions. Otherwise disconnect manipulation can evade
   removal, reset eligibility, or destroy Party state.
6. **Late roster changes need bounded eligibility.** Joining immediately before
   resolution, leaving after contribution, replaying an event, or roster cycling
   must not duplicate encounter, quest, loot, observation, or coordination
   credit.
7. **Mentorship naming is not evidence.** EQEmu's `mentor_percent` illustrates
   the risk of inferring semantics from labels. Project0 must audit the actual
   evidence consumer and never treat a UI selection as proof of observation.
8. **Coordination history cannot grant newcomer mastery.** Durable aggregate
   Party history needs roster-aware readiness so roster substitution cannot
   unlock advanced combinations for unpracticed Characters.
9. **Read models are not authority.** Health, readiness, proximity, role, and
   eligibility indicators must be replicated server results and should explain
   rejection without exposing exploitable hidden thresholds.

## Implications for the Party map

- [#321: identity, membership, leadership, and
  lifecycle](https://github.com/vnvalentin/project0/issues/321) should use the
  verified lifecycle/state precedents to decide durable ID versus roster,
  consent transitions, leader succession, disconnect grace, zoning, revisions,
  idempotency, and the client-visible read model. #321 does not explicitly list
  #320 as a blocker, but #320 supplies its comparative evidence.
- [#322: participation and shared encounter
  eligibility](https://github.com/vnvalentin/project0/issues/322) is explicitly
  blocked by #320 and #321. The evidence narrows its work to server-observed
  contribution plus proximity, support participation, encounter boundaries,
  death/disconnect/late-roster cases, task/quest/loot eligibility, and anti-idle
  controls without conventional XP.
- [#323: mentorship and observational
  learning](https://github.com/vnvalentin/project0/issues/323) is explicitly
  blocked by #320 and #321. Research found no verified model matching the
  destination, so it must define consent/opt-out, valid observable actions,
  attention/proximity/repetition evidence, basics-only output, and the hard
  boundary requiring personal practice.
- [#324: coordination progression and combined
  techniques](https://github.com/vnvalentin/project0/issues/324) is explicitly
  blocked by #320 and #321. Existing coordination tools are precedents for
  interaction and read state, not progression. #324 must decide ownership of
  durable coordination history and roster-aware practice/readiness without
  importing generic combos as proof.
- [#325: Party HUD, formation, and coordinated-action
  flow](https://github.com/vnvalentin/project0/issues/325) is blocked by
  #321-#324 rather than directly by #320. This research indirectly supplies
  verified read-model precedents: connection/instance state, health/defeat,
  roles, ready responses, participation/loot feedback, and transparent
  rejection, without copying proprietary presentation or exposing hidden
  authoritative values.

## Fog exposed by research

These are unresolved map questions, not implementation tickets or formulas:

- What exact event creates durable Party identity, and when can that identity
  be retired after the roster becomes empty?
- Which membership states distinguish invited, active, zoning, disconnected in
  grace, departed, removed, and ineligible without making transport state an
  authority loophole?
- What leader succession rule handles voluntary leave, timeout, removal, and
  cross-Sector absence while preserving consent and preventing hostile capture?
- Which combat, support, traversal, puzzle, and objective actions constitute
  meaningful participation, and how are encounter boundaries identified?
- How should eligibility treat defeated Characters, late joiners, prior
  contributors who leave range, reconnects, and members split across Sectors?
- Which shared quest/objective facts belong to this Party map versus the Quest
  Content and Runtime map, and which loot facts belong to Item Ownership and
  Loot Lifecycle?
- What observation evidence proves willingness, attention, proximity,
  repetition, and a mastered demonstrator while allowing either side to opt out?
- What is the minimum basics-only observation result that cannot be farmed as
  substitute proficiency or mastery?
- What entity owns coordination history, and which roster signature or
  relationship history prevents newcomer inheritance of advanced readiness?
- How do combined techniques represent consent, preparation, timing,
  interruption, failure, substitution, and actionable server rejection without
  choosing final timing windows or formulas yet?
- Which member-state indicators are necessary for mouse/keyboard and controller
  users, and which hidden anti-exploit thresholds must remain undisclosed?
- Are ready checks, role labels, target calls, markers, Party chat, and vote
  removal required for the five-member destination, or optional later breadth?

## Limitations

- EQEmu was inspected directly at the required revision. The code contains old
  TODOs and comments indicating some leader and loot paths need work; this note
  reports behavior at that commit, not intended EverQuest behavior.
- Guild Wars 2 official-wiki pages are primary ArenaNet-hosted documentation,
  but some mechanics are community-maintained. Claims marked by the source as
  needing verification were excluded.
- Square Enix's accessible official pages are live rather than revision-pinned
  and did not expose all requested mechanics. Missing values remain Unknown.
- AzerothCore was pinned to the resolved source revision. Some reward details
  delegate into Player/quest subsystems beyond the bounded group inspection;
  this note does not generalize beyond cited paths.
- Negative mentorship and Party-progression results are bounded searches, not
  proof that no mechanic under unrelated terminology exists.
