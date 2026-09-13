package bridge

import "sync"

// singleton registry: this prototype's C API supports exactly one active
// bridge instance per process, matching wgnetstack_start/wgnetstack_stop's
// no-argument stop signature.
var (
	activeMu sync.Mutex
	active   *Bridge
)

// StartActive starts a new bridge and registers it as the process-wide active
// instance. Starting again while one is already active stops the previous one
// first, so repeated start/stop cycles never leak a running bridge.
func StartActive(cfg Config) (int, error) {
	activeMu.Lock()
	defer activeMu.Unlock()

	if active != nil {
		active.Stop()
		active = nil
	}

	b, port, err := Start(cfg)
	if err != nil {
		return -1, err
	}
	active = b
	return port, nil
}

// StopActive stops the process-wide active bridge, if any.
func StopActive() {
	activeMu.Lock()
	defer activeMu.Unlock()

	if active == nil {
		return
	}
	active.Stop()
	active = nil
}
