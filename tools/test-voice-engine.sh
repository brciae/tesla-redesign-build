#!/bin/bash
set -euo pipefail
mkdir -p Xcode/BuildOutput
python3 tools/prepare-voice-probe.py
xcodegen generate --spec Xcode/VoiceProbe.json --project Xcode
xcodebuild -project Xcode/VoiceProbe.xcodeproj -scheme VoiceProbe -configuration Release -destination 'platform=macOS' -derivedDataPath Xcode/VoiceProbeDerivedData -clonedSourcePackagesDirPath Xcode/SourcePackages CODE_SIGNING_ALLOWED=NO build
Xcode/VoiceProbeDerivedData/Build/Products/Release/VoiceProbe "$PWD/Xcode/VoiceProbeData" "$PWD/Xcode/BuildOutput"
