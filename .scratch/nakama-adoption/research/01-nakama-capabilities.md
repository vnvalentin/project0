# Research: Nakama capabilities against Project0 replacement goals

Date: 2026-09-19
Ticket: #337, Research Nakama capabilities against Project0 replacement goals
Scope: research only; no implementation, delivery-record, GitHub issue, or code changes.

## Source policy

This note uses only first-party Nakama/Heroic Labs documentation plus local Project0 domain context from `CONTEXT.md`. Source URLs are cited inline next to the claims they support.

Primary sources:

- Nakama Authentication: https://heroiclabs.com/docs/nakama/concepts/authentication/
- Nakama Sessions: https://heroiclabs.com/docs/nakama/concepts/session/
- Nakama User Accounts: https://heroiclabs.com/docs/nakama/concepts/user-accounts/
- Nakama Storage Engine: https://heroiclabs.com/docs/nakama/concepts/storage/
- Nakama Multiplayer Engine: https://heroiclabs.com/docs/nakama/concepts/multiplayer/
- Nakama Authoritative Multiplayer: https://heroiclabs.com/docs/nakama/concepts/multiplayer/authoritative/
- Nakama Matchmaker: https://heroiclabs.com/docs/nakama/concepts/multiplayer/matchmaker/
- Nakama Friends: https://heroiclabs.com/docs/nakama/concepts/friends/
- Nakama Groups: https://heroiclabs.com/docs/nakama/concepts/groups/
- Nakama Godot 4 Client Guide: https://heroiclabs.com/docs/nakama/client-libraries/godot/
- Nakama Server Framework Introduction: https://heroiclabs.com/docs/nakama/server-framework/introduction/
- Nakama TypeScript Runtime: https://heroiclabs.com/docs/nakama/server-framework/typescript-runtime/
- Nakama Go Runtime: https://heroiclabs.com/docs/nakama/server-framework/go-runtime/
- Nakama Lua Runtime: https://heroiclabs.com/docs/nakama/server-framework/lua-runtime/

## Executive summary

Nakama is a plausible replacement candidate for Project0's generic backend surfaces: authentication, session tokens, account profile records, socket connection, realtime messages, matchmaking, social graph, groups, chat, notifications, and server-side RPC/hooks. The fit is strongest where Project0 needs authenticated users, short-lived sessions, Godot client integration, authoritative match loops, and social/matchmaking features already modeled by Nakama.

The fit is weaker for Project0's distinctive world model: Account-owned Characters, server-authoritative Player movement through long-lived generated Sectors, and Canon persisted as validated immutable base revisions plus append-only mutations. Nakama offers user metadata and JSON storage, and authoritative matches offer in-memory per-match state, but Nakama docs explicitly discourage custom tables and custom SQL when built-ins can be used, and authoritative match state is match-local, in-memory, and not automatically sent or persisted. Those constraints should shape later decisions rather than be papered over. Sources: storage engine guidance on collections/JSON/custom SQL/custom tables (https://heroiclabs.com/docs/nakama/concepts/storage/), server database handler guidance (https://heroiclabs.com/docs/nakama/server-framework/introduction/#database-handler), authoritative match state/lifecycle docs (https://heroiclabs.com/docs/nakama/concepts/multiplayer/authoritative/).

## Project0 term mapping

