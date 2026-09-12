extends Node
## Autoload singleton holding the current session's local identity in memory
## only. Never persisted to disk; cleared on process exit. See CONTEXT.md's
## "Identity gate" term and docs/adr/0001.

var display_name: String = ""
var target_host: String = ""
