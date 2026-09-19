extends RefCounted
class_name ClientSigningKey
## Slice 150 (Phase 16, F-037): the trusted release public key, shipped inside
## `Project0.pck`.
##
## This is the client's entire basis for trusting an update. The matching private
## key is held offline by the release operator and never appears in this
## repository, on the enrollment host, or in CI — the signature exists precisely
## to survive one of those being compromised, so a key reachable from them would
## be worthless.
##
## Anti-swap property: the updater verifies the NEXT pack's manifest using the key
## in the CURRENTLY installed pack, which the tester obtained through the trusted
## first-run channel. An attacker who can substitute a download therefore cannot
## substitute the key that judges it.
##
## Rotation is a full re-release through that same trusted channel (ADR 0008);
## there is deliberately no in-band key-update path, because an in-band path is
## exactly the hole this design closes.
##
## Public material only. Safe to read, publish, and diff.

## SHA-256 of the DER SubjectPublicKeyInfo, for identifying which key a build
## trusts without eyeballing base64.
const TRUSTED_KEY_FINGERPRINT: String = "69db4c67c0202e617925d6c6e82d1b54949ade0a48419e3d4ded8a001677a232"

const TRUSTED_PUBLIC_KEY_PEM: String = """-----BEGIN PUBLIC KEY-----
MIIBojANBgkqhkiG9w0BAQEFAAOCAY8AMIIBigKCAYEAqy81nl1CCXaKDK4jiMcY
tWww3/qzCOx1L5tfm+Ro+Pw9AhopUHyxOdxbBZCaFI9jolHWC9O8uEEjqdEzk9wS
EiL6JV+R08tO4/vhuE3YTvEk5LOCHeZ9ywCje1JESbzO9ApJqLE8JwnNiKZqg8dm
Rze2CqUr9VMaHR//GOzY6inkpVWclUKMHnOcmp712LK+vQ67pNvnHPVFg60b1sNQ
vCEXN9MxxpoQzFbzyi5a9u0uHN4G7JU6Ru3j6/meC+3irnOFp+VGuiwDSUxpPlNR
8XBxWvRquud71xKJItqSWKYvyPs9DHLmG+koMUIU1QmiOJ5qVYQh0NvJ7V2ZokWG
izShuKDIkoOzvP3AxsdT1ETrrxGF4syHs6mJj/7IYQKYvo2QnDibpWYLmLqpN2/o
eIbff8DT7HE45Juefg1oVYnmluDCIbHkNzb1Gcr4NtETGL566fZIK+roV13MF4Iv
yPYhJcljSJ1uUa7BXH0MBQS4wKjue/2vDL8Nw+K8qqHnAgMBAAE=
-----END PUBLIC KEY-----"""


## The key updates are verified against.
static func trusted_public_key_pem() -> String:
	return TRUSTED_PUBLIC_KEY_PEM


## Whether this build carries a usable trusted key. A build without one must
## refuse to self-update rather than fall back to trusting the download, so
## callers check this before starting an update at all.
static func is_configured() -> bool:
	if TRUSTED_PUBLIC_KEY_PEM.strip_edges().is_empty():
		return false
	var key := CryptoKey.new()
	return key.load_from_string(TRUSTED_PUBLIC_KEY_PEM, true) == OK
