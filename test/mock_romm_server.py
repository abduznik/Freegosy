"""
Mock RomM Server v2 — matches real RomM 4.9.0 API spec.

Based on the OpenAPI spec from a live RomM 4.9.0 instance.
Accurately models the save upload dedup, slot, autocleanup, and device sync behavior.

Usage:
    python test/mock_romm_server.py
"""

import os
import json
import hashlib
import time
import uuid
from datetime import datetime, timezone
from pathlib import Path
from flask import Flask, request, jsonify, send_file

app = Flask(__name__)

# ---------------------------------------------------------------------------
# In-memory stores
# ---------------------------------------------------------------------------
SAVES = {}          # {save_id: save_record}
DEVICES = {}        # {device_id: device_record}
SYNC_SESSIONS = {}  # {session_id: session_record}
NEXT_SAVE_ID = 1
NEXT_SESSION_ID = 1

STORAGE_DIR = Path(__file__).parent / "_mock_romm_storage"
STORAGE_DIR.mkdir(exist_ok=True)

REQUEST_LOG = []


def log_request(endpoint, details):
    entry = {
        "time": datetime.now(timezone.utc).isoformat(),
        "endpoint": endpoint,
        **details,
    }
    REQUEST_LOG.append(entry)
    print(f"\n{'='*70}")
    print(f"  [{endpoint}]")
    for k, v in details.items():
        print(f"    {k}: {v}")
    print(f"{'='*70}")


def compute_md5_file(filepath):
    h = hashlib.md5()
    with open(filepath, "rb") as f:
        for chunk in iter(lambda f=f: f.read(8192), b""):
            h.update(chunk)
    return h.hexdigest()


def compute_md5_bytes(data):
    return hashlib.md5(data).hexdigest()


# ---------------------------------------------------------------------------
# Heartbeat / Capabilities
# ---------------------------------------------------------------------------

@app.route("/api/heartbeat", methods=["GET"])
def heartbeat():
    return jsonify({
        "SYSTEM": {"VERSION": "4.9.0", "SHOW_SETUP_WIZARD": False},
        "METADATA_SOURCES": {"ANY_SOURCE_ENABLED": True},
        "FILESYSTEM": {"FS_PLATFORMS": ["gba", "ps2", "nds", "switch"]},
        "EMULATION": {"DISABLE_EMULATOR_JS": False},
    })


# ---------------------------------------------------------------------------
# Device Registration (matches RomM DeviceCreatePayload)
# ---------------------------------------------------------------------------

@app.route("/api/devices", methods=["POST"])
def register_device():
    data = request.json or {}
    device_id = str(uuid.uuid4())
    name = data.get("name")
    platform = data.get("platform")
    client = data.get("client")
    client_version = data.get("client_version")

    DEVICES[device_id] = {
        "id": device_id,
        "name": name,
        "platform": platform,
        "client": client,
        "client_version": client_version,
        "sync_mode": data.get("sync_mode", "api"),
        "sync_enabled": True,
        "last_seen": datetime.now(timezone.utc).isoformat(),
        "created_at": datetime.now(timezone.utc).isoformat(),
        "updated_at": datetime.now(timezone.utc).isoformat(),
    }

    log_request("POST /api/devices", {
        "device_id": device_id,
        "name": name,
        "platform": platform,
        "client": client,
    })

    return jsonify({
        "device_id": device_id,
        "name": name,
        "created_at": DEVICES[device_id]["created_at"],
    }), 201


# ---------------------------------------------------------------------------
# Save Upload (matches RomM POST /api/saves)
# ---------------------------------------------------------------------------

