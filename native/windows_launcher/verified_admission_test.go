//go:build windows

package main

import (
	"context"
	"crypto"
	"crypto/rand"
	"crypto/rsa"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"encoding/pem"
	"errors"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"sync/atomic"
	"syscall"
	"testing"
	"time"
)

func TestAdmissionEngineProbe(t *testing.T) {
	if os.Getenv("PROJECT0_ADMISSION_PROBE") != "1" {
		return
	}
	root := filepath.Join(os.Getenv("LOCALAPPDATA"), "Project0")
	raw, err := os.ReadFile(filepath.Join(root, "version-manifest.json"))
	if err != nil {
		t.Fatal(err)
	}
	var manifest map[string]any
	if err := json.Unmarshal(raw, &manifest); err != nil {
		t.Fatal(err)
	}
	if manifest["build_id"] != "experiment-1100-probe" || manifest["required_client_version"] != launcherClientVersion {
		t.Fatalf("unexpected tuple: %v", manifest)
	}
	executable, err := os.Executable()
	if err != nil || filepath.Clean(executable) != filepath.Join(root, "active", "Project0.exe") {
		t.Fatalf("unverified executable selected: %s (%v)", executable, err)
	}
	if err := os.WriteFile(os.Getenv("PROJECT0_ADMISSION_PROBE_RESULT"), raw, 0600); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(os.Getenv("PROJECT0_ADMISSION_PROBE_RESULT")+".pid", []byte(strconv.Itoa(os.Getpid())), 0600); err != nil {
		t.Fatal(err)
	}
	if os.Getenv("PROJECT0_ADMISSION_PROBE_HOLD") == "1" {
		<-time.After(30 * time.Second)
	}
}

func TestPackagedVerifiedAdmissionPersistsBeforeSpawn(t *testing.T) {
	executable, err := os.Executable()
	if err != nil {
		t.Fatal(err)
	}
	engine, err := os.ReadFile(executable)
	if err != nil {
		t.Fatal(err)
	}
	pack := []byte("experiment-1100-resource-pack")
	runAdmissionMatrix(t, engine, pack, []string{"-test.run=^TestAdmissionEngineProbe$"}, true)
}

func TestExperiment1100RealEngine(t *testing.T) {
	enginePath, packPath := os.Getenv("PROJECT0_1100_ENGINE"), os.Getenv("PROJECT0_1100_PACK")
	if enginePath == "" && packPath == "" {
		t.Skip("real-engine experiment is opt-in via run_windows_experiment_1100.ps1")
	}
	engine, err := os.ReadFile(enginePath)
	if err != nil {
		t.Fatal(err)
	}
	pack, err := os.ReadFile(packPath)
	if err != nil {
		t.Fatal(err)
	}
	runAdmissionMatrix(t, engine, pack, []string{"--headless", "--quit-after", "10"}, false)
}

