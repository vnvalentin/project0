extends Node
class_name NetworkConfig
## Shared constants for the client/server ENet connection proof (Slice 002)
## and its Slice 003 LAN configurability. No behavior beyond simple lookups
## lives here — only the values both sides must agree on, plus the safe
## defaulting rules for overriding them.
##
## Slice 003 scope: the server's bind address and the client's target host
## are each configurable via a `--` command-line argument, falling back to an
## environment variable, falling back to the existing localhost default. Port
## 9999 and every other Slice 002 default are unchanged. See
## docs/slices/003-lan-client-connection.md.
##
## Slice 004 scope: adds AUTHORITATIVE_MOVE_SPEED, the fixed speed the server
## applies to one connected Player's authoritative position. See
## docs/slices/004-authoritative-player-movement.md.

const SERVER_PORT: int = 9999
const SERVER_ADDRESS: String = "127.0.0.1"
const DEFAULT_TARGET_HOST: String = "192.69.180.236"
const MAX_CLIENTS: int = 10

## Slice 004 scope: the fixed server-tick speed (yards/second; 1 world unit =
## 1 yard, see shared/world_scale.gd) the server
## applies to a connected Player's authoritative position. Slice 005 also
## uses this same value client-side to predict and replay movement, so
## reconciliation replay matches the server's own integration exactly. See
## docs/slices/004-authoritative-player-movement.md and
## docs/slices/005-prediction-reconciliation.md.
const AUTHORITATIVE_MOVE_SPEED: float = 5.0

## Slice 005 scope: the maximum distance (yards) the client smooths the blue
## NetworkedPlayer toward an incoming authoritative snapshot per second. Used
## as a move_toward() speed, not a teleport threshold, so ordinary snapshot
## deltas are visually smoothed rather than jumped. See
## docs/slices/005-prediction-reconciliation.md.
const NETWORKED_PLAYER_SMOOTH_SPEED: float = 10.0

## Slice 005 scope: if an authoritative snapshot's distance from the blue
## NetworkedPlayer's current rendered position exceeds this many yards, the
## client snaps directly instead of smoothing — bounding the worst case (e.g.
## a fresh spawn or a large correction) to a single frame rather than a long
## visible slide. See docs/slices/005-prediction-reconciliation.md.
const NETWORKED_PLAYER_SNAP_DISTANCE: float = 15.0

## Slice 013 scope: how fast (radians/second) a Player/RemotePlayer node
## rotates to face its current movement direction. Bounded rather than an
## instant snap so the visible turn reads as smooth rather than a teleporting
## facing. Purely a client-side presentation constant — the server never
## reads or depends on this value; only the intent-supplied aim_direction
## (see shared/combat_contracts.gd) is authoritative for hit resolution. See
## docs/slices/013-melee-strike-visual-indicator.md.
const FACING_TURN_RATE: float = 12.0

const BIND_ADDRESS_CLI_ARG: String = "--server-bind-address="
const BIND_ADDRESS_ENV_VAR: String = "PROJECT0_SERVER_BIND_ADDRESS"

const TARGET_HOST_CLI_ARG: String = "--server-host="
const TARGET_HOST_ENV_VAR: String = "PROJECT0_SERVER_HOST"

const SERVER_PORT_CLI_ARG: String = "--server-port="
const SERVER_PORT_ENV_VAR: String = "PROJECT0_SERVER_PORT"

# Slice 072: the standalone login server's UDP port, resolved with the same
# precedence as the game port so the client and the login server never disagree.
const LOGIN_PORT: int = 9998
const LOGIN_PORT_CLI_ARG: String = "--login-port="
const LOGIN_PORT_ENV_VAR: String = "PROJECT0_LOGIN_PORT"

