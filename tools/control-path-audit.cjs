const fs = require('node:fs');
const assert = require('node:assert/strict');
const read = name => fs.readFileSync(`TeslaLocal.swiftpm/Sources/AppModule/${name}.swift`, 'utf8');
const client = read('TeslaFleetClient');
assert(!client.includes('(res?["result"] as? Bool) ?? true'), 'Missing result must not become success');
assert(client.includes('FleetCommandPolicy.accepted(data)'));
assert(client.includes('FleetCommandRedirectGuard()'));
for (const name of ['HomeViews', 'ControlViews', 'ChargingWorkspace']) {
  assert(!read(name).includes('link.askControl('), `${name} bypasses shared transport selection`);
}
assert(!read('TeslaInteractiveClimateView').includes('try? await'), 'Climate must show failures');
assert(!/func pause\(\)[^\n]*stopSpeech/.test(read('AppModel')), 'Background entry must not stop audio');
assert(!/func (pause|resignActive)\(\)[^\n]*resetObservation/.test(read('AppModel')));
assert(read('AutomationCoordinator').includes('UIApplication.shared.applicationState == .active,\n'), 'Background speech must not unlock physical automation');
assert(read('VehicleCommandRouting').includes('guard !demo'));
console.log('PASS: control route/error/background source guards (not live vehicle verification)');
