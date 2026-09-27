const fs = require('node:fs');
const assert = require('node:assert/strict');
const root = 'TeslaLocal.swiftpm/Sources/AppModule/';
// Existing bindings remain scoped; rendering is restricted by the shared opt-in policy.
// OS camera, sharing, file/permission pickers are intentionally outside app narration.
const screens = {
  'FleetInsightsView.swift': ['FleetInsightsView'],
  'App.swift': ['BriefingView','TripsView','TripListView','BatteryView','ChargeListView','ChargeForm'],
  // v90: EnergyTabRootView is a plain segment container now — its 배터리 분석
  // segment shows BatteryView, which carries the .batteryAndCharging briefing.
  'HomeViews.swift': ['HomeView','LocationStatusView','ChargeStatusView','SecurityStatusView','MenuTabRootView'],
  'ManagementViews.swift': ['CareView','ParkingHistoryView','MaintenanceForm','ParkingForm'],
  'AutomationViews.swift': ['AutomationDashboard','AutomationRuleEditor','AutomationHistory','AutomationImportView','AutomationAIView'],
  'VehicleAppearanceView.swift': ['VehicleAppearanceView'],
  'TypecastCharacterPickerSheet.swift': ['TypecastCharacterPickerSheet'],
  'TeslaInteractiveControlsView.swift': ['TeslaInteractiveControlsView'],
  'TeslaInteractiveClimateView.swift': ['TeslaInteractiveClimateView'],
  'ChargingWorkspace.swift': ['ChargingWorkspace'],
  'DrivingWorkspace.swift': ['DrivingWorkspace'],
  'EmbeddedNavigation.swift': ['EmbeddedNavigationScreen','NavigationSetupView'],
  'SmartParkingCard.swift': ['SmartParkingCard']
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
  ['TeslaInteractiveControlsView.swift','LocalBriefingControls(title: "토큰 발급 안내")']
]) assert(fs.readFileSync(root+file,'utf8').includes(marker), `Missing nested screen: ${marker}`);

// v90: the duplicate-entry-point audit, kept as a check so the menus cannot grow
// a second door to the same screen again. Every Page must be routed exactly once
// in destinationView, listed at most once in the 메뉴 tab, and reachable at all.
{
  const app = fs.readFileSync(root + 'App.swift', 'utf8');
  const enumBody = app.slice(app.indexOf('enum Page: String, Hashable {'), app.indexOf('func valueText('));
  const cases = [...enumBody.matchAll(/case ([A-Za-z0-9]+) =/g)].map(m => m[1])
    .concat([...enumBody.matchAll(/, ([A-Za-z0-9]+) =/g)].map(m => m[1]));
  const pages = [...new Set(cases)];
  assert(pages.length > 0, 'Page enum not found');
  const router = app.slice(app.indexOf('private func destinationView(for page: Page)'), app.indexOf('struct PageBody<Content: View>'));
  assert(router.length > 0, 'destinationView not found');
  const sources = fs.readdirSync(root).filter(x => x.endsWith('.swift'))
    .map(f => fs.readFileSync(root + f, 'utf8')).join('\n');
  for (const page of pages) {
    const routed = [...router.matchAll(new RegExp(`case \\.${page}:`, 'g'))].length;
    assert.equal(routed, 1, `Page.${page} must be routed exactly once in destinationView`);
    const menuRows = [...sources.matchAll(new RegExp(`glassMenuItem\\(\\.${page},`, 'g'))].length;
    assert(menuRows <= 1, `Page.${page} appears ${menuRows} times in the 메뉴 list`);
    // The home quick-action row and the 메뉴 index are different surfaces, so a
    // page may hold one of each — but never two rows on the same surface.
    const tiles = [...sources.matchAll(new RegExp(`quickControlTile\\(\\s*\\.${page},`, 'g'))].length;
    assert(tiles <= 1, `Page.${page} appears ${tiles} times in the home quick-action row`);
    const links = [...sources.matchAll(new RegExp(`(?:value: )?Page\\.${page}\\b`, 'g'))].length + menuRows + tiles;
    assert(links > 0, `Page.${page} is unreachable — delete the case or give it an entry point`);
  }
  // v91: EnergyCalendar.swift is compiled into both the app and the probe. The
  // probe's Theme was missing `green`, so the build passed every local check and
  // failed six minutes in, inside the simulator target. Compare the two lists.
  const members = (src) => {
    const body = src.slice(src.indexOf('enum Theme {'));
    return [...body.slice(0, body.indexOf('\n}')).matchAll(/static let (\w+)/g)].map(m => m[1]).sort();
  };
  const appTheme = members(fs.readFileSync(root + 'App.swift', 'utf8'));
  const probeTheme = members(fs.readFileSync('Xcode/InterfaceProbe/App.swift', 'utf8'));
  assert(appTheme.length > 0 && probeTheme.length > 0, 'Theme not found in one of the two targets');
  const missing = appTheme.filter(x => !probeTheme.includes(x));
  assert.equal(missing.length, 0, `InterfaceProbe's Theme is missing: ${missing.join(', ')}`);

  assert(!sources.includes('struct DriveView'), 'DriveView was folded into the 운행 tab; do not reintroduce it');
  assert(!fs.existsSync(root + 'HomeModules.swift'), 'HomeModules.swift was a dead second menu system');
  assert(sources.includes('Button("회차 수동 종료")'), '회차 수동 종료 must survive the DriveView removal');
}
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
console.log(`PASS: ${count} view structures + 1 nested screen; explicit scoped bindings (source audit, not rendered UI QA)`);

const scoped = fs.readFileSync(root+'ScreenBriefing.swift','utf8');
assert(scoped.includes('if scope.supportsSpeech'), 'Settings/menu scopes must not render voice controls');
const local = fs.readFileSync(root+'LocalBriefingControls.swift','utf8');
assert(local.includes('].contains(title)'), 'Local editor voice controls must be opt-in');
assert(!fs.readFileSync(root+'DrivingWorkspace.swift','utf8').includes('announceDashboardStart('), 'Opening a dashboard must be silent');
assert(fs.readFileSync(root+'VoiceCoordinator.swift','utf8').includes('guard category != "voiceControl"'), 'Routine command/selection acknowledgements must stay visual');
assert(!speech.includes('connectedFacts'), 'Do not mechanically join sentences');
