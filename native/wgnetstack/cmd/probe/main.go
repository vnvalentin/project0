// Command probe exercises the wgnetstack bridge without Godot or cgo, for
// fast iteration and as a standalone proof harness.
package main

import (
	"flag"
	"log"
	"os"
	"os/signal"
	"syscall"

	"project0/wgnetstack/bridge"
)

func main() {
	configPath := flag.String("config", "", "path to bridge config JSON")
	flag.Parse()

	if *configPath == "" {
		log.Fatal("probe: -config is required")
	}

	raw, err := os.ReadFile(*configPath)
	if err != nil {
		log.Fatalf("probe: reading config: %v", err)
	}

	cfg, err := bridge.ParseConfig(raw)
	if err != nil {
		log.Fatalf("probe: invalid config: %v", err)
	}

	port, err := bridge.StartActive(cfg)
	if err != nil {
		log.Fatalf("probe: failed to start bridge: %v", err)
	}
	log.Printf("probe: bridge listening on 127.0.0.1:%d", port)

	sigCh := make(chan os.Signal, 1)
	signal.Notify(sigCh, os.Interrupt, syscall.SIGTERM)
	<-sigCh

	log.Printf("probe: stopping bridge")
	bridge.StopActive()
}