| Project0 term | Nakama candidate | Fit | Notes |
|---|---|---:|---|
| Account | Nakama user account | Strong | Nakama user accounts have stable user IDs, usernames, public profile fields, linked auth identifiers, private email/devices/custom IDs, wallet, and server-only metadata. Project0's `account_id` maps most closely to `user.id`, but Nakama names the entity `user`. Sources: https://heroiclabs.com/docs/nakama/concepts/user-accounts/ and https://heroiclabs.com/docs/nakama/concepts/authentication/ |
| Character | Storage object(s) owned by account/user, plus server RPCs for create/select/delete | Medium | Nakama has no built-in multi-Character persona model. Character slots, display-name uniqueness, soft deletion, and selected Character semantics would be custom server runtime logic plus storage objects. Storage is JSON documents keyed by collection/key/user ID, with permissions and conditional writes. Source: https://heroiclabs.com/docs/nakama/concepts/storage/ |
| Player | Presence/session in an authoritative match, plus custom match state | Medium/Strong | Nakama presences identify connected users in matches; authoritative match handlers can validate input and broadcast state. Project0's Player as selected Character would need explicit mapping from session user ID to selected Character ID in match state. Sources: https://heroiclabs.com/docs/nakama/concepts/multiplayer/authoritative/ and https://heroiclabs.com/docs/nakama/client-libraries/godot/ |
| Sector | Custom storage object, external service, or authoritative-match-loaded data | Weak/Medium | Nakama storage can persist JSON records, but Sector generation/validation and fine Tile/Structure/Spawn content are Project0-specific. Nakama has no native Sector concept and custom tables are strongly discouraged. Source: https://heroiclabs.com/docs/nakama/concepts/storage/ |
| Canon | Server-owned storage plus custom validation/mutation protocol | Weak/Medium | Nakama can store authoritative data and server runtime can protect writes, but Project0's immutable base revisions plus append-only mutation log are not a built-in Nakama model. Later design must choose between Nakama storage collections, an external Canon service/database, or a hybrid. Sources: https://heroiclabs.com/docs/nakama/concepts/storage/ and https://heroiclabs.com/docs/nakama/server-framework/introduction/ |

## Authentication and accounts

Nakama requires clients to authenticate before accessing server features. Client apps connect with a server key, and individual users authenticate to obtain a session token. The docs warn to change the default `defaultkey` before production and embed the unique key in client code. Source: https://heroiclabs.com/docs/nakama/concepts/authentication/

A Nakama account is one server-side record with one or more linked identifiers. Supported auth categories include device ID, email/password, console providers, social providers, and custom identifiers. `Authenticate` finds or creates the account and returns a session; `Link` attaches an additional identifier to the already-signed-in account. Linking an identifier already owned by another account returns `409`; unlinking the last remaining identifier returns `403`. Source: https://heroiclabs.com/docs/nakama/concepts/authentication/

For Project0, email/password can cover a conventional Account login, while custom auth can cover a future migration from the current account system if Project0 wants to preserve existing opaque `account_id` identities. Nakama's device auth is frictionless but docs warn against OS-level hardware IDs such as Godot `OS.get_unique_id()`; they recommend generating a secure random UUID on first launch and storing it in private local storage. Source: https://heroiclabs.com/docs/nakama/concepts/authentication/#device

Nakama user accounts include public fields (`id`, `username`, `display_name`, avatar URL, language, location, timezone, metadata, friend count, provider IDs, timestamps, online flag) and private account fields (email, devices, custom ID, wallet, verify time). Users can update username/display/avatar/location/lang/timezone, but user metadata is read-only from the client and can only be set via server runtime. Source: https://heroiclabs.com/docs/nakama/concepts/user-accounts/

Project0 should not treat Nakama user metadata as the Character store. User metadata is public-facing, limited to 16KB per user, and recommended for common public fields such as character name, level, and stats. Character roster data, soft-delete state, and selected Character should instead live in server-protected storage objects or an external service. Source: https://heroiclabs.com/docs/nakama/concepts/user-accounts/#user-metadata

## Sessions

Nakama sessions are signed JWTs validated in memory. Authentication issues a short-lived session token and a longer-lived refresh token. The documented defaults are 60 seconds for the session token and 3,600 seconds for the refresh token, with production commonly setting the session token to about 2 to 3 times the average play session and refresh tokens to 24 hours to 30 days. Source: https://heroiclabs.com/docs/nakama/concepts/session/

The Godot SDK supports session auto-refresh according to the sessions documentation. Clients should persist updated auth/refresh tokens after refresh, restore tokens on app start, and fall back to full authentication only if the refresh token is also expired. Source: https://heroiclabs.com/docs/nakama/concepts/session/#session-refresh

Session variables can be set during authentication or by before-authentication hooks, then become read-only during the active session. They behave like an edge cache inside the token, not durable account state. Source: https://heroiclabs.com/docs/nakama/concepts/session/#session-variables

