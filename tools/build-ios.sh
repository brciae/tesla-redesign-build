#!/bin/bash
# Native macOS/Xcode build only. No signing credentials or vehicle connection.
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"
if [[ "$(uname -s)" != Darwin ]]; then
  echo "This build requires macOS with Xcode; source tests on Windows are not a native build." >&2
  exit 2
fi
# v43: the recorded voice packs outgrew a single upload, so the source ships as source.zip plus
# part*.zip beside it. The workflow unpacks source.zip; the rest is unpacked here, before anything
# reads the resources.
for part in part*.zip; do
  [ -e "$part" ] || continue
  unzip -oq "$part"
done
command -v xcodegen >/dev/null
xcodebuild -version
xcodegen --version
node tools/embed-js.cjs
node tools/typecast-only-audit.cjs
node tools/briefing-coverage.cjs
node tools/control-path-audit.cjs
xcrun swiftc -frontend -parse TeslaLocal.swiftpm/Sources/AppModule/*.swift
xcrun clang -fobjc-arc -framework Foundation tools/navigation-speech-tests.m -o Xcode/NavigationSpeechTests
Xcode/NavigationSpeechTests
swiftc TeslaLocal.swiftpm/Sources/AppModule/TypecastAPIPolicy.swift tools/typecast-policy-tests.swift -o Xcode/TypecastPolicyTests
Xcode/TypecastPolicyTests
# The original artwork stays unchanged; asset layout adds a 5% margin on each side.
node tools/js-logic-tests.cjs
swiftc TeslaLocal.swiftpm/Sources/AppModule/FleetAuthPolicy.swift tools/fleet-auth-tests.swift -o Xcode/FleetAuthTests
Xcode/FleetAuthTests
swiftc TeslaLocal.swiftpm/Sources/AppModule/FleetCommandPolicy.swift tools/fleet-command-tests.swift -o Xcode/FleetCommandTests
Xcode/FleetCommandTests
swiftc TeslaLocal.swiftpm/Sources/AppModule/FleetVehicleSnapshot.swift tools/fleet-snapshot-tests.swift -o Xcode/FleetSnapshotTests
Xcode/FleetSnapshotTests
swift tools/prepare-icon.swift
swiftc TeslaLocal.swiftpm/Sources/AppModule/VehicleUnits.swift tools/native-policy-tests.swift -o Xcode/NativePolicyTests
Xcode/NativePolicyTests
swiftc TeslaLocal.swiftpm/Sources/AppModule/AutomationPolicy.swift TeslaLocal.swiftpm/Sources/AppModule/AutomationTransfer.swift tools/automation-policy-tests.swift -o Xcode/AutomationPolicyTests
Xcode/AutomationPolicyTests
swiftc TeslaLocal.swiftpm/Sources/AppModule/BriefingScope.swift TeslaLocal.swiftpm/Sources/AppModule/FleetVehicleSnapshot.swift TeslaLocal.swiftpm/Sources/AppModule/ScreenBriefingText.swift tools/screen-briefing-tests.swift -o Xcode/ScreenBriefingTests
Xcode/ScreenBriefingTests
swiftc TeslaLocal.swiftpm/Sources/AppModule/ParkingModels.swift tools/parking-record-tests.swift -o Xcode/ParkingRecordTests
Xcode/ParkingRecordTests
bash tools/test-interface.sh
xcodegen generate --spec Xcode/project.json --project Xcode
xcodebuild -resolvePackageDependencies \
  -project Xcode/YLCompanion.xcodeproj -scheme YLCompanion \
  -clonedSourcePackagesDirPath Xcode/SourcePackages
xcodebuild -project Xcode/YLCompanion.xcodeproj -scheme YLCompanion \
  -configuration Release -destination 'generic/platform=iOS' \
  -derivedDataPath Xcode/DerivedData \
  -clonedSourcePackagesDirPath Xcode/SourcePackages \
  -disableAutomaticPackageResolution \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY='' build

app_path="$repo_root/Xcode/DerivedData/Build/Products/Release-iphoneos/YLCompanion.app"
test -s "$app_path/YLCompanion"
test -s "$app_path/Info.plist"
# Keep the original app/framework bundles unchanged for the local signing tool.
# No codesign removal, binary rewriting, or signing bypass is performed here.
stage_dir="$(mktemp -d "$repo_root/Xcode/package.XXXXXX")"
mkdir "$stage_dir/Payload"
ditto "$app_path" "$stage_dir/Payload/YLCompanion.app"
mkdir -p "$repo_root/Xcode/BuildOutput"
app_version=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$app_path/Info.plist")
app_build=$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' "$app_path/Info.plist")
artifact_path="$repo_root/Xcode/BuildOutput/App-Tesla ${app_version} Build${app_build} v01 Review.ipa"
ditto -c -k --keepParent "$stage_dir/Payload" "$artifact_path"
unzip -t "$artifact_path"
shasum -a 256 "$artifact_path"
python3 tools/inspect-ipa.py "$artifact_path"
echo "UNSIGNED build created. Local re-signing and actual iPhone installation are still unverified."
