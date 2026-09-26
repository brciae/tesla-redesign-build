const fs = require('node:fs');
const assert = require('node:assert/strict');
const root = 'TeslaLocal.swiftpm/Sources/AppModule/';
// Existing bindings remain scoped; rendering is restricted by the shared opt-in policy.
// OS camera, sharing, file/permission pickers are intentionally outside app narration.
const screens = {
  'FleetInsightsView.swift': ['FleetInsightsView'],
  'App.swift': ['DriveView','BriefingView','TripsView','TripListView','BatteryView','ChargeListView','ChargeForm'],
  'HomeViews.swift': ['HomeView','LocationStatusView','ChargeStatusView','SecurityStatusView','EnergyTabRootView','MenuTabRootView'],
  'ManagementViews.swift': ['CareView','ParkingHistoryView','MaintenanceForm','ParkingForm'],
  'AutomationViews.swift': ['AutomationDashboard','AutomationRuleEditor','AutomationHistory','AutomationImportView','AutomationAIView'],
  'VehicleAppearanceView.swift': ['VehicleAppearanceView'],
  'TypecastCharacterPickerSheet.swift': ['TypecastCharacterPickerSheet'],
  'TeslaInteractiveControlsView.swift': ['TeslaInteractiveControlsView'],
  'TeslaInteractiveClimateView.swift': ['TeslaInteractiveClimateView'],
  'ChargingWorkspace.swift': ['ChargingWorkspace'],
  'DrivingWorkspace.swift': ['DrivingWorkspace'],
  'EmbeddedNavigation.swift': ['EmbeddedNavigationScreen','NavigationSetupView'],
  'SmartParkingCard.swift': ['SmartParkingCard'],
  'HomeModules.swift': ['HomeLayoutEditor']
};
let count = 0;
for (const [file, names] of Object.entries(screens)) {
  const source = fs.readFileSync(root + file, 'utf8');
  for (const name of names) {
    const start = source.indexOf(`struct ${name}:`);
    assert(start >= 0, `${file}: missing ${name}; update coverage inventory`);
    const next = source.slice(start + 7).search(/\n(?:private )?struct /);
    const body = source.slice(start, next < 0 ? undefined : start + 7 + next);
    assert(/(?:ScreenBriefingControls\(scope:|LocalBriefingControls\(title:|PageBody\([^\n]+briefing:)/.test(body), `${name} has no scoped briefing`);
    count++;
  }
}
for (const [file, marker] of [
  ['TeslaInteractiveControlsView.swift','LocalBriefingControls(title: "토큰 발급 안내")'],
  ['App.swift','PageBody(title: "차량 3D", briefing: .vehicle3D)']
]) assert(fs.readFileSync(root+file,'utf8').includes(marker), `Missing nested screen: ${marker}`);
for (const file of fs.readdirSync(root).filter(x=>x.endsWith('.swift'))) {
  const source = fs.readFileSync(root+file,'utf8');
  assert(!source.includes('ScreenBriefingControls(screen:'), `${file}: title-based dispatch returned`);
  for (const match of source.matchAll(/PageBody\(([^\n]*)/g)) assert(match[1].includes('briefing:'), `${file}: unscoped PageBody`);
}
const speech = fs.readFileSync(root+'ScreenBriefingText.swift','utf8');
assert(!/default\s*:/.test(speech), 'Unknown screens must not inherit a global briefing');
assert(!speech.includes('clearCache'), 'Briefing must preserve voice caches');
const home = require('../'+root+'Resources/home.js');
for (const [state, expected] of [[5,true],[3,false],[0,null],[undefined,null]]) {
  assert.equal(home.presentation({groups:{charge:{charging:state}}}).charge.isCharging, expected, 'BLE charging enum must not be treated as Bool');
}
console.log(`PASS: ${count} view structures + 4 nested screens; explicit scoped bindings (source audit, not rendered UI QA)`);

const scoped = fs.readFileSync(root+'ScreenBriefing.swift','utf8');
assert(scoped.includes('if scope.supportsSpeech'), 'Settings/menu scopes must not render voice controls');
const local = fs.readFileSync(root+'LocalBriefingControls.swift','utf8');
assert(local.includes('].contains(title)'), 'Local editor voice controls must be opt-in');
assert(!fs.readFileSync(root+'DrivingWorkspace.swift','utf8').includes('announceDashboardStart('), 'Opening a dashboard must be silent');
assert(fs.readFileSync(root+'VoiceCoordinator.swift','utf8').includes('guard category != "voiceControl"'), 'Routine command/selection acknowledgements must stay visual');
assert(!speech.includes('connectedFacts'), 'Do not mechanically join sentences');