Logout invalidates auth and refresh tokens but does not disconnect open socket connections; server-side `sessionDisconnect` is needed to close sockets. This matters for Project0 moderation/account-disable paths. Source: https://heroiclabs.com/docs/nakama/concepts/session/#session-logout

## Godot and client integration

Heroic Labs provides a Godot 4 client guide. Installation paths include the Godot Asset Library and Heroic Labs GitHub releases; the guide instructs adding `Nakama.gd` from `addons/com.heroiclabs.nakama/` as an autoload singleton. Source: https://heroiclabs.com/docs/nakama/client-libraries/godot/

The Godot client creates a `NakamaClient` with scheme, host, port, and server key, and creates a socket from that client for realtime features such as chat, parties, matches, and socket RPCs. Source: https://heroiclabs.com/docs/nakama/client-libraries/godot/#getting-started

Godot SDK calls are asynchronous and use `await`. Because Godot does not support exceptions, the guide shows checking `is_exception()` on async results. This fits Project0's GDScript style but would require explicit error branches at every auth/socket/RPC boundary. Source: https://heroiclabs.com/docs/nakama/client-libraries/godot/#asynchronous-programming and https://heroiclabs.com/docs/nakama/client-libraries/godot/#handling-exceptions

The Godot guide demonstrates JSON serialization via Godot's `JSON` object and binary serialization via `var_to_bytes`/`bytes_to_var`. For Project0 movement and Sector data, later prototypes should measure whether JSON payload size/frequency is acceptable or whether compact binary encoding is needed. Source: https://heroiclabs.com/docs/nakama/client-libraries/godot/#serializing-and-deserializing-data

## Realtime multiplayer

Nakama supports relayed and server-authoritative multiplayer. Relayed multiplayer simply routes client data and maintains only match ID and presences; it has no insight into correctness. Authoritative multiplayer validates and broadcasts gameplay data in custom server runtime code. Sources: https://heroiclabs.com/docs/nakama/concepts/multiplayer/ and https://heroiclabs.com/docs/nakama/concepts/multiplayer/authoritative/

Project0's server-authoritative Player movement points toward authoritative matches, not relayed matches. Authoritative matches require custom gameplay logic: how many players can join, whether joins in progress are allowed, how state advances, how clients are updated, and how/when the match ends. Nakama docs state there are no out-of-the-box generic scenarios for authoritative multiplayer. Source: https://heroiclabs.com/docs/nakama/concepts/multiplayer/authoritative/

An authoritative match handler must implement seven lifecycle functions: Match Init, Match Join Attempt, Match Join, Match Leave, Match Loop, Match Terminate, and Match Signal. Clients cannot call these directly; they are invoked by Nakama. Source: https://heroiclabs.com/docs/nakama/concepts/multiplayer/authoritative/#match-handler

Authoritative match state is in-memory for the duration of the match, isolated per match, and not automatically sent to clients. Match logic must manually broadcast state changes with op codes and payloads. Source: https://heroiclabs.com/docs/nakama/concepts/multiplayer/authoritative/#match-state

Tick rate is configurable per match handler. The server calls `MatchLoop` at that frequency even with no input. Docs recommend the lowest possible tick rate that provides acceptable feel; if loops fall behind, the server may try to catch up and can end the match if too many loops fall behind. Source: https://heroiclabs.com/docs/nakama/concepts/multiplayer/authoritative/#tick-rate

Payload constraints should shape Project0 network design. Nakama recommends keeping data messages small within the 1500-byte MTU, preferring compact binary formats over JSON when appropriate, and trying to maintain no more than one message per tick per presence in each direction. If too many messages arrive for the tick rate, some may be dropped. Source: https://heroiclabs.com/docs/nakama/concepts/multiplayer/authoritative/#send-data-messages

Authoritative matches do not end just because all players leave; they stop only when lifecycle callbacks return a nil/null state. Empty/idle match cleanup must be explicit in Project0 logic. Source: https://heroiclabs.com/docs/nakama/concepts/multiplayer/authoritative/#managing-matches

