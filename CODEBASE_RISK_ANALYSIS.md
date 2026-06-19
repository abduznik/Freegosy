# Freegosy Codebase Risk Analysis

**Date:** 2026-06-19  
**Focus:** Identify failure modes, edge cases, and architectural risks

---

## Critical Areas at Risk

### 1. 🔴 Save Sync Pipeline (HIGHEST RISK)

**Current Behavior:** Issues #28 and #42 suggest complete failure

**Architecture:**
```
pullSave(game) / pushSaves(game)
  ├─ fetchCapabilities() [RomM API call]
  ├─ route to _devicePullSave/_devicePushSaves (RomM 4.9+)
  │  or _legacyPullSave/_legacyPushSaves (older)
  ├─ getStrategyForSlug(platformSlug)
  │  └─ Fetch game's SaveStrategy (emulator-specific)
  ├─ strategy.getSaveFilesWithScreenshots()
  │  └─ Scan emulator's save directory
  ├─ Download/upload via RomM API
  └─ Error handling???
```

**Identified Risks:**

#### 1.1: Async State Management
- `fetchCapabilities()` called fresh each time
- No caching → N RomM API calls per operation
- If RomM is slow/offline → operations hang
- No timeout handling visible

**Code Pattern (save_sync_service.dart:252-258):**
```dart
Future<bool> pushSaves(Game game, String romPath, ...) async {
  final caps = await _rommService.fetchCapabilities();  // BLOCKING
  if (caps.hasDeviceSaveSync) {
    return _devicePushSaves(...);  // Routes to heavy lifting
  }
  return _legacyPushSaves(...);
}
```

**Risk:** If `fetchCapabilities()` times out, entire save operation blocked

#### 1.2: Strategy Selection Logic
- `getStrategyForSlug(platformSlug)` has complex fallback chain
- If `platformSlug` is null → defaults by string matching
- Can return null if platform not recognized
- No error logging when strategy is null

**Code Pattern (save_sync_service.dart:106-126):**
```dart
SaveStrategy? getStrategyForSlug(String? platformSlug) {
  if (platformSlug != null) {
    final preferredId = _strategyRegistry.getPreferredEmulatorId(platformSlug);
    if (preferredId != null) {
      final id = preferredId.toLowerCase();
      // ... massive if-if-if chain ...
    }
  }
  switch (platformSlug?.toLowerCase()) {
    case 'nds':
      return _melonds;  // Hardcoded!
    // ...
  }
  // Falls through to null if not found
}
```

**Risk:** Returns null silently, then callers check `if (strategy == null) return false` without logging why

#### 1.3: Strategy Path Detection (Per-Emulator)
**Files:**
- `/lib/core/save/strategies/melonds_save_strategy.dart` — DS saves
- `/lib/core/save/strategies/retroarch_save_strategy.dart` — multi-platform
- `/lib/core/save/strategies/*.dart` — 14 strategies total

**Risk Pattern:**
```dart
// Example from melonds_save_strategy.dart
Future<Map<io.File, io.File?>> getSaveFilesWithScreenshots(...) async {
  final saveDir = _directoryService.getEmulatorAppSupportDirectory(
    'melonds',
    saveData?['emulator_id'],
  );
  // ...
  return Map.fromEntries(saves.map((s) => MapEntry(s, null)));
}
```

**Risks:**
1. Hardcoded emulator name → if user renamed their MelonDS install, path breaks
2. `DirectoryService.getEmulatorAppSupportDirectory()` may return wrong path
3. On Linux: searches `~/.config/melonds/` → but MelonDS might be in custom location
4. No validation that returned directory actually exists
5. No error if no saves found (silent failure)

#### 1.4: File Upload/Download
**Problem:** No visibility into actual RomM API calls

**Suspects:**
- `_rommService.uploadGameSave(...)` — does it handle 4xx/5xx errors?
- File encoding: binary vs text? Compression?
- Path normalization on RomM side?

#### 1.5: Temp File Cleanup
**Code (save_sync_service.dart:347-349):**
```dart
final tempDir = await _directoryService.getEmulatorDirectory('temp');
if (!await io.Directory(tempDir).exists()) {
  await io.Directory(tempDir).create(recursive: true);
  // ... zip files created here ...
}
```

**Risk:** Temp files created but cleanup missing?
- No `.delete()` call after upload/download
- Accumulates temp files over time
- Users can manually delete but should be automatic

---

### 2. 🟠 Emulator Launch Process (HIGH RISK)

**Problem:** #42 reports "MelonDS locks up on launch"

**Architecture:**
```
launchGame(game, romPath, emulatorId, exePath)
  ├─ Call emulator strategy's launch() method
  ├─ Process.start(exePath, [romPath, ...], detached: true)
  └─ Poll for process exit? Monitor? Nothing?
```

**Identified Risks:**

#### 2.1: Process Management
- `Process.start(..., detached: true)` fires and forgets
- No handle to monitor exit
- No timeout if emulator hangs
- What happens if emulator crashes?

