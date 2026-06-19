# Freegosy Open Issues Analysis

**Date:** 2026-06-19  
**Total Open Issues:** 6

## Summary by Category

| Category | Issues | Status | Impact |
|----------|--------|--------|--------|
| Save Sync | #28, #42 | CRITICAL | Users can't sync saves; blocking feature |
| Emulator Detection | #43 | HIGH | Linux AppImage emulators invisible |
| DS-Specific | #24, #42 | HIGH | DS emulator + save integration broken |
| Navigation/UX | #41 | MEDIUM | Steam Deck user experience question |
| Configuration | #40 | LOW | Documentation/enhancement |

---

## Issue Breakdown

### 🔴 CRITICAL: Save Sync Failures

#### #28: "Save Sync not working" (opened 2026-06-14)
**Reporter:** deletableman  
**Platform:** Windows, Linux (Bazzite)  
**Status:** Multiple failed test cases

**Problem:**
- Pull does not download saves from RomM
- Push does not upload new local saves to RomM
- Both actions show success notifications but fail silently
- Retested with A Link to the Past (ALTP): made new save locally → clicked PUSH → no upload occurs
- Same behavior on both Windows and Linux

**Evidence:**
- Logs attached (5-13-26.logs.txt)
- Consistent across multiple test games
- Both pull and push operations fail

**Root Causes (Suspected):**
1. Save file path detection broken (not finding local saves correctly)
2. RomM API integration issue (upload/download endpoints failing)
3. File format mismatch (save files not compatible with RomM format)
4. Missing or incorrect emulator-specific save path mapping

**Related:** #42 (similar symptoms)

---

#### #42: "DS Save Sync Still Not Working" (opened 2026-06-13)
**Reporter:** Ramza2k (Mike Sweeney)  
**Platform:** Windows  
**Status:** Two separate issues bundled

**Problems:**
1. **MelonDS Launch Hangs:** Latest version locks up 3/3 times when launching MelonDS
2. **DS Save Sync Broken:**
   - Local save detected and pushed to RomM successfully
   - RomM shows save (64KB, correct size)
   - RomM webplayer shows NO save exists
   - Testing via DeSmuMe in webplayer fails (no save visible)

**Possible Causes:**
1. MelonDS process hanging (launch/exit handler issue?)
2. Save file format incompatibility (MelonDS vs DeSmuMe save format)
3. Save file upload/download path mapping incorrect for DS
4. Incorrect emulator app support directory detection

**Timeline:**
- Previous version had more issues (now fixed)
- Recent RomM update
- Recent Freegosy update with save sync

---

### 🟠 HIGH: Linux AppImage Detection (FIXED IN THIS COMMIT)

#### #43: "Freegosy Not Recognizing All Installed Emulators on Linux" (opened 2026-06-16)
**Reporter:** ThiccChimichanga  
**Platform:** Linux  
**Status:** FIXED (see commit c627f33)

**Problem:**
- EmuDeck installs emulators as AppImages to `~/Applications/` or `~/AppImages/` (Gear Lever)
- Freegosy doesn't find them (only checks `emulatorsRoot` + Flatpak)
- Missing: Eden, PCSX2, DuckStation, Cemu (all AppImages)
- RPCS3 (also AppImage) is found (why? needs investigation)

**Fix Applied:**
- Added search paths: `~/Applications/` → `~/AppImages/`
- Added case-insensitive matching for filenames
- Tests verify behavior

**Future:** Monitor if Xenia (Proton-translated app) needs special handling

---

### 🟠 HIGH: DS-Specific Issues

#### #24: "Save RAM for DS games does not work in RetroArch Core" (opened 2026-05-16)
**Reporter:** Ramza2k  
**Platform:** Unspecified  
**Status:** UNRESOLVED

**Problem:**
- DS ROM + save RAM doesn't work with RetroArch + DS core
- Title suggests RetroArch-specific, but might be broader save sync issue

**Likely Related To:**
- #42, #28 (DS save handling broken)

**Needs Investigation:**
- RetroArch DS core save path mapping
- Save file detection for RetroArch

---

### 🟡 MEDIUM: Steam Deck UX Question

#### #41: "Best way to navigate Freegosy on Steam Deck?" (opened 2026-06-13)
**Reporter:** daruuuna  
**Status:** Question/Discussion

**Content:** User asking for navigation guidance on Steam Deck

**Action:** Not a bug — documentation or FAQ answer needed
- Controller focus fix (commit c627f33) will help
- Document Steam Deck controller layout in wiki

---

### 🟢 LOW: Configuration Documentation

#### #40: "Configuration Files and Application Folders - Linux" (opened 2026-05-29)
**Reporter:** BlueInterlude  
**Status:** Enhancement/Documentation

**Content:** User asking about config file locations on Linux

**Action:** Separate from code fixes — create/update documentation
- Document `~/.config/freegosy/` location
- Document RomM server config
- Document Linux platform expectations

---

## Pattern Analysis

### 🔍 Recurring Themes

1. **Save Sync is Completely Broken**
   - #28: Generic save sync failure (all games, all emulators)
   - #42: DS-specific save sync (plus MelonDS hang)
   - #24: DS RetroArch save (subset of #28?)
   - **→ Root cause likely in core save sync logic, not emulator-specific**