Cross-match/world continuity is a major design point. Nakama docs say every running match is self-contained and cannot communicate with or affect other matches; communication with matches is only via clients sending match data. `MatchSignal` can be used in a limited way for rare exceptions such as reserving a place or handing off players/data, but the docs say it should not be standard practice. Source: https://heroiclabs.com/docs/nakama/concepts/multiplayer/authoritative/#match-handler

## Authoritative match handlers and Project0 world model

Nakama authoritative matches can plausibly host a bounded Sector or local gameplay session. The public match API and labels can advertise joinable state such as mode/open/max players, and labels can be JSON for queryable match listing. Labels have a 2KB limit and should be updated infrequently, no more than once per tick. Source: https://heroiclabs.com/docs/nakama/concepts/multiplayer/authoritative/#match-label

Project0's generated world is not obviously a Nakama match. A Sector could be one authoritative match, but Nakama's match isolation makes neighboring Sector handoff and shared Canon mutation ordering non-trivial. A larger regional/world match could avoid cross-match handoff but increases match state, tick load, and persistence complexity. The docs do not prescribe either architecture; this is a later Project0 design/prototype decision. Sources: https://heroiclabs.com/docs/nakama/concepts/multiplayer/authoritative/ and local `CONTEXT.md` Sector/Canon definitions.

For passive or asynchronous gameplay, Nakama docs describe using storage/RPCs, or authoritative matches with a low tick rate, writing match state to database and terminating when all participants are offline. That pattern may inform Sector hibernation, but it is not a ready-made Canon model. Source: https://heroiclabs.com/docs/nakama/concepts/multiplayer/

## Storage, user metadata, and Canon

Nakama storage is a document-based storage engine for project-specific JSON data. Objects are in named collections and have unique keys plus user IDs. It is optimized for ownership, access permissions, and batch operations. Source: https://heroiclabs.com/docs/nakama/concepts/storage/

By default, players can create/read/update/delete their own storage objects. The Godot guide warns to consider what malicious users can do before allowing client writes, and recommends server-protecting authoritative data such as unlocks or progress. Source: https://heroiclabs.com/docs/nakama/client-libraries/godot/#storage-engine

Storage conditional writes protect against overwriting changed objects by requiring the latest object version. This is useful for Character roster edits or selected Character changes, but Project0's Canon mutation log would still need a custom idempotency/versioning protocol. Source: https://heroiclabs.com/docs/nakama/client-libraries/godot/#conditional-writes

Nakama documentation discourages writing custom SQL when built-in features can be used and strongly discourages creating custom tables. The server framework also warns custom SQL must release database rows/connections correctly and says to avoid custom SQL/tables unless the game design requires it. Sources: https://heroiclabs.com/docs/nakama/concepts/storage/ and https://heroiclabs.com/docs/nakama/server-framework/introduction/#database-handler

Implication: if Project0 wants to preserve a server-owned SQLite Canon database exactly as modeled today, Nakama is not a drop-in persistence replacement. Later decisions should compare: (1) remodel Canon into Nakama storage collections, (2) keep Canon as a separate service/database accessed by server runtime or an adjacent backend, or (3) use Nakama for accounts/realtime/social only while leaving world generation/persistence outside Nakama.

## Social features

Nakama includes friends, friend requests, blocking, social imports from providers such as Facebook/Steam, friends-of-friends listing, and server-side user banning. Friend states include mutual, outgoing request, incoming request, and blocked/banned relationship state. Source: https://heroiclabs.com/docs/nakama/concepts/friends/

A user ban via server-side code prevents future connection/interaction, but the docs warn it does not implicitly logout or disconnect active sessions. Project0 moderation workflows must ban, logout, and disconnect active sessions to be immediate. Source: https://heroiclabs.com/docs/nakama/concepts/friends/#ban-a-user

Nakama groups/clans provide public/private groups, superadmin/admin/member/join-request states, membership management, group chat, and group metadata. Group metadata is limited to 16KB and can only be set via server runtime. Source: https://heroiclabs.com/docs/nakama/concepts/groups/

These social features are likely additive for Project0. They do not directly replace Account/Character/Canon, but they can replace future friend/group/chat scaffolding if Project0 chooses to expose social systems.

