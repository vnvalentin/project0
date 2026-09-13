Type: research finding
Status: complete
Date: 2026-09-13
Godot target: 4.3 / 4.4 (verified against 4.3 docs, 4.3-stable engine source, and current stable/4.7 docs)
Scope: server-side credential storage + verification for a home-hosted, invite-gated server (trust level (b) per [map.md](../map.md)); NOT public-internet-grade.

---

## Summary / Recommendation (TL;DR)

Godot 4 ships **SHA-256 hashing, HMAC-SHA256, a real CSPRNG, and a constant-time
comparator** — but **no native password KDF** (no PBKDF2 / bcrypt / scrypt /
argon2 binding), and **no maintained KDF addon in the official Asset Library**.
For the stated home-hosted, invite-gated threat model, the minimal safe approach
is a **manual PBKDF2-HMAC-SHA256** built on `Crypto.hmac_digest`:

- **Store, per account:** `algo` (`"pbkdf2-sha256"`), `iterations` (int),
  a **per-account 16-byte CSPRNG salt**, and the **32-byte derived key**. Never
  store the plaintext or a bare SHA-256 of the password.
- **Derive:** `DK = PBKDF2(PRF=HMAC-SHA256, password_utf8, salt, iterations, dkLen=32)`,
  implemented by iterating `Crypto.hmac_digest(HashingContext.HASH_SHA256, password, …)`
  (RFC 8018). Salt from `Crypto.generate_random_bytes(16)`.
- **Verify:** re-derive from the submitted password + stored salt + stored
  iterations, then compare with **`Crypto.constant_time_compare(stored_dk, candidate)`**.
- **Tune iterations to a latency budget.** OWASP's FIPS baseline is 600,000
  iterations of PBKDF2-HMAC-SHA256, but **pure-GDScript PBKDF2 cannot reach that
  in <1 s** (each iteration is a GDScript→C++ HMAC call). Pick the largest count
  your server tolerates (measure; ~100k–300k is a realistic starting range for a
  handful of accounts), run it **off the main server thread**, and document that
  the security margin is below a native memory-hard KDF — acceptable **only**
  under this modest threat model.
- **This code is server-only** (per CLAUDE.md: secrets and outcome computation
  live on the authoritative server). Client-side hashing is **not** a substitute;
  instead secure the transport (Godot can do DTLS/TLS for ENet using
  `Crypto.generate_rsa` + `generate_self_signed_certificate`) and hash on the server.
- **If you want a memory-hard KDF (Argon2id/scrypt/bcrypt)** you must add and
  audit a third-party GDExtension — a human decision gated by the repo rule
  "no new dependencies without documented safety/rollback" (AGENTS.md).

---

## Threat model note

The [map](../map.md) fixes trust level (b): home-hosted, invite-gated, real
server-side credential verification, explicitly **not** public-internet-grade
(no email recovery, OAuth, MFA, or anti-abuse rate limiting in scope). The
recommendation below is calibrated to that: correct salting + constant-time
compare + a tuned iterated KDF, while being honest that PBKDF2 in interpreted
GDScript is weaker than a native memory-hard KDF.

---

## 1. What Godot 4 provides natively

All three classes inherit `RefCounted` (no scene tree / display / rendering
dependency), so they are usable in a `--headless` server. The crypto backend is
the bundled **mbedTLS module**; if that module were absent, `Crypto` operations
fail (see §9).

