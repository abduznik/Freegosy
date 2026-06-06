# RomM 4.9 Save Sync — Integration Research for Freegosy

> Status: 4.9.0-beta.1 is out (alpha.3 as of late May 2026). API is stable enough to build against.  
> Source: [RFC-0001](https://github.com/rommapp/romm/discussions/2199) · [PR #2917](https://github.com/rommapp/romm/pull/2917) · [4.9.0-alpha.3 release notes](https://github.com/rommapp/romm/releases/tag/4.9.0-alpha.3)

---

## 1. What Changed in RomM 4.9

RomM 4.9 adds **device-based save synchronization** — a first-class API for client apps to register themselves and keep saves in sync without rolling their own conflict detection.

### New concepts

| Concept | What it means |
|---|---|
| **Device** | A registered client (app, handheld, browser) with a persistent UUID |
| **Device sync record** | Tracks when that device last synced a given save file |
| `is_current` | Server-computed flag: `true` = device has the latest version |
| **Slot** | Named group of saves (e.g. "Main Playthrough", "Nuzlocke Run", "autosave") |
| **Autocleanup** | Server prunes old saves in a slot automatically after upload |
| **Play session tracking** | Client submits `start_time`/`end_time`/`duration_ms` per game session |

### What it does NOT cover

- **Save states** (`.state`, RetroArch `.state0` etc.) — these are core-specific and even version-specific. Explicitly out of scope.
- File-Transfer and Push-Pull modes (SSH/Syncthing) — defined in the RFC but not in the initial implementation.

---

## 2. New API Endpoints

All endpoints require standard auth (Bearer token / API key / Basic). New scopes: `devices.read`, `devices.write`.

### Device registration

```
POST /api/devices
```
```json
{
  "name": "Freegosy on Desktop",
  "platform": "windows",      // or "linux", "android", etc.
  "client": "freegosy",
  "client_version": "0.5.1",
  "hostname": "my-pc"
}
```
**Response:**
```json
{
  "device_id": "abc-123-uuid",
  "name": "Freegosy on Desktop",
  "created_at": "2026-06-06T12:00:00Z"
}
```
Store `device_id` persistently (SharedPreferences). Only register once per install.

**Conflict on re-registration:** Pass `allow_existing=true` to recover an existing device instead of creating a duplicate. Pass `reset_syncs=true` to clear all sync records (useful after reinstall). Pass `allow_duplicate=true` if you genuinely want a new parallel device.

```
GET /api/devices              → list all devices
GET /api/devices/{device_id}  → get device info
PUT /api/devices/{device_id}  → update name/sync_enabled
DELETE /api/devices/{device_id} → unregister
```

---

### Save upload (updated)

```
POST /api/saves?rom_id={id}&device_id={device_id}&slot={slot}&autocleanup=true&autocleanup_limit=10
```

Key new params:

| Param | Default | Notes |
|---|---|---|
| `device_id` | — | Enables sync tracking; required for conflict detection |
| `slot` | — | Groups saves; auto-tags filename with `[YYYY-MM-DD_HH-MM-SS]` |
| `autocleanup` | `false` | Prunes oldest saves in slot after upload |
| `autocleanup_limit` | `10` | Max saves to keep per slot |
| `overwrite` | `false` | Bypass conflict detection (force push) |

**409 Conflict response:**
```json
{
  "detail": {
    "error": "conflict",
    "message": "Save has been updated since last sync and will be overwritten",
    "save_id": 42,
    "current_save_time": "2026-06-06T14:00:00Z",
    "device_sync_time": "2026-06-05T10:00:00Z"
  }
}
```

---

### Save download (updated)

```
GET /api/saves/{id}/content?device_id={device_id}&optimistic=true
```
With `optimistic=true` (default), the server updates the device sync record automatically on download — no need to call `/downloaded` separately.

```
POST /api/saves/{id}/downloaded   → manual sync confirmation (non-optimistic)
POST /api/saves/{id}/track        → re-enable tracking for this save on this device  
POST /api/saves/{id}/untrack      → opt out of syncing a specific save
```

---

### Save list (updated)

```
GET /api/saves?rom_id={id}&device_id={device_id}&slot={slot}
```
Returns `device_syncs[]` array in each save object when `device_id` is provided:
```json
"device_syncs": [
  {
    "device_id": "abc-123-uuid",
    "device_name": "Freegosy on Desktop",
    "last_synced_at": "2026-06-05T10:00:00Z",
    "is_untracked": false,
    "is_current": false    // ← key flag: false = server has newer save
  }
]
```

---

### Save summary (new)

```
GET /api/saves/summary?rom_id={id}
```
```json
{
  "total_count": 6,
  "slots": [
    { "slot": null,              "count": 3, "latest": { ...SaveSchema... } },
    { "slot": "Main Playthrough","count": 2, "latest": { ...SaveSchema... } },
    { "slot": "autosave",        "count": 1, "latest": { ...SaveSchema... } }
  ]
}
```
Use this to build a slot picker in the game detail UI.

---

### Play session tracking (new in 4.9)

```
POST /api/play-sessions   (batch)
```
```json
[
  {
    "rom_id": 100,
    "device_id": "abc-123-uuid",
    "start_time": "2026-06-06T10:00:00Z",
    "end_time": "2026-06-06T11:30:00Z",
    "duration_ms": 5400000
  }
]
```
Submit at session end. `duration_ms` = actual screen-on time (may be less than end-start if device suspended mid-game).

---

## 3. SaveSchema Changes

The save object now has:

```json
{
  "id": 42,
  "rom_id": 100,
  "file_name": "pokemon_emerald [2026-06-06_14-00-00].sav",
  "file_name_no_tags": "pokemon_emerald",
  "file_name_no_ext": "pokemon_emerald [2026-06-06_14-00-00]",
  "file_extension": "sav",
  "download_path": "/api/saves/42/content",   // ← use this, not deprecated url field
  "slot": "Main Playthrough",
  "emulator": "freegosy",
  "device_syncs": [ ... ],
  "created_at": "...",
  "updated_at": "..."
}
```

Note: `download_path` is now the canonical download URL (replaces `download_path`/`url` ambiguity we currently work around).

---

## 4. Current Freegosy Save Sync — What We Have

Looking at `lib/core/save/save_sync_service.dart` and `lib/core/romm/romm_service.dart`:

### What we currently do

- `pushSaves()` — uploads a save file (or ZIP bundle) via `POST /api/saves` with `emulator=freegosy` and a timestamp slot string
- `pullSave()` — downloads latest save via `GET /api/saves`, then `GET /api/saves/{id}/content`
- Conflict detection — DIY: compare `updated_at` from remote vs our stored `last_pull` timestamp in SharedPreferences
- Hash cache — we store MD5 of last uploaded file to skip unchanged saves
- `pruneOldSaves()` — manually fetches + deletes old saves (keeps 5)
- No device registration, no `device_id`, no `is_current` flag

### What we can replace/improve with 4.9

| Current approach | 4.9 approach |
|---|---|
| DIY timestamp conflict detection in `pushSaves()` | Server does it; handle 409 response |
| Custom `last_pull` tracking in SharedPreferences | `is_current` flag from `device_syncs[]` |
| `pruneOldSaves()` manual delete loop | `autocleanup=true&autocleanup_limit=5` on upload |
| Single flat bucket of saves | Named slots (auto-save slot, manual slot, etc.) |
| No device identity | Register device once, pass `device_id` on every save op |
| Play time not tracked | Submit play sessions via new endpoint |

---

## 5. Integration Plan

### Step 1 — Device registration (one-time, on first launch / login)

Add to `RommService`:
```dart
Future<String?> registerDevice({
  required String name,
  required String platform,
  String clientVersion = '0.5.1',
  bool allowExisting = true,
}) async {
  final body = {
    'name': name,
    'platform': platform,
    'client': 'freegosy',
    'client_version': clientVersion,
    'hostname': await _getHostname(),
  };
  // POST /api/devices?allow_existing=true
  // Store returned device_id in SharedPreferences: 'romm_device_id'
}
```

Call this after successful login in the onboarding flow or `RommProvider` init.

---

### Step 2 — Pass `device_id` to all save operations

Update `uploadSave()` signature:
```dart
Future<bool> uploadSave(
  String gameId,
  io.File saveFile, {
  String? slot,
  String? deviceId,
  bool autocleanup = true,
  int autocleanupLimit = 5,
  bool overwrite = false,
  io.File? screenshotFile,
  String? overrideFilename,
})
```

Query params to add: `device_id`, `slot`, `autocleanup`, `autocleanup_limit`, `overwrite`.

Update `downloadSave()` / content fetch:
```
GET /api/saves/{id}/content?device_id={device_id}&optimistic=true
```

Update `getSavesList()`:
```
GET /api/saves?rom_id={id}&device_id={device_id}
```

---

### Step 3 — Replace DIY conflict detection with 409 handling

In `SaveSyncService.pushSaves()`, remove the current manual conflict check. Instead, catch HTTP 409 from `uploadSave()` and parse:
```dart
// In RommService.uploadSave():
if (response.statusCode == 409) {
  final detail = response.data['detail'];
  throw SaveConflictException(
    game: game,
    localTime: localSaveTime,
    cloudTime: DateTime.parse(detail['current_save_time']),
  );
}
```
The existing `SaveConflictException` class and `save_conflict_dialog.dart` can stay as-is.

---

### Step 4 — Replace `is_current` check before launch

Before launching a game, instead of comparing timestamps:
```dart
final saves = await rommService.getSavesWithDeviceSync(gameId, deviceId: deviceId);
final latest = saves.firstOrNull;
final isCurrent = latest?['device_syncs']
    ?.firstWhere((d) => d['device_id'] == deviceId, orElse: () => null)
    ?['is_current'] ?? false;

if (!isCurrent) {
  // Prompt user: server has newer save, pull before playing?
}
```

---

### Step 5 — Remove `pruneOldSaves()`, use autocleanup

Delete `pruneOldSaves()` from `RommService`. Instead, always upload with:
```
autocleanup=true&autocleanup_limit=5
```
The server handles cleanup atomically after each upload.

---

### Step 6 — Add save slots UI (optional, nice-to-have)

Add `GET /api/saves/summary` call in game detail screen to show slot picker. Users can have:
- `null` (legacy/unslotted saves — backward compat)
- `"autosave"` — autocleanup enabled
- `"manual"` — kept forever, explicit user saves

---

### Step 7 — Play session tracking

Add a `PlaySessionService` that:
1. Records `sessionStart = DateTime.now()` when a game launches
2. On game close, computes `duration_ms` (exclude suspended time if possible)
3. `POST /api/play-sessions` with the batch

Hook into `library_actions.dart` where game launch/return happens.

---

## 6. Required `romm_models.dart` Changes

Add `DeviceSync` model:
```dart
class DeviceSync {
  final String deviceId;
  final String? deviceName;
  final DateTime? lastSyncedAt;
  final bool isUntracked;
  final bool isCurrent;

  DeviceSync.fromJson(Map<String, dynamic> json) : ...
}
```

Add `slot` and `deviceSyncs` to `SaveFile`:
```dart
class SaveFile {
  // existing fields...
  final String? slot;
  final List<DeviceSync> deviceSyncs;
}
```

---

## 7. SharedPreferences Keys to Add

| Key | Value |
|---|---|
| `romm_device_id` | UUID string from device registration |

Remove (no longer needed after 4.9):
| Key | Was used for |
|---|---|
| `last_pull_{gameId}` | DIY pull timestamp tracking → replaced by `is_current` |

Keep (still useful):
| Key | Reason |
|---|---|
| `last_hash_{gameId}_{filename}` | Local deduplication before hitting network |

---

## 8. Version Compatibility

- These endpoints **require RomM 4.9+**. The `device_id` param silently has no effect on older versions, but 409 conflict responses won't come back either, so fallback is graceful.
- Check RomM version via `/api/heartbeat` or `/api/version` on connect and conditionally enable device-sync features.
- Existing save uploads without `device_id` still work — backward compatible.

---

## 9. Files to Modify

| File | Changes needed |
|---|---|
| `lib/core/romm/romm_service.dart` | `registerDevice()`, update `uploadSave()`, `getSavesList()`, `downloadSave()` signatures; add `getSaveSummary()`; remove `pruneOldSaves()` |
| `lib/core/romm/romm_models.dart` | Add `DeviceSync`, update `SaveFile` with `slot`/`deviceSyncs` |
| `lib/core/save/save_sync_service.dart` | Remove DIY conflict check, remove `pruneOldSaves()` call, pass `deviceId` through |
| `lib/providers/romm_provider.dart` | Call `registerDevice()` on login/init, expose `deviceId` |
| `lib/ui/screens/game_detail_screen.dart` | Add `is_current` check before launch, slot picker UI |
| `lib/ui/screens/library_actions.dart` | Hook play session tracking on game launch/return |
| New: `lib/core/romm/play_session_service.dart` | Session start/end tracking + batch submit |

---

## Sources

- [RFC-0001: Save Synchronization System](https://github.com/rommapp/romm/discussions/2199)
- [PR #2917: Add device-based save synchronization](https://github.com/rommapp/romm/pull/2917)
- [RomM 4.9.0-alpha.3 Release Notes](https://newreleases.io/project/github/rommapp/romm/release/4.9.0-alpha.3)
- [Grout Save Sync Guide](https://grout.romm.app/usage/save-sync/)
