Type: task
Status: resolved
Blocked by: 05

## Question
What is the smallest reproducible Windows client package that lets a tester run the current Godot client without installing the Godot editor, accessing the Linux network share, or receiving server/Ollama/SQLite project files?

## Decision boundary
- Produce a portable Windows 64-bit client package, initially as a versioned ZIP rather than an installer.
- Add a Godot Windows export preset and a documented reproducible export command.
- Include only client runtime files and required Godot export artifacts.
- Allow the tester to provide the Linux server host without PowerShell, preferably through a simple launch configuration or in-client connection setting while preserving the current development argument path.
- Include a short tester guide covering extraction, server address, LAN requirements, and expected connection status.
- Preserve the current login, flat-plane, rendering, movement, and network behavior; this slice packages existing behavior and does not add gameplay.

## Non-goals
- MSI/Inno Setup installer automation.
- Auto-update, code signing, public distribution, matchmaking, authentication, or internet deployment.
- Linux server packaging, Docker deployment, Ollama, SQLite, world generation, or new gameplay.

## Acceptance evidence
- A clean Windows export can be extracted to a directory without the source tree or Godot editor.
- The packaged client launches to the identity gate.
- A tester can configure the Linux server host and reach `connected: player spawned` over the LAN.
- The package export is reproducible from the repository and does not include secrets or server-only files.
- Existing focused Godot smoke tests remain green.

## Handoff workflow
Copilot owns the packaging decision, artifact boundary, and acceptance criteria. Claude Code CLI owns export configuration and reproducible build validation. Copilot reviews the artifact contents and launch procedure before any installer work.

## Answer
The portable Windows client package is complete. The export preset was
corrected to remove the invalid custom debug template and disable executable
PCK embedding, avoiding the PCX/PCK executable-header corruption. The user
exported the client on Windows, launched it outside the Godot editor/source
share, and connected it to the Linux server over LAN. Future installer,
signing, and auto-update work remains outside this slice.
