# Save-state sync (PCSX2)

Freegosy can sync **PCSX2 save states** between your machines through your RomM
server. Save states are the emulator snapshots you make with the quick-save keys
(`SERIAL (CRC).01.p2s` and so on). They are **not** the in-game memory-card
saves: those keep syncing through RomM's saves API exactly as before, and the
two never mix.

This page describes the feature and how it behaves.

## At a glance

| | |
|---|---|
| Emulators | PCSX2 only for now. Every other emulator shows the toggle disabled with "Not supported yet". |
| Default | **Off.** Turn it on per emulator. |
| Where | Settings → Emulators → PCSX2 → "Sync save states"; "Sync Save States" button on a game's page. |
| Resume | **Resume Game ▾** on the game page (see [Resume Game](#resume-game)). |
| RomM API | `/api/states` (separate from `/api/saves`). Works on any RomM that has the states API. |
| Privacy | States and their screenshots belong to your RomM user; Freegosy never makes them public. Checked on a real RomM: another user does not see them, and they do not appear in the game's screenshot gallery. |

## Using it

1. Open **Settings → Emulators** and switch on **Sync save states** for PCSX2.
2. Play as usual. Before the game launches, Freegosy downloads states that are
   missing or newer on RomM. After you quit, it uploads the states you changed
   during that session.
3. To sync without launching, open the game's page and press
   **Sync Save States**. It pulls, then pushes, and asks you about any conflict.

Both machines should run the **same PCSX2 build**. A save state is tied to the
emulator version, and Freegosy does not check or tag it. A state that PCSX2 can't
load simply fails to load inside PCSX2; nothing is corrupted.

## What is synced

- Files in the PCSX2 states folder named `SERIAL (CRC8).NN.p2s` (numbered slots)
  and `SERIAL (CRC8).resume.p2s` (the resume slot), for **the game being
  launched** only. The serial is read from the ROM.
- Ignored: `.p2s.backup` files, states of other games, and files smaller than
  100 bytes (treated as aborted writes).
- The file name on RomM is the same as the local file name.

States folder: `<PCSX2 folder>/sstates` for a portable install (the folder that
contains `memcards`), `~/.config/PCSX2/sstates` on a standard Linux install,
`~/Library/Application Support/PCSX2/sstates` on macOS, and `<root parent>/states`
for EmuDeck layouts. It uses the same folder detection as memory-card sync.

## When it runs

| Moment | What happens |
|---|---|
| Before launch | Awaited, with a "Checking save states..." toast. Skipped while RomM is offline. The server list call is bounded to 20 s, a download gives up after 30 s without receiving data (a slow download that keeps making progress finishes), and the pull stops at the first failed download, so a stalling server costs about that long at most. A failure never blocks the launch. |
| After the emulator exits | Uploads the states modified during the session. A failure never breaks the backup or play-session report that follow. |
| **Sync Save States** button | Pull, resolve conflicts, push, resolve conflicts. Fails fast with "RomM offline" when RomM is offline, and says "Sync already running" when another sync for the game is still going (for example the push after you quit). |
| Headless CLI | Push after exit only (no dialogs, so conflicts stay flagged until you resolve them in the app). |

Only one sync operation runs per game at a time. If another is already running
for that game, the new one does nothing (the **Sync Save States** button tells
you so instead of reporting a sync that did not happen; the pre-launch pull just
carries on and launches).

## Resume Game

An earlier opt-in switch, "Auto-load resume state on launch", booted PCSX2 straight
into the game's resume state on every launch. It was removed before it was
released: a resume state made by a different PCSX2 version crashed PCSX2 at boot,
and because the switch applied to every launch, the game could not be started
again until the switch was turned off. **Resume Game** replaces it with a
choice made for one launch at a time, and works for any emulator that
implements the contract below (PCSX2 today).

**The buttons.** When a game has at least one save state, its page shows
**Resume Game ▾** above **Play Game (fresh start)**. **Play Game** always
starts the game fresh, whether or not states exist.

**What Resume loads.** Pressing **Resume Game** loads the newest state. The
**▾** (or **X** on a controller) opens a centred dialog — not anchored to the
button — listing every state: when it was saved, the emulator version it was
made with, where it is (`this PC`, `RomM`, or `newer on RomM`), and a ⚠ line
when its version differs from the installed one. **B** on a controller closes
the dialog.

**Sources.** States on this PC are always listed. States on RomM are added
too when **Sync save states** is on for that emulator and RomM is reachable:
local states show first, and RomM's are merged in a moment later once the
server answers.

**The emulator rule.** Resume starts whichever emulator made the state: from
the state's own folder, from RomM's `emulator` tag, or — when neither
applies — the one emulator whose file-naming matches. It never asks which
emulator to use. A state whose emulator can't be determined isn't listed.
States uploaded before this feature all carry `emulator=freegosy`, which
isn't a real emulator id, so those fall back to the file-naming match too.

**Multi-disc games.** A state belongs to one disc (its serial), so the list
shows the states of every disc in the game's folder, and Resume boots the disc
that state was made with, whichever disc you'd pick for a fresh start.

**One launch at a time.** While a Play or Resume started from the game page is
still getting ready (e.g. downloading the state), pressing Resume, Play, a
slot or **X** again does nothing.

**Before launch:** the chosen state is downloaded first. Then:
- If it isn't on disk, nothing launches and the message says where it was
  expected: `Couldn't get <slot> from RomM. Nothing was started.` for a state
  that was only on RomM or newer there, `Couldn't find <slot> on this PC.
  Nothing was started.` for a local state that has since gone, and `Resume
  isn't available right now. Nothing was started.` when Freegosy's resume
  support isn't ready yet.
- If a newer RomM copy was expected but the download didn't bring it: the
  older local copy loads instead, and the "Launching" toast says `Couldn't
  update <slot> from RomM. Loading the copy on this PC.` A state you just
  settled in the conflict dialog never gets this notice: the copy on disk is
  the one you chose.
- If the state's version turns out different from the installed emulator and
  the list didn't already show ⚠ for it (e.g. the emulator was updated since
  the list was built): the **Load anyway / Cancel** prompt appears first.
  Cancel starts nothing.

A state that was synced and then deleted on this PC isn't listed even though
RomM still has it: the sync deliberately doesn't bring deleted states back.
When a RomM server is set up and Freegosy keeps a handle on the emulator it
started (it then syncs saves after exit), the list refreshes as soon as the
emulator exits, and again once the post-exit sync is done. Otherwise it
refreshes after **Sync Save States** or the next time the game's page opens.

**Versions.** Read from the state itself (PCSX2: the `.p2s` header). The
installed version comes from `pcsx2-qt.exe` on Windows only; Linux, AppImage,
Flatpak and macOS builds have no version reader, so there's no warning there.
A nightly or self-built emulator writes versions like `v2.3.72-12-gabcdef`;
when the numbers match the installed release (`2.3.72.0`) the build can't be
told apart from it, so there's no ⚠ and no prompt. Different numbers still
warn.

## Conflicts and safety

Freegosy keeps a small record per state file (server id, hash of the bytes at the
last sync, and RomM's `updated_at` used only as a "did it change" marker). From
that it decides what to do:

| Situation | Result |
|---|---|
| State only on RomM | Downloaded (first sync on a new machine). |
| You deleted it locally, RomM still has it | **Not** re-downloaded. |
| Changed on RomM, unchanged locally | Downloaded; the old local file is backed up first. |
| Changed locally, unchanged on RomM | Uploaded after you exit. |
| Same name on both sides, never synced, different bytes | **Conflict.** |
| Changed on both sides | **Conflict.** |

A **conflict** is never resolved silently. You get a dialog with
*Use Local Version* or *Use Cloud Version*. Cancel keeps your local file and
leaves the slot flagged; a flagged slot is skipped by uploads until you resolve
it. A conflict found after you quit is reported in an orange warning toast that
stays on screen until you dismiss it, with a **Resolve** button that runs the
same sync and shows the dialog; **Sync Save States** on the game page and the
next launch show the dialog too. If the server copy of a flagged slot has been
removed, the local state is uploaded again: there is nothing left to conflict
with.

Safety rules that always apply:

- A local state is only ever replaced through a temp file + rename, and only
  after a `.bak` copy exists (`.bak`, `.bak1`, `.bak2` rotate beside the state, so
  expect up to a few extra copies per slot). If the backup can't be made, the
  state is left untouched.
- Downloads must be non-trivial and start with the zip header PCSX2 states use.
- "Keep local" validates the local file before uploading, so a truncated state
  can never overwrite a good copy on RomM.
- Server-supplied names are checked to be plain file names (no path separators,
  `.` or `..`).

## Known limitations

- PCSX2 only; other emulators can opt in later.
- Deleting a state does not delete it on RomM, and deletes are not propagated
  between machines.
- One RomM account per Freegosy install. After switching accounts, states you had
  already synced can be downloaded again or show up as a conflict once, because
  the new account has its own copies.
- Older cloud saves that still contain states are now ignored when restored:
  states sync only through this feature.
- States are typically tens of MB, so the first sync on a new machine can take a
  while.

## Troubleshooting

- **The switch is greyed out** — the emulator doesn't support state sync yet.
- **Nothing syncs** — check the toggle is on, RomM is reachable, and that the
  game's serial can be read (a renamed ROM works; an unreadable disc image does
  not). The next entry shows how to see what state sync actually did.
- **How do I tell what state sync did?** — open the log: **Settings**, in the
  **Storage** card under **Troubleshooting**, press **View Logs** (the **System
  Logs** window). Leave the filter on **ALL** (the **ERROR** filter only shows
  the failure lines). State sync lines start with `[StateSync]`; Resume Game
  lines start with `[Resume]`, for example:

  ```
  [Resume] resume Ico: Slot 1 SCUS-97113 (A1B2C3D4).01.p2s (emulator pcsx2, where both)
  [Resume] version v2.8.2 vs installed 2.8.2.0: ok
  [Resume] SCUS-97113 (A1B2C3D4).01.p2s is stale: newer RomM copy did not arrive, loading the local copy
  [Resume] will load C:\PCSX2\sstates\SCUS-97113 (A1B2C3D4).01.p2s
  ```

  Select the text to copy it. The log is kept in memory
  only: the last 500 lines since Freegosy started (the trash-sweep icon with the
  tooltip **Clear Logs** empties it), so an older sync may have scrolled out. IP
  addresses are masked. The same lines also print to the console in a debug run.
  The window prefixes each line with the time, `[HH:MM:SS]`. A normal launch and
  exit looks like this (without the time prefix):

  ```
  [StateSync] pull Ico (rom 42, emulator pcsx2): states folder C:\PCSX2\sstates
  [StateSync] pull: RomM lists 1 state(s), 1 match this game
  [StateSync] downloaded SCUS-97113 (A1B2C3D4).01.p2s
  [StateSync] pull done: downloaded=1 restamped=0 conflicts=0
  [StateSync] post-exit push for Ico (emulator pcsx2)
  [StateSync] push Ico (rom 42): 2 of 2 local state(s) eligible (modified since 2026-01-01T20:00:00.000, at least 100 bytes)
  [StateSync] unchanged SCUS-97113 (A1B2C3D4).01.p2s
  [StateSync] uploaded SCUS-97113 (A1B2C3D4).resume.p2s (POST, id 2)
  [StateSync] push done: uploaded=1 conflicts=0
  ```

  A state is only counted as eligible for upload when it was modified since the
  session started and is at least 100 bytes. Per state file you also see
  `linked` (same bytes on both sides), `kept local` (changed here, uploaded
  after exit) and `conflict`. `restamped` means RomM changed a state's
  `updated_at` (or id) but the bytes are the same, so nothing was written. It
  is normal after a rescan on RomM; if it shows up after every upload of your
  own, RomM's upload response and its listing disagree on `updated_at`. If
  nothing ran, the line says why:
  - `not running for <game>: <reason>` at launch or on a manual sync, where the
    reason is `state sync is off for 'pcsx2': switch it on in Settings >
    Emulators` (the toggle is off) or `no state-sync support for emulator
    '...'` (the emulator has none). A pull or push that is started anyway logs
    the same reason as `<game>: <reason>`.
  - `<game>: cannot identify the game — skipping` (the serial could not be read),
    or `cannot set up state sync for <game>: ...` (the states folder could not
    be found).
  - `RomM is offline — skipping the pre-launch state pull` at launch, or
    `manual sync skipped for <game>: RomM is offline` for Sync Save States.
  - `push: nothing to upload (no matching state of at least 100 bytes was
    modified this session)`.
  - `post-exit push skipped: state sync service not available` (no RomM
    connection was set up).
- **A conflict keeps coming back** — you cancelled it. Press **Sync Save States**
  and choose a side.
- **A state won't load in PCSX2** — the two machines are on different PCSX2
  versions.
- **No Resume button** — the game has no state of at least 100 bytes that the
  emulator's naming matches; or the emulator can't load a state on launch; or
  the state's emulator can't be determined.

## For contributors

- Code: `lib/core/save/state_sync_service.dart` (pull, push, resolve),
  `state_sync_capable.dart` (what an emulator provides), `state_sync_record.dart`
  (records), `RommService` states client in `lib/core/romm/`, and Resume Game
  itself in `lib/core/save/resume_service.dart`, `lib/providers/resume_provider.dart`
  and `lib/ui/widgets/game_detail/` (split button, slot list, version dialog).
- To add an emulator: implement the `StateSyncCapable` mixin on its save
  strategy (`stateDirectory`, `stateFileMatcher`, optionally
  `looksLikeValidState`) and return `true` from
  `EmulatorStrategy.supportsStateSync`. A unit test fails if the two disagree.
- To add Resume Game for an emulator: an `EmulatorStrategy` returns `true`
  from `supportsStateLoadOnLaunch` and the command-line arguments that load a
  state from `stateLoadArgs` (PCSX2: `-statefile <path>`); optionally
  implement `installedVersion()` so mismatched-version warnings work. On the
  `StateSyncCapable` save strategy, `slotOf`, `describeState` and
  `stateScreenshot` are all optional (each has a safe default) but describe
  the slot label, the emulator version and a thumbnail respectively.
  `GameLaunchService.launch(..., loadStatePath: ...)` passes `stateLoadArgs`
  to the base `launchWithExtraArgs` / `launchWithHandleAndExtraArgs` methods
  for that launch only; nothing is stored on the shared strategy (launches of
  the same emulator can overlap). Do not override `launch` / `launchWithHandle`
  on such an emulator in a way that skips the base implementation; override
  the `...ExtraArgs` variants instead. A unit test checks that every such
  emulator has a `StateSyncCapable` save strategy.
- `ResumeService` itself must stay emulator-agnostic: it only calls through
  `EmulatorStrategy` and `StateSyncCapable`, never anything PCSX2-specific.
  Its tests exercise this against a made-up "fakeemu" emulator
  (`test/helpers/fake_state_emulator.dart`), not PCSX2, to prove it.
- State uploads now send `emulator=<emulatorId>` (the real emulator id, not
  the generic `freegosy` client tag used elsewhere) and, when the emulator
  provides one, the state's screenshot as `screenshotFile`.
- Tests: `test/unit/state_sync_*`, with an in-memory fake RomM in
  `test/helpers/fake_romm_states_api.dart`. `test/mock_romm_server.py` also
  serves `/api/states` for manual runs.
- Verified by hand on a real RomM and PCSX2:
  - a two-machine round trip in both directions (a state made on one PC is
    synced down and continued from on the other, and back again), which also
    shows RomM accepts the `.p2s` name and size;
  - after an upload (a `PUT` on exit), the next launch's pull reports the state
    as `unchanged` with `restamped=0`, so RomM's `updated_at` in the upload
    response matches its later listing;
  - the conflict flow: the persistent warning toast after exit, its **Resolve**
    button, the dialog, and both **Use Local Version** and **Use Cloud
    Version**;
  - an offline launch: with RomM unreachable (502 through a reverse proxy) the
    launch skipped the pre-launch state pull immediately and the game started;
  - Resume Game: a new upload is listed by RomM with `"emulator": "pcsx2"`; its
    screenshot is stored and shows as the slot's thumbnail on another PC; a
    second RomM user does not see the state's screenshot, and it does not
    appear in the game's screenshot gallery or header image; a PC with no
    local states lists the RomM state and resumes from it; a state made with
    an older PCSX2 asks **Load anyway / Cancel**, and Cancel starts nothing.
- Not yet verified against a real RomM: whether re-POSTing an existing file name
  replaces it (Freegosy does not rely on it); a launch against a RomM that
  is up but not answering (it should be delayed by no more than the ~20 s list
  timeout plus one 30 s download stall); and resuming a multi-disc or cue/bin
  game on real hardware.

## Possible follow-ups

- Headless CLI `--resume`: the `launch` command currently always starts
  fresh; a flag to resume the newest (or a named) state would bring Resume
  Game to scripted/headless launches too.
- Other emulators (DuckStation, RetroArch, PPSSPP, ares, Dolphin).
- Deleting states on RomM and propagating deletes.
