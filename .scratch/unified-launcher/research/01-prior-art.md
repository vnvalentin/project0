Type: research
Status: complete
Sources: Primary sources only — EQEmu server source (github.com/EQEmu/Server,
  `loginserver/` component) and docs.eqemu.io; Sparkle
  (sparkle-project.org/documentation) + WinSparkle/NetSparkle ports;
  Squirrel.Windows docs (github.com/Squirrel/Squirrel.Windows); Tauri v2 updater
  (v2.tauri.app/plugin/updater); itch.io wharf/butler (github.com/itchio/wharf,
  itch.io/docs/butler); OWASP Authentication Cheat Sheet
  (cheatsheetseries.owasp.org). Every claim cites the source that owns it (full
  URL + the exact symbol/route/field). Project0 mappings are labelled and refer
  to the existing login-authority + signed-assertion + assertion-only
  game-server split (ADR 0004/0005, `server/login_gateway.gd`,
  `server/login_server_main.gd`).

# Unified Windows Launcher: Prior-Art Facts

Research for the unified Windows game launcher design. Three areas: (1) EQEMU
login-server authority model, (2) launcher/patcher update patterns, (3) account
onboarding + abuse controls. Each area ends with a short "Implication for
Project0" takeaway.

---

## Area 1 — EQEMU login server: authority separation, accounts, handshake, server list

