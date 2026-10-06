# Skills Wars

Mobile hook-battle game built with Godot 4.7. See [PLAN.md](PLAN.md) for the game design and roadmap.

## Layout

```
game/                 Godot project (client and, later, the headless match server)
  heroes/             one folder per hero (model, visual scene, skill visuals)
  maps/               one folder per map
  ui/                 menu, touch controls, shop, kill feed
  fx/                 particle effects (Fx) and sound playback (Sfx)
  audio/              sound effects
  match/              server-authoritative simulation, networking, prediction and match view
  net/                Net autoload: practice, host, join, dedicated server
  sandbox/            art test scene: walk around and throw the hook at a dummy
  tests/              headless tests
tools/blender/        scripts that generate art (meshkit/posekit are shared helpers)
third_party/          downloaded asset packs, not committed
```

Map props come from Quaternius's *Stylized Nature MegaKit* (CC0), copied into `game/maps/shared/nature/`.

## Run

```bash
godot --path game
```

The menu offers **Practice vs bots** (3v3), **Host a game** (optionally filling empty slots with bots), a list of
**games found on your Wi-Fi**, and **Join by address**. Your name is saved and shown above your hero and in the kill feed.
Desktop controls: arrow keys to move, click and drag the HOOK button to aim and release to fire.

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

## Test

```bash
godot --headless --path game --script res://tests/simulation_smoke_test.gd
```

## Build

```bash
godot --headless --path game --export-debug "Android" build/android/skills-wars.apk
```

```bash
godot --headless --path game --export-release "Linux Server" build/server/skills-wars-server.x86_64
```

iOS exports an Xcode project to `game/build/ios`; building it needs Xcode 26 (Godot 4.7 templates use the iOS 26 SDK).

## Rebuild generated art

```bash
blender -b --factory-startup --python tools/blender/build_gaff.py -- game/heroes/gaff
```

```bash
blender -b --factory-startup --python tools/blender/build_river_arena.py -- game/maps/river_arena/terrain.glb
```

Add a second path after `game/heroes/gaff` to also render hero preview images there.

Effect textures and placeholder sound effects are generated too:

```bash
python3 tools/fx/generate_textures.py game/fx/textures
```

```bash
python3 tools/audio/generate_sfx.py game/audio/sfx
```