## Matchmaking and parties

Nakama matchmaking is for active players with open socket connections. Tickets remain until matched, cancelled, or the player disconnects; disconnect cancels pending tickets. Matchmaking is distinct from match listing, which shows existing matches to join. Source: https://heroiclabs.com/docs/nakama/concepts/multiplayer/matchmaker/

The matchmaker runs as a repeating batch process. The default interval is documented as 15 seconds. It compares tickets, forms matches that satisfy criteria, and notifies matched players with either a match token for relayed matches or a match ID for authoritative matches. Being matched does not automatically join a match; clients must call join. Source: https://heroiclabs.com/docs/nakama/concepts/multiplayer/matchmaker/#how-it-works

Match criteria include string/numeric properties, minimum/maximum counts, count multiple, and query syntax over ticket properties. Before hooks can authoritatively rewrite properties, counts, and queries. Source: https://heroiclabs.com/docs/nakama/concepts/multiplayer/matchmaker/#matchmaking-criteria

If exact matches are hard to find, docs recommend submitting multiple tickets with progressively broader criteria rather than repeatedly submitting identical requests. Source: https://heroiclabs.com/docs/nakama/concepts/multiplayer/matchmaker/#expanding-criteria

Nakama parties are short-lived realtime groups tied to sessions. Party matchmaking keeps party members together, can match parties with other parties or individual users, and sends the result callback to all party members. Source: https://heroiclabs.com/docs/nakama/concepts/multiplayer/matchmaker/#party-matchmaking and https://heroiclabs.com/docs/nakama/client-libraries/godot/#parties

For Project0, matchmaking can support finding parties/players for a shared Sector/session, but it does not solve world placement, Character selection, or Canon writes.

## Server runtime constraints

Nakama server runtime supports JavaScript/TypeScript bundles, Go plugins, and Lua modules. Runtime modules are loaded from the modules folder at startup, with precedence Go -> Lua -> JavaScript if multiple runtimes register the same functions/hooks. Heroic Labs recommends the JavaScript VM in the server framework introduction. Source: https://heroiclabs.com/docs/nakama/server-framework/introduction/#loading-modules

Server runtime can implement RPCs, hooks, server-to-server-only functions, run-once logic, validation, and authoritative logic. RPCs are exposed over REST HTTP endpoints, realtime socket APIs, and gRPC. Source: https://heroiclabs.com/docs/nakama/server-framework/introduction/#functionality

Background jobs are discouraged in favor of event-driven RPC/update-on-return patterns. Docs warn scheduled background jobs do dead work, create unnecessary load, and are limited to one Nakama instance unless duplicated or coordinated. Source: https://heroiclabs.com/docs/nakama/server-framework/introduction/#restrictions

TypeScript runtime is sandboxed inside Goja, targets ES5, has no Node/web/browser/native APIs, cannot access the filesystem, cannot spawn threads/processes, cannot use global variables for persistent state or inter-call communication, and is single-threaded. It cannot call Go runtime functions, and Go cannot call TypeScript runtime functions. Source: https://heroiclabs.com/docs/nakama/server-framework/typescript-runtime/#restrictions

Go runtime has full standard library and low-level environment access, but is not sandboxed; fatal errors can affect the server. Goroutines are discouraged, and global shared state is discouraged because it is not supported in multi-node environments. Go plugins cannot be built on Windows; docs recommend Docker for that path. Source: https://heroiclabs.com/docs/nakama/server-framework/go-runtime/#restrictions and https://heroiclabs.com/docs/nakama/server-framework/go-runtime/#build-the-go-shared-object

Lua runtime is Lua 5.1-compatible, sandboxed, has a restricted standard library, no Lua C API/extensions, no filesystem/OS process access, no global-state communication across VM contexts, and no coroutine/multithread support in Nakama's implementation. Source: https://heroiclabs.com/docs/nakama/server-framework/lua-runtime/#restrictions

Implication: Project0 logic that needs local filesystem access, Ollama access, SQLite Canon access, or OS/process integration probably belongs in Go runtime or outside Nakama. TypeScript/Lua are better for sandboxed validation/RPC logic but not for direct filesystem or process integration.

