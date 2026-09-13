Type: research finding
Status: complete
Date: 2026-09-13
Godot target: 4.3 (verified against 4.3 docs and the 4.3-stable engine source `modules/mbedtls/crypto_mbedtls.cpp`)
Scope: verifying the **integrity and authenticity** of a downloaded client patch **before** it is loaded/executed, for the home-hosted, invite-gated Windows tester build — **unsigned** (no public code-signing certificate) per [map.md](../map.md). Auto-update is remote code delivery, so the design is **fail-closed**. Feeds [07-integrity-and-trust](../issues/07-integrity-and-trust.md).

---

## Summary / Recommendation (TL;DR)

Godot 4.3 GDScript **does** provide everything needed for a real verify-before-apply
scheme, natively, with no third-party dependency:

- **`Crypto.sign()` / `Crypto.verify()` exist and are RSA** (via `CryptoKey` from
  `Crypto.generate_rsa`), accepting a `HashingContext.HashType` — and **SHA-256 is
  an accepted type** (`sign(HASH_SHA256, digest, key)` / `verify(HASH_SHA256,
  digest, signature, key)`). Confirmed in the class reference **and** the engine
  source (`CryptoMbedTLS::sign`/`verify` → `mbedtls_pk_sign`/`mbedtls_pk_verify`).
- **`verify()` accepts a public-only key** (only `sign()` rejects public-only), so
  the client can bundle **only the trusted public key** and never possess the
  private key.
- **`HashingContext`** streams a large `.pck` through SHA-256 chunk-by-chunk
  (`start`/`update`/`finish`) without loading it all in memory — this is the exact
  official example.
- **`Crypto.generate_random_bytes` (CSPRNG)** and **`Crypto.constant_time_compare`**
  are available for nonces and timing-safe digest comparison.

**Recommended minimal scheme (native RSA-signed manifest):**

1. **Hash the patch:** `patch_sha256 = SHA-256(Project0.pck)` computed by streaming
   the file through `HashingContext`.
2. **Sign a manifest, not the pck:** the server operator, **offline**, builds an
   `update manifest` (JSON: required `client build version`, `patch_sha256` hex,
   byte size, patch URL) and signs the **SHA-256 digest of the canonical manifest
   bytes** with a **private RSA key that never leaves the operator's machine**
   (`Crypto.sign(HASH_SHA256, manifest_digest, private_key)`).
3. **Ship the public key inside the client** as a PEM string constant / bundled
   `res://` file, loaded with `CryptoKey.load_from_string(PUBLIC_KEY_PEM, true)`
   (`public_only = true`).
4. **Verify before apply, fail-closed:** client fetches the manifest + signature,
   calls `Crypto.verify(HASH_SHA256, SHA-256(manifest_bytes), signature,
   public_key)`; **only if true**, downloads the pck, recomputes its SHA-256, and
   `Crypto.constant_time_compare`s it to the manifest's `patch_sha256`; **only if
   equal** does it hand the pck to the apply step. Any failure ⇒ refuse, keep the
   prior known-good client, emit telemetry, never `load_resource_pack`.

**Trust-level honesty:** this authenticates the **artifact's publisher** (whoever
holds the private key) independently of the transport, which is exactly what TLS
cannot do. It is acceptable **only** because the trust anchor — the bundled public
key — rides inside the already-installed, out-of-band-delivered client. It does
**not** give you: OS-level code-signing / SmartScreen trust, protection if the
signing private key leaks, protection if an attacker can already write to the
installed client on disk (they could swap the public key), rollback-attack
prevention by itself (the manifest must also be version-bound and monotonic), or
revocation. Those are outside this home-hosted / invite-gated threat model.

---

## Threat model note

Per [map.md](../map.md): the packaged Windows tester client is delivered out of
band today (manual versioned ZIP), the server is home-hosted and invite-gated, and
there is **no public code-signing certificate** (`export_presets.cfg` has
`codesign/enable=false`). The asset we must protect is **executable code** (the
`.pck` carries scripts/scenes), so the bar is "a downloaded patch cannot be
tampered with or substituted by a network attacker or a compromised download
host without detection, and an unverifiable patch is never executed." A
publisher-signed manifest verified against a key baked into the prior client meets
that bar; it is deliberately weaker than public-CA code signing, which is out of
scope.

---

## 1. `Crypto` class — `sign` / `verify`, hashing type, CSPRNG, constant-time compare

All of these live on `Crypto` (inherits `RefCounted`, so usable in a `--headless`
build). The backend is the bundled **mbedTLS** module.

