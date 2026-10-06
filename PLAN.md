# Skills Wars — Plan

A mobile hook-battle game inspired by the Warcraft 3 "Pudge Wars" map, with original heroes, maps and art.
Built with Godot 4 (3D low-poly, top-down camera), online and LAN multiplayer from the first playable version,
published on the App Store and Google Play.

> Never use "Pudge", "Dota", "Warcraft" or Blizzard/Valve art in the name, assets, store text or keywords.
> Before registering the store listing, run a trademark search for "Skills Wars" (a browser FPS called *SkillWarz* exists).

---

## 1. Core gameplay

- **Map:** two banks separated by a river. Nobody can cross the water, but skills fly over it. Rocks on each bank
  block skills and give cover. Power-ups spawn in the river and are collected by hooking them.
- **The hook is the only attack and kills in one hit.** No health bars, no auto-attack. Survival is about dodging.
  - Enemy hit → instant kill; the body is reeled back across the river as your catch.
  - Teammate hit → pulls them to you without harm (no score), e.g. out of the path of an enemy hook.
  - Rock hit → hook returns. Two hooks collide → both return.
- **Stun arrow (second skill, Mirana-style):** a 0.2 s throw sends a slow bolt (15.5 m/s, like Mirana's) across the whole map; the first enemy it
  touches is stunned for 2 s (can't move, hook or shoot, and any throw in progress is cancelled). It passes through
  allies, rocks block it, a Shield absorbs it, 20 s cooldown. Stun + hook is the core combo.
- **Bear trap (third skill, Sun Strike-style):** drag TRAP to target any point on the map (short drag = near, full
  drag = far). A 0.5 s casting animation that everyone sees, then the trap arms for 1.7 s — visible only to the
  caster's team (the server doesn't send it to enemies) — then snaps shut, visible to all, rooting every enemy inside
  (~1.8 m radius) for 2.5 s: they can't move but can still throw. Allies are never caught; a Shield absorbs it;
  25 s cooldown. Enemies react to the casting animation by moving; bots do the same.
- **Hesi hook:** touching HOOK starts a 0.6 s wind-up (aim by dragging during it); still holding at the end → the
  hook launches and the 10 s cooldown starts. Letting go earlier cancels the throw (hesi): no hook, cooldown stays
  ready, a Big Hook is kept. Faking throws to bait dodges is part of the skill; bots fake ~15% of their throws.
- **Reach and cooldown:** the hook reaches from your river edge to the enemy's back wall (20.5 m), so nobody can
  hide out of range. It has a 10 s cooldown that starts on the throw; the HOOK button shows the countdown.
- **Commitment:** the hero can't move from wind-up until the hook is back (tunable). Missing leaves you exposed.
- **Economy:** gold from kills and assists buys in-match upgrades — hook range, speed, size, cooldown (5 levels each).
  Items are about dodging and positioning (short dash, a shield that blocks one hook, speed boost).
  Everything resets each match; money never buys power.
- **Match:** 3v3 by default (1v1/2v2 too, up to 4v4 on LAN). First to 20 kills or the leader after 6 minutes;
  ~3 s respawn. Targets tuned in playtests since one-hit kills make kills fast.
- **Controls (landscape):** floating joystick on the left half. HOOK (bottom-right) is hold-to-cast: press to start
  the wind-up, drag to aim, keep holding to throw or let go early to hesi; a ring fills during the wind-up. ARROW (next
  to it) is drag-to-aim, release to fire. TRAP (above HOOK) is drag-to-place, release to cast. Each button shows its
  cooldown.
- **Look:** smooth cartoon in the style of Brawl Stars — toon shading, dark outlines on heroes, bright but
  not neon colors, checkered arena tiles. Map props from CC0 packs (Quaternius), anything missing built in Blender.
- **Tone:** cartoony, no blood or gore, to keep a low age rating.

## 2. Built for many heroes and maps

More heroes and maps come after launch, so content is data, not code:

- **Hero = a folder** `game/heroes/<id>/` with the model (`.glb`), a visual scene, and (from Phase 1) a hero
  definition resource: stats + skill configuration.
- **Skills are built from shared pieces** simulated on the server (projectile, pull, area, dash, shield…).
  Gaff's hook = projectile + pull. A new hero mostly combines existing pieces with new numbers and art.
- **Every hero model follows the same contract:**
  - Animations: `idle`, `run`, `<skill>_cast`, `reel`, `dragged`, `death`, `spawn`, `taunt`
    (`-loop` suffix in Blender marks looping ones).
  - Team-colored parts painted magenta (darker magenta = darker team shade); the hero shader swaps in the team color.
  - Sockets: bones where effects attach (Gaff: `hook_socket`, `chain_socket`).
  - glTF export, Blender front = −Y, ~10,000–12,000 triangles.
- **Map = a scene** `game/maps/<id>/` using standard markers: spawn points in groups `spawn_team_0/1`,
  physics layers `hero_walls` (river edges, borders) and `hook_walls` (rocks), power-up spawn points.

## 3. The first hero: Gaff

A huge river butcher and fisherman who hauls rivals out of the water like catch.

- Living (not undead), no stitches or guts, no cleaver. The hook fires from a **winch strapped to the right forearm**.
- Read from above: wide-brim rain hat in team color, broad shoulders, oversized winch arm, short chunky body.
- Current model: generated by `tools/blender/build_gaff.py` — smooth cartoon style, ~12,000 triangles, 19 bones,
  8 animations, vertex colors. Mustard knit sweater (neutral for both teams); hat, hat band, apron and pocket take
  the team color. Grumpy face with bushy brows, beard and mustache; a fish peeks out of the apron pocket.
  Hook (~350 tris) and chain link (120 tris) are separate models.
- `hook_cast` releases at **0.3 s** — the moment the hook spawns. Gameplay and the animation must agree on this.
- Final art: concept sheet (front/side/top) → hire a 3D artist using the placeholder as size/timing reference
  (recommended), or AI 3D generator + cleanup as the budget path (check commercial license; rig by hand because
  auto-riggers struggle with the oversized arm).

## 4. Multiplayer architecture

One netcode for every mode; only where the server runs changes.

```
Online:  Phone ──UDP (ENet)──> Match server (Godot headless, authoritative)
           └──HTTPS──> Backend (NestJS + Postgres + Redis) ──allocates──┘
LAN:     One phone hosts (server + player), others on the same Wi-Fi join directly
```

- **Server decides everything** at 30 ticks/s. Phones send inputs only (move vector, hook aim/fire).
- **Own movement predicted** on the phone; other heroes interpolated (~100 ms).
- **Hook hits decided only on the server.** The 0.3 s wind-up plays instantly on the phone and hides latency.
  Because every hit kills, hit fairness under lag is tested first (Phase 1).
- **LAN discovery:** host broadcasts on the local network; QR code / IP join as fallback.
  iOS needs the Local Network permission and Apple's multicast entitlement (request early).
  Android may need a multicast lock.
- **Backend (NestJS):** guest accounts (Sign in with Apple/Google later), private rooms by code, then matchmaking;
  starts Godot server processes and hands players a one-time ticket; stores results. Nakama is the alternative.

## 5. Phases

| Phase | What we build | Done when |
|---|---|---|
| **0. Setup** ✅ done (iOS needs Xcode 26) | Godot project, placeholder Gaff, greybox river map, joystick + hook button, local hook demo, phone builds | The sandbox runs on your phone |
| **1. Networked basics** 🟡 mostly done | Server-authoritative movement + hook; hero/skill definitions; LAN and online by IP (server on a small VPS) | Two phones hook each other on Wi-Fi and over the internet, and it feels fair at 150 ms simulated lag |
| **2. Full match** 🟡 mostly done | Teams, one-hit kills, respawn, score, gold + shop upgrades, LAN discovery, HUD | Full 3v3 LAN match from lobby to victory screen |
| **3. Online services** | NestJS backend, guest accounts, rooms by code, then quick match | Friends in different cities play via a code |
| **4. Final Gaff + feel** 🟡 started | Final model/animations, VFX, sound, haptics | The hook feels great to land |
| **5. Content** 🟡 started | River power-ups, items, bots, tutorial, progression, cosmetics, **second hero and map** | Ready for players outside your circle |
| **6. Launch** | TestFlight / Play testing, analytics, crash reports, store pages, privacy policy | Soft launch in 1–2 countries |

## 6. Risks

1. **Hook feel with lag** — the core of the game; Phase 1 tests it before anything else.
2. **Not enough players online for 3v3** — bots fill slots, smaller modes, private rooms.
3. **Apple's multicast entitlement for LAN discovery** — request early; QR/IP join as fallback.
4. **Trademarks** — original names/art only; check "Skills Wars" before the store listing.
5. **Costs** — Apple Developer $99/year, Google Play $25 once, servers start at one small VPS in one region.

## 7. Status log

**Phase 0 — done**
- Android debug build runs (tested on the emulator: renderer, touch, hook). iOS exports an Xcode project; building it
  requires Xcode 26, which requires macOS Tahoe 26.2+ (current Xcode) — also mandatory for App Store uploads.
- App ID `com.angelonicuesta.skillswars` (change before registering in the stores if needed). App icon from Gaff's face.

**Phase 1 — mostly done**
- Done: server-authoritative simulation (movement, hook, one-hit kills, ally rescue, respawn, score), hero/skill
  definitions as data, arena geometry read from the map scene, practice vs bots, host + join by address,
  dedicated server (`--server`), client-side prediction for your own hero, interpolation for everyone else,
  simulated lag (`--lag`), ping display, Linux server builds (x86_64 and ARM) tested inside Docker.
- Left: put the Linux server on a small VPS; play on two real phones at ~150 ms and tune feel; predict your own
  hook's flight locally if the delay feels bad; finger-friendly menu polish.

**Phase 2 — mostly done**
- Done: match rules as data (`match/default_rules.tres`: 3v3, first to 20 or 6 minutes, overtime on a tie, 3 s respawn,
  8 s between matches), victory/defeat screen and automatic next match, player names (saved) with name tags and a
  kill feed, gold (100 per kill + 5 per second) and a shop with 5 levels of Range, Speed, Size and Cooldown, bots
  that fill empty slots and step aside for players, games on the same Wi-Fi listed automatically in the menu.
- Left: a pre-match lobby if drop-in play feels too chaotic; tune gold, prices and upgrade strength in playtests;
  iOS needs Apple's multicast entitlement before Wi-Fi discovery works there (joining by address works without it).

**Phase 4 — started (game feel)**
- Done: impact burst + shockwave and screen shake on catches, sparks and clank when a hook hits a rock, splashes and
  ripples while bodies are dragged through the river, smoke puff on death, team-colored sparkles on respawn, running
  dust, floating "+100" gold, phone vibration (being hooked, hooking someone, buying), and generated placeholder
  sounds (throw, chain, clank, thwack, splash, poof, spawn, coin, kill ding, victory, defeat, UI click).
- Left: replace placeholder sounds with a professional pack, music, final Gaff art, own-hook prediction if real
  phones show the hook appearing late.

**Phase 5 — started (river power-ups)**
- Done: an orb floats down the river every 12 s (max 2). Hook it to reel it in: Shield (blocks the next enemy hook,
  15 s), Haste (+40% speed, 8 s), Gold bag (+150), Big Hook (next throw has double catch size). Bots go for orbs
  when no enemy is in range. Visuals: floating orbs with icons and rings, shield bubble with a pop, haste sparkle
  trail, glowing hand for a ready Big Hook, HUD icons for active effects. Tuning lives in `default_rules.tres`.
- Left: second hero, second map, tutorial, progression, cosmetics.
