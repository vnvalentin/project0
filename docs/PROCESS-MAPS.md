# Project0 Process Maps

These maps make the TPSA flow visible for the current Project0 value stream.
They are living delivery artifacts: update them when a new phase changes the
customer journey, runtime behavior, or delivery loop.

## Scope

The current value stream is:

> A developer or playtester launches the Windows client, connects to the Linux
> server, enters a local identity, and moves a Player while the server remains
> authoritative for networked movement. Up to two clients (Slice 007) can be
> connected at once, each seeing the other's server-authoritative movement and
> a clean removal of the other's representation on disconnect.

The maps stop before JIT world generation, SQLite canon persistence,
production authentication, and support for more than two concurrent peers,
because those systems are not yet in the live path.

## Material And Information Flow

This is the MIFC for one bounded implementation slice. The material flow is
the changing product state and runtime artifact. The information flow is the
decision, handoff, evidence, and feedback that tells the next step what to do.

```mermaid
flowchart LR
    A[User outcome or observed defect] --> B[Wayfinder decision ticket]
    B --> C[Slice record: SDD, BDD, public seam, non-goals]
    C --> D[Claude Code handoff]
    D --> E[Source change]
    E --> F[Focused executable check]
    F --> G{Passes?}
    G -- No --> H[Andon: stop and preserve evidence]
    H --> I[Root-cause correction]
    I --> E
    G -- Yes --> J[Runtime or LAN validation]
    J --> K{Observed behavior matches?}
    K -- No --> H
    K -- Yes --> L[Update feature, debt, tracker, and slice evidence]
    L --> M[User-visible capability]
    M --> N[Feedback or next constraint]
    N --> A

    B -. decision .-> D
    F -. validation evidence .-> L
    J -. observation .-> L
```

### Flow units and queues

| Flow unit | Information carried | Value-added step | Queue or stop signal |
| --- | --- | --- | --- |
| User outcome | Desired behavior, screenshot, or failure text | Clarify the smallest observable outcome | Ambiguous scope stops at Wayfinder/grilling |
| Decision ticket | One answerable design question | Resolve one decision | Blocked ticket remains unclaimed or blocked |
| Handoff brief | Scope, public seam, invariants, validation | Give Claude one bounded implementation unit | Missing acceptance evidence stops handoff |
| Source change | Client/server/docs artifact | Implement the decision | Unrelated file changes trigger review |
| Validation result | Exit code, logs, observed state, machine-readable result artifact | Prove behavior at the public seam and preserve trend evidence | Any failure or missing artifact pulls the Andon cord |
| Runtime observation | Windows/LAN behavior and user feedback | Confirm the real customer path | Contradiction reopens diagnosis |
| Delivery record | Feature, debt, phase, and evidence status | Preserve organizational learning | Stale records are a process defect |

## Kanban Board

This is the delivery board for the current value stream. The board is
intentionally small-lot: one active implementation handoff at a time. A card
may move right only when the exit evidence for its current column exists.

```mermaid
flowchart LR
    subgraph Ready[READY - WIP 2]
        R1[Slice 007 follow-up: physical two-client LAN run]
        R2[Phase 8: JIT generation contract decision]
    end
    subgraph Claimed[CLAIMED - WIP 1]
        C1[Slice 007 multi-peer replication]
    end
    subgraph Handoff[CLAUDE HANDOFF - WIP 1]
        H1[One bounded implementation brief]
    end
    subgraph Evidence[AWAITING EVIDENCE - WIP 1]
        E1[Focused test plus Windows/LAN observation]
    end
    subgraph Done[DONE]
        D1[Slice 001-006 validated]
    end
    subgraph Andon[ANDON / STOP]
        A1[Failure, contradiction, stale process, or missing evidence]
    end

    Ready --> Claimed --> Handoff --> Evidence --> Done
    Handoff --> Andon
    Evidence --> Andon
    Andon --> Claimed
```

### Current board

| Card | Column | Exit condition for next move | Evidence or stop reason |
| --- | --- | --- | --- |
| Slice 001: identity, plane, local movement | Done | None; regression only | Headless smoke test passes; Windows rendering confirmed during client work |
| Slice 002: server connection proof | Done | None; regression only | ENet connection and Player spawn smoke test pass |
| Slice 003: LAN client connection | Done with follow-up | Physical LAN behavior remains a reusable regression check | User connected Windows client to Linux server |
| Slice 004: authoritative movement | Done with follow-up | Multi-peer behavior must preserve authority | Server-owned movement smoke test passes |
| Slice 005: prediction/reconciliation | Done with follow-up | Multi-peer behavior must preserve sequence acknowledgement | Prediction smoke test passes; visual quality remains a manual check |
| Slice 006: portable Windows client | Done | None for this slice; release hardening is separate | Exported client launched outside editor/source share and connected over LAN |
| Slice 007: multi-peer replication | Evidence / handoff review | Two-client Windows/LAN run and final review | Headless multi-peer evidence exists; physical two-client run remains open |
| JIT world generation | Ready / fog | Slice 007 review and authority model must settle first | Not eligible for implementation yet |

