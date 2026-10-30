"""Allowlisted, time-bound dashboard projection. No position, history, raw payloads or commands."""
import json
import math
from datetime import datetime, timezone
from pathlib import Path

FIELDS = {"Soc": ("배터리", "%", 0, 100), "VehicleSpeed": ("속도", "km/h", 0, 400),
          "Gear": ("기어", "", None, None), "ChargerPower": ("충전 전력", "kW", 0, 1000)}
ASSETS = {"/dashboard": ("dashboard.html", "text/html; charset=utf-8"),
          "/dashboard.js": ("dashboard.js", "text/javascript; charset=utf-8"),
          "/dashboard.css": ("dashboard.css", "text/css; charset=utf-8")}


def asset(route):
    name, content_type = ASSETS[route]
    return (Path(__file__).parent / name).read_bytes(), content_type


def timestamp(payload):
    value = payload.get("createdAt", payload.get("created_at"))
    try:
        if isinstance(value, str):
            parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
            if parsed.tzinfo is None:
                return None
            return parsed.timestamp()
        if isinstance(value, dict):
            seconds = float(value["seconds"])
            return seconds if math.isfinite(seconds) else None
    except (ValueError, TypeError, KeyError, OverflowError):
        pass
    return None


def snapshot(archive, vin, now):
    latest, seen, size = {}, 0, 0
    with archive.connect() as db:
        cursor = db.execute("SELECT payload FROM events WHERE vin=? AND kind='tesla_V' AND valid=1 ORDER BY id DESC LIMIT 1000", (vin,))
        for (raw,) in cursor:
            size += len(raw.encode())
            if size > 8_000_000:
                break
            seen += 1
            payload = json.loads(raw)
            at = timestamp(payload)
            if at is None or at <= 0:
                continue
            for item in payload.get("data", []):
                if not isinstance(item, dict) or item.get("key") not in FIELDS:
                    continue
                key = item["key"]
                if key in latest and at <= latest[key]["at"]:
                    continue
                value = item.get("value", {})
                status, number = "invalid", None
                if isinstance(value, dict) and value.get("invalid") is not True:
                    if key == "Gear":
                        gear = value.get("shiftStateValue", value.get("stringValue"))
                        number = {"P": "P", "R": "R", "N": "N", "D": "D", "ShiftStateP": "P", "ShiftStateR": "R", "ShiftStateN": "N", "ShiftStateD": "D"}.get(gear) if isinstance(gear, str) else None
                    else:
                        candidate = next((value[k] for k in ("doubleValue", "floatValue", "intValue", "longValue") if k in value), None)
                        try:
                            number = None if isinstance(candidate, bool) else float(candidate)
                            if key == "VehicleSpeed" and number is not None:
                                number *= 1.609344  # Fleet VehicleSpeed is mph; never infer another speed field's units.
                            low, high = FIELDS[key][2:]
                            if number is not None and (not math.isfinite(number) or not low <= number <= high):
                                number = None
                        except (ValueError, TypeError, OverflowError):
                            number = None
                    if number is not None:
                        status = "recent" if -5 <= now - at <= 120 else "stale"
                latest[key] = {"at": at, "status": status, "value": number if status == "recent" else None}
    fields = []
    for key, (label, unit, _, _) in FIELDS.items():
        entry = latest.get(key, {"at": None, "status": "missing", "value": None})
        fields.append({"key": key, "label": label, "unit": unit, **entry})
    return {"fields": fields, "received_at": now, "coverage": "bounded", "examined_packets": seen,
            "note": "120초 이내 관측만 표시 · 위치·차량 명령·전체 기록은 제공하지 않음"}
