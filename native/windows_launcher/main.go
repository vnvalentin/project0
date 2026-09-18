//go:build windows

package main

import (
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"syscall"
	"unsafe"
)

const (
	updateRequiredExitCode = 20
	launcherClientVersion  = "0.6.0"
	directWANEnvVar        = "PROJECT0_DIRECT_WAN"
	directWANHost          = "project0.valentin.vip"
	directWANEnrollmentURL = "https://project0.valentin.vip"
)

func main() {
	if hasArg(os.Args[1:], "--project0-update-helper") {
		if err := runUpdaterHelperWithEnv(os.Args[1:], os.Environ()); err != nil {
			fail(err)
		}
		return
	}

	directWAN := directWANEnabled()
	var config peerConfig
	var privateKey []byte
	var err error
	if !directWAN {
		config, privateKey, err = ensurePeerConfig()
		if err != nil {
			fail(err)
		}
	}
	payloadDirectory, err := payloadDirectory()
	if err != nil {
		fail(err)
	}
	if outcome, recoveryErr := RecoverInterrupted(payloadDirectory); recoveryErr != nil {
		fail(fmt.Errorf("recover interrupted update: %w", recoveryErr))
	} else if outcome == "repair_required" {
		fail(ErrRepairRequired)
	}
	if !payloadInstalled(payloadDirectory) && !confirmInstallation() {
		fail(errors.New("installation declined"))
	}
	if err := seedPayloadFromPackage(payloadDirectory); err != nil {
		fail(err)
	}

	rejectionPath := filepath.Join(payloadDirectory, "update-rejection.json")
	_ = os.Remove(rejectionPath)
	command := exec.Command(filepath.Join(payloadDirectory, "Project0.exe"), forwardedArgs(os.Args[1:])...)
	command.Dir = payloadDirectory
	clientEnv := filteredEnvironment()
	if directWAN {
		clientEnv = append(clientEnv,
			"PROJECT0_CLIENT_HTTPS_LOGIN=1",
			"PROJECT0_ENROLLMENT_URL="+directWANEnrollmentURL,
			"PROJECT0_SERVER_HOST="+directWANHost,
		)
	} else {
		keyPath, keyErr := privateKeyFile(privateKey)
		if keyErr != nil {
			fail(keyErr)
		}
		defer os.Remove(keyPath)
		clientEnv = append(clientEnv,
			"PROJECT0_TUNNEL=1",
			"PROJECT0_TUNNEL_SERVER_PUBKEY="+config.ServerPublicKey,
			"PROJECT0_TUNNEL_ENDPOINT="+config.Endpoint,
			"PROJECT0_TUNNEL_GAME_HOST="+strings.TrimSuffix(config.AllowedIPs, "/32")+":9999",
			"PROJECT0_TUNNEL_CLIENT_ADDRESS="+config.AssignedAddress,
			"PROJECT0_TUNNEL_KEY_PATH="+keyPath,
			"PROJECT0_TUNNEL_KEEPALIVE="+fmt.Sprint(config.Keepalive),
		)
	}
	clientEnv = append(clientEnv, "PROJECT0_UPDATE_REJECTION_PATH="+rejectionPath)
	command.Env = clientEnv
	command.Stdout = nil
	command.Stderr = nil
	command.Stdin = nil

	if err := command.Run(); err != nil {
		if exitError, ok := err.(*exec.ExitError); ok {
			if exitError.ExitCode() == updateRequiredExitCode {
				if updateErr := runUpdateFromRejection(rejectionPath, payloadDirectory, clientEnv); updateErr != nil {
					fail(updateErr)
				}
				return
			}
			os.Exit(exitError.ExitCode())
		}
		fail(err)
	}
}

func directWANEnabled() bool {
	return os.Getenv(directWANEnvVar) != "0"
}

func hasArg(args []string, wanted string) bool {
	for _, arg := range args {
		if arg == wanted {
			return true
		}
	}
	return false
}

func payloadDirectory() (string, error) {
	root, err := appDataDirectory()
	if err != nil {
		return "", err
	}
	directory := filepath.Join(root, "payload")
	if err := os.MkdirAll(directory, 0700); err != nil {
		return "", fmt.Errorf("create payload directory: %w", err)
	}
	return directory, nil
}

func runUpdaterHelper(args []string) error {
	return runUpdaterHelperWithEnv(args, os.Environ())
}

func runUpdaterHelperWithEnv(args []string, clientEnv []string) error {
	values := parseUpdaterArgs(args)
	for _, required := range []string{"staged-pack", "pending-version", "previous-version", "expected-sha256", "payload-dir"} {
		if values[required] == "" {
			return fmt.Errorf("updater helper requires --project0-%s", required)
		}
	}
	if err := ApplyStagedPatch(
		values["payload-dir"],
		values["staged-pack"],
		values["pending-version"],
		values["previous-version"],
		values["expected-sha256"],
	); err != nil {
		return err
	}

	client := exec.Command(filepath.Join(values["payload-dir"], "Project0.exe"), "--project0-run-client")
	client.Dir = values["payload-dir"]
	client.Env = clientEnv
	if err := client.Run(); err != nil {
		if rollbackErr := Rollback(values["payload-dir"]); rollbackErr != nil {
			return fmt.Errorf("client readiness failed: %v; rollback failed: %w", err, rollbackErr)
		}
		return fmt.Errorf("client readiness failed; update rolled back: %w", err)
	}
	return nil
}