# Slice 088: the login process's loopback-only HTTP endpoint port
# (server/login_loopback_http_endpoint.gd), adjacent to the ENet LOGIN_PORT.
# Unlike LOGIN_PORT, the endpoint's bind ADDRESS is never configurable (always
# hardcoded to "127.0.0.1" in the endpoint itself) — only the port is resolved
# here, with the same CLI/env/default precedence as the other network config.
const LOGIN_HTTP_PORT: int = 9997
const LOGIN_HTTP_PORT_CLI_ARG: String = "--login-http-port="
const LOGIN_HTTP_PORT_ENV_VAR: String = "PROJECT0_LOGIN_HTTP_PORT"

# Slice 078: opt-in client login split. When set, the client authenticates on the
# separate login process and hands off to the game process; default off keeps the
# single-connection flow.
const CLIENT_LOGIN_SPLIT_ENV_VAR: String = "PROJECT0_CLIENT_LOGIN_SPLIT"

# Slice 093: opt-in client HTTPS login/character flow (ADR 0005 Option A, WAN).
# When enabled the client authenticates and performs Character CRUD over the
# public HTTPS surface, obtains a signed Character assertion, then presents it
# to the assertion-only game server instead of the ENet login/character path.
const CLIENT_HTTPS_LOGIN_ENV_VAR: String = "PROJECT0_CLIENT_HTTPS_LOGIN"

# Slice 167: opt-in Nakama login/session entry. Defaults off until the Character
# service and world-entry ticket slices exist. The Nakama server key is a client
# API key (not a Project0 gameplay authority) and must be configured by the
# launcher/operator before this path is used.
const CLIENT_NAKAMA_LOGIN_ENV_VAR: String = "PROJECT0_CLIENT_NAKAMA_LOGIN"
const NAKAMA_URL_ENV_VAR: String = "PROJECT0_NAKAMA_URL"
const NAKAMA_SERVER_KEY_ENV_VAR: String = "PROJECT0_NAKAMA_SERVER_KEY"
const CLIENT_NAKAMA_GAMEPLAY_ENV_VAR: String = "PROJECT0_CLIENT_NAKAMA_GAMEPLAY"
const DEFAULT_NAKAMA_URL: String = "https://project0.valentin.vip:7350"
const NAKAMA_MATCH_ID_ENV_VAR: String = "PROJECT0_NAKAMA_MATCH_ID"


## Public seam: resolves the address the headless server should bind to.
## Precedence: `--server-bind-address=<addr>` CLI argument, then the
## `PROJECT0_SERVER_BIND_ADDRESS` environment variable, then the localhost
## default (SERVER_ADDRESS). Never returns an empty string.
static func resolve_server_bind_address() -> String:
	var from_cli: String = _find_cli_arg_value(BIND_ADDRESS_CLI_ARG)
	if not from_cli.is_empty():
		return from_cli

	var from_env: String = OS.get_environment(BIND_ADDRESS_ENV_VAR)
	if not from_env.is_empty():
		return from_env

	return SERVER_ADDRESS


## Public seam: resolves the host the client should connect to.
## Precedence: `--server-host=<addr>` CLI argument, then the
## `PROJECT0_SERVER_HOST` environment variable, then the configured WAN default
## (DEFAULT_TARGET_HOST). Never returns an empty string.
static func resolve_client_target_host() -> String:
	var from_cli: String = _find_cli_arg_value(TARGET_HOST_CLI_ARG)
	if not from_cli.is_empty():
		return from_cli

	var from_env: String = OS.get_environment(TARGET_HOST_ENV_VAR)
	if not from_env.is_empty():
		return from_env

	return DEFAULT_TARGET_HOST


## Public seam: resolves the UDP port the headless server should listen on.
## Precedence: `--server-port=<n>` CLI argument, then the `PROJECT0_SERVER_PORT`
## environment variable, then the default (SERVER_PORT). A value that is not a
## valid 1-65535 integer falls back to the default, so a malformed override can
## never bind port 0 or an out-of-range port. Added for DT-007 so tests can bind
## an ephemeral port instead of the shared default.
static func resolve_server_port() -> int:
	var from_cli: int = _parse_port(_find_cli_arg_value(SERVER_PORT_CLI_ARG))
	if from_cli != 0:
		return from_cli

	var from_env: int = _parse_port(OS.get_environment(SERVER_PORT_ENV_VAR))
	if from_env != 0:
		return from_env

	return SERVER_PORT


