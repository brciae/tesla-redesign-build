"""Read-only validation of the real unsigned native build; not a device test."""
import hashlib
import json
import plistlib
import struct
import sys
import zipfile
from pathlib import Path
from pathlib import PurePosixPath

ipa_path = sys.argv[1]

def macho_info(data):
    assert data[:4] == bytes.fromhex("cffaedfe"), "Not a little-endian 64-bit Mach-O"
    cpu, subtype, kind, count, length, flags = struct.unpack_from("<6I", data, 4)
    assert cpu == 0x0100000C, "Expected device arm64"
    cursor, dependencies, platform = 32, [], None
    for _ in range(count):
        command, size = struct.unpack_from("<II", data, cursor)
        assert size >= 8 and cursor + size <= len(data)
        if command == 0x32:
            platform = struct.unpack_from("<I", data, cursor + 8)[0]
        if command in (0xC, 0x80000018, 0x8000001F):
            offset = struct.unpack_from("<I", data, cursor + 8)[0]
            dependencies.append(data[cursor + offset:cursor + size].split(b"\0")[0].decode())
        cursor += size
    assert platform in (None, 2), f"Not an iOS device slice: {platform}"
    return {"architecture": "arm64", "platform": platform, "dependencies": dependencies}

with zipfile.ZipFile(ipa_path) as archive:
    names = archive.namelist()
    retired = [n for n in names if '/recorded/' in n.lower() or 'onnxruntime' in n.lower()
               or n.lower().endswith(('.onnx', '/voiceenginelicense.txt'))]
    assert not retired, f"Retired voice resources/runtime still in IPA: {retired[:5]}"
    assert len(names) == len(set(names)), "Duplicate IPA entries"
    assert all(not PurePosixPath(n).is_absolute() and ".." not in PurePosixPath(n).parts for n in names)
    assert archive.testzip() is None, "ZIP integrity failure"
    app = "Payload/YLCompanion.app/"
    info = plistlib.loads(archive.read(app + "Info.plist"))
    expected = json.loads((Path(__file__).resolve().parent.parent / "Xcode/project.json").read_text(encoding="utf-8"))["settings"]["base"]
    assert info["CFBundleShortVersionString"] == str(expected["MARKETING_VERSION"]), "IPA version differs from requested source"
    assert info["CFBundleVersion"] == str(expected["CURRENT_PROJECT_VERSION"]), "IPA build differs from requested source"
    # The separator has to match tools/build-ios.sh, which names the artifact. It was changed there
    # from spaces to hyphens without this check following, and the build failed on its very last
    # line with a message that did not say what it had compared. Name both sides in the failure.
    expected_name = f"App-Tesla-{info['CFBundleShortVersionString']}-Build{info['CFBundleVersion']}-v01-Review.ipa"
    assert Path(ipa_path).name == expected_name, f"IPA filename version/build mismatch: {Path(ipa_path).name} != {expected_name}"
    home_source = (Path(__file__).resolve().parent.parent / "TeslaLocal.swiftpm/Sources/AppModule/HomeViews.swift").read_text(encoding="utf-8")
    assert "CFBundleShortVersionString" in home_source and "CFBundleVersion" in home_source, "Home must read its version from the installed bundle"
    assert "v0.73 (Build 73)" not in home_source, "Stale hard-coded home version"
    assert info["CFBundleExecutable"] == "YLCompanion"
    assert info.get("CFBundleIcons") or info.get("CFBundleIconFiles"), "App icon declaration missing"
    assert app + "Assets.car" in names, "Compiled icon catalog missing"
    assert any(n.startswith(app + "AppIcon") and n.endswith(".png") for n in names), "Generated app icon PNG missing"
    assert set(info["UIDeviceFamily"]) == {1, 2}
    assert info.get("NSBluetoothAlwaysUsageDescription")
    assert info.get("NSLocationWhenInUseUsageDescription")
    assert info.get("NSLocationAlwaysAndWhenInUseUsageDescription")
    assert info.get("NSLocationTemporaryUsageDescriptionDictionary", {}).get("NavigationAccuracy")
    assert set(info["UIBackgroundModes"]) == {"bluetooth-central", "location", "audio"}
    assert len(info["UISupportedInterfaceOrientations"]) == 4
    assert len(info["UISupportedInterfaceOrientations~ipad"]) == 4
    binaries = {"YLCompanion": app + "YLCompanion"}
    for framework in ("KakaoNavigationBridge", "KNSDK", "KNSDKCore", "KMLocationSDK"):
        binaries[framework] = app + f"Frameworks/{framework}.framework/{framework}"
    binary_results = {name: macho_info(archive.read(member)) for name, member in binaries.items()}
    assert any("KakaoNavigationBridge" in dep for dep in binary_results["YLCompanion"]["dependencies"])
    assert any("KNSDK.framework" in dep for dep in binary_results["KakaoNavigationBridge"]["dependencies"])
    privacy_files = [n for n in names if n.endswith("PrivacyInfo.xcprivacy")]
    assert privacy_files, "No SDK privacy manifests included"
    with open(ipa_path, "rb") as stream:
        checksum = hashlib.file_digest(stream, "sha256").hexdigest()
    result = {
        "native_package_check": "PASS", "device_install_test": "NOT_RUN",
        "signing": "Unsigned CI output; local Apple account re-sign required",
        "bundle_id": info["CFBundleIdentifier"], "version": info["CFBundleShortVersionString"],
        "build": info["CFBundleVersion"],
        "entries": len(names), "sha256": checksum, "binaries": binary_results,
        "privacy_manifests": privacy_files,
        "app_icon_declared": bool(info.get("CFBundleIcons") or info.get("CFBundleIconFiles"))
    }
    print(json.dumps(result, ensure_ascii=False, indent=2))