@app.route("/api/saves", methods=["POST"])
def upload_save():
    global NEXT_SAVE_ID

    rom_id = request.args.get("rom_id")
    emulator = request.args.get("emulator")
    slot = request.args.get("slot")
    device_id = request.args.get("device_id")
    session_id = request.args.get("session_id")
    overwrite = request.args.get("overwrite", "false").lower() == "true"
    autocleanup = request.args.get("autocleanup", "false").lower() == "true"
    autocleanup_limit = int(request.args.get("autocleanup_limit", 10))

    save_file = request.files.get("saveFile")
    if save_file is None:
        return jsonify({"detail": "No saveFile provided"}), 400

    uploaded_filename = save_file.filename
    content_bytes = save_file.read()
    content_hash = compute_md5_bytes(content_bytes)

    log_request("POST /api/saves (upload)", {
        "rom_id": rom_id,
        "emulator": emulator,
        "slot": slot,
        "device_id": device_id,
        "overwrite": overwrite,
        "autocleanup": autocleanup,
        "autocleanup_limit": autocleanup_limit,
        "uploaded_filename": uploaded_filename,
        "content_size": len(content_bytes),
        "content_md5": content_hash[:12],
    })

    # --- RomM behavior: find existing save by rom_id + emulator + slot ---
    existing = None
    for sid, s in SAVES.items():
        if s["rom_id"] == rom_id and s["emulator"] == emulator and s["slot"] == slot:
            existing = s
            break

    if existing:
        if overwrite:
            # Overwrite existing save record
            log_request("OVERWRITE", {
                "reason": "overwrite=true, updating existing save",
                "existing_save_id": existing["id"],
                "old_hash": existing["content_hash"][:12] if existing["content_hash"] else None,
                "new_hash": content_hash[:12],
            })
            filepath = STORAGE_DIR / f"{existing['id']}_{uploaded_filename}"
            with open(filepath, "wb") as f:
                f.write(content_bytes)
            # Clean up old file if name changed
            old_path = STORAGE_DIR / f"{existing['id']}_{existing['file_name']}"
            if old_path != filepath and old_path.exists():
                old_path.unlink()

            now = datetime.now(timezone.utc).isoformat()
            existing["file_name"] = uploaded_filename
            existing["file_size_bytes"] = len(content_bytes)
            existing["content_hash"] = content_hash
            existing["updated_at"] = now
            existing["origin_device_id"] = device_id
            # Update device sync
            _update_device_sync(existing, device_id, now)
            return jsonify(_save_to_response(existing)), 200

        elif autocleanup:
            # Create new record (version), then prune old ones
            log_request("AUTOCLEANUP-NEW", {
                "reason": "overwrite=false + autocleanup=true, creating new version",
                "existing_save_id": existing["id"],
            })
            # Fall through to create new record
        else:
            # No overwrite, no autocleanup — RomM creates a duplicate record
            log_request("DUPLICATE", {
                "reason": "No overwrite, no autocleanup — creating duplicate",
                "existing_save_id": existing["id"],
            })
            # Fall through to create new record

    # --- Create new save record ---
    save_id = NEXT_SAVE_ID
    NEXT_SAVE_ID += 1

    filepath = STORAGE_DIR / f"{save_id}_{uploaded_filename}"
    with open(filepath, "wb") as f:
        f.write(content_bytes)

    now = datetime.now(timezone.utc).isoformat()
    file_ext = Path(uploaded_filename).suffix.lstrip(".")
    file_name_no_ext = Path(uploaded_filename).stem

    save_record = {
        "id": save_id,
        "rom_id": rom_id,
        "user_id": 1,
        "file_name": uploaded_filename,
        "file_name_no_tags": uploaded_filename,
        "file_name_no_ext": file_name_no_ext,
        "file_extension": file_ext,
        "file_path": f"saves/{rom_id}/{uploaded_filename}",
        "file_size_bytes": len(content_bytes),
        "full_path": f"saves/{rom_id}/{uploaded_filename}",
        "download_path": f"/api/saves/{save_id}/content",
        "missing_from_fs": False,
        "created_at": now,
        "updated_at": now,
        "emulator": emulator,
        "slot": slot,
        "content_hash": content_hash,
        "screenshot": None,
        "origin_device_id": device_id,
        "device_syncs": [],
    }

    if device_id:
        save_record["device_syncs"] = [{
            "device_id": device_id,
            "device_name": DEVICES.get(device_id, {}).get("name"),
            "last_synced_at": now,
            "is_untracked": False,
            "is_current": True,
        }]

    SAVES[save_id] = save_record

    # --- Autocleanup: prune old saves in same slot ---
    if autocleanup and slot:
        same_slot = [
            s for s in SAVES.values()
            if s["rom_id"] == rom_id and s["emulator"] == emulator and s["slot"] == slot
        ]
        same_slot.sort(key=lambda s: s["created_at"], reverse=True)
        if len(same_slot) > autocleanup_limit:
            for old in same_slot[autocleanup_limit:]:
                old_path = STORAGE_DIR / f"{old['id']}_{old['file_name']}"
                if old_path.exists():
                    old_path.unlink()
                del SAVES[old["id"]]
                log_request("AUTOCLEANUP-PRUNE", {"deleted_save_id": old["id"]})

    log_request("SAVE-CREATED", {
        "save_id": save_id,
        "file_name": uploaded_filename,
        "content_hash": content_hash[:12],
        "slot": slot,
    })

    return jsonify(_save_to_response(save_record)), 201


