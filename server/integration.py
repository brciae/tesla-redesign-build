"""Synthetic single-vehicle smoke test inside the isolated archive container."""
import json
import time
import urllib.request
from pathlib import Path
from confluent_kafka import Producer

vin = "LRWYGCEK0NC000001"
event = {"vin": vin, "createdAt": "2026-01-01T10:00:00Z",
         "data": [{"key": "Soc", "value": {"doubleValue": 42}}]}
producer = Producer({"bootstrap.servers": "kafka:9092", "acks": "all"})
for _ in range(2):
    producer.produce("tesla_V", key=vin, value=json.dumps(event))
assert producer.flush(30) == 0, "queue did not drain"
token = Path("/data/api-token").read_text().strip()
request = urllib.request.Request("http://127.0.0.1:8787/v1/telemetry?vin=" + vin,
                                 headers={"Authorization": "Bearer " + token})
for attempt in range(30):
    with urllib.request.urlopen(request, timeout=5) as response:
        page = json.load(response)
    if page["payloads"]:
        assert page["payloads"] == [event], "duplicate, timestamp or payload mismatch"
        print("archive delivery/replay/isolation smoke PASS")
        break
    time.sleep(1)
else:
    raise AssertionError("event was not stored within 30 seconds")