### Kanban operating rules

- `Ready`: decision is clear, ticket is unclaimed, and acceptance evidence is
  known.
- `Claimed`: one agent owns the ticket; no second implementation handoff may
  start for the same slice.
- `Claude Handoff`: exactly one bounded implementation request is active.
- `Awaiting Evidence`: code is present, but executable or real-client proof is
  still required; no new feature scope enters this column.
- `Done`: the public seam, focused validation, relevant regression checks, and
  user-visible evidence are recorded in the slice and delivery records.
- `Andon / Stop`: work pauses immediately on failure, stale runtime code,
  contradictory tracker state, or missing evidence. The card returns only
  after the root cause and countermeasure are recorded.

WIP limits are deliberate: one active Claude implementation handoff and one
slice awaiting evidence. If either limit is exceeded, stop pulling new work.

## Three Concurrent Processes

These lanes run concurrently. They are related, but they must not be mixed:
the player journey is not a server implementation detail, and a test result is
not proof of a user-visible rendering outcome.

```mermaid
flowchart TB
    Trigger[Need: launch and play a connected minimal game]

    subgraph Customer[1. Customer Process]
        C1[Launch client]
        C2[Enter identity]
        C3[See connection status]
        C4[See plane and Players]
        C5[Press WASD]
        C6[Observe responsive and corrected movement]
        C1 --> C2 --> C3 --> C4 --> C5 --> C6
    end

    subgraph Product[2. Product Behavior Process]
        P1[Load identity gate]
        P2[Create ENet client]
        P3[Server accepts peer]
        P4[Spawn networked Player]
        P5[Sample input intent]
        P6[Server integrates authoritative position]
        P7[Return snapshot and sequence]
        P8[Predict, reconcile, and smooth]
        P1 --> P2 --> P3 --> P4 --> P5 --> P6 --> P7 --> P8
    end

    subgraph Delivery[3. Delivery And Learning Process]
        D1[Capture request or defect]
        D2[Resolve decision and scope]
        D3[Write handoff]
        D4[Implement small batch]
        D5[Run focused and regression checks]
        D6[Test on Windows/Linux]
        D7[Record evidence and debt]
        D1 --> D2 --> D3 --> D4 --> D5 --> D6 --> D7
    end

    Trigger --> C1
    Trigger --> D1
    C2 -. behavior validates .-> P1
    C3 -. behavior validates .-> P3
    C4 -. behavior validates .-> P4
    C6 -. feedback and evidence .-> D7
    D7 -. next standard .-> D1
```

## Customer Process Map

```mermaid
flowchart LR
    A[Developer/playtester has client build] --> B{Can launch?}
    B -- No --> Z[Stop: package or runtime defect]
    B -- Yes --> C[Identity gate]
    C --> D{Identity accepted?}
    D -- No --> C
    D -- Yes --> E[Gameplay scene loads]
    E --> F{Server reachable?}
    F -- No --> G[Show failure; keep local scene usable]
    F -- Yes --> H[Show connected Player]
    H --> I[Press movement input]
    I --> J{Movement feels responsive and converges?}
    J -- No --> K[Capture screenshot/log and stop for diagnosis]
    J -- Yes --> L[Minimal playable outcome achieved]
```

Primary customer measures:

- Time from launching the client to seeing the connected gameplay scene.
- Time from pressing movement input to seeing a visible response.

Guardrails:

- Connection failure is visible and does not silently appear successful.
- A stale or incompatible server is surfaced by the connection/RPC error path.
- No client input is allowed to become authoritative position directly.
- The client package must not include server-only files or credentials.

## Product Behavior Map

```mermaid
stateDiagram-v2
    [*] --> IdentityGate
    IdentityGate --> IdentityGate: empty identity
    IdentityGate --> Connecting: valid identity
    Connecting --> Connected: ENet handshake succeeds
    Connecting --> ConnectionFailed: handshake fails
    Connecting --> ConnectionRejected: peer cap already reached (2)
    ConnectionFailed --> GameplayLocal: local scene remains usable
    ConnectionRejected --> GameplayLocal: local scene remains usable
    Connected --> PlayerSpawned: server confirms peer
    PlayerSpawned --> PeerReplicated: spawn_remote_player_representation both ways
    PeerReplicated --> InputSampled: WASD state changes
    InputSampled --> ServerAuthority: intent + sequence sent
    ServerAuthority --> SnapshotReturned: server integrates position
    ServerAuthority --> PeerPositionBroadcast: position relayed to other connected peer(s)
    SnapshotReturned --> PredictedReconciled: sequence acknowledged
    SnapshotReturned --> BlueSmoothed: authoritative visual target updated
    PeerPositionBroadcast --> RemotePlayerSmoothed: other peer's RemotePlayer target updated
    PredictedReconciled --> InputSampled
    BlueSmoothed --> InputSampled
    RemotePlayerSmoothed --> InputSampled
    PeerReplicated --> PeerDisconnectCleanup: other peer disconnects
    PeerDisconnectCleanup --> InputSampled: despawn_remote_player_representation
    GameplayLocal --> [*]
```