def _update_device_sync(save_record, device_id, now):
    if not device_id:
        return
    syncs = save_record.get("device_syncs", [])
    found = False
    for ds in syncs:
        if ds["device_id"] == device_id:
            ds["last_synced_at"] = now
            ds["is_current"] = True
            found = True
            break
    if not found:
        syncs.append({
            "device_id": device_id,
            "device_name": DEVICES.get(device_id, {}).get("name"),
            "last_synced_at": now,
            "is_untracked": False,
            "is_current": True,
        })
    save_record["device_syncs"] = syncs


def _save_to_response(save):
    return {
        "id": save["id"],
        "rom_id": save["rom_id"],
        "user_id": save.get("user_id", 1),
        "file_name": save["file_name"],
        "file_name_no_tags": save.get("file_name_no_tags", save["file_name"]),
        "file_name_no_ext": save.get("file_name_no_ext", Path(save["file_name"]).stem),
        "file_extension": save.get("file_extension", Path(save["file_name"]).suffix.lstrip(".")),
        "file_path": save.get("file_path", ""),
        "file_size_bytes": save["file_size_bytes"],
        "full_path": save.get("full_path", ""),
        "download_path": save["download_path"],
        "missing_from_fs": False,
        "created_at": save["created_at"],
        "updated_at": save["updated_at"],
        "emulator": save.get("emulator"),
        "slot": save.get("slot"),
        "content_hash": save.get("content_hash"),
        "screenshot": save.get("screenshot"),
        "origin_device_id": save.get("origin_device_id"),
        "device_syncs": save.get("device_syncs", []),
    }


# ---------------------------------------------------------------------------
# Save List (GET /api/saves)
# ---------------------------------------------------------------------------

@app.route("/api/saves", methods=["GET"])
def list_saves():
    rom_id = request.args.get("rom_id")
    platform_id = request.args.get("platform_id")
    device_id = request.args.get("device_id")
    slot = request.args.get("slot")

    log_request("GET /api/saves", {
        "rom_id": rom_id, "platform_id": platform_id,
        "device_id": device_id, "slot": slot,
    })

    results = []
    for s in SAVES.values():
        if rom_id and str(s["rom_id"]) != str(rom_id):
            continue
        if slot and s.get("slot") != slot:
            continue
        entry = _save_to_response(s)
        results.append(entry)

    results.sort(key=lambda s: s["created_at"], reverse=True)
    return jsonify(results)


# ---------------------------------------------------------------------------
# Save Summary (GET /api/saves/summary)
# ---------------------------------------------------------------------------

