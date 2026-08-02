# Private Blackbox Test Harness

This folder is a **local-only** harness for running Freegosy's save-sync logic
against a live RomM server ("blackbox": we only observe inputs and outputs —
the API responses — not the server internals).

Everything under `testing/data/` and `testing/config/` is git-ignored, so test
credentials, API keys, and exported dumps never reach the public repository.
`README.md` and `scripts/` are committed for reference.

## Layout

```
testing/
  README.md                 # this file
  config/                   # (git-ignored) RomM credentials + dumps
    .env                    # ROMM_URL + ROMM_API_KEY (see .env.example)
    .env.example            # committed template (no secrets)
  data/
    exports/                # (git-ignored) pulled save files, dumps
    summaries/              # (git-ignored) test run summaries
  scripts/                  # committed helper scripts
    blackbox.sh             # run the full round-trip suite
```

## Setup

1. Copy the template and fill in your instance:

   ```bash
   cp testing/config/.env.example testing/config/.env
   # edit testing/config/.env
   ```

2. Source it and confirm connectivity:

   ```bash
   set -a; . testing/config/.env; set +a
   curl -s "$ROMM_URL/api/heartbeat" -H "Authorization: Bearer $ROMM_API_KEY"
   ```

## What the harness verifies (blackbox)

Two harnesses live here:

### 1. HTTP round-trip (`save_sync_integration.dart`)

Talks to the **public RomM API only** (`/api/roms`, `/api/saves`,
`/api/saves/{id}/content`) and exercises the same endpoint sequence Freegosy
uses on push/pull. Per platform it:

1. picks the first game on the platform,
2. deletes any prior `freegosy` test saves,
3. pushes a marker-padded save file (`FREEGOSY_TEST_<SLUG>_<ts>`),
4. lists saves back and confirms the server stored it with the right size,
5. downloads the save again and byte-compares the round-trip,
6. cleans up all test saves afterwards.

### 2. Strategy blackbox (`strategy_blackbox_test.dart`)

Drives Freegosy's **real save strategies** end-to-end against the live server,
uploading every platform's selected saves to the fake `test_ps2_rom.iso`
(rom id 6418) on the ps2 platform. It:

1. builds a fake per-emulator save layout in a temp dir (portable exe + memcards,
   folder saves, `PARAM.SFO`, Wii title dirs, GC `Card A`, `0000000000000000`,
   `mlc01`, etc.),
2. wires the real strategies through `SaveSyncService` + a real `RommService`
   (API key from env), with a stub `DirectoryService`/`StrategyRegistry` so each
   slug resolves to the strategy under test,
3. calls `pushSaves()` (the full chain: `getSaveFiles()` → filter → bundle → upload),
4. verifies a new save landed on the server for rom 6418,
5. deletes all test saves afterwards.

This confirms the whole pipeline — emulator folder layout → file selection →
bundling → HTTP upload → server store — works for **every strategy**, not just
the HTTP layer. Currently covers: ps2, psx (per-game + shared memcard),
wii, gc, snes (RetroArch), gba (mGBA), psp (PPSSPP), ps3 (RPCS3), switch (Eden),
wiiu (Cemu), 3ds (Azahar). Xenia (xbox360) is Windows-only and skipped on
macOS/Linux.

## Running

HTTP round-trip across all supported platforms:

```bash
ROMM_URL=... ROMM_API_KEY=... dart run tool/integration_tests/save_sync_integration.dart
```

Strategy blackbox (drives the real save strategies; needs a Flutter test env):

```bash
ROMM_URL=... ROMM_API_KEY=... \
  flutter test tool/integration_tests/strategy_blackbox_test.dart
```

Or via the wrapper (reads `testing/config/.env`, writes a summary):

```bash
./testing/scripts/blackbox.sh
```

## Manual API probes

Quick one-liners against the configured instance:

```bash
set -a; . testing/config/.env; set +a
H="Authorization: Bearer $ROMM_API_KEY"

# list platforms + ids
curl -s "$ROMM_URL/api/platforms" -H "$H" | python3 -m json.tool

# find a game on a platform (ps2 = 6, psx = 14)
curl -s "$ROMM_URL/api/roms?platform_ids=6&limit=5" -H "$H" | python3 -m json.tool

# list saves for a rom
curl -s "$ROMM_URL/api/saves?rom_id=<ROM_ID>" -H "$H" | python3 -m json.tool

# push a save
curl -s -X POST "$ROMM_URL/api/saves?rom_id=<ROM_ID>&emulator=freegosy&slot=freegosy" \
  -H "$H" -F "saveFile=@save.ps2;filename=Mcd001.ps2"

# download a save's bytes
curl -s "$ROMM_URL/api/saves/<SAVE_ID>/content" -H "$H" -o save_download.ps2
```

## Notes on the environment used for development

The developer instance is a self-hosted RomM 5.0.0 at `romm.arbusville.duckdns.org`
with a read-only API key. Test ROM `test_ps2_rom.iso` (rom id `6418`) exists on
the `ps2` platform for PS2-specific probes. New test ROMs can be uploaded via
the chunked endpoint:

```bash
# start
curl -s -X POST "$ROMM_URL/api/roms/upload/start" -H "$H" \
  -H "x-upload-platform: 6" -H "x-upload-filename: test_ps2_rom.iso" \
  -H "x-upload-total-size: 9" -H "x-upload-total-chunks: 1"
# upload chunk
curl -s -X PUT "$ROMM_URL/api/roms/upload/<UPLOAD_ID>" -H "$H" \
  -H "x-chunk-index: 0" --data-binary @/tmp/test_ps2_rom.bin
# complete (a platform rescan registers it)
curl -s -X POST "$ROMM_URL/api/roms/upload/<UPLOAD_ID>/complete" -H "$H"
```
