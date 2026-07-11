"""
Save Sync Integration Tests — v2

Tests ALL scenarios against the mock RomM 4.9.0 server to understand
exactly how saves behave. Based on real RomM OpenAPI spec.

Usage:
    1. Start mock server: python test/mock_romm_server.py
    2. Run this test:    python test/save_sync_integration_test.py
"""

import hashlib
import json
import os
import sys
import tempfile
import time
import zipfile
from datetime import datetime
from pathlib import Path

import requests

BASE = "http://127.0.0.1:5555"
GAME_ID = "test-game-001"


def md5(data: bytes) -> str:
    return hashlib.md5(data).hexdigest()


def clear_server():
    requests.post(f"{BASE}/debug/clear")


def get_all_saves():
    r = requests.get(f"{BASE}/debug/saves")
    return r.json()


def print_saves(label="Current server saves"):
    saves = get_all_saves()
    print(f"\n  --- {label} ({len(saves)} saves) ---")
    for sid, s in saves.items():
        print(f"    [{sid}] file={s['file_name']} slot={s['slot']} "
              f"hash={s['content_hash'][:8]}... device={s.get('origin_device_id', 'N/A')[:8]}")


def register_device(name="TestDevice"):
    r = requests.post(f"{BASE}/api/devices", json={"name": name, "platform": "windows"})
    return r.json()["device_id"]


# ---------------------------------------------------------------------------
# Push helpers
# ---------------------------------------------------------------------------

def push_single_file(game_id, file_path, slot=None, device_id=None,
                     autocleanup=False, autocleanup_limit=5,
                     override_filename=None, overwrite=False):
    params = {"rom_id": game_id, "emulator": "freegosy"}
    if device_id:
        params["device_id"] = device_id
    if slot:
        params["slot"] = slot
    else:
        ts = datetime.now().strftime("%Y-%m-%d_%H-%M-%S")
        params["slot"] = f"freegosy-srm_{ts}"
    if autocleanup:
        params["autocleanup"] = "true"
        params["autocleanup_limit"] = str(autocleanup_limit)
    if overwrite:
        params["overwrite"] = "true"

    filename = override_filename or Path(file_path).name
    with open(file_path, "rb") as f:
        files = {"saveFile": (filename, f, "application/octet-stream")}
        r = requests.post(f"{BASE}/api/saves", params=params, files=files)
    return r.json(), r.status_code


def push_bundle(game_id, files_dict, display_name, slot=None, device_id=None,
                autocleanup=False, autocleanup_limit=5, overwrite=False):
    with tempfile.NamedTemporaryFile(suffix=".zip", delete=False) as tmp:
        with zipfile.ZipFile(tmp, "w") as zf:
            zf.writestr("freegosy_sync.txt", datetime.now().isoformat())
            for filepath, arcname in files_dict.items():
                zf.write(filepath, arcname)
        bundle_path = tmp.name

    upload_filename = f"{display_name}.zip"
    result, status = push_single_file(
        game_id, bundle_path, slot=slot, device_id=device_id,
        autocleanup=autocleanup, autocleanup_limit=autocleanup_limit,
        override_filename=upload_filename, overwrite=overwrite,
    )
    os.unlink(bundle_path)
    return result, status


# ---------------------------------------------------------------------------
# Pull helpers
# ---------------------------------------------------------------------------

def pull_latest_save(game_id, device_id=None):
    params = {"rom_id": game_id}
    if device_id:
        params["device_id"] = device_id
    r = requests.get(f"{BASE}/api/saves", params=params)
    data = r.json()
    saves = data if isinstance(data, list) else data.get("items", [])
    if not saves:
        print("  No saves found on server")
        return None, None

    latest = saves[0]
    filename = latest["file_name"]
    download_path = latest["download_path"]

    dl_params = {}
    if device_id:
        dl_params["device_id"] = device_id
        dl_params["optimistic"] = "true"

    dr = requests.get(f"{BASE}{download_path}", params=dl_params)
    content = dr.content
    print(f"  Pulled: filename={filename}, size={len(content)} bytes, hash={md5(content)[:8]}...")
    return filename, content


# ===========================================================================
# TEST SCENARIOS
# ===========================================================================