@app.route("/api/saves/summary", methods=["GET"])
def saves_summary():
    rom_id = request.args.get("rom_id")
    log_request("GET /api/saves/summary", {"rom_id": rom_id})

    by_slot = {}
    for s in SAVES.values():
        if rom_id and str(s["rom_id"]) != str(rom_id):
            continue
        slot_key = s.get("slot") or "__null__"
        if slot_key not in by_slot:
            by_slot[slot_key] = []
        by_slot[slot_key].append(s)

    slots = []
    for slot_key, saves in by_slot.items():
        saves.sort(key=lambda s: s["created_at"], reverse=True)
        slots.append({
            "slot": slot_key if slot_key != "__null__" else None,
            "count": len(saves),
            "latest": _save_to_response(saves[0]),
        })

    return jsonify({
        "total_count": sum(len(v) for v in by_slot.values()),
        "slots": slots,
    })


# ---------------------------------------------------------------------------
# Save Download (GET /api/saves/{id}/content)
# ---------------------------------------------------------------------------

@app.route("/api/saves/<int:save_id>/content", methods=["GET"])
def download_save(save_id):
    device_id = request.args.get("device_id")
    session_id = request.args.get("session_id")
    optimistic = request.args.get("optimistic", "true").lower() == "true"

    save = SAVES.get(save_id)
    if save is None:
        return jsonify({"detail": "Save not found"}), 404

    log_request(f"GET /api/saves/{save_id}/content", {
        "device_id": device_id,
        "session_id": session_id,
        "optimistic": optimistic,
        "file_name": save["file_name"],
    })

    # Optimistic mode: mark device as current
    if device_id and optimistic:
        now = datetime.now(timezone.utc).isoformat()
        _update_device_sync(save, device_id, now)

    filepath = STORAGE_DIR / f"{save_id}_{save['file_name']}"
    if not filepath.exists():
        return jsonify({"detail": "File missing from filesystem"}), 500

    return send_file(filepath, as_attachment=True, download_name=save["file_name"])


# ---------------------------------------------------------------------------
# Confirm Download (POST /api/saves/{id}/downloaded)
# ---------------------------------------------------------------------------

@app.route("/api/saves/<int:save_id>/downloaded", methods=["POST"])
def confirm_downloaded(save_id):
    data = request.json or {}
    device_id = data.get("device_id")

    save = SAVES.get(save_id)
    if save is None:
        return jsonify({"detail": "Save not found"}), 404

    log_request(f"POST /api/saves/{save_id}/downloaded", {"device_id": device_id})

    now = datetime.now(timezone.utc).isoformat()
    _update_device_sync(save, device_id, now)

    return jsonify(_save_to_response(save))


# ---------------------------------------------------------------------------
# Save Delete (POST /api/saves/delete)
# ---------------------------------------------------------------------------

@app.route("/api/saves/delete", methods=["POST"])
def delete_saves():
    data = request.json or {}
    ids = data.get("saves", [])

    log_request("POST /api/saves/delete", {"save_ids": ids})

    deleted = []
    for save_id in ids:
        save = SAVES.get(save_id)
        if save:
            filepath = STORAGE_DIR / f"{save_id}_{save['file_name']}"
            if filepath.exists():
                filepath.unlink()
            del SAVES[save_id]
            deleted.append(save_id)

    return jsonify(deleted)


# ---------------------------------------------------------------------------
# Sync Negotiate (POST /api/sync/negotiate)
# ---------------------------------------------------------------------------

