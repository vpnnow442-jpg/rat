# Chaos Course

A Roblox party platformer for 2–8 players. Everyone grabs a piece from the box,
sneaks it into the course, then everyone races it.
Make it too easy and nobody scores. Make it too hard and nobody scores.
Make it *just* evil enough and you win.

## Play it

1. Download **`ChaosCourse.rbxlx`**
2. Open it in **Roblox Studio** (File → Open from File)
3. Press **Play**, then hit **Play** again in the game's menu

Multiplayer test: **Test → Clients and Servers → pick 2–4 players → Start**.

> **Parties (Create party / Join with code / Invite) only work in the published game.**
> Roblox doesn't allow private servers or teleports inside Studio, so in Studio those
> buttons show a friendly message instead. Publish the place (File → Publish to Roblox),
> then in Game Settings → Security turn on **Enable Studio Access to API Services**
> and set **Max Players to 8**.

**Controls**

| | Keyboard | Gamepad | Mobile |
|---|---|---|---|
| Move | A / D | Left stick | Thumbstick |
| Jump / double jump | Space | A | Jump button |
| Wall jump | Hold toward a wall in the air, jump | same | same |
| Grab from the box | Click a piece | A | Tap |
| Place piece | Click | A | Tap spot, then **Place** |
| Rotate | R | X | **Rotate** |
| Back | Right-click / Q | B | **Back** |
| Look around the map while building | Just move the cursor: the map follows it | Stick | Drag |
| Zoom while building | Mouse wheel | — | Pinch |
| Jetpack (after grabbing one) | Hold jump | Hold A | Hold jump |
| Emotes: wave, dance, laugh, sit | 1 / 2 / 3 / 4 | — | Buttons, bottom left |

## Worlds

| World | Maps | What's different |
|---|---|---|
| Forest | Mossy Hollow, Fallen Log, Canopy Run | grass, logs, treetop decks, river below |
| Mountain | Frosty Ridge, Avalanche Pass | natural **ice** (keeps your momentum), cliffs, snowfall |
| Factory | Assembly Line, Pipe Dream | **conveyor belts** (some run backwards), girders, pipes, toxic goo below |

A different map every match, and a different world whenever possible.

## How a round works

1. **Pick**: your screen turns into a crate with 4–7 pieces tossed in. First click wins.
2. **Build**: everyone places their piece. You see other players' ghosts live.
3. **Run**: race to the flag. For the first second nothing can take you out
   (spawn protection), and lasers stay off for 2 seconds.
4. **Score**: the full-screen bar table fills in. First to **600** wins (max 12 rounds, last one double).
   Carry a **coin** to the flag for bonus points.

## Project layout

```
src/
  ReplicatedFirst/Loading.client.luau   loading screen
  ReplicatedStorage/Shared/             shared by server + client
    Config  Objects  Levels  Characters  Style  Net
  ServerScriptService/Services/         server authority
    MatchService  RoundService  BuildService  LevelService  LobbyService
    PlayerService  ScoringService  HazardService
  StarterPlayer/StarterPlayerScripts/Controllers/
    MenuController  PickController  BuildController  MovementController
    CameraController  ObjectController  CharacterAnimator  HudController
    ResultsUI  FxController  SoundController  State  UI
build.py                                bundles src/ into ChaosCourse.rbxlx
```

Edit anything in `src/`, then run `python3 build.py` to rebuild the place file.
The layout also works with [Rojo](https://rojo.space) (`default.project.json`).

See [`docs/PLAN.md`](docs/PLAN.md) for design decisions, phase status, and the playtest checklist.