func runUpdateFromRejection(rejectionPath, payloadDir string, clientEnv []string) error {
	raw, err := os.ReadFile(rejectionPath)
	if err != nil {
		return fmt.Errorf("read update rejection: %w", err)
	}
	_ = os.Remove(rejectionPath)
	var rejection struct {
		RequiredVersion string `json:"required_version"`
		ManifestBaseURL string `json:"manifest_base_url"`
		Outcome         string `json:"outcome"`
	}
	if err := json.Unmarshal(raw, &rejection); err != nil {
		return fmt.Errorf("parse update rejection: %w", err)
	}
	if rejection.Outcome != "CLIENT_OUTDATED" || rejection.RequiredVersion == "" || rejection.ManifestBaseURL == "" {
		return fmt.Errorf("update rejection is not actionable: %s", rejection.Outcome)
	}
	if !confirmUpdate(rejection.RequiredVersion) {
		return errors.New("update declined")
	}
	result := DownloadAndStageUpdate(http.DefaultClient, rejection.ManifestBaseURL, launcherClientVersion, payloadDir)
	if result.Outcome != UpdateOutcomeOK {
		return fmt.Errorf("download update: %s: %s", result.Outcome, result.Detail)
	}
	return runUpdaterHelperWithEnv([]string{
		"--project0-update-helper",
		"--project0-staged-pack=" + result.StagedPath,
		"--project0-pending-version=" + result.Manifest.RequiredClientVersion,
		"--project0-previous-version=" + launcherClientVersion,
		"--project0-expected-sha256=" + result.Manifest.PCKSHA256,
		"--project0-payload-dir=" + payloadDir,
	}, clientEnv)
}

func seedPayloadFromPackage(destination string) error {
	if payloadInstalled(destination) {
		return nil
	}
	executable, err := os.Executable()
	if err != nil {
		return fmt.Errorf("find launcher package: %w", err)
	}
	sourceDir := filepath.Dir(executable)
	files := []string{
		"Project0.exe",
		"Project0.pck",
		"libwgnetstack_gdext.windows.template_release.x86_64.dll",
		filepath.Join("native", "wgnetstack", "gdext", "build", "libwgnetstack_gdext.windows.template_release.x86_64.dll"),
	}
	for _, name := range files {
		contents, readErr := os.ReadFile(filepath.Join(sourceDir, name))
		if readErr != nil {
			return fmt.Errorf("read packaged %s: %w", name, readErr)
		}
		target := filepath.Join(destination, name)
		if err := os.MkdirAll(filepath.Dir(target), 0700); err != nil {
			return fmt.Errorf("create package directory for %s: %w", name, err)
		}
		if err := os.WriteFile(target, contents, 0600); err != nil {
			return fmt.Errorf("install packaged %s: %w", name, err)
		}
	}
	return nil
}

func payloadInstalled(directory string) bool {
	for _, name := range []string{"Project0.exe", "Project0.pck", "libwgnetstack_gdext.windows.template_release.x86_64.dll"} {
		if _, err := os.Stat(filepath.Join(directory, name)); err != nil {
			return false
		}
	}
	return true
}

func confirmInstallation() bool {
	return confirmMessage("Install Project0 into %LOCALAPPDATA%\\Project0?", "Project0 installation")
}

func confirmUpdate(requiredVersion string) bool {
	return confirmMessage(fmt.Sprintf("Project0 %s is required. Download and install it now?", requiredVersion), "Project0 update available")
}

func confirmMessage(text, title string) bool {
	message := syscall.StringToUTF16Ptr(text)
	titlePtr := syscall.StringToUTF16Ptr(title)
	user32 := syscall.NewLazyDLL("user32.dll")
	messageBox := user32.NewProc("MessageBoxW")
	result, _, _ := messageBox.Call(0, uintptr(unsafe.Pointer(message)), uintptr(unsafe.Pointer(titlePtr)), 0x24)
	return result == 6
}

func parseUpdaterArgs(args []string) map[string]string {
	values := map[string]string{}
	for _, arg := range args {
		if !strings.HasPrefix(arg, "--project0-") {
			continue
		}
		parts := strings.SplitN(strings.TrimPrefix(arg, "--project0-"), "=", 2)
		if len(parts) == 2 {
			values[parts[0]] = parts[1]
		}
	}
	return values
}

func forwardedArgs(args []string) []string {
	forwarded := make([]string, 0, len(args))
	for _, arg := range args {
		if strings.HasPrefix(arg, "--invite-code=") {
			continue
		}
		forwarded = append(forwarded, arg)
	}
	return forwarded
}

func filteredEnvironment() []string {
	filtered := make([]string, 0, len(os.Environ()))
	for _, entry := range os.Environ() {
		if strings.HasPrefix(entry, "PROJECT0_INVITE_CODE=") {
			continue
		}
		filtered = append(filtered, entry)
	}
	return filtered
}

func fail(err error) {
	message := syscall.StringToUTF16Ptr("Project0 could not start:\n\n" + err.Error())
	title := syscall.StringToUTF16Ptr("Project0")
	user32 := syscall.NewLazyDLL("user32.dll")
	messageBox := user32.NewProc("MessageBoxW")
	messageBox.Call(0, uintptr(unsafe.Pointer(message)), uintptr(unsafe.Pointer(title)), 0x10)
	os.Exit(1)
}
