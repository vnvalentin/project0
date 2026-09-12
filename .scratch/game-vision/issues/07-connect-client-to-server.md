Type: task
Status: unclaimed
Blocked by: 01, 02

## Question
What is the smallest networked interaction slice that starts a Godot headless server, connects the existing client over Godot's ENet high-level multiplayer API, and visibly represents the connected player in the existing flat-plane scene without adding prediction, persistence, generated world content, or production networking architecture?

## Proposed decision boundary
- Use one Godot project with an explicit headless server entry path and the existing client entry path.
- Use ENetMultiplayerPeer on localhost for the first connection proof.
- The server owns connection membership and spawns a visible Player representation for a connected client.
- The client displays connection state and the spawned Player in the existing fixed 3/4 flat-plane scene.
- Movement synchronization, client prediction, interpolation, authentication, reconnect, and remote deployment remain later decisions.

## Handoff workflow
Copilot owns the decision, acceptance scenarios, and implementation brief. Claude Code CLI owns code edits and executable validation. Copilot reviews the returned files and fresh command output before the next network slice.
