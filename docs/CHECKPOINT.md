# 002-obby — Build Checkpoint (2026-11-15)

## Status: playable v0.2.0, 16/16 levels (4 worlds), published to cykgames/002-obby

## v0.2.0 — World 4 VOLCANO (2026-11-15)

- Content expansion: 12 -> 16 levels, 3 -> 4 worlds. New VOLCANO theme
  (dark basalt terrain, glowing lava-red sky) + 4 levels: EMBER HOP (par 70),
  MAGMA RUN (75), CRUMBLE PEAK (80), ERUPTION (90). Data-only addition to
  LevelGen LEVELS/THEMES; no physics/engine changes.
- Game.gd LEVEL_COUNT 16 / WORLD_COUNT 4; LevelSelect 4th world name/color,
  subtitle now dynamic (WORLD_COUNT / LEVEL_COUNT / LEVEL_COUNT*3).
- Headless regression build/regression5.log: 16/16 FINAL, 0 falls every level,
  ALL_LEVELS_DONE, no errors. World 4: EMBER HOP / CRUMBLE PEAK 3-star,
  MAGMA RUN / ERUPTION 2-star (bot coin-skip on mover/bounce, same as worlds 1-3).
- On-device A54 (USB): install Success; select shows 4 worlds / 16 levels /
  STARS x/48; VOLCANO theme renders (basalt + lava + red sky); EMBER HOP plays
  (TIME running, no crash); sequential unlock verified via a temporary save
  (original save restored afterward). Shots: docs/screenshots/level_select.png
  (4 worlds), volcano_gameplay.png.
- APK 31.3 MB arm64 debug-signed; release v0.2.0.
- A57 gameplay still pending owner unlock (device offline this session).

## What was built

- New repo `cykgames/002-obby` via `cykgames-org/scripts/new_game.py`
  (worked first try; local repo pre-initialized with git identity so the
  scaffold commit succeeded).
- Core reused from 001-parkour (read-only copy, source repo untouched):
  Joystick (anchored disc, full Vector2, 1.5x grab radius), JumpButton
  (1.5x hit radius), Audio (procedural wav pool + BGM), Coin, HUD layout,
  CameraRig (trauma shake), export preset (package `com.cykagent.obby`).
- New gameplay: omnidirectional camera-relative movement (joystick x AND y),
  double jump (coyote + buffer kept), ice friction, bounce pads, checkpoint
  respawn by grounded proximity (generalizes the W7 `checkpoint_behind` fix
  to arbitrary 2D paths — only checkpoints actually stood on are used).
- `LevelGen.gd`: data-driven LEVELS table (12 levels, 3 worlds x 4), cursor
  path builder with 9 step types; chunked vertex-color terrain (parkour
  proven), AnimatableBody3D movers/spinners, Area3D lava, vanish blocks with
  staggered solid/ghost cycle, per-world themes.
- `LevelSelect.tscn/gd`: 3 world rows x 4 buttons, stars, sequential unlock,
  total-star counter; `Game.gd` autoload persists `user://progress.json`.
- Stars: clear=1, all coins=+1, under par=+1 (spec-exact).
- Headless waypoint bot in Player.gd for regression (edge-ray jump, predicted
  landing double-jump gate, vanish-block wait, stuck recovery).

## Verification evidence

- Headless unit: `JOYSTICK_TEST_PASS` (tools/test_joystick.tscn).
- Headless regression (build/regression4.log, `--fixed-fps 60`):
  12/12 FINAL, 0 falls on every level, 7 levels 3-star (all coins + par),
  `ALL_LEVELS_DONE`, no script errors.
- APK: `--export-debug` (release keystore absent; debug keystore auto),
  28.4 MB, arm64-v8a, `install -r` Success.
