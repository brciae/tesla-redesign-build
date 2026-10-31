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
node tools/project-source-tests.cjs
node tools/ui-copy-audit.cjs
node tools/typecast-only-audit.cjs
node tools/briefing-coverage.cjs
node tools/control-path-audit.cjs
mkdir -p Xcode/BuildOutput
swiftc TeslaLocal.swiftpm/Sources/AppModule/VoiceDiskCache.swift tools/voice-cache-tests.swift -o Xcode/VoiceCacheTests
Xcode/VoiceCacheTests
swiftc TeslaLocal.swiftpm/Sources/AppModule/AppEnergyPolicy.swift tools/energy-policy-tests.swift -o Xcode/EnergyPolicyTests
Xcode/EnergyPolicyTests
node tools/commercial-review-tests.cjs
swiftc TeslaLocal.swiftpm/Sources/AppModule/NavigationRecovery.swift TeslaLocal.swiftpm/Sources/AppModule/TripComparisonPolicy.swift TeslaLocal.swiftpm/Sources/AppModule/ChargingAvailabilityPolicy.swift TeslaLocal.swiftpm/Sources/AppModule/ChargeImportParser.swift TeslaLocal.swiftpm/Sources/AppModule/SharedDestinationInput.swift tools/commercial-review-policy-tests.swift -o Xcode/CommercialReviewTests
Xcode/CommercialReviewTests
node tools/energy-battery-regression-tests.cjs
node tools/collection-regression-tests.cjs
node tools/navigation-card-tests.cjs
swiftc TeslaLocal.swiftpm/Sources/AppModule/NavigationPipLifecycle.swift tools/navigation-pip-lifecycle-tests.swift -o Xcode/NavigationPipLifecycleTests
Xcode/NavigationPipLifecycleTests
swiftc TeslaLocal.swiftpm/Sources/AppModule/SpotifyPlaybackPolicy.swift tools/spotify-policy-tests.swift -o Xcode/SpotifyPolicyTests
Xcode/SpotifyPolicyTests
xcrun swiftc -frontend -parse TeslaLocal.swiftpm/Sources/AppModule/*.swift
swiftc Xcode/LiveActivityShared/NavigationCardFormat.swift Xcode/LiveActivityShared/GuidanceCardLabel.swift Xcode/LiveActivityShared/VehicleActivitySessionPolicy.swift tools/guidance-card-tests.swift -o Xcode/GuidanceCardTests
Xcode/GuidanceCardTests
swiftc TeslaLocal.swiftpm/Sources/AppModule/MediaPlaybackSource.swift tools/media-source-tests.swift -o Xcode/MediaSourceTests
Xcode/MediaSourceTests
swiftc TeslaLocal.swiftpm/Sources/AppModule/AttachmentSafety.swift tools/attachment-safety-tests.swift -o Xcode/AttachmentSafetyTests
Xcode/AttachmentSafetyTests
swiftc TeslaLocal.swiftpm/Sources/AppModule/VoiceGainPolicy.swift tools/voice-gain-tests.swift -o Xcode/VoiceGainTests
Xcode/VoiceGainTests
swiftc TeslaLocal.swiftpm/Sources/AppModule/NavigationRecovery.swift tools/navigation-recovery-tests.swift -o Xcode/NavigationRecoveryTests
Xcode/NavigationRecoveryTests
swiftc TeslaLocal.swiftpm/Sources/AppModule/NavigationRecovery.swift tools/vehicle-route-sync-tests.swift -o Xcode/VehicleRouteSyncTests
Xcode/VehicleRouteSyncTests
swiftc TeslaLocal.swiftpm/Sources/AppModule/TripEnergyPrediction.swift TeslaLocal.swiftpm/Sources/AppModule/TripEnergyStore.swift tools/trip-energy-tests.swift -o Xcode/TripEnergyTests
Xcode/TripEnergyTests
swiftc TeslaLocal.swiftpm/Sources/AppModule/TripComparisonPolicy.swift tools/trip-comparison-tests.swift -o Xcode/TripComparisonTests
Xcode/TripComparisonTests
swiftc TeslaLocal.swiftpm/Sources/AppModule/AutomationSpeechPolicy.swift tools/automation-speech-tests.swift -o Xcode/AutomationSpeechTests
Xcode/AutomationSpeechTests
swiftc TeslaLocal.swiftpm/Sources/AppModule/GuidanceJournal.swift tools/guidance-journal-tests.swift -o Xcode/GuidanceJournalTests
Xcode/GuidanceJournalTests
xcrun clang -fobjc-arc -framework Foundation tools/navigation-speech-tests.m -o Xcode/NavigationSpeechTests
Xcode/NavigationSpeechTests
swiftc TeslaLocal.swiftpm/Sources/AppModule/TypecastAPIPolicy.swift tools/typecast-policy-tests.swift -o Xcode/TypecastPolicyTests
Xcode/TypecastPolicyTests
# The original artwork stays unchanged; asset layout adds a 5% margin on each side.
node tools/js-logic-tests.cjs
node tools/battery-analysis-tests.cjs
node tools/data-consistency-tests.cjs
node tools/stability-runtime-tests.cjs
swiftc TeslaLocal.swiftpm/Sources/AppModule/LocalRuntime.swift TeslaLocal.swiftpm/Sources/AppModule/EmbeddedAppResources.swift tools/runtime-bridge-tests.swift -o Xcode/RuntimeBridgeTests
Xcode/RuntimeBridgeTests
swiftc TeslaLocal.swiftpm/Sources/AppModule/FleetTelemetryData.swift TeslaLocal.swiftpm/Sources/AppModule/ChargeEventPolicy.swift tools/telemetry-display-index-tests.swift -o Xcode/TelemetryDisplayIndexTests
Xcode/TelemetryDisplayIndexTests
swiftc TeslaLocal.swiftpm/Sources/AppModule/FleetTelemetryData.swift TeslaLocal.swiftpm/Sources/AppModule/ChargeEventPolicy.swift TeslaLocal.swiftpm/Sources/AppModule/FleetTelemetryJournal.swift tools/telemetry-journal-tests.swift -o Xcode/TelemetryJournalTests
Xcode/TelemetryJournalTests
node tools/gps-loss-tests.cjs
node tools/charge-integrity-tests.cjs
node tools/charge-cost-tests.cjs
node tools/published-tariff-tests.cjs
node tools/charge-enrichment-tests.cjs
node tools/history-endpoint-tests.cjs
node tools/free-drive-recording-tests.cjs
swiftc TeslaLocal.swiftpm/Sources/AppModule/EnergyCalendarAnalysis.swift tools/energy-calendar-tests.swift -o Xcode/EnergyCalendarTests
Xcode/EnergyCalendarTests
swiftc TeslaLocal.swiftpm/Sources/AppModule/FleetAuthPolicy.swift tools/fleet-auth-tests.swift -o Xcode/FleetAuthTests
Xcode/FleetAuthTests
swiftc TeslaLocal.swiftpm/Sources/AppModule/FleetCommandPolicy.swift tools/fleet-command-tests.swift -o Xcode/FleetCommandTests
Xcode/FleetCommandTests
swiftc TeslaLocal.swiftpm/Sources/AppModule/FleetVehicleSnapshot.swift TeslaLocal.swiftpm/Sources/AppModule/FleetSupplement.swift TeslaLocal.swiftpm/Sources/AppModule/PublicChargingData.swift tools/fleet-snapshot-tests.swift -o Xcode/FleetSnapshotTests
Xcode/FleetSnapshotTests
swiftc TeslaLocal.swiftpm/Sources/AppModule/FleetTelemetryData.swift TeslaLocal.swiftpm/Sources/AppModule/FleetParkingAnalysis.swift TeslaLocal.swiftpm/Sources/AppModule/OwnershipAnalysis.swift TeslaLocal.swiftpm/Sources/AppModule/ChargeEventPolicy.swift tools/fleet-telemetry-tests.swift -o Xcode/FleetTelemetryTests
Xcode/FleetTelemetryTests
swift tools/prepare-icon.swift
swiftc TeslaLocal.swiftpm/Sources/AppModule/VehicleUnits.swift tools/native-policy-tests.swift -o Xcode/NativePolicyTests
Xcode/NativePolicyTests
swiftc TeslaLocal.swiftpm/Sources/AppModule/AutomationPolicy.swift TeslaLocal.swiftpm/Sources/AppModule/AutomationTransfer.swift tools/automation-policy-tests.swift -o Xcode/AutomationPolicyTests
Xcode/AutomationPolicyTests
swiftc TeslaLocal.swiftpm/Sources/AppModule/VehicleUnits.swift TeslaLocal.swiftpm/Sources/AppModule/BriefingStyle.swift TeslaLocal.swiftpm/Sources/AppModule/AutomationPolicy.swift TeslaLocal.swiftpm/Sources/AppModule/AutomationTransfer.swift tools/speech-wording-tests.swift -o Xcode/SpeechWordingTests
Xcode/SpeechWordingTests
swiftc TeslaLocal.swiftpm/Sources/AppModule/AutomationAPI.swift tools/automation-api-tests.swift -o Xcode/AutomationAPITests
Xcode/AutomationAPITests
swiftc TeslaLocal.swiftpm/Sources/AppModule/ChargeEventPolicy.swift TeslaLocal.swiftpm/Sources/AppModule/BriefingScope.swift TeslaLocal.swiftpm/Sources/AppModule/FleetVehicleSnapshot.swift TeslaLocal.swiftpm/Sources/AppModule/ScreenBriefingText.swift tools/screen-briefing-tests.swift -o Xcode/ScreenBriefingTests
Xcode/ScreenBriefingTests
swiftc TeslaLocal.swiftpm/Sources/AppModule/ParkingModels.swift tools/parking-record-tests.swift -o Xcode/ParkingRecordTests
Xcode/ParkingRecordTests
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

if [[ "${RUN_INTERFACE_TESTS:-1}" == 1 ]]; then
  bash tools/test-production-ui.sh
  bash tools/test-interface.sh
fi

app_path="$repo_root/Xcode/DerivedData/Build/Products/Release-iphoneos/YLCompanion.app"
test -s "$app_path/YLCompanion"
test -s "$app_path/Info.plist"
# Seal every executable bundle before distribution; the installer must still
# re-sign app AND extension with its own Apple identity and provisioning profiles.
while IFS= read -r -d '' framework; do
  codesign --force --sign - --generate-entitlement-der "$framework"
done < <(find "$app_path/Frameworks" -depth -type d -name '*.framework' -print0)
codesign --force --sign - --generate-entitlement-der "$app_path/PlugIns/VehicleLiveActivity.appex"
codesign --force --sign - --generate-entitlement-der "$app_path"
codesign --verify --deep --strict --verbose=2 "$app_path"
stage_dir="$(mktemp -d "$repo_root/Xcode/package.XXXXXX")"
mkdir "$stage_dir/Payload"
ditto "$app_path" "$stage_dir/Payload/YLCompanion.app"
mkdir -p "$repo_root/Xcode/BuildOutput"
app_version=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$app_path/Info.plist")
app_build=$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' "$app_path/Info.plist")
artifact_path="$repo_root/Xcode/BuildOutput/App-Tesla-${app_version}-Build${app_build}-v01-Review.ipa"
ditto -c -k --keepParent "$stage_dir/Payload" "$artifact_path"
unzip -t "$artifact_path"
shasum -a 256 "$artifact_path"
python3 tools/inspect-ipa.py "$artifact_path"
echo "Ad-hoc integrity-sealed IPA created. Apple account re-signing/provisioning and actual iPhone installation are still unverified."
