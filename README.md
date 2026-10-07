# Skills Wars

Mobile hook-battle game built with Godot 4.7. See [PLAN.md](PLAN.md) for the game design and roadmap.

## Layout

```
game/                 Godot project (client and headless match server)
  heroes/             one folder per hero (model, visual scene, skill visuals)
  maps/               one folder per map
  ui/                 menu, touch controls, shop, kill feed
  fx/                 particle effects (Fx) and sound playback (Sfx)
  audio/              sound effects
  match/              server-authoritative simulation, networking, prediction and match view
  net/                Net autoload, LAN discovery, online API client, match heartbeat, snapshot codec
  sandbox/            art test scene: walk around and throw the hook at a dummy
  tests/              headless tests
backend/              NestJS online backend: rooms, quick play, match server processes
deploy/               Dockerfile and docker compose for running the backend + match servers on a server
tools/blender/        scripts that generate art (meshkit/posekit are shared helpers)
third_party/          downloaded asset packs, not committed
```

Map props come from Quaternius's *Stylized Nature MegaKit* (CC0), copied into `game/maps/shared/nature/`.

## Run

```bash
godot --path game
```

The menu offers **Play online** (Quick play, Create room, or Join with a 4-letter code), **Practice vs bots** (3v3), **Host a game** (optionally filling empty slots with bots), a list of
**games found on your Wi-Fi**, and **Join by address**. Your name is saved and shown above your hero and in the kill feed
(offensive names are replaced by "Player", checked again by the server). **Settings** (menu corner or in a match) turns
sound and vibration on or off and shows the game version. The game is capped at 60 FPS to save battery.
Controls: joystick (arrow keys on desktop) to move. Drag the HOOK button to aim (you can keep walking) and release
to throw; Gaff winds up for 0.7 s, and tapping HOOK again during the wind-up cancels the throw (hesi).
ARROW and TRAP aim the same way and fire on release.
In a match, **Shop** opens the upgrade strip (Hook / Arrow / Trap tabs); star an upgrade to make it the
**Quick buy** pick next to the Shop button.

### Command-line flags

Pass them after `--`, e.g. `godot --path game -- --host --bots=2`.

| Flag | Effect |
|---|---|
| `--practice` | Offline match against bots |
| `--host` | Host a match and play in it |
| `--server` | Dedicated server, no local player (use with `--headless`) |
| `--join=ADDRESS` | Join a host or server |
| `--port=N` | Port to host or join (default 7777) |
| `--fill` | Host/server keeps teams at 3v3 with bots that step aside when players join |
| `--bots=N` | Fixed number of bots added by the host or server (without `--fill`) |
| `--name=NAME` | Player name for this run |
| `--lag=MS` | Client only: adds simulated round-trip lag |
| `--autopilot` | The local hero is driven by the bot brain (for automated tests) |
| `--quickplay` | Client: start online quick play right away |
| `--join-room=CODE` | Client: join an online room by code right away |
| `--backend=URL` | Online backend address (default `http://127.0.0.1:3000`, or the one saved in the menu) |
| `--room=CODE` | Match server only: the room it serves; set by the backend, which also passes `MATCH_SECRET` |
| `--print-protocol` | Print the game's network protocol number and quit (the backend uses this at startup) |

### Game versions

`Net.PROTOCOL` in `game/net/net.gd` is the network protocol number. **Bump it whenever RPCs, input packets or the
snapshot layout change.** Games with a different number can't play together:

- **Online:** the game sends its number in the `x-game-protocol` header. The backend asks its match server build for its
  number at startup and answers anything else with `426`. The player then sees "A new version of Skills Wars is out.
  Update the game" or "The servers are being updated".
- **Wi-Fi and join by address:** a handshake runs when connecting, before any game data, so mismatched versions are
  turned away with the same messages. The Wi-Fi list only shows games with the same number.

## Online backend

Needs Node 22 or 24. Run it on your Mac; it starts a headless Godot match server for each room.

```bash
cd backend && cp .env.example .env
```

Set `MATCH_SECRET` in `backend/.env` to a long random string. The defaults run match servers with the `godot` on your PATH.

```bash
cd backend && npm install && npm run start:dev
```

Then press **Quick play** in two game windows. To play from a phone on the same Wi-Fi, set `PUBLIC_HOST` in
`backend/.env` to your Mac's IP and type `http://<that IP>:3000` in the menu's **Online server** field.

| Endpoint | Purpose |
|---|---|
| `POST /v1/rooms` `{"visibility":"private"}` | Create a room, returns `{code, host, port, ...}` (room routes need the `x-game-protocol` header) |
| `POST /v1/rooms/:code/join` | Join a room by code (404 unknown, 409 full) |
| `POST /v1/rooms/quick-play` | Join the fullest public room with space, or open a new one |
| `POST /v1/internal/rooms/:code/heartbeat` | Match servers report player counts (needs the `x-match-secret` header) |
| `GET /health` | Health check with room count and free slots |

## Deploy

Export both Linux server builds (see Build), then on the server, with Docker installed:

```bash
cp deploy/.env.example deploy/.env
```

Set `PUBLIC_HOST` (the server's public IP or domain) and `MATCH_SECRET` in `deploy/.env`, then:

```bash
docker compose -f deploy/docker-compose.yml up -d --build
```

Open TCP 3000 and UDP 7800–7819 in the server's firewall.

## Test

```bash
godot --headless --path game --script res://tests/simulation_smoke_test.gd
```

```bash
cd backend && npm test && npm run test:e2e
```

## Build

```bash
godot --headless --path game --export-debug "Android" build/android/skills-wars.apk
```

```bash
godot --headless --path game --export-release "Linux Server" build/server/skills-wars-server.x86_64
```

```bash
godot --headless --path game --export-release "Linux Server ARM" build/server/skills-wars-server.arm64
```

iOS exports an Xcode project to `game/build/ios`; building it needs Xcode 26 (Godot 4.7 templates use the iOS 26 SDK).

## Rebuild generated art

```bash
blender -b --factory-startup --python tools/blender/build_gaff.py -- game/heroes/gaff
```

```bash
blender -b --factory-startup --python tools/blender/build_river_arena.py -- game/maps/river_arena/terrain.glb
```

```bash
python3 tools/blender/build_river_arena_scene.py game/maps/river_arena/river_arena.tscn
```

Map sizes (play area, river width, banks) live in `tools/blender/river_arena_shape.py`; after changing them, run both
commands above. The hook's reach (`max_range` in `game/heroes/hook_skill.gd`) must still cover your river edge to the
enemy's back wall; the smoke test checks it.

Add a second path after `game/heroes/gaff` to also render hero preview images there.

Effect textures and placeholder sound effects are generated too:

```bash
python3 tools/fx/generate_textures.py game/fx/textures
```

```bash
python3 tools/audio/generate_sfx.py game/audio/sfx
```
