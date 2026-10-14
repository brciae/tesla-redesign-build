const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const base = path.resolve(__dirname, '../Xcode');
const probe = JSON.parse(fs.readFileSync(path.join(base,'InterfaceProbe.json'),'utf8'));
const declared = probe.targets.InterfaceProbe.sources.map(s=>path.resolve(base,typeof s==='string'?s:s.path));
const sharedSource = name => path.resolve(base, '../TeslaLocal.swiftpm/Sources/AppModule', name);
for (const source of ['TripEnergyPrediction.swift','TripEnergyStore.swift','TripEnergyPredictionView.swift', 'TripComparisonPolicy.swift', 'TripRecordComponents.swift', 'AutomationAPI.swift', 'AutomationSpeechPolicy.swift', 'AutomationContextSpeech.swift', 'ContextSpeechSettings.swift', 'GuidanceJournal.swift']) {
  assert.ok(declared.includes(sharedSource(source)), 'Trip energy shared UI dependency missing: '+source);
}
if (declared.includes(sharedSource('FleetTelemetryStore.swift'))) {
  assert.ok(declared.includes(sharedSource('FleetTelemetryJournal.swift')), 'Telemetry store requires its durable journal in the simulator target');
}
for(const file of fs.readdirSync(path.join(base,'InterfaceProbe')).filter(f=>f.endsWith('.swift')&&f!=='InteractionTests.swift')) {
  const actual = path.join(base,'InterfaceProbe',file);
  assert.ok(declared.some(p=>p===actual || fs.statSync(p).isDirectory()&&actual.startsWith(p+path.sep)), 'Unregistered probe source '+file);
}
const project = JSON.parse(fs.readFileSync(path.join(base,'project.json'),'utf8'));
const app=project.targets.YLCompanion,ext=project.targets.VehicleLiveActivity;
assert.equal(app.info.properties.NSSupportsLiveActivities,true);
assert.ok(app.dependencies.some(d=>d.target==='VehicleLiveActivity'&&d.embed));
assert.equal(ext.settings.base.PRODUCT_BUNDLE_IDENTIFIER,app.settings.base.PRODUCT_BUNDLE_IDENTIFIER+'.liveactivity');
console.log('PASS: explicit simulator source registration, live activity extension identity and embedding');
