# Sabotage Sprint: plan & status

An original 2–8 player party platformer. Everyone builds the level, then everyone races it.
Core loop: **BUILD → RUN → FAIL/LAUGH → SCORE → BUILD AGAIN**.

## Design decisions (and why)

| Decision | Why |
|---|---|
| **2.5D side view**: movement locked to one plane | Deaths are readable ("I saw the saw"), building is a 2D click, clips look clean. 3D depth misjudgement is the #1 cause of "unfair" deaths in Roblox obbies. |
| **Same hitbox for every character** | Avatar sizes vary on Roblox. In a platformer that's unfair. Animals are visual only. |
| **Too easy / too hard rule** | If everyone finishes, nobody scores. If nobody finishes, trap points don't count. So the winning strategy is a level that's deadly *but beatable*, which is exactly the fun. |
| **Every hand has a route piece** | Stops a round where nobody can add a way through. Bomb card (from round 2) is the counter to a griefed level. |
| **Trap points capped per round (75)** | One nasty trap can't decide the whole match. |
| **Fixed 8 rounds, last one double** | Predictable ~10 minute matches; the final round always matters. |
| **Object motion computed from server clock** | Every client animates saws/hammers/shuttles/cannons identically with zero network traffic. |
| **Knockback/launch effects client-side, deaths server-side** | Pushes must feel instant (client owns its physics); outcomes that score must be authoritative. |
| **Procedural animation, no assets** | Squash/stretch, waddle, flips, tumble, victory hops, all in code. Fits the clean cartoon style and costs nothing to replicate. |

## Phase status

| # | Phase | Status |
|---|---|---|
| 1 | Movement & physics | ✅ coyote time, jump buffer, air jump, wall slide/jump, ice, honey, launches, 2.5D lock |
| 2 | Level & goal | ✅ 3 Forest layouts, data-driven, safe zones, flag |
| 3 | Build phase | ✅ cards, ghost preview, snap, rotate, cancel, live ghosts of other builders, server validation |
| 4 | Round system | ✅ intro → (build → countdown → run → results) × 8 → winner |
| 5 | Scoring | ✅ 100/75/50/25, traps, clutch, own-route, too easy / too hard, final round x2 |
| 6 | Objects & hazards | ✅ 15 objects: plank, crate, spring, conveyor, shuttle, ice, crumbly ledge, trick plank, honey, spikes, buzzsaw, swing hammer, fan, cannon, bomb |
| 7 | Characters & animation | 🟡 4 of 8 animals (fox, raccoon, penguin, frog), procedural anims. Missing: goat, cat, duck, possum; emotes; character picker |
| 8 | UI | 🟡 in-match HUD done. Missing: main menu, settings |
| 9 | Lobbies / parties / matchmaking | ⬜ needs a published place (TeleportService, MemoryStore) |
| 10 | Cosmetic progression | ⬜ needs DataStores (published place) |
| 11 | Community levels | ⬜ the level format is already plain data (`Levels.luau`), ready to save |
| 12 | Optimisation & polish | ⬜ real audio, more worlds, tuning from playtests |

**Rule for what comes next: nothing in phases 9–12 until the playtest says phases 1–6 are fun.**

## Playtest checklist (please report back on these)

Open `SabotageSprint.rbxlx` in Studio and press **Play** (solo works). For multiplayer:
**Test → Clients and Servers → 2–4 players → Start**.

Movement, the most important part:
- [ ] Does running and jumping feel snappy or floaty?
- [ ] Double jump: does a second press in the air always work? Does it ever fire by accident?
- [ ] Wall jump: hold toward a crate wall in the air, press jump. Does it work reliably?
- [ ] Ice: slidey in a fun way, or just annoying?
- [ ] Shuttle (moving platform): does it carry you, or slide out from under you? *(the riskiest bit)*

Building:
- [ ] Can you place a piece in under 5 seconds without reading anything?
- [ ] Is green/red always correct? Any "it said green but the server refused"?
- [ ] Do you see other players' ghosts move around while they choose?

Objects: for each one, does it do what the card says?
- [ ] Spring (flat and rotated), conveyor, fan (pointing up and sideways), hammer, cannon, crumbly ledge, trick plank, honey, bomb

Round flow:
- [ ] Does the camera ever lose you or go somewhere weird?
- [ ] After you fail, is the wait boring?
- [ ] Do the results make sense at a glance?

Screenshots of anything ugly are the most useful feedback of all.

## Known limitations

- **Sounds are placeholders** built into Roblox. Swap in real audio in `SoundController.luau` (one table).
- **Untested in Roblox**: the code is type-checked against the real Roblox API, but it has not been run.
  Expect a round of fixes after the first playtest.
- Gamepad building works but is basic (stick moves the cursor).