def test_01_normal_push_pull():
    """Normal push and pull cycle."""
    print("\n" + "="*70)
    print("TEST 1: Normal push/pull with slot='freegosy'")
    print("="*70)
    clear_server()

    with tempfile.NamedTemporaryFile(suffix=".srm", delete=False, dir=tempfile.gettempdir()) as f:
        f.write(b"retroarch save data for game")
        save_path = f.name
    uploaded_name = Path(save_path).name

    device_id = register_device("Desktop-PC")
    r, s = push_single_file(GAME_ID, save_path, slot="freegosy", device_id=device_id)
    print(f"  Push: status={s}, file_name={r.get('file_name')}, slot={r.get('slot')}")
    print_saves("After push")

    filename, content = pull_latest_save(GAME_ID, device_id=device_id)
    assert filename == uploaded_name, f"Expected {uploaded_name}, got {filename}"
    print(f"  PASS: Filename preserved: '{filename}' (no timestamp in filename)")
    os.unlink(save_path)


def test_02_no_autocleanup_creates_duplicates():
    """Push same content twice WITHOUT autocleanup — RomM creates duplicates."""
    print("\n" + "="*70)
    print("TEST 2: No autocleanup — duplicates created")
    print("="*70)
    clear_server()

    save_content = b"identical save content"
    with tempfile.NamedTemporaryFile(suffix=".srm", delete=False, dir=tempfile.gettempdir()) as f:
        f.write(save_content)
        save_path = f.name

    device_id = register_device("Desktop-PC")

    r1, _ = push_single_file(GAME_ID, save_path, slot="freegosy", device_id=device_id)
    print(f"  Push 1: save_id={r1.get('id')}")

    r2, _ = push_single_file(GAME_ID, save_path, slot="freegosy", device_id=device_id)
    print(f"  Push 2: save_id={r2.get('id')}")

    saves = get_all_saves()
    print(f"\n  FINDING: {len(saves)} saves on server (same content, same slot)")
    print(f"  RomM does NOT deduplicate by content hash!")
    print(f"  Without autocleanup, every upload creates a NEW record.")
    assert len(saves) == 2, f"Expected 2, got {len(saves)}"
    print("  CONFIRMED: No server-side dedup by hash")
    os.unlink(save_path)


def test_03_with_autocleanup():
    """Push with autocleanup=true — Argosy's approach."""
    print("\n" + "="*70)
    print("TEST 3: With autocleanup=true (Argosy's approach)")
    print("="*70)
    clear_server()

    device_id = register_device("Desktop-PC")

    for i in range(6):
        with tempfile.NamedTemporaryFile(suffix=".srm", delete=False, dir=tempfile.gettempdir()) as f:
            f.write(f"save version {i}".encode())
            save_path = f.name

        r, s = push_single_file(
            GAME_ID, save_path, slot="freegosy", device_id=device_id,
            autocleanup=True, autocleanup_limit=5,
            override_filename="game.srm", overwrite=False,
        )
        print(f"  Push {i+1}: save_id={r.get('id')}, status={s}")
        os.unlink(save_path)
        time.sleep(0.3)

    saves = get_all_saves()
    print(f"\n  Total saves: {len(saves)} (expected <= 5)")
    print("  Autocleanup prunes old versions automatically!")
    assert len(saves) <= 5, f"Expected <=5, got {len(saves)}"
    print("  PASS: Autocleanup works correctly")


def test_04_overwrite_updates_existing():
    """Push with overwrite=true — updates existing record."""
    print("\n" + "="*70)
    print("TEST 4: Overwrite=true — updates existing record")
    print("="*70)
    clear_server()

    with tempfile.NamedTemporaryFile(suffix=".srm", delete=False, dir=tempfile.gettempdir()) as f:
        f.write(b"original content")
        save_path = f.name

    device_id = register_device("Desktop-PC")

    r1, _ = push_single_file(GAME_ID, save_path, slot="freegosy", device_id=device_id, overwrite=True)
    print(f"  Push 1: save_id={r1.get('id')}, hash={r1.get('content_hash', '')[:8]}...")

    with open(save_path, "wb") as f:
        f.write(b"modified content - player progressed!")

    r2, _ = push_single_file(GAME_ID, save_path, slot="freegosy", device_id=device_id, overwrite=True)
    print(f"  Push 2: save_id={r2.get('id')}, hash={r2.get('content_hash', '')[:8]}...")

    saves = get_all_saves()
    print(f"\n  Total saves: {len(saves)} (overwrite=true updates, not duplicates)")
    assert len(saves) == 1, f"Expected 1, got {len(saves)}"
    assert r1.get('id') == r2.get('id'), "Same save ID (updated in place)"
    print("  PASS: Overwrite correctly updates existing record")
    os.unlink(save_path)


