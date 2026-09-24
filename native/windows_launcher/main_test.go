//go:build windows

package main

import (
	"os"
	"path/filepath"
	"reflect"
	"testing"
)

func TestParseUpdaterArgsReadsOnlyProject0Flags(t *testing.T) {
	values := parseUpdaterArgs([]string{
		"--project0-update-helper",
		"--project0-staged-pack=C:\\staging\\Project0.pck",
		"--project0-pending-version=0.7.0",
		"--project0-previous-version=0.6.0",
		"--project0-expected-sha256=abc123",
		"--project0-payload-dir=C:\\Users\\tester\\AppData\\Local\\Project0\\payload",
		"--unrelated=value",
	})
	if values["staged-pack"] != "C:\\staging\\Project0.pck" {
		t.Fatalf("staged-pack = %q", values["staged-pack"])
	}
	if values["pending-version"] != "0.7.0" || values["previous-version"] != "0.6.0" {
		t.Fatalf("versions = %+v", values)
	}
	if _, ok := values["unrelated"]; ok {
		t.Fatal("non-project0 flags must not enter updater args")
	}
}
func TestHasArgRequiresAnExactFlag(t *testing.T) {
	if !hasArg([]string{"--project0-update-helper"}, "--project0-update-helper") {
		t.Fatal("expected exact helper flag")
	}
	if hasArg([]string{"--project0-update-helper=true"}, "--project0-update-helper") {
		t.Fatal("must not accept a value-bearing variant")
	}
}

func TestLoadLauncherConfigDefaultsToWAN(t *testing.T) {
	config, err := loadLauncherConfig(filepath.Join(t.TempDir(), "launcher-config.json"))
	if err != nil {
		t.Fatal(err)
	}
	if config.Mode != launcherModeWAN || config.LANHost != "" {
		t.Fatalf("config = %+v, want WAN with no LAN host", config)
	}
}

func TestSaveAndLoadLauncherConfigPreservesLANSelection(t *testing.T) {
	path := filepath.Join(t.TempDir(), "launcher-config.json")
	want := launcherConfig{Mode: launcherModeLAN, LANHost: "192.168.1.44"}
	if err := saveLauncherConfig(path, want); err != nil {
		t.Fatal(err)
	}
	got, err := loadLauncherConfig(path)
	if err != nil {
		t.Fatal(err)
	}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("config = %+v, want %+v", got, want)
	}
}

func TestBuildLaunchRequestSetsModeOutputsAndPreservesExplicitHost(t *testing.T) {
	request, err := buildLaunchRequest(
		launcherConfig{Mode: launcherModeLAN, LANHost: "192.168.1.44"},
		[]string{"--server-host=10.0.0.5"},
		[]string{"PROJECT0_TUNNEL=1", "PROJECT0_CLIENT_HTTPS_LOGIN=1"},
	)
	if err != nil {
		t.Fatal(err)
	}
	if request.Env["PROJECT0_TUNNEL"] != "0" || request.Env["PROJECT0_CLIENT_HTTPS_LOGIN"] != "0" {
		t.Fatalf("LAN environment = %+v", request.Env)
	}
	if !reflect.DeepEqual(request.Args, []string{"--server-host=10.0.0.5"}) {
		t.Fatalf("args = %+v, explicit host was not preserved", request.Args)
	}
}

func TestBuildLaunchRequestAddsLANHostWhenNoExplicitHostExists(t *testing.T) {
	request, err := buildLaunchRequest(
		launcherConfig{Mode: launcherModeLAN, LANHost: "192.168.1.44"},
		nil,
		os.Environ(),
	)
	if err != nil {
		t.Fatal(err)
	}
	if !reflect.DeepEqual(request.Args, []string{"--server-host=192.168.1.44"}) {
		t.Fatalf("args = %+v, want persisted LAN host", request.Args)
	}
}

func TestLANModeWithoutHostFailsClosed(t *testing.T) {
	if _, err := buildLaunchRequest(launcherConfig{Mode: launcherModeLAN}, nil, nil); err == nil {
		t.Fatal("expected LAN mode without a host to fail")
	}
}

func TestForwardedArgsRemoveLauncherOnlyFlags(t *testing.T) {
	got := forwardedArgs([]string{lanModeArg, lanHostArgPrefix + "192.168.1.44", "--invite-code=secret", "--fullscreen"})
	if !reflect.DeepEqual(got, []string{"--fullscreen"}) {
		t.Fatalf("forwarded args = %+v", got)
	}
}
