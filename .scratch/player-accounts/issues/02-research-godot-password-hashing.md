Type: research
Status: resolved

## Question

What password-hashing and credential-verification primitives are available in
Godot 4 GDScript for a **server-side** credential check at trust level (b)
(home-hosted, invite-gated — real verification, not public-internet-grade)?

Investigate against primary sources (Godot 4 official docs, engine source):

- What does the `Crypto` class provide (HMAC, secure random bytes, constant-time
  comparison)? What does `HashingContext` provide (SHA-256 / SHA-512)?
- Is a real password KDF available (PBKDF2 / bcrypt / scrypt / argon2),
  natively or via a maintained GDExtension/addon? If only SHA/HMAC exist
  natively, what is the safe pattern — per-account cryptographically random salt
  + iterated derivation + constant-time compare?
- How to generate cryptographically secure random salts and session tokens
  (`Crypto.generate_random_bytes` and friends).
- Any known constraints running these primitives in a `--headless` server
  context.

Output: a recommended, minimal, safe server-side credential
storage-and-verification approach (what is stored, how it is derived, how it is
compared), with primary sources cited. Unblocks the credential-storage half of
the authentication model.

Findings file: `.scratch/player-accounts/research/02-godot-password-hashing.md`.

## Answer

Godot 4 exposes **no native password KDF** (no PBKDF2 / bcrypt / scrypt /
argon2) and **no SHA-512** — only MD5 / SHA-1 / SHA-256, with `Crypto.hmac_digest`
limited to SHA-1 / SHA-256 (source: `4.3-stable modules/mbedtls/crypto_mbedtls.cpp`).
Usable primitives: `Crypto.generate_random_bytes` (mbedTLS CTR_DRBG CSPRNG),
`Crypto.hmac_digest`, `Crypto.constant_time_compare`, `HashingContext`.

**Recommended server-side credential storage + verify:**

- Store per account: `algo="pbkdf2-sha256"`, `iterations`, a 16-byte per-account
  CSPRNG salt, and the 32-byte derived key. Never store plaintext or a bare
  single-round SHA-256.
- Derive with a **manual PBKDF2-HMAC-SHA256** built on `Crypto.hmac_digest`
  (SHA-256). Verify by re-deriving and comparing with
  `Crypto.constant_time_compare`. Run the derivation off the main thread and
  bound password length.
- Tune iterations to a measured latency budget (~100k–300k) and record it as a
  deliberate choice **below** OWASP's 600k baseline: pure-GDScript PBKDF2 cannot
  reach 600k in <1s and PBKDF2 is not memory-hard. Acceptable **only** at this
  home-hosted / invite-gated trust level; explicitly not public-internet-grade.
- Sessions: `generate_random_bytes(32)` token; persist only its SHA-256 and
  compare constant-time. Secure the ENet transport (native `generate_rsa` +
  `generate_self_signed_certificate`) — client-side hashing is not a substitute.

**Open (decide in the authentication-model ticket):** exact iteration count
(measure on the real host); whether to adopt an Argon2id GDExtension (biggest
security lever, but a dependency/rollback decision under AGENTS.md — no
currently-maintained Godot 4.3/4.4 one verified from a primary source); optional
pepper; session-token TTL and reconnect behavior; and confirming the server
binary is built with the mbedTLS module before relying on `Crypto` under
`--headless`.

Full findings with primary-source citations:
[research/02-godot-password-hashing.md](../research/02-godot-password-hashing.md).