- On-device (A54 USB; A57 was behind a secure lockscreen — see below):
  - Level select renders, 1-1 unlocked, others LOCKED.
  - Scripted tap run (tools/obby_play.py): L1 cleared in 7.2s, FALLS 0,
    COIN 4/6 -> LEVEL CLEAR! **- + NEW RECORD, NEXT LEVEL/RESTART/LEVELS,
    joystick/J hidden (docs/screenshots/level_clear.png).
  - Checkpoint: flag turns green on reach; deliberate fall respawns at that
    checkpoint, not the start (docs/screenshots/gameplay_checkpoint.png).
  - Double jump: second Space in mid-air lifts the character above the flag
    pole (~3m) (docs/screenshots/double_jump.png).
  - Persistence: after force-stop + relaunch, select shows STARS 2/36,
    1-1 **- , 1-2 unlocked; `progress.json` = {"0":{"coins":4,"stars":2,"time":7.2}}.

## Key decisions / ruled-out alternatives

- **Assets**: full Kenney Platformer Kit download endpoint 404s
  (kenney.nl/download-link), Quaternius itch download is JS/CSRF-gated
  (token page returns HTML, no direct zip). Used the CC0 models from Kenney
  Starter Kit 3D Platformer GitHub repo instead (character with idle/walk/jump
  animations + cloud/grass decorations). Full-kit GridMap terrain and
  TrenchBroom/FuncGodot brush pipeline deferred to the level-mass-production
  phase; terrain stays procedural voxel for physics reliability.
- **glb textures**: copied `.import` files pointed at the starter kit's
  original `res://models/...` paths -> models rendered white. Fix: delete
  stale `.import`, re-import (source_file now `res://assets/...`), copy
  `Textures/colormap.png` alongside the glbs.
- **On-device jump input**: adb `input motionevent` is single-pointer (id 0);
  tapping J while holding the stick corrupts the stick stream (character
  stops / veers). Fix: jump via `input keyevent 62` (Space) — separate input
  stream, same "jump" action. Documented in tools/obby_play.py.
- **Device**: task targeted A57; A57 WiFi ADB reconnected and APK installed
  Success, but the phone is behind a secure lockscreen (mDreamingLockscreen=
  true, mInputRestricted=true; swipe/MENU cannot dismiss) — needs the owner
  to unlock. Fell back to A54 (USB, awake, unlocked) for all gameplay
  verification. Re-run `tools/obby_play.py full` on A57 once unlocked.
- **Bot coins**: first regression missed coins near pad edges (bot double-
  jumped every gap and flew over them). Fixed by (a) coins mid-pad, (b) bot
  double-jumps only when neither below nor 0.35s-ahead predicted landing has
  floor. 7/12 levels now 3-star headless; remaining 2-star levels are bot
  trajectory skips on bounce/spinner/mover sections (mechanics work, a human
  can collect all coins).

## Open items / next steps

- A57 gameplay screenshots pending owner unlock (install already done).
- Full Kenney Platformer Kit / Quaternius character when downloads become
  accessible (manual browser download); GridMap + TrenchBroom for mass
  level production.
- Release keystore for signed release builds (currently debug-signed).
- Difficulty tuning from human play feedback (par times are generous).

## Reproduce

```
godot --headless --path . --import
godot --headless --path . res://tools/test_joystick.tscn
godot --headless --fixed-fps 60 --path . res://Main.tscn
godot --headless --path . --export-debug "Android" build/002-obby.apk
set OBBY_ADB_SERIAL=<serial>&& python tools/obby_play.py full
```

## Author credit + handoff docs (2026-11-15, docs pass by cykbot1)

- Game author is **cykbot9** (the cykgames catalog lists cykbot9 for
  001/002). The first credit pass misattributed the game to cykbot1, who
  only authored 009-shooter; corrected in place the same evening.
- In-game: "by cykbot9 · cykgames #002" on level select (LevelSelect.gd).
  project.godot description: author + corrected 16 levels / 4 worlds.
- README: author line, design inspiration, Handoff/debugging section
  (entry points, data-driven levels, tests, known issues, privacy rule).
- Verify: `build/verify_author_joy.log` = JOYSTICK_TEST_PASS;
  `build/verify_author_reg.log` = 16/16 FINAL, 0 falls, ALL_LEVELS_DONE
  (2-star levels = known bot coin-skip, unchanged). Re-run after the
  attribution fix.
- Released v0.2.0 APK predates the credit; rebuild + new release pending
  owner consent.