| Primitive | Exact signature | Returns | Source |
| --- | --- | --- | --- |
| Sign a hash (asymmetric) | `Crypto.sign(hash_type: HashType, hash: PackedByteArray, key: CryptoKey)` | `PackedByteArray` | [class_crypto (4.3), `sign`](https://docs.godotengine.org/en/4.3/classes/class_crypto.html#class-crypto-method-sign) |
| Verify a signature | `Crypto.verify(hash_type: HashType, hash: PackedByteArray, signature: PackedByteArray, key: CryptoKey)` | `bool` | [class_crypto (4.3), `verify`](https://docs.godotengine.org/en/4.3/classes/class_crypto.html#class-crypto-method-verify) |
| RSA keygen | `Crypto.generate_rsa(size: int)` | `CryptoKey` | [class_crypto (4.3), `generate_rsa`](https://docs.godotengine.org/en/4.3/classes/class_crypto.html#class-crypto-method-generate-rsa) |
| Secure random | `Crypto.generate_random_bytes(size: int)` | `PackedByteArray` | [class_crypto (4.3), `generate_random_bytes`](https://docs.godotengine.org/en/4.3/classes/class_crypto.html#class-crypto-method-generate-random-bytes) |
| Constant-time compare | `Crypto.constant_time_compare(trusted: PackedByteArray, received: PackedByteArray)` | `bool` | [class_crypto (4.3), `constant_time_compare`](https://docs.godotengine.org/en/4.3/classes/class_crypto.html#class-crypto-method-constant-time-compare) |
| HMAC (one-shot) | `Crypto.hmac_digest(hash_type, key, msg)` | `PackedByteArray` | [class_crypto (4.3), `hmac_digest`](https://docs.godotengine.org/en/4.3/classes/class_crypto.html#class-crypto-method-hmac-digest) |

**`sign` / `verify` are RSA and take a pre-computed hash, not the raw data.** The
official example signs a digest:

```gdscript
var signature = crypto.sign(HashingContext.HASH_SHA256, data.sha256_buffer(), key)
var verified  = crypto.verify(HashingContext.HASH_SHA256, data.sha256_buffer(), signature, key)
```

Source: [class_crypto (4.3) Description example](https://docs.godotengine.org/en/4.3/classes/class_crypto.html).

**Engine-source confirmation (authoritative for what is actually implemented)** —
`4.3-stable modules/mbedtls/crypto_mbedtls.cpp`:

```cpp
Vector<uint8_t> CryptoMbedTLS::sign(HashingContext::HashType p_hash_type, const Vector<uint8_t> &p_hash, Ref<CryptoKey> p_key) {
    mbedtls_md_type_t type = CryptoMbedTLS::md_type_from_hashtype(p_hash_type, size);
    ERR_FAIL_COND_V_MSG(type == MBEDTLS_MD_NONE, ..., "Invalid hash type.");
    ERR_FAIL_COND_V_MSG(p_hash.size() != size, ..., "Invalid hash provided. Size must be " + itos(size));
    ERR_FAIL_COND_V_MSG(key->is_public_only(), ..., "Invalid key provided. Cannot sign with public_only keys.");
    int ret = mbedtls_pk_sign(&(key->pkey), type, p_hash.ptr(), size, buf, ...);   // RSA
}

bool CryptoMbedTLS::verify(HashingContext::HashType p_hash_type, const Vector<uint8_t> &p_hash, const Vector<uint8_t> &p_signature, Ref<CryptoKey> p_key) {
    mbedtls_md_type_t type = CryptoMbedTLS::md_type_from_hashtype(p_hash_type, size);
    ERR_FAIL_COND_V_MSG(type == MBEDTLS_MD_NONE, false, "Invalid hash type.");
    ERR_FAIL_COND_V_MSG(p_hash.size() != size, false, "Invalid hash provided. Size must be " + itos(size));
    return mbedtls_pk_verify(&(key->pkey), type, p_hash.ptr(), size, p_signature.ptr(), p_signature.size()) == 0;
}
```

Source: [godot 4.3-stable `modules/mbedtls/crypto_mbedtls.cpp`](https://github.com/godotengine/godot/blob/4.3-stable/modules/mbedtls/crypto_mbedtls.cpp).

Key facts drawn directly from that source:

- **`verify()` does NOT reject a public-only key** (only `sign()` does). So the
  client can hold **only** the public key and still verify. ✅ This is the linchpin
  that makes a bundled-public-key scheme possible.
- **The hash length must exactly match the hash type** (SHA-256 ⇒ the `hash`
  argument must be 32 bytes). Pass a real SHA-256 digest, not the file bytes.
- **`generate_rsa`** builds an RSA key: `mbedtls_pk_setup(..., MBEDTLS_PK_RSA)` +
  `mbedtls_rsa_gen_key(..., 65537)` (public exponent 65537).
- **Accepted hash types** come from `md_type_from_hashtype`: `HASH_MD5` (16),
  `HASH_SHA1` (20), `HASH_SHA256` (32); anything else ⇒ `MBEDTLS_MD_NONE` +
  `"Invalid hash type."`. **SHA-256 is the strongest available** — there is no
  SHA-512/SHA-3 (matches the sibling [player-accounts finding](../../player-accounts/research/02-godot-password-hashing.md)).

> **Signature padding scheme (partial-verify):** `mbedtls_pk_sign` on a
> `MBEDTLS_PK_RSA` key uses mbedTLS's default RSA padding, **RSASSA-PKCS#1-v1.5**
> (not PSS). This is an mbedTLS default inferred from the `MBEDTLS_PK_RSA` context;
> the Godot class reference does not state the padding explicitly. It is a valid,
> widely used signature scheme; if PSS is ever required it would need a different
> primitive not exposed to GDScript. Marked **partially verified** (behavior read
> from Godot source + mbedTLS defaults, not from a Godot doc sentence).

`generate_random_bytes` is a real CSPRNG (mbedTLS **CTR_DRBG** seeded from the
entropy source in the `CryptoMbedTLS` constructor; returns an **empty**
`PackedByteArray` on failure — always check `.size()`). `constant_time_compare`
is a timing-safe comparator ("compares two `PackedByteArray`s for equality without
leaking timing information"). Sources: [class_crypto (4.3)](https://docs.godotengine.org/en/4.3/classes/class_crypto.html#class-crypto-method-constant-time-compare)
and the CTR_DRBG constructor in [crypto_mbedtls.cpp](https://github.com/godotengine/godot/blob/4.3-stable/modules/mbedtls/crypto_mbedtls.cpp).

---

## 2. Hashing large files — stream a `.pck` through SHA-256

`HashingContext` exists precisely for this: "Useful for computing hashes of big
files (so you don't have to load them all in memory)." API: `start(type)` →
`update(chunk)` (repeat) → `finish()` → `PackedByteArray`. Source: [class_hashingcontext (4.3)](https://docs.godotengine.org/en/4.3/classes/class_hashingcontext.html).

`HashType` enum: `HASH_MD5 = 0`, `HASH_SHA1 = 1`, `HASH_SHA256 = 2`
([Enumerations](https://docs.godotengine.org/en/4.3/classes/class_hashingcontext.html#enum-hashingcontext-hashtype)).
Use `HASH_SHA256`.

Official streaming example (paraphrased from the class reference), driven by
`FileAccess` chunked reads — this is exactly what the updater needs for a
multi-MB `Project0.pck`:

```gdscript
const CHUNK_SIZE := 1024   # small for illustration; 64 KiB is a fine real value
var ctx := HashingContext.new()
ctx.start(HashingContext.HASH_SHA256)
var file := FileAccess.open(path, FileAccess.READ)
while file.get_position() < file.get_length():
    var remaining := file.get_length() - file.get_position()
    ctx.update(file.get_buffer(min(remaining, CHUNK_SIZE)))
var digest := ctx.finish()          # 32-byte PackedByteArray
# digest.hex_encode() → lowercase hex for the manifest
```

Source: [class_hashingcontext (4.3) Description example](https://docs.godotengine.org/en/4.3/classes/class_hashingcontext.html).

This digest is (a) compared to the manifest's `patch_sha256`, and (b) the exact
32-byte value the operator fed to `Crypto.sign` when building the manifest — the
two link the signed manifest to the concrete bytes on disk.

---

## 3. Signed-manifest feasibility — bundling a trusted public key; RSA vs Ed25519

**Bundling the public key is directly supported.** `CryptoKey` is a `Resource`
with `load(path, public_only)`, `load_from_string(string_key, public_only)`,
`save`, `save_to_string(public_only)`, and `is_public_only()`.
`save_to_string(true)` "Returns a string containing the key in PEM format …
only the public key". Source: [class_cryptokey (4.3)](https://docs.godotengine.org/en/4.3/classes/class_cryptokey.html).

So the workflow is:

- **Operator, once, offline:** `var key = Crypto.new().generate_rsa(3072)` (or 4096);
  keep `key.save("signing.key")` **private/offline**; publish
  `key.save_to_string(true)` (public PEM) into the client source.
- **Client:** `var pub := CryptoKey.new(); pub.load_from_string(PUBLIC_KEY_PEM, true)`
  then `Crypto.new().verify(HASH_SHA256, manifest_digest, sig, pub)`.

Engine source confirms `load_from_string(..., public_only=true)` parses via
`mbedtls_pk_parse_public_key`, and `save_to_string(true)` emits via
`mbedtls_pk_write_pubkey_pem` — i.e. a normal public-key PEM the client can embed.
Source: `CryptoKeyMbedTLS::load_from_string` / `save_to_string` in
[crypto_mbedtls.cpp](https://github.com/godotengine/godot/blob/4.3-stable/modules/mbedtls/crypto_mbedtls.cpp).

**RSA is the only practical native asymmetric path.** The entire `Crypto` keygen
surface is `generate_rsa` — there is **no `generate_ec` / Ed25519 / EdDSA**
generator exposed to GDScript, and `sign`/`verify` route through
`mbedtls_pk_sign`/`_verify` with a `HashType` limited to MD5/SHA1/SHA256, which is
the RSA "hash-then-sign" shape, not EdDSA. (`CryptoKey`'s description says "RSA or
elliptic-curve" and `load` can parse an EC key, but nothing in the GDScript API
generates or signs with Ed25519.) Sources: method list in [class_crypto (4.3)](https://docs.godotengine.org/en/4.3/classes/class_crypto.html)
and `md_type_from_hashtype` in [crypto_mbedtls.cpp](https://github.com/godotengine/godot/blob/4.3-stable/modules/mbedtls/crypto_mbedtls.cpp).

- **Native Ed25519: effectively unavailable** (no keygen, no EdDSA sign/verify
  binding). Marked **UNVERIFIED-as-usable**; do not rely on it.
- **Pure-GDScript Ed25519:** theoretically possible to hand-implement, but I found
  **no maintained, audited primary-source implementation**, and hand-rolled curve
  crypto is a security anti-pattern. Recommendation: **use native RSA**, not a
  bespoke Ed25519. (Open item — see §7.)

**HMAC alternative (rejected for this use).** `Crypto.hmac_digest` (SHA-256) works
and is cheap, but HMAC is **symmetric** — the verifying client would need the same
secret the signer uses, and that secret would ship inside the client, so anyone
with the client could forge a "valid" manifest. HMAC gives integrity + *shared-secret*
authenticity only; for code delivery where the client is in untrusted hands, use
**asymmetric RSA signatures** so the client holds only a non-forging public key.

---

## 4. pck-level features (`encrypt_pck`, `script_export_mode`, `load_resource_pack`) — orthogonal to authenticity

These are about **confidentiality / packaging**, not **authenticity**, and must not
be mistaken for a signature.

- **`ProjectSettings.load_resource_pack(pack, replace_files=true, offset=0)`** is
  the apply mechanism: it mounts a `.pck` and a same-path file "will replace" the
  existing one — "a way of creating patches for one's own game. A PCK file of this
  kind can fix the content of a previously loaded PCK." Crucially, the docs
  describe **no integrity or signature check** — it loads and its scripts become
  executable. Source: [Exporting packs, patches, and mods (4.3)](https://docs.godotengine.org/en/4.3/tutorials/export/exporting_pcks.html).
  ⇒ **Verification must happen BEFORE `load_resource_pack`**, in our own code.
- **`encrypt_pck` / `encryption_*` filters** (this repo: `encrypt_pck=false`)
  encrypt pack **contents with a symmetric AES key** compiled into a custom export
  template. That protects **secrecy of assets**, and the key would have to ship in
  (or alongside) the client — so it provides **no authenticity** against someone
  who has the client, and does not prove *who* produced a downloaded pck. Repo
  config: [export_presets.cfg](../../../export_presets.cfg) (`encrypt_pck=false`,
  `encrypt_directory=false`).
- **`script_export_mode`** (this repo: `2`) controls whether GDScript ships as
  text vs binary tokens (obfuscation / tamper-*evidence* of source), again **not**
  a cryptographic authenticity control. Repo config: [export_presets.cfg](../../../export_presets.cfg).
- **`binary_format/embed_pck=false`** (repo config) is why the `.pck` is a separate
  file and thus a natural patch unit — relevant to *packaging*, not trust.

**Conclusion:** pck encryption / script mode are **orthogonal** to the integrity
question. Keep them as-is; layer a signed-manifest check on top.

---

## 5. TLS — HTTPRequest validates by default; can be pinned; why TLS ≠ authenticity

- **HTTPRequest validates server certificates by default.** Godot uses the OS
  certificate bundle, "but also includes the TLS certificate bundle from Mozilla
  as a fallback"; CA-signed servers "do not require any configuration on the
  client to work". Source: [TLS/SSL certificates (4.3)](https://docs.godotengine.org/en/4.3/tutorials/networking/ssl_certificates.html).
- **Pinning / private-CA / self-signed** is done with `TLSOptions.client(trusted_chain,
  common_name_override)` passed to `HTTPRequest.set_tls_options(...)`.
  `TLSOptions.client` "Creates a TLS client configuration which validates
  certificates and their common names … you can specify a custom `trusted_chain`
  … and optionally provide a `common_name_override`." The opposite,
  `TLSOptions.client_unsafe()`, disables validation and is "not recommended".
  Sources: [class_tlsoptions (4.3)](https://docs.godotengine.org/en/4.3/classes/class_tlsoptions.html),
  [class_httprequest (4.3), `set_tls_options`](https://docs.godotengine.org/en/4.3/classes/class_httprequest.html#class-httprequest-method-set-tls-options).
  So a home-hosted server with a self-signed cert can be pinned by shipping its CA
  cert as `trusted_chain` (add it via project setting or `X509Certificate`).
- **Why TLS alone is insufficient for artifact authenticity:** TLS authenticates
  the **transport endpoint** (that you reached *this host*) and protects bytes
  **in transit**. It says nothing about **who authored the artifact** or whether
  the bytes **at rest on the download host** are the operator's real build. If the
  download host/CDN is compromised, or an attacker obtains a valid cert for the
  host, or serves a malicious pck over a perfectly valid TLS connection, TLS still
  shows green. A **publisher signature over the artifact**, verified against a key
  the client already trusts, is what binds the bytes to the operator independently
  of the transport. TLS and signing are complementary: **use both** (TLS for
  confidentiality + host auth + downgrade resistance; RSA signature for artifact
  authenticity). This matches ticket [07](../issues/07-integrity-and-trust.md)'s
  "note explicitly why TLS/HTTPS alone is not [sufficient]".

---

## 6. Recommendation — minimal verify-before-apply scheme (fail-closed)

**What is hashed:** the patch unit (`Project0.pck`) → `patch_sha256` (SHA-256,
streamed via `HashingContext`).

**What is signed:** the **update manifest**, not the pck directly. The manifest is
canonical bytes (e.g. sorted-key JSON) binding the **required client build
version** to `patch_sha256` (+ size + download URL). The operator signs
`SHA-256(manifest_bytes)` with the **private RSA key**:
`Crypto.sign(HASH_SHA256, SHA-256(manifest_bytes), private_key)`. Signing is done
**offline**, so RSA-3072/4096 performance is irrelevant.

**Which key ships in the client:** **only the RSA public key**, as a PEM constant /
bundled `res://` resource, loaded with `CryptoKey.load_from_string(PUBLIC_KEY_PEM,
true)`. The private key never leaves the operator.

**How it is verified, before apply:**

```
1. GET manifest + signature over HTTPS (HTTPRequest, default cert validation;
   pin the home server's CA via TLSOptions.client if self-signed).
2. m_digest = SHA-256(manifest_bytes)                       # HashingContext
3. if not Crypto.verify(HASH_SHA256, m_digest, signature, PUBLIC_KEY):  REFUSE
4. Parse manifest; enforce version is the server-required one and > installed
   (monotonic — blocks rollback/replay to an older signed build).
5. Download patch to a temp file (HTTPRequest.download_file; bound body_size_limit).
6. got = SHA-256(temp_pck)                                  # streamed
7. if not Crypto.constant_time_compare(got, manifest.patch_sha256):    REFUSE
8. Only now hand temp_pck to the apply step (load_resource_pack / launcher swap).
```

**Fail-closed path:** any REFUSE (bad signature, version not acceptable, hash
mismatch, download/timeout/`generate_random_bytes` empty) ⇒ do **not**
`load_resource_pack`, keep the prior known-good client, surface a bounded reason,
emit telemetry (reuse CLAUDE.md's Andon seam), and abort the update — never
execute unverified bytes. This satisfies the repo's "server owns outcomes / no
client-authored trust" laws and the OWASP-critical posture for remote code
delivery.

**Suggested manifest fields (for the domain-model / spec ticket):**
`schema_version`, `client_build_version`, `patch_sha256` (hex), `patch_size`,
`patch_url`, `algo` (`"rsa-pkcs1-sha256"`), `signature` (base64 over the
manifest's canonical bytes, excluding the signature field itself).

---

## 7. Trust-level note — what this does and does NOT provide

**Acceptable at this level because:** the trust anchor (the bundled public key)
arrives with the **already-installed** client, which is delivered out of band
(operator → invited tester). An attacker on the update channel (compromised
download host, LAN MITM, DNS spoof) cannot forge a manifest without the offline
private key, and cannot substitute the pck without breaking the signed hash. That
is the whole threat we must close for home-hosted, invite-gated code delivery.

**It explicitly does NOT provide:**

- **OS code-signing trust** — Windows SmartScreen / Authenticode is separate
  (`codesign/enable=false`); users may still see "unknown publisher".
- **Private-key-compromise resilience** — if `signing.key` leaks, an attacker can
  sign malicious updates; there is **no revocation** here. Protect the key
  offline; key rotation means shipping a new client out of band.
- **Trusted-client assumption** — if malware can already write to the installed
  client on disk, it can replace the bundled public key (ticket 07's "swapped by
  the same attacker" concern). This scheme defends the **update channel**, not an
  already-compromised host; that is an accepted boundary at this trust level.
- **Rollback protection by signature alone** — an old but validly signed manifest
  still verifies; the **version-monotonic check (step 4)** is what prevents replay
  to an older build, so it is mandatory, not optional.
- **PSS / modern signature hardening** — native path is RSASSA-PKCS#1-v1.5 (§1);
  adequate here, but not the newest scheme.

---

## Open / unverified items

- **RSA padding scheme (PKCS#1 v1.5 vs PSS):** read from Godot source + mbedTLS
  defaults for a `MBEDTLS_PK_RSA` context, **not** stated in the Godot class
  reference. Behaviorally sufficient for verify-before-apply; flagged as
  **partially verified**. A downstream prototype should round-trip
  `sign`→`verify` with a `generate_rsa` key to confirm end-to-end in the actual
  Godot 4.3 headless binary.
- **Native Ed25519 / EdDSA:** **UNVERIFIED as usable** — no keygen or EdDSA
  sign/verify is exposed in the GDScript `Crypto` API; treat as unavailable and
  use RSA.
- **Maintained pure-GDScript Ed25519 addon:** none found from a primary source;
  not recommended (hand-rolled curve crypto).
- **`load_resource_pack` and code execution timing** (whether a verified pck's
  scripts can be safely hot-loaded vs requiring a relaunch) is the apply/rollback
  ticket's concern ([08](../issues/08-apply-restart-and-rollback.md)) and the
  pck-mechanics research ([02](../issues/02-research-godot-pck-and-windows-self-replace.md)),
  not this crypto research.

## Primary sources

- Godot 4.3 class reference — [Crypto](https://docs.godotengine.org/en/4.3/classes/class_crypto.html),
  [HashingContext](https://docs.godotengine.org/en/4.3/classes/class_hashingcontext.html),
  [CryptoKey](https://docs.godotengine.org/en/4.3/classes/class_cryptokey.html),
  [TLSOptions](https://docs.godotengine.org/en/4.3/classes/class_tlsoptions.html),
  [HTTPRequest](https://docs.godotengine.org/en/4.3/classes/class_httprequest.html).
- Godot 4.3 tutorials — [TLS/SSL certificates](https://docs.godotengine.org/en/4.3/tutorials/networking/ssl_certificates.html),
  [Exporting packs, patches, and mods](https://docs.godotengine.org/en/4.3/tutorials/export/exporting_pcks.html).
- Engine source (tag 4.3-stable) — [`modules/mbedtls/crypto_mbedtls.cpp`](https://github.com/godotengine/godot/blob/4.3-stable/modules/mbedtls/crypto_mbedtls.cpp)
  (`sign`, `verify`, `md_type_from_hashtype`, `generate_rsa`,
  `generate_random_bytes`, `CryptoKey` load/save).
- Repo config — [export_presets.cfg](../../../export_presets.cfg)
  (`encrypt_pck=false`, `script_export_mode=2`, `embed_pck=false`,
  `codesign/enable=false`).
