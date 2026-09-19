//go:build windows

package main

import (
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

func TestDirectWANIsTheDefaultAndCanBeDisabled(t *testing.T) {
	t.Setenv(directWANEnvVar, "")
	if !directWANEnabled() {
		t.Fatal("direct WAN must be the default")
	}
	t.Setenv(directWANEnvVar, "0")
	if directWANEnabled() {
		t.Fatal("tunnel fallback must remain explicitly selectable")
	}
}