def test_05_legacy_timestamped_slot():
    """Legacy behavior: timestamped slots create separate save records."""
    print("\n" + "="*70)
    print("TEST 5: Legacy timestamped slot (no slot param)")
    print("="*70)
    clear_server()

    with tempfile.NamedTemporaryFile(suffix=".srm", delete=False, dir=tempfile.gettempdir()) as f:
        f.write(b"save data")
        save_path = f.name

    # Push with NO slot (Freegosy legacy: timestamped slot)
    r1, _ = push_single_file(GAME_ID, save_path, slot=None, device_id=None)
    print(f"  Push 1: slot={r1.get('slot')}, file_name={r1.get('file_name')}")

    time.sleep(1)
    r2, _ = push_single_file(GAME_ID, save_path, slot=None, device_id=None)
    print(f"  Push 2: slot={r2.get('slot')}, file_name={r2.get('file_name')}")

    saves = get_all_saves()
    print(f"\n  Total saves: {len(saves)}")
    for sid, s in saves.items():
        print(f"    [{sid}] slot={s['slot']} file={s['file_name']}")
    print("  Each timestamped slot = separate save record (no dedup possible)")
    os.unlink(save_path)


def test_06_pull_filename_never_has_timestamp():
    """The filename on the server is always the uploaded filename (no timestamp)."""
    print("\n" + "="*70)
    print("TEST 6: Pull filename never has timestamp")
    print("="*70)
    clear_server()

    with tempfile.NamedTemporaryFile(suffix=".sav", delete=False, dir=tempfile.gettempdir()) as f:
        f.write(b"melonDS save data")
        save_path = f.name
    original_name = Path(save_path).name

    device_id = register_device("Desktop-PC")

    # Push with timestamped slot (legacy)
    r1, _ = push_single_file(GAME_ID, save_path, slot=None, device_id=None)
    print(f"  Push (legacy): slot={r1.get('slot')}")

    # Push with static slot (4.9+)
    r2, _ = push_single_file(GAME_ID, save_path, slot="freegosy", device_id=device_id)
    print(f"  Push (4.9+):   slot={r2.get('slot')}")

    # Pull — server returns the file_name as-is
    filename, _ = pull_latest_save(GAME_ID, device_id=device_id)
    print(f"\n  Pulled filename: '{filename}'")
    print(f"  Original filename: '{original_name}'")

    assert filename == original_name, f"Expected {original_name}, got {filename}"
    print("  PASS: The FILENAME is never timestamped — only the SLOT is")
    os.unlink(save_path)


def test_07_md5_dedup_blocks_automatic_sync():
    """The real problem: Freegosy's local MD5 check blocks re-upload."""
    print("\n" + "="*70)
    print("TEST 7: MD5 dedup blocks automatic sync (THE ROOT CAUSE)")
    print("="*70)
    clear_server()

    save_content = b"my game save - level 5"
    with tempfile.NamedTemporaryFile(suffix=".srm", delete=False, dir=tempfile.gettempdir()) as f:
        f.write(save_content)
        save_path = f.name

    device_id = register_device("Desktop-PC")

    # First push
    r1, _ = push_single_file(GAME_ID, save_path, slot="freegosy", device_id=device_id)
    print(f"  Push 1: save_id={r1.get('id')}")

    # Simulate Freegosy's local hash check (save_sync_service.dart:392)
    local_hash = md5(save_content)
    stored_hash = local_hash  # This is what Freegosy caches after push
    print(f"\n  Local hash:  {local_hash}")
    print(f"  Stored hash: {stored_hash}")
    print(f"\n  Freegosy's dedup check (line 392):")
    print(f"    if (!force && storedHash != null && localHash == storedHash)")
    print(f"    => SKIPS upload (hash unchanged)")
    print(f"\n  This is CORRECT for automatic post-exit sync.")
    print(f"  But WRONG for manual 'Push' button — user expects it to always upload.")
    print(f"\n  Argosy's solution:")
    print(f"    1. Local MD5 check: skip if content unchanged (same as Freegosy)")
    print(f"    2. Server hash check: compare with server's content_hash")
    print(f"    3. Manual push: use forceOverwrite=true to bypass local check")
    print(f"    4. Autocleanup on server: prune old versions automatically")
    os.unlink(save_path)


