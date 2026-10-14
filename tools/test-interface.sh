#!/bin/bash
set -euo pipefail
swift tools/prepare-icon.swift
python3 tools/prepare-music-probe.py
python3 -m http.server 18757 --bind 127.0.0.1 --directory Xcode/BuildOutput/MusicProbe > Xcode/BuildOutput/MusicProbe/server.log 2>&1 &
music_probe_pid=$!
trap 'kill "$music_probe_pid" 2>/dev/null || true' EXIT
xcodegen generate --spec Xcode/InterfaceProbe.json --project Xcode
# Pick an installed available iPhone simulator, not a guessed model/runtime identifier.
device_id="$(xcrun simctl list devices available -j | python3 -c 'import json,sys; d=json.load(sys.stdin); print(next(v["udid"] for a in d["devices"].values() for v in a if v["isAvailable"] and v["name"].startswith("iPhone")))')"
test_filter=(-only-testing:InterfaceProbeTests)
if [[ "${1:-}" == fullscreen ]]; then
  test_filter=(-only-testing:InterfaceProbeTests/InteractionTests/testFullscreenChromeAcrossThemesAndRotation)
elif [[ "${1:-}" == junction ]]; then
  test_filter=(-only-testing:InterfaceProbeTests/InteractionTests/testJunctionStaysInGuidanceAndDisappearsAfterExit)
elif [[ "${1:-}" == new ]]; then
  test_filter=(
      -only-testing:InterfaceProbeTests/InteractionTests/testTripEnergyForecastAcrossThemesAndRotation
      -only-testing:InterfaceProbeTests/InteractionTests/testTripRecordSummaryAndSelectedComparison
      -only-testing:InterfaceProbeTests/InteractionTests/testContextSpeechSettingsAndRoutineOmission
    -only-testing:InterfaceProbeTests/InteractionTests/testBatteryBaselineAndPeriods
    -only-testing:InterfaceProbeTests/InteractionTests/testHomeChargingRadiusAndDatedSave
    -only-testing:InterfaceProbeTests/InteractionTests/testChargingFourTimeBands
    -only-testing:InterfaceProbeTests/InteractionTests/testAttachmentDownsampleAndMalformedInput
    -only-testing:InterfaceProbeTests/InteractionTests/testPlaybackSourceIconsAcrossThemesAndSourceChanges
    -only-testing:InterfaceProbeTests/InteractionTests/testActualLiveActivityExtensionOnHomeScreen
    -only-testing:InterfaceProbeTests/InteractionTests/testAudioSettingsInterruptionsPreemptionAndRecovery
    -only-testing:InterfaceProbeTests/InteractionTests/testRoundaboutSymbol
    -only-testing:InterfaceProbeTests/InteractionTests/testDashboardShadeSliderAndWhiteGuidance
    -only-testing:InterfaceProbeTests/InteractionTests/testJunctionStaysInGuidanceAndDisappearsAfterExit
    -only-testing:InterfaceProbeTests/InteractionTests/testLiveActivityViewsAndBackgroundReturn
    -only-testing:InterfaceProbeTests/InteractionTests/testRobotWithoutFootRodsSurvivesAppSwitching
    -only-testing:InterfaceProbeTests/InteractionTests/testTrafficRefreshBlocksRepeatedTapAndKeepsRouteOnFailure
  )
fi
test_status=0
xcodebuild test -project Xcode/InterfaceProbe.xcodeproj -scheme InterfaceProbe \
  -destination "platform=iOS Simulator,id=$device_id" -destination-timeout 90 \
  -derivedDataPath Xcode/ProbeDerivedData -resultBundlePath Xcode/InterfaceResults.xcresult \
  -retry-tests-on-failure -test-iterations 2 \
  "${test_filter[@]}" -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO || test_status=$?
mkdir -p Xcode/BuildOutput/InterfaceScreens
xcrun simctl spawn "$device_id" log show --last 30m --style compact --predicate '(process == "chronod" OR process == "liveactivitiesd" OR process == "SpringBoard" OR process == "ProbeLiveActivity") AND (eventMessage CONTAINS[c] "ylcompanion" OR eventMessage CONTAINS[c] "error" OR eventMessage CONTAINS[c] "widget")' > Xcode/BuildOutput/InterfaceScreens/live-activity-system.log 2>&1 || true
for info in Xcode/ProbeDerivedData/Build/Products/Debug-iphonesimulator/InterfaceProbe.app/Info.plist Xcode/ProbeDerivedData/Build/Products/Debug-iphonesimulator/InterfaceProbe.app/PlugIns/ProbeLiveActivity.appex/Info.plist; do
  if [ -f "$info" ]; then
    echo "$info" >> Xcode/BuildOutput/InterfaceScreens/live-activity-bundles.log
    plutil -p "$info" >> Xcode/BuildOutput/InterfaceScreens/live-activity-bundles.log
  fi
done
xcrun xcresulttool export attachments --path Xcode/InterfaceResults.xcresult --output-path Xcode/BuildOutput/InterfaceScreens
if [ "$test_status" -ne 0 ]; then
  xcrun xcresulttool export diagnostics --path Xcode/InterfaceResults.xcresult --output-path Xcode/BuildOutput/InterfaceScreens/Diagnostics || true
  exit "$test_status"
fi
echo 'PASS: Simulator navigation themes, rotation, unknown state, Form actions and independent tab roots'
