"""Check explicit coverage against the pinned SDK headers, without credentials."""
import re
import sys
import zipfile
from pathlib import Path

root = Path(__file__).resolve().parent.parent
bridge = (root / "TeslaLocal.swiftpm/Sources/KakaoNavigationBridge/YLKakaoController.m").read_text(encoding="utf-8")
with zipfile.ZipFile(sys.argv[1]) as archive:
    for header, prefix in [("KNGuide_Voice.h", "KNVoiceCode_"), ("KNSafety.h", "KNSafetyCode_")]:
        source = archive.read(next(n for n in archive.namelist() if n.endswith("/" + header))).decode("utf-8")
        entries = re.findall(r"^\s*(" + prefix + r"\w+)\s*(?:=\s*(\d+))?\s*,?", source, re.M)
        missing = []
        for name, value in entries:
            covered = ("case " + name + ":") in bridge if prefix == "KNVoiceCode_" else bool(re.search(r"@" + value + r"\s*:", bridge))
            if not covered:
                missing.append(name)
        assert entries and not missing, (header, missing)
        print(f"PASS: {header}: {len(entries)} explicitly handled entries")