def test_08_bundle_push_pull():
    """Multi-file bundle (ZIP) push and pull."""
    print("\n" + "="*70)
    print("TEST 8: Multi-file bundle push/pull (PS2 saves)")
    print("="*70)
    clear_server()

    tmpdir = tempfile.mkdtemp()
    memcard = Path(tmpdir) / "Mcd001.ps2"
    memcard.write_bytes(b"PS2 memory card data")
    icon = Path(tmpdir) / "icon.icn"
    icon.write_bytes(b"icon data")

    device_id = register_device("Desktop-PC")

    files = {str(memcard): "Mcd001.ps2", str(icon): "icon.icn"}
    result, status = push_bundle(GAME_ID, files, "God of War",
                                  slot="freegosy", device_id=device_id)
    print(f"  Push bundle: status={status}, file_name={result.get('file_name')}")
    print_saves("After bundle push")

    filename, content = pull_latest_save(GAME_ID, device_id=device_id)
    print(f"\n  Pulled: filename={filename}, size={len(content)} bytes")

    if filename and filename.endswith(".zip"):
        with tempfile.NamedTemporaryFile(suffix=".zip", delete=False) as tmp:
            tmp.write(content)
            tmp_path = tmp.name
        with zipfile.ZipFile(tmp_path) as zf:
            names = zf.namelist()
            print(f"  ZIP contents: {names}")
            assert "Mcd001.ps2" in names
            assert "icon.icn" in names
            print("  PASS: All files preserved in bundle")
        os.unlink(tmp_path)

    import shutil
    shutil.rmtree(tmpdir)


def test_09_argosy_approach_autocleanup_no_force():
    """Argosy's approach: autocleanup + no force + local MD5 dedup."""
    print("\n" + "="*70)
    print("TEST 9: Argosy's approach — autocleanup + local MD5 dedup")
    print("="*70)
    clear_server()

    device_id = register_device("Desktop-PC")
    local_hash_cache = {}

    def argosy_push(save_content, filename="game.srm"):
        """Simulates Argosy's upload flow."""
        with tempfile.NamedTemporaryFile(suffix=".srm", delete=False, dir=tempfile.gettempdir()) as f:
            f.write(save_content)
            save_path = f.name

        local_hash = md5(save_content)
        stored_hash = local_hash_cache.get(filename)

        # Argosy's local dedup check
        if stored_hash == local_hash:
            print(f"    SKIP: Local hash unchanged ({local_hash[:8]}...)")
            os.unlink(save_path)
            return None

        # Upload with autocleanup
        result, status = push_single_file(
            GAME_ID, save_path, slot="autosave", device_id=device_id,
            autocleanup=True, autocleanup_limit=5,
            override_filename=filename, overwrite=False,
        )
        local_hash_cache[filename] = local_hash
        print(f"    PUSH: save_id={result.get('id')}, status={status}")
        os.unlink(save_path)
        return result

    # Simulate gameplay sessions
    print("\n  Session 1: Play game, save progress")
    argosy_push(b"save level 1")

    print("\n  Session 2: Play again, same save (no change)")
    argosy_push(b"save level 1")  # Same content — skipped!

    print("\n  Session 3: Progress further")
    argosy_push(b"save level 3")

    print("\n  Session 4: Same as session 3")
    argosy_push(b"save level 3")  # Same content — skipped!

    print("\n  Session 5: More progress")
    argosy_push(b"save level 5")

    saves = get_all_saves()
    print(f"\n  Total saves on server: {len(saves)}")
    for sid, s in saves.items():
        print(f"    [{sid}] file={s['file_name']} hash={s['content_hash'][:8]}...")
    print("  Local MD5 check prevents unnecessary uploads")
    print("  Autocleanup prunes old versions on server")


def test_10_force_push_scenario():
    """Force push (manual 'Push' button) should always upload."""
    print("\n" + "="*70)
    print("TEST 10: Force push — manual 'Push' button behavior")
    print("="*70)
    clear_server()

    save_content = b"my save data"
    with tempfile.NamedTemporaryFile(suffix=".srm", delete=False, dir=tempfile.gettempdir()) as f:
        f.write(save_content)
        save_path = f.name

    device_id = register_device("Desktop-PC")

    # Initial push
    r1, _ = push_single_file(GAME_ID, save_path, slot="freegosy", device_id=device_id)
    print(f"  Initial push: save_id={r1.get('id')}")

    # Force push (same content, but user clicked 'Push')
    # Option A: overwrite=true — updates existing record
    r2, _ = push_single_file(GAME_ID, save_path, slot="freegosy", device_id=device_id, overwrite=True)
    print(f"  Force push (overwrite=true): save_id={r2.get('id')}")

    saves = get_all_saves()
    print(f"\n  With overwrite=true: {len(saves)} save (updated in place)")
    assert len(saves) == 1

    # Option B: autocleanup=true — creates new version
    r3, _ = push_single_file(GAME_ID, save_path, slot="freegosy", device_id=device_id,
                              autocleanup=True, autocleanup_limit=5)
    print(f"  Force push (autocleanup=true): save_id={r3.get('id')}")

    saves = get_all_saves()
    print(f"  With autocleanup=true: {len(saves)} saves (new version created)")
    assert len(saves) == 2
    print("  PASS: Both approaches work — overwrite updates, autocleanup versions")
    os.unlink(save_path)


