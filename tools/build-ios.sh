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
xcrun swiftc -frontend -parse TeslaLocal.swiftpm/Sources/AppModule/*.swift
# The original artwork stays unchanged; asset layout adds a 5% margin on each side.
node tools/js-logic-tests.cjs
swift tools/prepare-icon.swift
swiftc TeslaLocal.swiftpm/Sources/AppModule/VehicleUnits.swift tools/native-policy-tests.swift -o Xcode/NativePolicyTests
Xcode/NativePolicyTests
swiftc TeslaLocal.swiftpm/Sources/AppModule/AutomationPolicy.swift TeslaLocal.swiftpm/Sources/AppModule/AutomationTransfer.swift tools/automation-policy-tests.swift -o Xcode/AutomationPolicyTests
Xcode/AutomationPolicyTests
bash tools/test-interface.sh
bash tools/test-voice-engine.sh
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
artifact_path="$repo_root/Xcode/BuildOutput/App-Tesla iPhone v65 OAuth.ipa"
ditto -c -k --keepParent "$stage_dir/Payload" "$artifact_path"
unzip -t "$artifact_path"
shasum -a 256 "$artifact_path"
python3 tools/inspect-ipa.py "$artifact_path"
echo "UNSIGNED build created. Local re-signing and actual iPhone installation are still unverified."