Product stop signals:

- RPC checksum or argument mismatch: stop, restart both ends from the same
  source revision, and do not interpret partial movement as valid evidence.
- Server bind failure: stop; do not silently fall back to a wider interface.
- Failed authoritative snapshot: keep the last known state visible and surface
  the degraded connection instead of claiming synchronized movement.
- Headless pass with missing Windows rendering: stop the claim at headless
  evidence and require a real client observation.
- A third concurrent connection attempt (Slice 007's `MAX_REPLICATED_PEERS`):
  the server disconnects it immediately in `_on_peer_connected`, before any
  `ServerPlayerState` or spawn RPC is created for it, rather than silently
  accepting undefined replication behavior.
- Abrupt peer loss (process killed with no graceful ENet disconnect packet):
  the server's own peer-timeout heartbeat is the only stop signal; remaining
  peers must not be left with a stale `RemotePlayer` representation once that
  timeout fires — `despawn_remote_player_representation` is the queue-drain
  step that clears it.

## Delivery And Learning Map

```mermaid
flowchart LR
    A[Trigger or defect] --> B[Go and see evidence]
    B --> C[State one falsifiable hypothesis]
    C --> D[Choose cheapest discriminating check]
    D --> E{Check result}
    E -- Hypothesis false --> F[One nearby hop; revise model]
    F --> C
    E -- Hypothesis supported --> G[Smallest reversible handoff]
    G --> H[Claude implementation]
    H --> I[Focused validation]
    I --> J{Pass?}
    J -- No --> K[Andon: stop, preserve logs, repair root cause]
    K --> H
    J -- Yes --> L[Manual/runtime observation]
    L --> M[Update slice, feature, debt, tracker]
    M --> N[Hansei: what did reality teach us?]
    N --> O[Update standard work and next ticket]
    O --> A
```

Learning measures:

- **Lead time:** user request to validated user-visible result.
- **Atomic Batch Index:** one handoff should resolve one bounded decision or
  implementation slice.
- **Cost per Learning:** tool calls and validation effort needed to falsify or
  confirm the current hypothesis.
- **Rework signal:** repeated stale-server, renderer, or shared-folder failures
  are process defects to remove from the standard runbook.

## Current Andon Board

The live visual board is available through the read-only Docker dashboard in
`dashboard/`. The markdown table below remains the authoritative source; the
dashboard is the at-a-glance view for action.

| Signal | Current state | Stop condition | Countermeasure owner |
| --- | --- | --- | --- |
| Source/runtime mismatch | Slice 005 required a fresh server restart after RPC changes | RPC checksum or argument-count error | Delivery workflow; restart both ends |
| Headless vs. Windows rendering | Compatibility renderer resolved the Windows mesh issue | Camera/scene test passes but client pixels are wrong | Client validation runbook |
| Shared-folder operation | Windows and Linux use the same project files | Running the wrong OS binary or stale process | Runtime boundary documentation |
| Package readiness | Export slice is planned/in progress | No reproducible artifact or host configuration | Slice 006 handoff |
| Automated behavior tests | Hand-rolled public-seam smoke tests | Test framework gap grows with branching behavior | DT-002 remediation |
| Multi-peer capacity | Hard-capped at 2 concurrent peers (`MAX_REPLICATED_PEERS`) | A third connection attempt | Slice 007 handoff; future slice required to raise the cap deliberately |
| Multi-process test isolation | Slice 007's smoke test spawns 3 real OS processes (server + 2 client harnesses) coordinated via polled state files | A harness process dies or never reaches "connected: player spawned" | Slice 007 handoff; wall-clock (not frame-count) waits for real disconnect timing |

## Andon Lifecycle

```mermaid
flowchart TD
  S[Signal: failure, contradiction, stale runtime, or missing proof]
  S --> V[Visualize card in Andon column]
  V --> P[Preserve logs, screenshots, process IDs, and exact commands]
  P --> R[Root-cause check at the nearest boundary]
  R --> C[Countermeasure and focused rerun]
  C --> Q{Evidence clears signal?}
  Q -- No --> V
  Q -- Yes --> U[Update slice, feature, debt, tracker, and board]
  U --> W[Return card to normal Kanban column]
```

The Andon board is not a bug backlog. It is a stop-and-respond surface. A
card cannot be marked `Done` while its stop signal is merely explained away.