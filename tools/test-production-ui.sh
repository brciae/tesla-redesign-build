#!/bin/bash
set -euo pipefail
device_id="$(xcrun simctl list devices available -j | python3 -c 'import json,sys; print(next(v["udid"] for a in json.load(sys.stdin)["devices"].values() for v in a if v["isAvailable"] and v["name"].startswith("iPhone")))')"
test_status=0
test_filter=(-only-testing:ProductionReviewTests)
if [[ "${1:-all}" == backup ]]; then
  test_filter=(
    -only-testing:ProductionReviewTests/ProductionReviewTests/testMenuHierarchy
    -only-testing:ProductionReviewTests/ProductionReviewTests/testNASRecordSync
    -only-testing:ProductionReviewTests/ProductionReviewTests/testNASConnectionHelp
    -only-testing:ProductionReviewTests/ProductionReviewTests/testOfflineMapHelp
    -only-testing:ProductionReviewTests/ProductionReviewTests/testCoverage
    -only-testing:ProductionReviewTests/ProductionReviewTests/testImportPreview
    -only-testing:ProductionReviewTests/ProductionReviewTests/testBatterySummary
    -only-testing:ProductionReviewTests/ProductionReviewTests/testNavigationSettings
    -only-testing:ProductionReviewTests/ProductionReviewTests/testDriving
    -only-testing:ProductionReviewTests/ProductionReviewTests/testDrivingFocus
  )
fi
xcodebuild test -project Xcode/YLCompanion.xcodeproj -scheme YLCompanion \
  -destination "platform=iOS Simulator,id=$device_id" -destination-timeout 90 \
  -derivedDataPath Xcode/ProductionDerivedData -resultBundlePath Xcode/ProductionResults.xcresult \
  -clonedSourcePackagesDirPath Xcode/SourcePackages -disableAutomaticPackageResolution \
  "${test_filter[@]}" -parallel-testing-enabled NO \
  CODE_SIGNING_ALLOWED=YES CODE_SIGNING_REQUIRED=YES CODE_SIGN_IDENTITY=- || test_status=$?
mkdir -p Xcode/BuildOutput/InterfaceScreens/Production
xcrun xcresulttool export attachments --path Xcode/ProductionResults.xcresult --output-path Xcode/BuildOutput/InterfaceScreens/Production || true
xcrun xcresulttool get test-results summary --path Xcode/ProductionResults.xcresult > Xcode/BuildOutput/InterfaceScreens/Production/summary.json || true
exit "$test_status"