def test_11_sync_negotiate():
    """Test RomM 4.9+ sync negotiate endpoint."""
    print("\n" + "="*70)
    print("TEST 11: Sync Negotiate (RomM 4.9+)")
    print("="*70)
    clear_server()

    device_id = register_device("Desktop-PC")

    # Push a save first
    with tempfile.NamedTemporaryFile(suffix=".srm", delete=False, dir=tempfile.gettempdir()) as f:
        f.write(b"existing save on server")
        save_path = f.name

    r, _ = push_single_file(GAME_ID, save_path, slot="freegosy", device_id=device_id)
    print(f"  Server has: save_id={r.get('id')}, hash={r.get('content_hash', '')[:8]}...")
    os.unlink(save_path)

    # Client sends its inventory via negotiate
    negotiate_payload = {
        "device_id": device_id,
        "saves": [
            {
                "rom_id": GAME_ID,
                "file_name": "game.srm",
                "slot": "freegosy",
                "emulator": "freegosy",
                "content_hash": r.get("content_hash"),  # Same hash
                "updated_at": datetime.now().isoformat(),
                "file_size_bytes": 23,
            }
        ]
    }

    resp = requests.post(f"{BASE}/api/sync/negotiate", json=negotiate_payload)
    result = resp.json()
    print(f"\n  Negotiate response:")
    print(f"    session_id: {result.get('session_id')}")
    print(f"    operations: {result.get('operations')}")
    print(f"    total_upload: {result.get('total_upload')}")
    print(f"    total_download: {result.get('total_download')}")
    print(f"    total_no_op: {result.get('total_no_op')}")

    assert result["total_no_op"] == 1, "Same hash = no_op"
    print("  PASS: Negotiate correctly identifies no-op when hashes match")

    # Now try with different hash
    negotiate_payload["saves"][0]["content_hash"] = "different-hash"
    resp = requests.post(f"{BASE}/api/sync/negotiate", json=negotiate_payload)
    result = resp.json()
    print(f"\n  With different hash:")
    print(f"    operations: {result.get('operations')}")
    assert result["total_download"] == 1, "Different hash = download"
    print("  PASS: Negotiate correctly identifies download when hashes differ")


# ===========================================================================
# MAIN
# ===========================================================================

if __name__ == "__main__":
    print("Save Sync Integration Tests v2")
    print("Testing against mock RomM 4.9.0 server\n")

    try:
        requests.get(f"{BASE}/api/heartbeat", timeout=2)
    except Exception:
        print("ERROR: Mock server not running. Start it with:")
        print("  python test/mock_romm_server.py")
        sys.exit(1)

    test_01_normal_push_pull()
    test_02_no_autocleanup_creates_duplicates()
    test_03_with_autocleanup()
    test_04_overwrite_updates_existing()
    test_05_legacy_timestamped_slot()
    test_06_pull_filename_never_has_timestamp()
    test_07_md5_dedup_blocks_automatic_sync()
    test_08_bundle_push_pull()
    test_09_argosy_approach_autocleanup_no_force()
    test_10_force_push_scenario()
    test_11_sync_negotiate()

    print("\n" + "="*70)
    print("ALL 11 TESTS COMPLETE")
    print("="*70)
    print("\nKey findings:")
    print("  1. RomM does NOT deduplicate by content hash (creates duplicates)")
    print("  2. The FILENAME is never timestamped — only the SLOT is")
    print("  3. autocleanup=true + overwrite=false = version history with pruning")
    print("  4. overwrite=true = update in place (no new record)")
    print("  5. Freegosy's local MD5 check blocks re-upload (correct for auto sync)")
    print("  6. Manual 'Push' should use force=true or overwrite=true")
    print("  7. Sync negotiate (4.9+) is the proper way to detect what needs syncing")