func runAdmissionMatrix(t *testing.T, engine, pack []byte, childArgs []string, probe bool) {
	t.Helper()
	buildRoot, err := os.MkdirTemp(os.Getenv("PROJECT0_1100_WORK_ROOT"), "project0-1100-build-")
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() {
		if err := os.RemoveAll(buildRoot); err != nil {
			t.Error(err)
		}
	})
	launcher := filepath.Join(buildRoot, "launcher.exe")
	if output, err := exec.Command("go", "build", "-ldflags", "-X main.launcherClientVersion="+launcherClientVersion, "-o", launcher, ".").CombinedOutput(); err != nil {
		t.Fatalf("build: %v: %s", err, output)
	}
	scenarios := []string{"valid", "signature", "malformed_signature", "missing_signature", "exe_hash", "pck_hash", "existing_root", "missing_build"}
	if probe {
		scenarios = append(scenarios, "child_timeout")
	}
	for _, scenario := range scenarios {
		t.Run(scenario, func(t *testing.T) {
			root, err := os.MkdirTemp(os.Getenv("PROJECT0_1100_WORK_ROOT"), "project0-1100-")
			if err != nil {
				t.Fatal(err)
			}
			evidence := map[string]any{"scenario": scenario, "probe": probe, "test_root": root, "host": os.Getenv("COMPUTERNAME"), "authentication": "login remains in Godot; gameplay authentication not exercised"}
			t.Cleanup(func() {
				cleanupErr := os.RemoveAll(root)
				evidence["cleanup_succeeded"] = cleanupErr == nil
				if cleanupErr != nil {
					evidence["cleanup_error"] = cleanupErr.Error()
					t.Error(cleanupErr)
				}
				evidence["passed"] = !t.Failed()
				if directory := os.Getenv("PROJECT0_1100_EVIDENCE"); directory != "" {
					raw, encodeErr := json.MarshalIndent(evidence, "", "  ")
					if encodeErr != nil {
						t.Error(encodeErr)
						return
					}
					if err := os.WriteFile(filepath.Join(directory, strconv.FormatBool(probe)+"-"+scenario+".json"), raw, 0600); err != nil {
						t.Error(err)
					}
				}
			})
			key, public := testKey(t)
			var manifest, signature []byte
			var payloadRequests atomic.Int32
			server := httptest.NewTLSServer(http.HandlerFunc(func(response http.ResponseWriter, request *http.Request) {
				switch request.URL.Path {
				case "/manifest":
					response.Header().Set("X-Project0-Manifest-Signature", base64.StdEncoding.EncodeToString(signature))
					if scenario == "malformed_signature" {
						response.Header().Set("X-Project0-Manifest-Signature", "%%invalid%%")
					}
					if scenario == "missing_signature" {
						response.Header().Del("X-Project0-Manifest-Signature")
					}
					_, _ = response.Write(manifest)
				case "/Project0.exe":
					payloadRequests.Add(1)
					if scenario == "exe_hash" {
						_, _ = response.Write([]byte("corrupt engine"))
					} else {
						_, _ = response.Write(engine)
					}
				case "/Project0.pck":
					payloadRequests.Add(1)
					if scenario == "pck_hash" {
						_, _ = response.Write([]byte("corrupt pack"))
					} else {
						_, _ = response.Write(pack)
					}
				default:
					http.NotFound(response, request)
				}
			}))
			defer server.Close()
			engineHash, packHash := sha256.Sum256(engine), sha256.Sum256(pack)
			buildID := "experiment-1100-probe"
			if !probe {
				buildID = "experiment-1100-" + hex.EncodeToString(packHash[:8])
			}
			if scenario == "missing_build" {
				buildID = ""
			}
			manifest, err = json.Marshal(map[string]any{
				"schema_version": 1, "required_client_version": launcherClientVersion,
				"build_id": buildID, "pck_sha256": hex.EncodeToString(packHash[:]),
				"pck_url": server.URL + "/Project0.pck", "size_bytes": len(pack),
				"payloads": []manifestPayload{
					{Name: "Project0.exe", URL: server.URL + "/Project0.exe", SHA256: hex.EncodeToString(engineHash[:])},
					{Name: "Project0.pck", URL: server.URL + "/Project0.pck", SHA256: hex.EncodeToString(packHash[:])},
				},
			})
			if err != nil {
				t.Fatal(err)
			}
			digest := sha256.Sum256(manifest)
			signature, err = rsa.SignPKCS1v15(rand.Reader, key, crypto.SHA256, digest[:])
			if err != nil {
				t.Fatal(err)
			}
			if scenario == "signature" {
				signature[0] ^= 1
			}
			evidence["engine_sha256"], evidence["pck_sha256"], evidence["build_id"] = hex.EncodeToString(engineHash[:]), hex.EncodeToString(packHash[:]), buildID
			certificatePath, keyPath := filepath.Join(root, "ca.pem"), filepath.Join(root, "public.pem")
			if err := os.WriteFile(certificatePath, pem.EncodeToMemory(&pem.Block{Type: "CERTIFICATE", Bytes: server.Certificate().Raw}), 0600); err != nil {
				t.Fatal(err)
			}
			if err := os.WriteFile(keyPath, []byte(public), 0600); err != nil {
				t.Fatal(err)
			}
			deadline := 45 * time.Second
			if scenario == "child_timeout" {
				deadline = 2 * time.Second
			}
			ctx, cancel := context.WithTimeout(context.Background(), deadline)
			defer cancel()
			command := exec.CommandContext(ctx, launcher, append([]string{"--test-ca-cert=" + certificatePath}, childArgs...)...)
			probeResult := filepath.Join(root, "probe.json")
			command.Cancel = func() error {
				var handle syscall.Handle
				var handleErr error
				if rawPID, err := os.ReadFile(probeResult + ".pid"); err == nil {
					childPID, err := strconv.ParseUint(string(rawPID), 10, 32)
					if err != nil {
						handleErr = err
					} else {
						handle, handleErr = syscall.OpenProcess(syscall.SYNCHRONIZE, false, uint32(childPID))
						if handle != 0 {
							defer syscall.CloseHandle(handle)
						}
					}
				}
				killErr := exec.Command("taskkill", "/PID", strconv.Itoa(command.Process.Pid), "/T", "/F").Run()
				if handle != 0 {
					status, waitErr := syscall.WaitForSingleObject(handle, 5000)
					if waitErr != nil || status != syscall.WAIT_OBJECT_0 {
						return errors.Join(killErr, fmt.Errorf("child termination wait: status=%d error=%v", status, waitErr))
					}
				}
				return errors.Join(killErr, handleErr)
			}
			command.WaitDelay = 5 * time.Second
			installRoot := filepath.Join(root, "local", "Project0")
			if scenario == "existing_root" {
				for _, name := range []string{"active", "backup"} {
					if err := os.MkdirAll(filepath.Join(installRoot, name), 0700); err != nil {
						t.Fatal(err)
					}
					if err := os.WriteFile(filepath.Join(installRoot, name, "sentinel"), []byte("preserve existing state"), 0600); err != nil {
						t.Fatal(err)
					}
				}
			}
			var baseEnvironment []string
			for _, entry := range os.Environ() {
				if !strings.HasPrefix(strings.ToUpper(entry), "PROJECT0_") {
					baseEnvironment = append(baseEnvironment, entry)
				}
			}
			command.Env = testEnvironment(baseEnvironment, map[string]string{
				"LOCALAPPDATA": filepath.Join(root, "local"), "APPDATA": filepath.Join(root, "roaming"),
				testManifestURLEnv: server.URL + "/manifest", testSigningPublicKeyFileEnv: keyPath,
				"PROJECT0_ADMISSION_PROBE": "1", "PROJECT0_ADMISSION_PROBE_RESULT": probeResult,
				"PROJECT0_ENROLLMENT_URL": "https://127.0.0.1:1", "PROJECT0_NAKAMA_URL": "https://127.0.0.1:1",
				"PROJECT0_SERVER_HOST": "127.0.0.1", "PROJECT0_SERVER_PORT": "1", "PROJECT0_LOGIN_PORT": "1",
			})
			if scenario == "child_timeout" {
				command.Env = append(command.Env, "PROJECT0_ADMISSION_PROBE_HOLD=1")
			}
			output, runErr := command.CombinedOutput()
			if command.ProcessState == nil {
				t.Fatalf("launcher did not start: %v", runErr)
			}
			evidence["exit_code"], evidence["payload_requests"], evidence["output"] = command.ProcessState.ExitCode(), payloadRequests.Load(), string(output)
			var events []map[string]any
			for _, line := range strings.Split(string(output), "\n") {
				if strings.HasPrefix(line, "PROJECT0_ADMISSION ") {
					var event map[string]any
					if err := json.Unmarshal([]byte(strings.TrimPrefix(line, "PROJECT0_ADMISSION ")), &event); err != nil {
						t.Fatal(err)
					}
					events = append(events, event)
				}
			}
			evidence["events"] = events
			if scenario == "child_timeout" {
				if ctx.Err() == nil || runErr == nil || len(events) != 2 {
					t.Fatalf("timeout recovery not exercised: %v %v %s", ctx.Err(), runErr, output)
				}
				if _, err := os.Stat(probeResult); err != nil {
					t.Fatalf("probe never started before timeout: %v", err)
				}
				evidence["project0_exe_spawn_count"], evidence["expected_timeout"] = 1, true
				return
			}
			if ctx.Err() != nil {
				t.Fatalf("launcher deadline exceeded: %s", output)
			}
			if scenario != "valid" {
				if _, err := os.Stat(probeResult); !os.IsNotExist(err) {
					t.Fatalf("rejected case ran the engine probe: %v", err)
				}
				expectedCode := 2
				if strings.Contains(scenario, "signature") {
					expectedCode = 1
				}
				if scenario == "exe_hash" || scenario == "pck_hash" {
					expectedCode = 3
				}
				if runErr == nil || command.ProcessState.ExitCode() != expectedCode || len(events) != 0 {
					t.Fatalf("rejection: %v, events=%v: %s", runErr, events, output)
				}
				if strings.Contains(scenario, "signature") && payloadRequests.Load() != 0 {
					t.Fatal("invalid signature downloaded payloads")
				}
				if scenario == "existing_root" {
					for _, name := range []string{"active", "backup"} {
						raw, err := os.ReadFile(filepath.Join(installRoot, name, "sentinel"))
						if err != nil || string(raw) != "preserve existing state" {
							t.Fatalf("existing state changed: %v", err)
						}
					}
				} else if _, err := os.Stat(installRoot); !os.IsNotExist(err) {
					t.Fatalf("rejected install left state: %v", err)
				}
				evidence["project0_exe_spawn_count"], evidence["staging_bytes_written"] = 0, 0
				return
			}
			if runErr != nil {
				t.Fatalf("verified launcher failed: %v: %s", runErr, output)
			}
			if len(events) != 2 || events[0]["event"] != "manifest_persisted" || events[1]["event"] != "engine_started" {
				t.Fatalf("wrong event ordering: %v", events)
			}
			if events[1]["pid"].(float64) <= 0 || events[1]["path"] != filepath.Join(installRoot, "active", "Project0.exe") {
				t.Fatalf("wrong process: %v", events[1])
			}
			evidence["project0_exe_spawn_count"] = 1
			for _, path := range []string{filepath.Join(installRoot, "version-manifest.json"), filepath.Join(installRoot, "active", "version-manifest.json")} {
				observed, err := os.ReadFile(path)
				if err != nil || string(observed) != string(manifest) {
					t.Fatalf("persisted tuple differs: %v", err)
				}
			}
			for name, expected := range map[string]string{"Project0.exe": hex.EncodeToString(engineHash[:]), "Project0.pck": hex.EncodeToString(packHash[:])} {
				actual, err := sha256File(filepath.Join(installRoot, "active", name))
				if err != nil || actual != expected {
					t.Fatalf("installed payload differs: %s %v", name, err)
				}
			}
			if _, err := os.Stat(filepath.Join(installRoot, "staging")); !os.IsNotExist(err) {
				t.Fatalf("staging was not promoted: %v", err)
			}
			if probe {
				observed, err := os.ReadFile(probeResult)
				if err != nil || string(observed) != string(manifest) {
					t.Fatalf("child did not observe tuple: %v", err)
				}
			} else if !strings.Contains(string(output), "Godot Engine") {
				t.Fatal("real engine startup not observed")
			}
		})
	}
}
