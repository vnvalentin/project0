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