@app.route("/api/sync/negotiate", methods=["POST"])
def sync_negotiate():
    global NEXT_SESSION_ID
    data = request.json or {}
    device_id = data.get("device_id")
    client_saves = data.get("saves", [])

    log_request("POST /api/sync/negotiate", {
        "device_id": device_id,
        "client_saves_count": len(client_saves),
    })

    session_id = NEXT_SESSION_ID
    NEXT_SESSION_ID += 1

    operations = []
    for cs in client_saves:
        rom_id = str(cs.get("rom_id"))
        slot = cs.get("slot")
        client_hash = cs.get("content_hash")
        client_updated = cs.get("updated_at")

        # Find matching server save
        server_save = None
        for s in SAVES.values():
            if str(s["rom_id"]) == rom_id and s.get("slot") == slot:
                server_save = s
                break

        if server_save is None:
            operations.append({
                "action": "upload",
                "rom_id": rom_id,
                "save_id": None,
                "file_name": cs.get("file_name", "unknown"),
                "slot": slot,
                "emulator": cs.get("emulator"),
                "reason": "No save exists on server",
                "server_updated_at": None,
                "server_content_hash": None,
            })
        elif server_save.get("content_hash") == client_hash:
            operations.append({
                "action": "no_op",
                "rom_id": rom_id,
                "save_id": server_save["id"],
                "file_name": server_save["file_name"],
                "slot": slot,
                "emulator": server_save.get("emulator"),
                "reason": "Content hashes match",
                "server_updated_at": server_save["updated_at"],
                "server_content_hash": server_save["content_hash"],
            })
        else:
            operations.append({
                "action": "download",
                "rom_id": rom_id,
                "save_id": server_save["id"],
                "file_name": server_save["file_name"],
                "slot": slot,
                "emulator": server_save.get("emulator"),
                "reason": "Server has newer content",
                "server_updated_at": server_save["updated_at"],
                "server_content_hash": server_save["content_hash"],
            })

    now = datetime.now(timezone.utc).isoformat()
    session = {
        "id": session_id,
        "device_id": device_id,
        "user_id": 1,
        "status": "pending",
        "initiated_at": now,
        "completed_at": None,
        "operations_planned": len(operations),
        "operations_completed": 0,
        "operations_failed": 0,
        "error_message": None,
        "created_at": now,
        "updated_at": now,
    }
    SYNC_SESSIONS[session_id] = session

    return jsonify({
        "session_id": session_id,
        "operations": operations,
        "total_upload": sum(1 for o in operations if o["action"] == "upload"),
        "total_download": sum(1 for o in operations if o["action"] == "download"),
        "total_conflict": sum(1 for o in operations if o["action"] == "conflict"),
        "total_no_op": sum(1 for o in operations if o["action"] == "no_op"),
    })


# ---------------------------------------------------------------------------
# Debug endpoints
# ---------------------------------------------------------------------------

@app.route("/debug/saves", methods=["GET"])
def debug_saves():
    return jsonify({sid: _save_to_response(s) for sid, s in SAVES.items()})


@app.route("/debug/log", methods=["GET"])
def debug_log():
    return jsonify(REQUEST_LOG)


@app.route("/debug/clear", methods=["POST"])
def debug_clear():
    global NEXT_SAVE_ID, NEXT_SESSION_ID, SAVES, REQUEST_LOG, DEVICES, SYNC_SESSIONS
    SAVES = {}
    DEVICES = {}
    SYNC_SESSIONS = {}
    REQUEST_LOG = []
    NEXT_SAVE_ID = 1
    NEXT_SESSION_ID = 1
    for f in STORAGE_DIR.iterdir():
        f.unlink()
    return jsonify({"status": "cleared"})


if __name__ == "__main__":
    print(f"Mock RomM Server v2 starting on http://127.0.0.1:5555")
    print(f"Storage: {STORAGE_DIR}")
    print(f"Matches RomM 4.9.0 API spec")
    print(f"\nEndpoints:")
    print(f"  POST   /api/saves              - Upload save")
    print(f"  GET    /api/saves               - List saves")
    print(f"  GET    /api/saves/summary        - Save summary by slot")
    print(f"  GET    /api/saves/<id>/content   - Download save")
    print(f"  POST   /api/saves/<id>/downloaded - Confirm download")
    print(f"  POST   /api/saves/delete        - Delete saves")
    print(f"  POST   /api/devices             - Register device")
    print(f"  POST   /api/sync/negotiate      - Negotiate sync")
    print(f"  GET    /api/heartbeat           - Capabilities")
    print(f"  GET    /debug/saves             - List all saves")
    print(f"  GET    /debug/log               - Request log")
    print(f"  POST   /debug/clear             - Clear everything")
    app.run(host="127.0.0.1", port=5555, debug=False)