| Primitive | Exact signature | Returns | Source |
| --- | --- | --- | --- |
| Secure random | `Crypto.generate_random_bytes(size: int)` | `PackedByteArray` | [class_crypto (4.3)](https://docs.godotengine.org/en/4.3/classes/class_crypto.html#class-crypto-method-generate-random-bytes) |
| HMAC (one-shot) | `Crypto.hmac_digest(hash_type: HashingContext.HashType, key: PackedByteArray, msg: PackedByteArray)` | `PackedByteArray` | [class_crypto (4.3)](https://docs.godotengine.org/en/4.3/classes/class_crypto.html#class-crypto-method-hmac-digest) |
| Constant-time compare | `Crypto.constant_time_compare(trusted: PackedByteArray, received: PackedByteArray)` | `bool` | [class_crypto (4.3)](https://docs.godotengine.org/en/4.3/classes/class_crypto.html#class-crypto-method-constant-time-compare) |
| RSA key (for TLS certs) | `Crypto.generate_rsa(size: int)` | `CryptoKey` | [class_crypto (4.3)](https://docs.godotengine.org/en/4.3/classes/class_crypto.html#class-crypto-method-generate-rsa) |
| Self-signed cert (for DTLS) | `Crypto.generate_self_signed_certificate(key, issuer_name, not_before, not_after)` | `X509Certificate` | [class_crypto (4.3)](https://docs.godotengine.org/en/4.3/classes/class_crypto.html#class-crypto-method-generate-self-signed-certificate) |
| Hash (one-shot/streaming) | `HashingContext.start(type)` / `update(chunk)` / `finish()` | `Error` / `Error` / `PackedByteArray` | [class_hashingcontext (4.3)](https://docs.godotengine.org/en/4.3/classes/class_hashingcontext.html) |
| HMAC (streaming) | `HMACContext.start(hash_type, key)` / `update(data)` / `finish()` | `Error` / `Error` / `PackedByteArray` | [class_hmaccontext](https://docs.godotengine.org/en/stable/classes/class_hmaccontext.html) |

`Crypto` also exposes `encrypt` / `decrypt` / `sign` / `verify` (RSA/asymmetric),
which are **not** relevant to password storage and are listed only for
completeness ([class_crypto](https://docs.godotengine.org/en/4.3/classes/class_crypto.html)).

---

## 2. Hash algorithms available — and the SHA-512 gap

`HashingContext.HashType` enumerates **only** MD5, SHA-1, SHA-256. **There is no
SHA-512 (and no SHA-3) in Godot 4.x.**

- `HASH_MD5 = 0`, `HASH_SHA1 = 1`, `HASH_SHA256 = 2` — [class_hashingcontext (4.3), Enumerations](https://docs.godotengine.org/en/4.3/classes/class_hashingcontext.html#enum-hashingcontext-hashtype); identical in [stable/4.7](https://docs.godotengine.org/en/stable/classes/class_hashingcontext.html#enum-hashingcontext-hashtype).
- Confirmed in engine source — the only mapped types are MD5/SHA1/SHA256, and any
  other value fails with "Invalid hash type":

  ```cpp
  // modules/mbedtls/crypto_mbedtls.cpp — CryptoMbedTLS::md_type_from_hashtype
  case HashingContext::HASH_MD5:    r_size = 16; return MBEDTLS_MD_MD5;
  case HashingContext::HASH_SHA1:   r_size = 20; return MBEDTLS_MD_SHA1;
  case HashingContext::HASH_SHA256: r_size = 32; return MBEDTLS_MD_SHA256;
  default: r_size = 0; ERR_FAIL_V_MSG(MBEDTLS_MD_NONE, "Invalid hash type.");
  ```

  Source: [godot 4.3-stable `modules/mbedtls/crypto_mbedtls.cpp`](https://github.com/godotengine/godot/blob/4.3-stable/modules/mbedtls/crypto_mbedtls.cpp).

**Consequence:** the strongest hash you can use is **SHA-256** (32-byte output).
Plan around SHA-256; SHA-512-based variants (e.g. PBKDF2-HMAC-SHA512) are not
possible with native primitives.

---

## 3. HMAC is restricted to SHA-1 / SHA-256

Even though `HashType` includes MD5, **HMAC rejects MD5** and allows only SHA-1
and SHA-256.

- Docs: "Currently, only `HashingContext.HASH_SHA256` and
  `HashingContext.HASH_SHA1` are supported." — [class_crypto (4.3), `hmac_digest`](https://docs.godotengine.org/en/4.3/classes/class_crypto.html#class-crypto-method-hmac-digest).
- Source of truth (hard allow-list):

  ```cpp
  // modules/mbedtls/crypto_mbedtls.cpp — HMACContextMbedTLS::is_md_type_allowed
  switch (p_md_type) {
      case MBEDTLS_MD_SHA1:
      case MBEDTLS_MD_SHA256:
          return true;
      default:
          return false;   // MD5 and everything else rejected: "Unsupported hash type."
  }
  ```

  Source: [godot 4.3-stable `modules/mbedtls/crypto_mbedtls.cpp`](https://github.com/godotengine/godot/blob/4.3-stable/modules/mbedtls/crypto_mbedtls.cpp).
- `Crypto.hmac_digest` is itself a thin wrapper over `HMACContext`
  (`core/crypto/crypto.cpp`), and requires the mbedTLS module: it errors with
  "HMAC is not available without mbedtls module." — [godot 4.3-stable `core/crypto/crypto.cpp`](https://github.com/godotengine/godot/blob/4.3-stable/core/crypto/crypto.cpp).

**Use `HashingContext.HASH_SHA256` for HMAC.** (Do not use SHA-1 for new work.)

Practical constraints from source: `HMACContext.start` **rejects an empty key**
("Key must not be empty.") and `update` **rejects empty data** — both matter for
the PBKDF2 loop (password key and message inputs are always non-empty there).

---

## 4. Secure random generation (salts + session tokens)

`Crypto.generate_random_bytes(size)` is a **cryptographically secure** DRBG, not
`RandomNumberGenerator`/`randi()`.

- Docs: "Generates a `PackedByteArray` of cryptographically secure random bytes
  with given `size`." — [class_crypto (4.3), `generate_random_bytes`](https://docs.godotengine.org/en/4.3/classes/class_crypto.html#class-crypto-method-generate-random-bytes).
- Source: it uses mbedTLS **CTR_DRBG**, seeded from the mbedTLS entropy source in
  the `CryptoMbedTLS` constructor (`mbedtls_ctr_drbg_seed(&ctr_drbg, mbedtls_entropy_func, …)`),
  and draws bytes via `mbedtls_ctr_drbg_random` in `MBEDTLS_CTR_DRBG_MAX_REQUEST`
  chunks. Source: [godot 4.3-stable `modules/mbedtls/crypto_mbedtls.cpp`](https://github.com/godotengine/godot/blob/4.3-stable/modules/mbedtls/crypto_mbedtls.cpp).
- **Error mode:** on failure it returns an **empty** `PackedByteArray` — always
  check `result.size() == requested` before use.

**Encoding for storage.** Bytes can be stored directly as SQLite `BLOB`
(the chosen persistence engine — no encoding needed). If a text form is required:
`PackedByteArray.hex_encode()` (used in the official HashingContext example —
[class_hashingcontext](https://docs.godotengine.org/en/stable/classes/class_hashingcontext.html)),
or base64 via `Marshalls.raw_to_base64()` / `Marshalls.base64_to_raw()`.

Recommended sizes: **salt = 16 bytes (128-bit)**; **session token = 32 bytes
(256-bit)**.

---

## 5. Constant-time comparison

`Crypto.constant_time_compare(trusted, received) -> bool` "compares two
`PackedByteArray`s for equality without leaking timing information in order to
prevent timing attacks." — [class_crypto (4.3), `constant_time_compare`](https://docs.godotengine.org/en/4.3/classes/class_crypto.html#class-crypto-method-constant-time-compare)
(the docs cite the Paragonie double-HMAC write-up). Implemented in the base
`Crypto` class (`core/crypto/crypto.cpp`), so it is available whenever `Crypto`
is. **Use it for every password-hash and token comparison** instead of `==`.

---

## 6. Is a real password KDF available? (PBKDF2 / bcrypt / scrypt / argon2)

**Natively: No.**

- The Godot 4 class reference exposes no `PBKDF2`, `Argon2`, `Bcrypt`, or `Scrypt`
  class or method; the entire crypto surface is the classes in §1
  ([class list is authoritative for the GDScript API](https://docs.godotengine.org/en/stable/classes/index.html)).
- The mbedTLS backend implements only key/cert handling, HMAC, `generate_random_bytes`,
  hash-type mapping, `sign`/`verify`, and `encrypt`/`decrypt` — **no `pbkdf2` /
  `argon2` / `scrypt` / `bcrypt`** anywhere in the file. Source (full method set
  inspected): [godot 4.3-stable `modules/mbedtls/crypto_mbedtls.cpp`](https://github.com/godotengine/godot/blob/4.3-stable/modules/mbedtls/crypto_mbedtls.cpp).
  (mbedTLS *ships* a PKCS#5 PBKDF2 internally, but Godot does not bind it to
  GDScript.)

**Via addon: none through the official channel (verify before adopting any).**

- The official **Godot Asset Library** returns **zero** results for `argon2` and
  `bcrypt` filtered to Godot 4.3:
  `{"result":[],"total_items":0}` for both —
  [asset-library API `filter=argon2`](https://godotengine.org/asset-library/api/asset?filter=argon2&godot_version=4.3),
  [`filter=bcrypt`](https://godotengine.org/asset-library/api/asset?filter=bcrypt&godot_version=4.3).
- Independent native GDExtensions (e.g. wrappers around libsodium/argon2) exist
  in the wider GitHub ecosystem, but I could not confirm a currently-maintained,
  Godot-4.3/4.4-verified one from a primary source. Adopting one is a **human
  decision** requiring a maintenance + security audit and, per
  [AGENTS.md](../../../AGENTS.md), documented safety/rollback for the new
  dependency. **Open uncertainty — see the last section.**

---

## 7. Recommended safe pattern — manual PBKDF2-HMAC-SHA256

PBKDF2 (RFC 8018 / RFC 2898) is defined with a pseudo-random function; with
**PRF = HMAC-SHA256** it maps directly onto `Crypto.hmac_digest`. Because our
derived-key length (32 bytes) equals the SHA-256 output length, PBKDF2 needs
**only block index 1** — no outer block loop, which keeps the GDScript simple:

```
DK      = U_1 XOR U_2 XOR … XOR U_c
U_1     = HMAC-SHA256(key = password, msg = salt || INT32_BE(1))
U_j     = HMAC-SHA256(key = password, msg = U_{j-1})   for j = 2..c   (c = iterations)
```

Reference implementation (illustrative — the downstream slice owns the tested,
strictly-typed version; this is **server-only** code):

```gdscript
# server-side only. Never runs on the client.
const ALGO_ID := "pbkdf2-sha256"
const SALT_LEN := 16            # 128-bit per-account CSPRNG salt
const DK_LEN := 32             # 256-bit derived key == HMAC-SHA256 output
const ITERATIONS := 200_000    # TUNE to a per-login latency budget (see §10)
const MAX_PASSWORD_BYTES := 128 # bound work; avoids long-password DoS

static func make_salt() -> PackedByteArray:
    return Crypto.new().generate_random_bytes(SALT_LEN)   # check .size() == SALT_LEN

static func derive(password_utf8: PackedByteArray, salt: PackedByteArray, iterations: int) -> PackedByteArray:
    var crypto := Crypto.new()
    var msg := salt.duplicate()
    msg.append_array(PackedByteArray([0, 0, 0, 1]))       # INT32_BE(block index 1)
    var u := crypto.hmac_digest(HashingContext.HASH_SHA256, password_utf8, msg)
    var out := u.duplicate()
    for _i in iterations - 1:
        u = crypto.hmac_digest(HashingContext.HASH_SHA256, password_utf8, u)
        for j in DK_LEN:
            out[j] ^= u[j]
    return out                                            # 32 bytes

static func verify(password_utf8: PackedByteArray, salt: PackedByteArray, expected_dk: PackedByteArray, iterations: int) -> bool:
    if password_utf8.is_empty() or password_utf8.size() > MAX_PASSWORD_BYTES:
        return false
    var candidate := derive(password_utf8, salt, iterations)
    return Crypto.new().constant_time_compare(expected_dk, candidate)
```

Enrollment (create account): generate a fresh salt, derive, store the record.
Verify (login): load the account's `salt` + `iterations` + `dk`, re-derive, and
`constant_time_compare`.

**Stored record (per account).** In the chosen SQLite engine, store as columns:

| column | type | value |
| --- | --- | --- |
| `algo` | TEXT | `"pbkdf2-sha256"` |
| `iterations` | INTEGER | e.g. `200000` (kept per-record so it can be raised later) |
| `salt` | BLOB | 16 CSPRNG bytes |
| `pw_hash` | BLOB | 32-byte derived key |

Portable text alternative (PHC-style, if you prefer a single string):
`$pbkdf2-sha256$i=200000$<base64(salt)>$<base64(dk)>`. OWASP recommends storing
algorithm + work factor with the hash so it can be upgraded —
[OWASP Password Storage, Upgrading the Work Factor](https://cheatsheetseries.owasp.org/cheatsheets/Password_Storage_Cheat_Sheet.html#upgrading-the-work-factor).

**Why each element:**

- **Per-account random salt** defeats rainbow tables and forces the attacker to
  crack each account separately — [OWASP Password Storage, Salting](https://cheatsheetseries.owasp.org/cheatsheets/Password_Storage_Cheat_Sheet.html#salting).
- **Many HMAC-SHA256 iterations** are the work factor that slows brute force —
  [OWASP Password Storage, Using Work Factors](https://cheatsheetseries.owasp.org/cheatsheets/Password_Storage_Cheat_Sheet.html#using-work-factors).
- **Constant-time compare** removes the timing side channel (§5).
- **Max password length** bounds per-login CPU (a real PBKDF2 DoS class; see the
  2013 Django advisory referenced by
  [OWASP Password Storage, PBKDF2 Pre-Hashing](https://cheatsheetseries.owasp.org/cheatsheets/Password_Storage_Cheat_Sheet.html#pbkdf2-pre-hashing)).

---

## 8. Session tokens

- Generate `Crypto.generate_random_bytes(32)` → a 256-bit token; send it to the
  client as `hex_encode()` (or base64) **over an encrypted channel**.
- Store server-side **only a SHA-256 of the token** (via `HashingContext`), not
  the token itself, so a leak of the session store does not yield live tokens.
  On each request, hash the presented token and `constant_time_compare` against
  the stored value.

```gdscript
var token_bytes := Crypto.new().generate_random_bytes(32)   # 256-bit
var token_wire := token_bytes.hex_encode()                  # -> client
var ctx := HashingContext.new()
ctx.start(HashingContext.HASH_SHA256)
ctx.update(token_bytes)
var token_lookup := ctx.finish()                            # store this, not the token
```

Transport confidentiality is a **dependency, not part of this file**: do not rely
on client-side hashing to protect the password in transit. Godot supports
DTLS/TLS for ENet, and the enabling primitives are native (`Crypto.generate_rsa`
+ `Crypto.generate_self_signed_certificate`, §1). Securing the ENet channel is a
separate design point for the auth slice.

---

## 9. `--headless` server constraints

- **No documented headless restriction.** `Crypto`, `HashingContext`, and
  `HMACContext` are `RefCounted` with no `DisplayServer`/`RenderingServer`
  dependency ([class_crypto](https://docs.godotengine.org/en/4.3/classes/class_crypto.html),
  [class_hashingcontext](https://docs.godotengine.org/en/4.3/classes/class_hashingcontext.html)),
  so they run in `godot --headless`.
- **One real requirement: the mbedTLS module must be compiled in.** The backend
  is `CryptoMbedTLS`; without the module, `Crypto`/HMAC fail ("HMAC is not
  available without mbedtls module.") — [godot 4.3-stable `core/crypto/crypto.cpp`](https://github.com/godotengine/godot/blob/4.3-stable/core/crypto/crypto.cpp).
  **Official Godot binaries and export templates (desktop + server) include
  mbedTLS**, so a standard `godot`/`godot.linuxbsd.template_release` build is
  fine; only an unusual custom build with `module_mbedtls_enabled=no` would break
  it. (Validate on the actual server binary before relying on it — see open
  questions.)
- **Performance is the practical constraint, not availability.** The KDF loop is
  interpreted GDScript crossing into C++ once per iteration; it is single-threaded
  and will block the caller. Run derivation on a worker `Thread` so it never
  stalls the authoritative simulation tick, and keep iteration counts within a
  measured latency budget (§10).

---

## 10. Honest security tradeoffs (PBKDF2 in GDScript vs a memory-hard KDF)

- **PBKDF2 is not memory-hard.** It resists CPU brute force via iteration count
  but is cheaply parallelizable on GPUs/ASICs, so per-dollar it is weaker than a
  memory-hard KDF. OWASP's ordered preference is **Argon2id > scrypt > bcrypt >
  PBKDF2**, with PBKDF2 positioned as the choice "when FIPS-140 / NIST compliance
  is required." — [OWASP Password Storage, Password Hashing Algorithms](https://cheatsheetseries.owasp.org/cheatsheets/Password_Storage_Cheat_Sheet.html#password-hashing-algorithms).
- **Iteration guidance vs GDScript reality.** OWASP's baseline is
  **PBKDF2-HMAC-SHA256 = 600,000 iterations** (and a hash "should take less than
  one second") — [OWASP Password Storage, PBKDF2](https://cheatsheetseries.owasp.org/cheatsheets/Password_Storage_Cheat_Sheet.html#pbkdf2).
  A **native** implementation hits that in well under a second; a **pure-GDScript**
  loop of 600k HMAC calls will typically take several seconds and allocate heavily.
  So there is a genuine tension: matching OWASP's count costs unacceptable login
  latency, while a comfortable-latency count (e.g. ~100k–300k, **measure on the
  real server**) sits below the FIPS baseline. **For a home-hosted, invite-gated
  server with a few known accounts and low login volume this is a defensible
  tradeoff**, but it must be recorded as a deliberate, below-baseline choice —
  and it is explicitly **not** public-internet-grade (which the map already
  places out of scope).
- **If stronger is wanted later:** adopt a vetted Argon2id GDExtension (moves the
  heavy loop into native code, gains memory-hardness, and can then meet OWASP's
  Argon2id parameters). That is a dependency decision (audit + rollback doc per
  AGENTS.md), not a native capability.
- **Optional hardening (cheap, in-scope-friendly):** a server-side **pepper**
  (an HMAC key stored outside the DB) applied around the hash adds defense-in-depth
  if the DB alone leaks — [OWASP Password Storage, Peppering](https://cheatsheetseries.owasp.org/cheatsheets/Password_Storage_Cheat_Sheet.html#peppering);
  and to avoid username-enumeration timing, run a dummy `derive()` when the
  account is unknown so login timing is uniform.

---

## Version notes (4.3 vs 4.4 vs stable/4.7)

The relevant API is **stable across Godot 4.x** — no behavioral difference for
4.3 or 4.4:

- `HashType` = {MD5, SHA1, SHA256} in both [4.3](https://docs.godotengine.org/en/4.3/classes/class_hashingcontext.html#enum-hashingcontext-hashtype)
  and [stable/4.7](https://docs.godotengine.org/en/stable/classes/class_hashingcontext.html#enum-hashingcontext-hashtype) (no SHA-512 added).
- `hmac_digest` restricted to SHA-256/SHA-1 in both [4.3](https://docs.godotengine.org/en/4.3/classes/class_crypto.html#class-crypto-method-hmac-digest)
  and [stable](https://docs.godotengine.org/en/stable/classes/class_crypto.html#class-crypto-method-hmac-digest); the `is_md_type_allowed` allow-list is unchanged in current source.
- `generate_random_bytes` and `constant_time_compare` present and unchanged in
  [4.3](https://docs.godotengine.org/en/4.3/classes/class_crypto.html) and stable.
- 4.4 falls between the two verified points and shares the same API; no KDF class
  was introduced in any 4.x.

---

## Primary sources

| # | Source (owner of the claim) | Used for |
| --- | --- | --- |
| 1 | [Godot 4.3 docs — `Crypto`](https://docs.godotengine.org/en/4.3/classes/class_crypto.html) | Method signatures: `generate_random_bytes`, `hmac_digest` (SHA256/SHA1 only), `constant_time_compare`, `generate_rsa`, `generate_self_signed_certificate` |
| 2 | [Godot 4.3 docs — `HashingContext`](https://docs.godotengine.org/en/4.3/classes/class_hashingcontext.html) | `HashType` enum (MD5/SHA1/SHA256; no SHA-512); `start`/`update`/`finish` |
| 3 | [Godot docs — `HMACContext`](https://docs.godotengine.org/en/stable/classes/class_hmaccontext.html) | Streaming HMAC API |
| 4 | [Godot stable/4.7 docs — `Crypto`](https://docs.godotengine.org/en/stable/classes/class_crypto.html) / [`HashingContext`](https://docs.godotengine.org/en/stable/classes/class_hashingcontext.html) | Cross-version confirmation (unchanged) |
| 5 | [godot 4.3-stable `modules/mbedtls/crypto_mbedtls.cpp`](https://github.com/godotengine/godot/blob/4.3-stable/modules/mbedtls/crypto_mbedtls.cpp) | Source of truth: `is_md_type_allowed` (SHA1/SHA256), `md_type_from_hashtype` (no SHA-512), CTR_DRBG in `generate_random_bytes`, **no PBKDF2/argon2/bcrypt/scrypt** |
| 6 | [godot 4.3-stable `core/crypto/crypto.cpp`](https://github.com/godotengine/godot/blob/4.3-stable/core/crypto/crypto.cpp) | `hmac_digest` wraps `HMACContext`; "HMAC is not available without mbedtls module." |
| 7 | [Godot Asset Library API — `argon2`](https://godotengine.org/asset-library/api/asset?filter=argon2&godot_version=4.3) / [`bcrypt`](https://godotengine.org/asset-library/api/asset?filter=bcrypt&godot_version=4.3) | No maintained KDF addon in the official channel (0 results) |
| 8 | [OWASP Password Storage Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Password_Storage_Cheat_Sheet.html) | Salting, work factors, PBKDF2-HMAC-SHA256 = 600k iterations, algorithm ordering, upgrade/pepper guidance |
| 9 | [RFC 8018 (PKCS #5 / PBKDF2)](https://www.rfc-editor.org/rfc/rfc8018) | PBKDF2 algorithm definition reproduced in §7 |

---

## Open questions for human decision

1. **Iteration count vs latency:** what per-login latency is acceptable on the
   actual server host? Measure pure-GDScript PBKDF2 throughput there and pick the
   largest count under that budget; record it as a deliberate below-OWASP-baseline
   choice for this trust level.
2. **Native memory-hard KDF?** Decide whether to add/audit an Argon2id (or scrypt)
   GDExtension for a stronger margin, or accept PBKDF2-in-GDScript. This is the
   single biggest security lever and is a dependency/rollback decision under
   AGENTS.md.
3. **Pepper:** adopt a server-held pepper (extra defense if only the DB leaks)?
   Requires a secret-storage location outside the DB and a rotation story.
4. **Session-token storage:** store a SHA-256 of the token (recommended) vs the
   raw token; and the token TTL / reconnect-reauth behavior (the map lists these
   as not-yet-specified).
5. **Build validation:** confirm the server binary actually used for Project0 is
   built with the mbedTLS module (standard official builds are), so `Crypto` is
   present under `--headless`.
6. **Transport security:** the auth slice must secure the ENet channel (DTLS via
   `generate_rsa` + `generate_self_signed_certificate`) so the plaintext password
   is protected in transit — out of scope here but a hard prerequisite.
