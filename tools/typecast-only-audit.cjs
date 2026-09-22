const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const root = path.resolve(__dirname, '..');
const app = path.join(root, 'TeslaLocal.swiftpm/Sources/AppModule');
const forbidden = /\b(?:AVSpeechSynthesizer|AVSpeechUtterance|AVSpeechSynthesisVoice|RecordedVoice|OfflineSpeechEngine|OfflineVoicePack|VoicePackManifest|VoiceLibrary|VoiceProfile|VoicePlaybackEngine|OnnxRuntimeBindings)\b/;
for (const file of fs.readdirSync(app).filter(f => f.endsWith('.swift'))) {
  const text = fs.readFileSync(path.join(app, file), 'utf8');
  assert(!forbidden.test(text), `Legacy voice path in ${file}`);
  if (/AVAudioPlayer\s*\(/.test(text)) {
    assert(['TypecastClient.swift', 'VoiceCoordinator.swift'].includes(file), `Unexpected playback path in ${file}`);
  }
}
assert(!fs.existsSync(path.join(app, 'Resources/recorded')), 'Recorded data still present');
const project = JSON.parse(fs.readFileSync(path.join(root, 'Xcode/project.json')));
assert(!project.packages.onnxruntime, 'Retired inference runtime still linked');
assert(!JSON.stringify(project.targets.YLCompanion).match(/Resources\/recorded|VoiceEngineLicense|onnxruntime/));
const bridge = fs.readFileSync(path.join(root, 'TeslaLocal.swiftpm/Sources/KakaoNavigationBridge/YLKakaoController.m'), 'utf8');
const start = bridge.indexOf('- (BOOL)guidance:(KNGuidance *)guidance shouldPlayVoiceGuide:');
assert(start >= 0, 'Missing SDK voice gate');
const end = bridge.indexOf('\n}', start);
assert(end > start, 'Missing SDK voice gate boundary');
const guide = bridge.slice(start, end);
assert(guide.includes('spokenGuide') && guide.includes('return NO;'), 'SDK must forward text without playing its own speech');
assert(!guide.includes('return YES;'), 'SDK speech must stay disabled');
console.log('PASS: Typecast-only source, resources, runtime dependencies and navigation speech routing');