**Code Pattern (native_linux_strategy.dart:53-67):**
```dart
Future<void> launch(Game game, String romPath, String emulatorId, String exePath, {List<String> args = const []}) async {
  if (exePath.startsWith('flatpak ')) {
    final parts = exePath.split(' ');
    await io.Process.start(
      parts.first,
      [...parts.sublist(1), ...args, romPath],
      mode: io.ProcessStartMode.detached,  // ← FIRE AND FORGET
    );
  }
}
```

**Risk:** No way to know if emulator started successfully or hung

#### 2.2: MelonDS Specific Issue
- Issue #42: "MelonDS locks up each time"
- What's different about MelonDS vs other emulators?

**Questions:**
1. Is it a MelonDS version issue?
2. Are arguments incorrect?
3. Does save restore logic block launch?
4. Is it a Wii U (Cemu) issue vs DS (MelonDS) issue?

#### 2.3: Save Restoration Before Launch
**Flow:**
```
launchGame(game, romPath)
  ├─ Pull save from RomM?
  ├─ Extract to emulator save dir
  └─ Launch emulator
```

**Risk:** If save restoration hangs, launch hangs
- `pullSave()` can block (see #1.1)
- No timeout on pull operation
- No fallback if pull fails

---

### 3. 🟠 Linux Path Detection (MEDIUM RISK)

**Problem:** #43 (now fixed) was about AppImage detection

**Still At Risk:**

#### 3.1: Environment Variable Assumptions
- Assumes `$HOME` is set
- On containerized systems (Docker), might be weird
- On Steam Deck, HOME=/home/deck

**Code Pattern (native_linux_strategy.dart:43):**
```dart
final home = io.Platform.environment['HOME'] ?? '';
```

**Risk:** Empty string if HOME unset → paths become `/Applications/`

#### 3.2: Directory Traversal
- New AppImage search uses `dir.list().toList()` (all files at once)
- On slow USB drives → could timeout
- No limit on recursion depth

#### 3.3: Case Sensitivity
- Linux filesystems case-sensitive
- Windows/macOS case-insensitive
- Code uses `.toLowerCase()` matching but filesystem may differ

**Risk:** Case-insensitive matching on Linux can match wrong file

#### 3.4: Symlink Resolution
- Does `.exists()` follow symlinks?
- What if user symlinks ROM/save directories?

```dart
final candidate = io.File(p.join(dir.path, executableName));
if (await candidate.exists()) return candidate.path;  // Follows symlinks
```

---

### 4. 🟡 RomM API Integration (MEDIUM-HIGH RISK)

**Problem:** Issues #28, #42 mention RomM v4.9 update

**Suspects:**

#### 4.1: Version Compatibility
- Code mentions `_devicePullSave()` (RomM 4.9+) vs `_legacyPullSave()` (older)
- What if RomM API changed but `fetchCapabilities()` is wrong?
- What if user has hybrid setup (old + new RomM)?

#### 4.2: API Error Handling
- `fetchCapabilities()` — what if it returns 403/500?
- Upload endpoint — what if server out of disk?
- Download endpoint — what if file corrupted on server?

**Missing:**
- No DioException handling visible
- No retry logic
- No user feedback on API failures

#### 4.3: Device ID Management
```dart
String? _getDeviceId() => _prefs.getString('romm_device_id');
```

**Risk:**
- What if device ID stolen/leaked?
- What if user has multiple devices?
- What if device ID expires?

---

### 5. 🟡 DS Emulator Specifics (MEDIUM-HIGH RISK)

**Problem:** #24, #42 — both DS-related issues

#### 5.1: DS Save Format Incompatibility
- MelonDS saves vs DeSmuMe saves (different formats)
- Issue #42: Save uploaded to RomM, but DeSmuMe webplayer can't read it

**Question:** Is Freegosy converting formats?
- MelonDS → some intermediate format → DeSmuMe?
- Or just copying raw `.dsv` files?

#### 5.2: MelonDS Save Path
**Where does MelonDS store saves?**
- Default: `~/.config/melonds/saves/`?
- Customizable in MelonDS settings?
- Different per game or global?

**Current code (melonds_save_strategy.dart):**
```dart
final saveDir = _directoryService.getEmulatorAppSupportDirectory('melonds', ...);
```

**Risk:** If MelonDS was customized, this path is wrong

#### 5.3: RetroArch DS Core
- Issue #24: "Save RAM for DS games does not work in RetroArch Core"
- RetroArch stores saves differently than standalone emulators
- Path might be `~/.config/retroarch/saves/Nintendo DS/game.srm`

**Question:** Does `RetroArchSaveStrategy` handle DS specifically?

---

### 6. 🟡 Concurrent Operations (MEDIUM RISK)

**Problem:** No evidence of operation locking

**Scenario:**
```
User launches game (pulls save)
  ↓
Save sync in progress (waiting for RomM)
  ↓
User manually clicks "Push Save" button
  ↓
Two operations touching same save directory = race condition
```

**Evidence of Lack of Locking:**
- No `Mutex` or file locks
- Multiple `SaveStrategy` instances not serialized
- Background sync queue (`background_sync_queue.dart`) separate from manual

**Risk:** File corruption if two operations write simultaneously

---

### 7. 🟡 File System Edge Cases (MEDIUM RISK)

#### 7.1: Very Long Paths
- Windows: 260 char limit (deprecated but still an issue)
- Some emulators with deep directory structures
- ROM name + emulator path + save path = could exceed limit

#### 7.2: Special Characters
- Filenames with spaces, quotes, unicode
- Path normalization missing?
- Shell escaping?

**Code Pattern (linux_appimage_detection_test.dart):**
```dart
p.basename(entry.path).toLowerCase() == executableName.toLowerCase()
```

**Risk:** Doesn't account for symlinks, relative paths, canonicalization

#### 7.3: Permissions
- Read-only ROMs (game cartridges)?
- Save directory not writable?
- Temp directory permissions denied?

**No validation:**
```dart
await io.Directory(tempDir).create(recursive: true);
// What if this fails?
```

#### 7.4: Disk Full
- No check if save upload will fit on device
- No check if download will fit locally
- No cleanup if out of space mid-operation

---

## Architectural Debt

### 1. Missing Abstraction: Path Locator
**Current State:**
- Each emulator strategy hardcodes its paths
- `DirectoryService` has platform-specific logic
- Linux has 3 strategies (EmuDeck, RetroDeck, Native)

**Better:**
- Unified `PathLocator` service
- Pluggable path resolvers
- Testable path detection

### 2. Missing Abstraction: Save Format Handler
**Current State:**
- Assumes emulator saves are already in correct format
- No conversion between MelonDS↔DeSmuMe, etc.

**Better:**
- `SaveFormatConverter` interface
- Platform-aware save format detection
- Auto-conversion pipeline

### 3. Missing Observability
- No structured logging
- No telemetry on success/failure rates
- No user-facing error messages (silent failures)

### 4. Missing Resilience
- No retry logic
- No circuit breaker for RomM API
- No graceful degradation (local-only mode)

---

## Failure Mode Summary

| Failure Mode | Likelihood | Impact | User Sees |
|--------------|------------|--------|-----------|
| RomM API timeout | HIGH | Save operation blocks | App freeze |
| Save path wrong | HIGH | Saves not found | "No saves to sync" |
| Emulator hangs on launch | HIGH | Game won't start | Stuck on launch |
| DS save format mismatch | MEDIUM | Saves incompatible | "Save doesn't work" |
| Temp file accumulation | MEDIUM | Disk fills slowly | Disk space issues |
| Concurrent sync race | LOW | File corruption | Corrupted saves |
| Path too long | LOW | Save operation fails | Silent failure |
| Permissions denied | LOW | Can't write saves | Silent failure |

---

## Recommended Investigations

### Immediate (This Week)
1. **Add logging to SaveSyncService:**
   - Log each operation: pull, push, upload, download
   - Log strategy selection (which emulator?)
   - Log file paths discovered
   
2. **Test RomM API directly:**
   ```bash
   curl -X GET https://romm-server/api/v1/saves
   curl -X POST https://romm-server/api/v1/saves/upload ...
   ```
   
3. **Reproduce #28:**
   - Set up fresh RomM instance
   - Launch game, create save
   - Click Push → capture network traffic (Fiddler/Charles)
   - Check RomM server logs

### Short-term (Next Sprint)
1. Refactor SaveSyncService to add timeouts
2. Implement file locking for concurrent operations
3. Add user-facing error dialogs (not just silent failures)
4. Create per-emulator path validation tests

### Medium-term
1. Implement SaveFormatConverter for DS saves
2. Add cache for `fetchCapabilities()` with TTL
3. Implement graceful fallback (local-only mode)
4. Add telemetry/analytics for sync operations

---

## Test Cases to Add

```dart
// test/core/save/save_sync_robustness_test.dart

test('saveSync tolerates slow RomM API (timeout)', () async {
  // Mock RomM API with 30s delay
  // Verify operation completes or gives timeout error
});

test('saveSync handles missing strategy gracefully', () async {
  // Unknown platformSlug
  // Should log and return false, not crash
});

test('saveSync handles concurrent pull+push', () async {
  // Start pull, immediately start push
  // Should serialize or error, not corrupt
});

test('melonds save path detection', () async {
  // Test default vs custom MelonDS config
  // Verify correct path selected
});

test('DS save format validation', () async {
  // MelonDS save vs DeSmuMe save
  // Verify format detection works
});
```

---

## Quick Wins

1. ✅ Add timeout to `fetchCapabilities()` (2-3 hrs)
2. ✅ Add logging to save sync pipeline (1-2 hrs)
3. ✅ Validate strategy exists before calling (1 hr)
4. ✅ Add error dialogs to save operations (2 hrs)
5. ✅ Cleanup temp files on success (1 hr)

---

## Code Audit Checklist

- [ ] Run static analysis: `flutter analyze`
- [ ] Check for unhandled exceptions in save service
- [ ] Audit all `Platform.environment` accesses
- [ ] Review all `Process.start()` calls for error handling
- [ ] Check all file I/O for exception handling
- [ ] Verify all async operations have timeouts
- [ ] Check for memory leaks (event listeners not cleaned up)
