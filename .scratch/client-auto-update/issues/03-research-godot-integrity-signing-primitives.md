Type: research
Status: resolved

## Question

What cryptographic primitives does Godot 4.3 GDScript provide to verify the
**integrity and authenticity** of a downloaded patch **before** it is loaded or
executed, for an unsigned home-hosted build at this trust level (home-hosted,
invite-gated, no public code-signing certificate)?

Investigate against primary sources (Godot 4.3 official docs, engine source):

- **`Crypto` class**: does `sign()` / `verify()` exist (RSA via `CryptoKey` /
  `X509Certificate`)? Which `HashingContext.HashType` values are accepted? Is
  there `constant_time_compare` and `generate_random_bytes`?
- **Hashing large files**: streaming a `.pck` through `HashingContext`
  (SHA-256) to a digest without loading it all into memory.
- **Signed manifest feasibility**: can the client bundle a trusted **public
  key** and verify an RSA-signed **update manifest** that lists the patch's
  SHA-256? Is there any pure-GDScript Ed25519 option, or is RSA-via-`CryptoKey`
  the only native path?
- **pck-level features**: are Godot's pck encryption / `script_export_mode` /
  `encrypt_pck` relevant to authenticity here, or orthogonal?
- **TLS**: does `HTTPRequest` validate server certificates by default, and can
  a cert/host be pinned? (Note why TLS alone is insufficient for authenticity.)

Output: a recommended minimal integrity-and-authenticity verification (what is
hashed, what is signed, which key ships in the client, and how it is verified
before apply), with primary sources cited, and an explicit note about the
trust level. Feeds the integrity-and-trust ticket.

Findings file: `.scratch/client-auto-update/research/03-godot-integrity-signing-primitives.md`.

## Answer

Godot 4.3 GDScript has everything needed natively (mbedTLS), no addon required.
Confirmed against the class reference **and** `4.3-stable
modules/mbedtls/crypto_mbedtls.cpp`: `Crypto.sign()` / `Crypto.verify()` exist
and are **RSA** (key from `Crypto.generate_rsa`), taking a `HashingContext.HashType`
— **SHA-256 is accepted** (strongest available; no SHA-512/SHA-3). Critically,
**`verify()` accepts a public-only key** (only `sign()` rejects it), so the client
can bundle only a trusted **public** key. `HashingContext` streams a large `.pck`
through SHA-256 chunk-by-chunk; `generate_random_bytes` (CSPRNG) and
`constant_time_compare` are present.

**Recommended verify-before-apply (fail-closed):** operator signs, **offline**, the
SHA-256 digest of a canonical **update manifest** (binds required client build
version → the pck's `patch_sha256`) with a private RSA-3072/4096 key. The client
bundles only the **public key** (`CryptoKey.load_from_string(PEM, true)`),
`Crypto.verify(HASH_SHA256, SHA-256(manifest), sig, pub)`, enforces the version is
monotonic (anti-rollback), then streams SHA-256 over the downloaded pck and
`constant_time_compare`s it to the manifest hash. Only on all-pass does it hand the
pck to apply (`load_resource_pack`); any failure refuses and keeps the prior
known-good build. `load_resource_pack` does **no** integrity check itself, so
verification must precede it. pck encryption / `script_export_mode` are
confidentiality/packaging, **orthogonal** to authenticity. TLS (HTTPRequest
validates by default; pin via `TLSOptions.client`) authenticates the transport
host only, **not** the artifact's publisher — so it is necessary but insufficient;
use both. Ed25519 has no native path (RSA is the only practical one). Acceptable
**only** at this home-hosted / invite-gated level: it defends the update channel,
not an already-compromised client host, and provides no OS code-signing trust,
key-leak resilience, or revocation.

Findings file: .scratch/client-auto-update/research/03-godot-integrity-signing-primitives.md
