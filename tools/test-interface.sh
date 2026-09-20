#!/bin/bash
set -euo pipefail
xcodegen generate --spec Xcode/InterfaceProbe.json --project Xcode
# Pick an installed available iPhone simulator, not a guessed model/runtime identifier.
device_id="$(xcrun simctl list devices available -j | python3 -c 'import json,sys; d=json.load(sys.stdin); print(next(v["udid"] for a in d["devices"].values() for v in a if v["isAvailable"] and v["name"].startswith("iPhone")))')"
test_status=0
xcodebuild test -project Xcode/InterfaceProbe.xcodeproj -scheme InterfaceProbe \
  -destination "platform=iOS Simulator,id=$device_id" -destination-timeout 90 \
  -derivedDataPath Xcode/ProbeDerivedData -resultBundlePath Xcode/InterfaceResults.xcresult \
  -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO || test_status=$?
mkdir -p Xcode/BuildOutput/InterfaceScreens
xcrun xcresulttool export attachments --path Xcode/InterfaceResults.xcresult --output-path Xcode/BuildOutput/InterfaceScreens
if [ "$test_status" -ne 0 ]; then
  xcrun xcresulttool export diagnostics --path Xcode/InterfaceResults.xcresult --output-path Xcode/BuildOutput/InterfaceScreens/Diagnostics || true
  exit "$test_status"
fi
echo 'PASS: Simulator navigation themes, rotation, unknown state, Form actions and independent tab roots'