2. **Emulator Path Detection Issues**
   - #43: AppImage detection (fixed)
   - Suggests path detection logic needs hardening
   - May affect other platforms (Windows, macOS?)

3. **DS Emulator Trouble**
   - #24, #42: Both DS-related
   - MelonDS launch hang (#42)
   - DS save format/compatibility (#42)
   - Save paths for DS may be wrong

4. **Platform-Specific Edge Cases**
   - Linux: AppImage, Flatpak, system installation
   - Windows: No AppImage equivalent, registry paths?
   - macOS: Not mentioned in issues
   - Steam Deck: Special environment (#41)

---

## Critical Paths for Investigation

### Priority 1: Fix Save Sync (Blocks Everything Else)

**Files to Audit:**
- `/lib/core/save/save_sync_service.dart` — main orchestrator
- `/lib/core/save/save_strategy.dart` — path detection per emulator
- `/lib/core/romm/romm_service.dart` — RomM API integration
- `/lib/core/emulator/strategies/` — per-emulator save path mappings

**Test Cases:**
1. Pull: RomM has save → local save not created
2. Push: Local save exists → not uploaded to RomM
3. Round-trip: Create local, push, delete local, pull → verify restore

**Suspect Areas:**
- Async operation sequencing (push while pull in flight?)
- File path normalization (trailing slashes? case sensitivity?)
- Emulator-specific save directory detection
- RomM server compatibility (version mismatch?)

### Priority 2: DS Emulator Breakage

**Files to Audit:**
- `/lib/core/emulator/strategies/melonds_strategy.dart` — MelonDS launch
- `/lib/core/emulator/strategies/` — DS-related emulator configs
- Save path detection for MelonDS, DeSmuMe, RetroArch DS core

**Specific Issues:**
1. Why does MelonDS hang on launch? (process exit handler?)
2. Why are DS saves incompatible between emulators?
3. Where are DS saves stored for each emulator?

### Priority 3: Hardening Path Detection

**Files to Audit:**
- `/lib/core/emulator/linux_strategies/` — Linux strategy classes
- `/lib/core/emulator/strategies/` — per-emulator path logic
- Verify all emulator strategies handle edge cases

**Test Scenarios:**
- Symlinks in save/ROM directories
- Paths with spaces
- Unicode filenames
- Very long paths
- Paths on different filesystems (SD card, USB)

---

## Potential Failure Modes (Codebase Review)

### 1. Async/Concurrency Issues
- Save pull starts before push finishes
- Multiple save operations race
- File locks cause failures silently

### 2. Path Normalization
- Different path formats (relative, absolute, symlinks)
- Case sensitivity on different filesystems
- Trailing slashes inconsistently handled

### 3. Emulator Configuration
- Save paths hardcoded but wrong for user's setup
- EmuDeck vs native Linux install paths differ
- RomM metadata doesn't match actual save locations

### 4. API Integration
- RomM API changed (version bump #42 mentions)
- Token auth issues
- Network timeouts not handled

### 5. File Format
- Save file encoding mismatch (binary vs text)
- Compression issues
- Emulator-specific save headers

---

## Recommendations

### Immediate (Next PR)
1. ✅ Fix Linux AppImage detection (#43) — DONE
2. ✅ Add controller focus gating — DONE
3. Add debug logging to save sync pipeline
4. Create integration test for save pull/push round-trip

### Short-term (Next Sprint)
1. Audit `SaveSyncService` for race conditions
2. Test save pull on clean install (no existing saves)
3. Test save push with RomM API directly (curl)
4. Verify MelonDS process handling
5. Create DS emulator save path mapping test

### Medium-term
1. Refactor save path detection into separate, testable service
2. Add comprehensive path normalization utility
3. Create per-emulator save format validator
4. Add telemetry for save operations (success rate, timing)

### Long-term
1. Support multiple save versions/backups
2. Cloud save resume/conflict resolution
3. Save game encryption
4. Per-game save strategies (e.g., suspend state vs traditional saves)

---

## Test Coverage Gaps

### Missing Tests
- [ ] SaveSyncService round-trip (pull + push)
- [ ] Per-emulator save path detection
- [ ] RomM API integration (mock server)
- [ ] MelonDS launch + exit handlers
- [ ] Concurrent save operations
- [ ] Save file format validation

### Suggested Test Files
- `/test/core/save/save_sync_roundtrip_test.dart`
- `/test/core/save/emulator_save_paths_test.dart`
- `/test/core/romm/romm_save_integration_test.dart`
- `/test/core/emulator/melonds_launch_test.dart`

---

## Questions for Contributors

1. **Save Sync:** Have users updated RomM server? Is version mismatch possible?
2. **DS:** Which versions of MelonDS are tested? (hangs suggest process management issue)
3. **Linux:** Are there other emulator installation methods we're missing?
4. **General:** Are there any recent refactors to save/emulator code that broke behavior?

---

## Links
- Issue #24: DS Save RAM RetroArch
- Issue #28: Generic save sync failure (CRITICAL)
- Issue #40: Linux config paths
- Issue #41: Steam Deck navigation
- Issue #42: DS save sync + MelonDS hang (CRITICAL)
- Issue #43: Linux AppImage detection (FIXED)