## Public seam: resolves the UDP port the standalone login server listens on and
## the client dials for the login handoff. Precedence: `--login-port=<n>` CLI
## argument, then `PROJECT0_LOGIN_PORT`, then LOGIN_PORT. A malformed value falls
## back to the default (never binds port 0 or an out-of-range port).
static func resolve_login_port() -> int:
	var from_cli: int = _parse_port(_find_cli_arg_value(LOGIN_PORT_CLI_ARG))
	if from_cli != 0:
		return from_cli

	var from_env: int = _parse_port(OS.get_environment(LOGIN_PORT_ENV_VAR))
	if from_env != 0:
		return from_env

	return LOGIN_PORT


## Public seam (Slice 088): resolves the TCP port the login process's loopback
## HTTP endpoint listens on. Precedence: `--login-http-port=<n>` CLI argument,
## then `PROJECT0_LOGIN_HTTP_PORT`, then LOGIN_HTTP_PORT. A malformed value
## falls back to the default (never binds port 0 or an out-of-range port).
static func resolve_login_http_port() -> int:
	var from_cli: int = _parse_port(_find_cli_arg_value(LOGIN_HTTP_PORT_CLI_ARG))
	if from_cli != 0:
		return from_cli

	var from_env: int = _parse_port(OS.get_environment(LOGIN_HTTP_PORT_ENV_VAR))
	if from_env != 0:
		return from_env

	return LOGIN_HTTP_PORT


## Public seam: whether the client should authenticate on the separate login
## process (then hand off to the game process) instead of the single-connection
## flow. Default ON (the login split is canonical after the Slice 084 cutover);
## set PROJECT0_CLIENT_LOGIN_SPLIT=0 to use the legacy single-connection flow.
static func client_login_split_enabled() -> bool:
	return OS.get_environment(CLIENT_LOGIN_SPLIT_ENV_VAR).strip_edges() != "0"


## Public seam (Slice 093): whether the client runs the HTTPS account/character
## flow instead of the ENet login/character path. HTTPS is the normal portable
## client path; set PROJECT0_CLIENT_HTTPS_LOGIN=0 only for legacy LAN servers.
static func client_https_login_enabled() -> bool:
	var explicit: String = OS.get_environment(CLIENT_HTTPS_LOGIN_ENV_VAR).strip_edges()
	return explicit != "0"


static func client_nakama_login_enabled() -> bool:
	return OS.get_environment(CLIENT_NAKAMA_LOGIN_ENV_VAR).strip_edges() == "1"


static func client_nakama_gameplay_enabled() -> bool:
	return OS.get_environment(CLIENT_NAKAMA_GAMEPLAY_ENV_VAR).strip_edges() == "1"


static func resolve_nakama_base_url() -> String:
	var value: String = OS.get_environment(NAKAMA_URL_ENV_VAR).strip_edges().rstrip("/")
	if value.is_empty():
		return DEFAULT_NAKAMA_URL
	return value


static func resolve_nakama_server_key() -> String:
	return OS.get_environment(NAKAMA_SERVER_KEY_ENV_VAR).strip_edges()


static func resolve_nakama_match_id() -> String:
	return OS.get_environment(NAKAMA_MATCH_ID_ENV_VAR).strip_edges()


## Returns a valid 1-65535 port parsed from `value`, or 0 when it is empty,
## non-numeric, or out of range so callers fall through to their default.
static func _parse_port(value: String) -> int:
	if not value.is_valid_int():
		return 0
	var port: int = value.to_int()
	if port < 1 or port > 65535:
		return 0
	return port


## Checks user arguments first, then raw process arguments so exported clients
## accept both `-- --server-host=...` and direct launch arguments.
static func _find_cli_arg_value(prefix: String) -> String:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with(prefix):
			return argument.substr(prefix.length())

	for argument in OS.get_cmdline_args():
		if argument.begins_with(prefix):
			return argument.substr(prefix.length())

	return ""
