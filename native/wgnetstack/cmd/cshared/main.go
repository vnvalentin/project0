// Command cshared builds the C-exported wgnetstack bridge library
// (libwgnetstack.so / wgnetstack.dll). It has no Go-callable entry point of
// its own; see bridge/ for the implementation and cmd/probe for a pure-Go
// harness that exercises the same logic without the cgo boundary.
package main

/*
#include <stdlib.h>
*/
import "C"

import (
	"log"

	"project0/wgnetstack/bridge"
)

//export wgnetstack_start
func wgnetstack_start(configJSON *C.char) C.int {
	raw := []byte(C.GoString(configJSON))
	cfg, err := bridge.ParseConfig(raw)
	if err != nil {
		log.Printf("wgnetstack_start: invalid config: %v", err)
		return -1
	}
	port, err := bridge.StartActive(cfg)
	if err != nil {
		log.Printf("wgnetstack_start: failed to start bridge: %v", err)
		return -1
	}
	return C.int(port)
}

//export wgnetstack_stop
func wgnetstack_stop() {
	bridge.StopActive()
}

func main() {}