EQEmu ships the login server as a **standalone process/component** in
`loginserver/`, with its own `main.cpp`, `Database`, `client_manager`,
`world_server_manager`, and `loginserver_webserver` — physically separate from
the world/zone server binaries.
[loginserver/ directory listing](https://github.com/EQEmu/Server/tree/master/loginserver)
(files: `account_management.cpp`, `client.cpp`, `world_server.cpp`,
`world_server_manager.cpp`, `loginserver_webserver.cpp`).

### 1a. Login authority vs world/zone servers

- **World servers register *into* the login server**, not vice-versa. A world
  connects over a servertalk stream and sends `ServerOP_NewLSInfo`
  (`LoginserverNewWorldRequest`) carrying `server_long_name`, `server_short_name`,
  `remote_ip_address`, `local_ip_address`, `account_name`, `account_password`,
  and `server_process_type`. The login server handles it in
  `WorldServer::ProcessNewLSInfo` → `HandleNewWorldserver`.
  [world_server.cpp](https://raw.githubusercontent.com/EQEmu/Server/master/loginserver/world_server.cpp).
- **World registration is persisted and gated.** `HandleNewWorldserver` looks
  up the world in `login_world_servers` (`LoginWorldServersRepository`). If it is
  unknown, the login server auto-registers it **only if**
  `server.options.IsUnregisteredAllowed()`, otherwise it logs
  "not registered, and unregistered servers are not allowed" and refuses to list
  it. Registered worlds carry `is_server_trusted` and
  `login_server_list_type_id` (Standard/Preferred/Legends).
  [world_server.cpp](https://raw.githubusercontent.com/EQEmu/Server/master/loginserver/world_server.cpp).
- **Trust is a first-class flag.** Elevated cross-server operations require it:
  `WorldServer::ProcessLSAccountUpdate` (a world pushing an account
  email/password change back to the LS) executes **only** `if
  (m_is_server_trusted)`.
  [world_server.cpp](https://raw.githubusercontent.com/EQEmu/Server/master/loginserver/world_server.cpp).

> Project0 mapping — **maps:** LS↔world split ≈ Project0 login authority (UDP
> 9998, `server/login_server_main.gd`) vs assertion-only game server (UDP 9999).
> **Does not map:** EQEmu worlds self-register to the LS with a shared
> account/password over servertalk and share the LS account DB; Project0's game
> server holds no account DB and never registers "worlds" this way (ADR 0004).

### 1b. Account creation / registration model

- Player accounts live in `login_accounts` (`LoginAccountsRepository`).
  `AccountManagement::CreateLoginServerAccount(LoginAccountContext)` **dedups on
  username** — it returns `-1` if the account already exists, else inserts.
  [account_management.cpp](https://raw.githubusercontent.com/EQEmu/Server/master/loginserver/account_management.cpp).
- Passwords are hashed with `eqcrypt_hash(username, password, mode)` where `mode`
  is a configurable `EncryptionMode` (Argon2 / SHA512 / SHA / MD5, with `*Triple`
  variants). Verification is `eqcrypt_verify_hash(...)` in
  `CheckLoginserverUserCredentials`; weak hashes are **auto-upgraded** on a
  successful login (see `ValidateWorldServerAdminLogin`, which re-hashes to
  Argon2 when it detects an insecure source mode).
  [account_management.cpp](https://raw.githubusercontent.com/EQEmu/Server/master/loginserver/account_management.cpp),
  [world_server.cpp](https://raw.githubusercontent.com/EQEmu/Server/master/loginserver/world_server.cpp).
- **Federation exists.** `AccountManagement::CheckExternalLoginserverUserCredentials`
  opens a reliable stream to a *remote* EQEmu login server
  (`server.options.GetEQEmuLoginServerAddress()`), sends `OP_Login` with an
  encrypted username/password block, and returns the remote account id — i.e. a
  local LS can defer credential checks to a central authority
  (`source_loginserver = "eqemu"` vs `"local"`).
  [account_management.cpp](https://raw.githubusercontent.com/EQEmu/Server/master/loginserver/account_management.cpp).

> Project0 mapping — **maps:** the local-vs-external credential split ≈ Project0's
> public HTTPS enrollment surface loopback-delegating to the login authority
> (`/internal/verify-and-mint`, ADR 0004/0005). **Does not map:** EQEmu creates
> accounts against a SQL table with an app-chosen hash mode; Project0 mints a
> signed assertion rather than returning a raw account id.

### 1c. Client ↔ login ↔ world handshake and session/credential flow

1. **Client → login:** the client sends `OP_Login` (opcode `2`) with the
   username/password packed and block-encrypted (`eqcrypt_block`); the LS
   responds with the account id + a status code (`response_error`).
   [account_management.cpp](https://raw.githubusercontent.com/EQEmu/Server/master/loginserver/account_management.cpp).
2. **Login → client (server list):** `WorldServer::SerializeForClientServerList`
   writes per world: IP (local or remote), `server_id`, `server_long_name`,
   country code `"us"`, language `"en"`, a status flag (Up / Down / Locked), and
   `players_online`; server-list *type* (Standard/Preferred/Legends) is encoded
   too. `server_id == 0` makes the client hide the server.
   [world_server.cpp](https://raw.githubusercontent.com/EQEmu/Server/master/loginserver/world_server.cpp).
3. **Client selects a world → login asks that world:** the LS sends
   `ServerOP_UsertoWorld(Req)` and the world answers `UsertoWorldResponse`. The
   LS maps the world's verdict to a `PlayEverquestResponse` reason: `Success`,
   `WorldUnavail`, `Suspended`, `Banned`, `WorldAtCapacity`, `AlreadyOnline`.
   So capacity/ban/duplicate-session policy is enforced by the **world**, relayed
   through the LS.
   [world_server.cpp](https://raw.githubusercontent.com/EQEmu/Server/master/loginserver/world_server.cpp).
4. **Login → world (session credential):** on success the LS calls
   `SendClientAuthToWorld` → `ServerOP_LSClientAuth` with a `ClientAuth` struct:
   `loginserver_account_id`, `account_name`, a short **`key`** (the login key,
   `c->GetLoginKey()`), `ip_address`, `loginserver_name`, and
   `is_client_from_local_network`. The world subsequently trusts a client that
   presents that account id + key.
   [world_server.cpp](https://raw.githubusercontent.com/EQEmu/Server/master/loginserver/world_server.cpp).

> Project0 mapping — **maps:** the `ClientAuth.key` handed to the world ≈
> Project0's signed HMAC session/character assertion presented to the game
> server (`establish_session_from_assertion`); the `UsertoWorld` gate ≈ the game
> server accepting/refusing the assertion for capacity/ban reasons. **Does not
> map:** EQEmu's `key` is an **opaque, unsigned** token the world validates via
> the shared LS/DB back-channel; Project0's assertion is **cryptographically
> signed** and self-verifiable by the game server *without* a back-channel to the
> login authority (Slices 059/060). Also, EQEmu's client speaks its own protocol
> to the LS *before* any tunnel, whereas Project0 authenticates over public HTTPS
> *before* the WireGuard tunnel exists (ADR 0004).

### 1d. Server-list presentation surface

Besides the in-client list, the LS exposes an authenticated HTTP mirror: `GET
/v1/servers/list` returns JSON rows with `server_long_name`, `server_short_name`,
`server_list_type_id`, `server_status`, `zones_booted`, `local_ip`, `remote_ip`,
`players_online`, `world_id`.
[loginserver_webserver.cpp](https://raw.githubusercontent.com/EQEmu/Server/master/loginserver/loginserver_webserver.cpp).
Dev/test worlds are sorted to the bottom by name decoration (`|D|`, `|T|`,
`|I|`) in `WorldServer::FormatWorldServerName`.
[world_server.cpp](https://raw.githubusercontent.com/EQEmu/Server/master/loginserver/world_server.cpp).

**Implication for Project0:** EQEmu validates the split Project0 already chose — a
standalone login authority that owns accounts and a "which world" selection step,
plus per-world capacity/ban enforcement — but its session token is a
back-channel-validated opaque key. Project0's signed, self-verifying assertion is
strictly stronger; the reusable idea for a *unified launcher* is the explicit
**server-list → select → session-credential-to-server** sequence, which a
launcher can present as a UI even when Project0 currently ships a single world.

---

## Area 2 — Launcher / patcher update patterns

Four production patterns, each with a primary source. Focus: version manifest,
patch delivery (full vs delta), integrity/authenticity, atomic apply + rollback,
launcher-separate-from-payload.

### 2a. Squirrel.Windows — `RELEASES` manifest, SHA1, delta-or-full, versioned dirs

- **Manifest:** a `RELEASES` text file at the distribution URL is downloaded and
  compared to the local `RELEASES` to detect updates. Packages are verified
  against **their SHA1 recorded in `RELEASES`**.
  [update-process.md](https://github.com/Squirrel/Squirrel.Windows/blob/master/docs/using/update-process.md).
- **Delivery:** the `UpdateManager` chooses **deltas vs the latest full package
  by whichever requires less total download**, then **rebuilds a new full package
  from previous-full + delta**.
  [update-process.md](https://github.com/Squirrel/Squirrel.Windows/blob/master/docs/using/update-process.md).
- **Atomic apply:** the new version is extracted into a **new versioned install
  dir** `%LocalAppData%\MyApp\app-1.0.1`; shortcuts are repointed via
  `Update.exe --processStart`.
  [update-process.md](https://github.com/Squirrel/Squirrel.Windows/blob/master/docs/using/update-process.md).
- **Rollback/retention:** it keeps the **current and immediately previous
  version** and deletes older ones on next startup (e.g. after 1.0.5, 1.0.4
  remains but 1.0.3 is removed).
  [update-process.md](https://github.com/Squirrel/Squirrel.Windows/blob/master/docs/using/update-process.md).
- **Launcher separate from payload:** `Update.exe` is the stub updater, distinct
  from the app it installs/launches; packaging metadata (Id/Version) comes from
  the NuGet package.
  [nuget-package-metadata.md](https://github.com/Squirrel/Squirrel.Windows/blob/master/docs/using/nuget-package-metadata.md).

### 2b. Sparkle (macOS; WinSparkle/NetSparkle ports) — signed appcast + EdDSA

- **Manifest = appcast (RSS XML).** Each `<item>` has `<sparkle:version>`
  (machine-readable) + `<sparkle:shortVersionString>` (human), and an
  `<enclosure>` with `url`, `length` (**file size in bytes**), and
  `sparkle:edSignature`.
  [publishing/](https://sparkle-project.org/documentation/publishing/).
- **Integrity/authenticity:** updates **must be EdDSA (ed25519) signed**; the
  app embeds `SUPublicEDKey`; `sign_update` emits the signature+length; keys
  should be kept **off the hosting machine** so a server compromise can't sign.
  Optional `SURequireSignedFeed` signs the **whole appcast** (so an attacker who
  compromises the update server can't redirect users), and
  `SUVerifyUpdateBeforeExtraction` validates the archive **before** extraction.
  Serve over HTTPS.
  [documentation/ §3 security](https://sparkle-project.org/documentation/),
  [publishing/](https://sparkle-project.org/documentation/publishing/).
- **Delta delivery:** `generate_appcast` auto-produces `*.delta` incremental
  files; **Sparkle ignores a delta if the installed app's checksum doesn't
  match** the update's expected base — an implicit integrity guard on the delta
  base.
  [publishing/ (Delta updates)](https://sparkle-project.org/documentation/publishing/).
- **Gating/rollout:** `sparkle:minimumSystemVersion`,
  `sparkle:minimumAutoupdateVersion` (block silent auto-install of major
  upgrades), `sparkle:criticalUpdate`, phased rollout via
  `sparkle:phasedRolloutInterval`, and `sparkle:channel` (beta/stable).
  [publishing/](https://sparkle-project.org/documentation/publishing/).

### 2c. Tauri v2 updater — static `latest.json`, mandatory signature, downgrade hook

- **Manifest = static JSON** (`latest.json`) or a dynamic server. Fields:
  `version` (SemVer), `pub_date` (RFC 3339), and
  `platforms[OS-ARCH] = { url, signature }`. Required keys: `version`,
  `platforms.[target].url`, `platforms.[target].signature`. `endpoints` is an
  array of URLs; **TLS is enforced in production** (only
  `dangerousInsecureTransportProtocol` opts out). A dynamic server returns `204
  No Content` when no update, else `200` with the JSON.
  [Server Support](https://v2.tauri.app/plugin/updater/).
- **Integrity/authenticity:** signing **"cannot be disabled."** A keypair is
  generated (`tauri signer generate`); the **public key lives in
  `tauri.conf.json`** and validates artifacts before install; each artifact has
  a `.sig`. The private key must be kept safe — **losing it means you can no
  longer publish updates to already-installed users**. The public key can be set
  at **runtime** to support key rotation.
  [Signing updates / Public key](https://v2.tauri.app/plugin/updater/).
- **Rollback:** the `version_comparator` API can permit **downgrades** ("useful
  if you need to roll back your app"), and a dynamic server can push any version.
  [Allowing downgrades](https://v2.tauri.app/plugin/updater/).
- **Launcher/payload separation:** the updater is a plugin; on **Windows the app
  auto-exits before the installer runs** (`on_before_exit` hook), keeping the
  running binary separate from the install step. `installMode` (passive / basicUi
  / quiet) controls the Windows installer UX.
  [Windows before exit hook / installMode](https://v2.tauri.app/plugin/updater/).

### 2d. itch.io wharf / butler — rsync + bsdiff binary patching, open spec, channels

- **wharf is an open protocol to incrementally transfer builds with minimal
  time/bandwidth**, used in production at itch.io; the repo is the reference Go
  implementation with protobuf definitions, and the full spec is public.
  [wharf README](https://github.com/itchio/wharf),
  [wharf spec](https://itch.io/docs/wharf/).
- **Delivery = block sync + binary diff.** wharf contains modified
  `kardianos/rsync` (**rsync algorithm**, block-based diff) and `kr/binarydist`
  (**bsdiff binary-diff algorithm**) — i.e. it computes per-block and
  binary-delta patches rather than shipping whole files.
  [wharf README (License / contains modified code)](https://github.com/itchio/wharf).
- **Builds are organized into "channels"** and butler (the wharf client) can
  push builds, preview what would change, expose an **update-check API**, do
  **offline diff/patch**, and back a launcher via `butlerd`.
  [butler docs index](https://itch.io/docs/butler/),
  [butler intro](https://itch.io/docs/butler/).

**Implication for Project0:** Converging pattern across all four — a **signed
version manifest** enumerating artifacts with **per-file size + hash** and a
**manifest/artifact signature**, verified **before** any swap. Project0 already
signs assertions with HMAC and enforces HTTPS, so the launcher should reuse that
posture: sign the manifest, verify hashes, do an **atomic versioned-dir swap with
prior-version retention for rollback** (Squirrel), keep the **launcher binary
separate from the game payload** it patches (Squirrel `Update.exe` / Tauri
plugin), and prefer **delta patching** (Sparkle deltas / wharf rsync+bsdiff) only
as a bandwidth optimization gated by a base-checksum check. Signing is
non-negotiable (Tauri: "cannot be disabled"); keep signing keys off the host that
serves the manifest (Sparkle).

---

## Area 3 — Account onboarding in launchers: first-run login vs registration + abuse controls

### 3a. Where account creation happens (EQEmu)

EQEmu does **not** put self-service account creation in the game client login
flow by default — it is an **out-of-band / operator / web** action behind an
authenticated API:

- The LS web server exposes `POST /v1/account/create` (and
  `/v1/account/create/external`), but every write route is **gated by a Bearer
  API token with write scope** (`TokenManager::AuthCanWrite`, tokens loaded from
  `login_api_tokens` with `can_read` / `can_write`). Anonymous clients cannot hit
  it. The handler validates that username+password are present and returns
  `"Account already exists!"` on duplicate.
  [loginserver_webserver.cpp](https://raw.githubusercontent.com/EQEmu/Server/master/loginserver/loginserver_webserver.cpp).
- Read routes (`/v1/servers/list`, `/v1/account/credentials/validate/*`) require
  a **read** token (`AuthCanRead`). So registration in EQEmu is a
  **server-operator website/CLI calling a token-authenticated endpoint**, not an
  open in-client signup.
  [loginserver_webserver.cpp](https://raw.githubusercontent.com/EQEmu/Server/master/loginserver/loginserver_webserver.cpp).

> Project0 mapping — this matches Project0's *prior* invite-code delivery model
> (operator-minted, `infra/enrollment/cli.py mint-invite`, ADR 0004): keep
> registration gated/out-of-band and you sidestep most public-registration abuse
> controls. It contrasts with the *self-service* direction of ADR 0004's public
> HTTPS `/login`.

### 3b. Abuse controls for public self-service registration (OWASP, primary)

If registration is exposed publicly (self-service), the OWASP Authentication
Cheat Sheet prescribes:

- **No user enumeration on account creation.** Return a generic
  *"A link to activate your account has been emailed to the address provided"* —
  **not** *"This user ID is already in use"* — and avoid a timing/message
  **discrepancy factor** that lets an attacker enumerate existing accounts. Same
  generic-response rule applies to login and password recovery.
  [Authentication Cheat Sheet — Account creation / Authentication Responses](https://cheatsheetseries.owasp.org/cheatsheets/Authentication_Cheat_Sheet.html).
- **Verify contact before trusting it.** Allow email-as-username **only if the
  email is verified during sign-up**; account creation should emit an activation
  link rather than immediately confirming success.
  [Authentication Cheat Sheet — Usernames / Account creation](https://cheatsheetseries.owasp.org/cheatsheets/Authentication_Cheat_Sheet.html).
- **Throttling / lockout tied to the account, not the IP** (to defeat
  distributed attempts); consider **exponential** lockout; defend against Brute
  Force, Credential Stuffing, and Password Spraying (the three named automated
  attacks).
  [Authentication Cheat Sheet — Protect Against Automated Attacks / Login Throttling](https://cheatsheetseries.owasp.org/cheatsheets/Authentication_Cheat_Sheet.html).
- **CAPTCHA as defense-in-depth, not a preventative** — many CAPTCHAs are
  bypassable/outsourceable; prefer requiring it **after** a few failed attempts
  to preserve UX.
  [Authentication Cheat Sheet — CAPTCHA](https://cheatsheetseries.owasp.org/cheatsheets/Authentication_Cheat_Sheet.html).
- **TLS is mandatory** for the login/registration pages and all authenticated
  pages.
  [Authentication Cheat Sheet — Transmit Passwords Only Over TLS](https://cheatsheetseries.owasp.org/cheatsheets/Authentication_Cheat_Sheet.html).
- **Password policy:** length-first (weak if < 8 with MFA, < 15 without),
  max ≥ 64 to allow passphrases, allow all characters incl. unicode/whitespace,
  **block breached/common passwords** (e.g. Pwned Passwords), and **do not**
  mandate periodic rotation.
  [Authentication Cheat Sheet — Password Strength Controls](https://cheatsheetseries.owasp.org/cheatsheets/Authentication_Cheat_Sheet.html).
- Dedicated bot mitigation guidance exists in OWASP's **Bot Management and
  Anti-Automation Cheat Sheet** (referenced from the same series index).
  [Cheat Sheet index](https://cheatsheetseries.owasp.org/cheatsheets/Bot_Management_and_Anti-Automation_Cheat_Sheet.html).

**Implication for Project0:** Two viable onboarding shapes. (A) **Operator/invite-
gated** registration (EQEmu's token-gated `/account/create`; Project0's existing
`mint-invite`) — minimal abuse surface, defer public controls. (B) **Public
self-service** registration on the existing HTTPS surface — then it **must** add
generic (non-enumerating) responses, contact verification before minting the
first assertion, per-account **and** per-IP rate limiting, CAPTCHA/bot mitigation
as defense-in-depth, and breached-password blocking. Note `DT-009` already tracks
deferred rate-limiting for public `/login`; a public `/register` would extend the
same requirement. The launcher UI should present **first-run login vs
new-account** as distinct paths, but the *authority* for both stays on the login
server that mints the signed assertion — the launcher never validates
credentials itself.

---

## Executive summary (most decision-relevant)

- **EQEmu confirms Project0's split but with a weaker token.** LS↔world
  separation, a server-list→select→auth handshake, and world-side capacity/ban
  enforcement all map onto Project0; but EQEmu's `ClientAuth.key` is an opaque,
  back-channel-validated token, whereas Project0's **signed HMAC assertion is
  self-verifying** at the game server — keep that advantage.
  [world_server.cpp](https://raw.githubusercontent.com/EQEmu/Server/master/loginserver/world_server.cpp)
- **Every serious updater signs a version manifest and verifies before swap.**
  Squirrel `RELEASES`+SHA1, Sparkle appcast+EdDSA (+ optional signed feed), Tauri
  `latest.json`+mandatory signature. Adopt a **signed manifest with per-file
  size+hash**; Tauri's signing "cannot be disabled" is the right default.
- **Atomic apply = versioned staging dir + swap + retain N-1 for rollback**
  (Squirrel keeps current+previous and deletes older). This is the cheapest
  reliable rollback strategy and fits Project0's "reversible deploy unit" rule.
  [update-process.md](https://github.com/Squirrel/Squirrel.Windows/blob/master/docs/using/update-process.md)
- **Delta/binary patching is an optimization, not the trust boundary.** Sparkle
  deltas and itch wharf (rsync + bsdiff) reduce bandwidth but are always gated by
  a base-checksum/hash check; keep full-file replacement as the correctness
  fallback.
- **Onboarding is a policy fork.** Operator/invite-gated registration (EQEmu
  token-gated create; Project0 `mint-invite`) avoids most abuse controls; public
  self-service requires OWASP's full set (non-enumerating responses, contact
  verification, per-account+IP rate limiting, CAPTCHA/bot mitigation) — and
  extends the already-filed `DT-009` rate-limiting debt to `/register`.
  [loginserver_webserver.cpp](https://raw.githubusercontent.com/EQEmu/Server/master/loginserver/loginserver_webserver.cpp),
  [OWASP Authentication Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Authentication_Cheat_Sheet.html)