## Limitations and decision-shaping risks

1. Nakama user accounts are close to Project0 Accounts, but Project0 Characters are custom. Character slot rules, display-name uniqueness, soft deletion, and selected Character handoff to Player state must be built in server runtime/storage. Sources: https://heroiclabs.com/docs/nakama/concepts/user-accounts/ and https://heroiclabs.com/docs/nakama/concepts/storage/

2. Nakama authoritative matches fit bounded realtime Player control, but not automatically a continuous generated world. Match state is in-memory, per-match, isolated, manually broadcast, and explicitly ended by runtime code. Source: https://heroiclabs.com/docs/nakama/concepts/multiplayer/authoritative/

3. Canon persistence is not a built-in Nakama primitive. Storage objects are JSON documents with owner/key/collection semantics; custom SQL and custom tables are discouraged. Source: https://heroiclabs.com/docs/nakama/concepts/storage/

4. Project0's local LLM/Sector-generation model is outside Nakama's built-ins. Server runtime can call HTTPS services, but TypeScript/Lua sandboxing prevents local filesystem/process access; Go has access but is unsandboxed and must be treated carefully. Sources: https://heroiclabs.com/docs/nakama/server-framework/introduction/ and https://heroiclabs.com/docs/nakama/server-framework/go-runtime/

5. Matchmaker only serves active socket-connected users unless a separate offline matchmaking design is adopted. Source: https://heroiclabs.com/docs/nakama/concepts/multiplayer/matchmaker/

6. Production moderation/account-disable flows must handle token logout plus socket disconnect. Ban alone is not immediate for already-connected clients. Source: https://heroiclabs.com/docs/nakama/concepts/friends/#ban-a-user and https://heroiclabs.com/docs/nakama/concepts/session/#session-logout

7. Payload size/frequency can become a real constraint for Sector/Player replication. Authoritative docs recommend small payloads within MTU, compact binary where appropriate, one message per tick per presence, and adjusting tick rate/input queue if messages drop. Source: https://heroiclabs.com/docs/nakama/concepts/multiplayer/authoritative/#send-data-messages

8. Enterprise/Open Source boundary matters for scale/failover. Official docs mark presence replication across cluster nodes and match migration as Nakama Enterprise-only in the authoritative multiplayer page. Source: https://heroiclabs.com/docs/nakama/concepts/multiplayer/authoritative/#match-handler and https://heroiclabs.com/docs/nakama/concepts/multiplayer/authoritative/#match-migration

## Suggested later prototypes

These are not implementation tasks for this ticket; they are the smallest future checks that would reduce uncertainty.

1. Account/Character spike: authenticate via Nakama, create five Character storage objects with server-only validation, select one, and pass selected Character ID into an authoritative match join path.

2. Sector-as-match spike: run one low-player authoritative match that accepts movement input, broadcasts Player state, tracks idle termination, and writes a minimal Sector-state snapshot or mutation record via storage.

3. Canon persistence spike: compare Nakama storage collections versus external Canon service/database for immutable base Sector plus append-only mutation semantics.

4. Godot payload spike: measure JSON versus binary GDScript payloads for position updates and a small Sector blueprint against Nakama's message-frequency guidance.

5. Runtime-language spike: test whether Project0's future Ollama/Canon integration needs Go runtime or should stay outside Nakama behind an HTTP service.

## Blocked or uncertain facts

- I did not verify the current `nakama-godot` SDK source/API signatures from the GitHub repository; the report relies on the official Godot 4 client guide and its links to Heroic Labs releases/changelog. If later implementation depends on exact class/method names, inspect the SDK source/release tag selected for Project0.

- I did not verify Nakama Open Source versus Enterprise licensing beyond features explicitly marked Enterprise-only in the official docs excerpts used here. Before architecture commitment, confirm the required clustering, presence replication, match migration, and operational features against the exact Nakama edition.

- I did not prove whether Project0 should remodel Canon into Nakama storage or keep Canon external. Official docs show both the available storage model and cautions against custom SQL/tables, but the product decision needs a prototype with Project0 Sector/Canon data shapes.
