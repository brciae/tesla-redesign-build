const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const root = path.resolve(__dirname, '..');
const sourceDir = path.join(root, 'TeslaLocal.swiftpm/Sources/AppModule');
function longInlineCopy(source) {
  return [...source.matchAll(/Text\("((?:\\.|[^"\\])*)"\)/g)]
    .filter(m => !m[1].includes('\\(') && m[1].length >= 80);
}
// A recurring regression guard: fail on a known paragraph bypass, then accept the folded form.
const prose = '계산 근거를 상세히 확인할 수 있음. '.repeat(6);
assert.equal(longInlineCopy('Text(' + JSON.stringify(prose) + ')').length, 1);
assert.equal(longInlineCopy('Caption(' + JSON.stringify(prose) + ')').length, 0);
let scanned = 0, captions = 0;
for (const file of fs.readdirSync(sourceDir).filter(f => f.endsWith('.swift'))) {
  const source = fs.readFileSync(path.join(sourceDir,file), 'utf8');
  scanned++; captions += [...source.matchAll(/struct Caption\s*:\s*View/g)].length;
  for (const m of longInlineCopy(source)) {
    const line = source.slice(0,m.index).split('\n').length;
    assert.fail(file + ':' + line + ' long inline explanation: shorten or use shared supporting detail');
  }
}
assert.equal(captions, 1, 'Use one Caption implementation in production');
const probe = fs.readFileSync(path.join(root,'Xcode/InterfaceProbe/App.swift'),'utf8');
assert.ok(!probe.includes('struct Caption:'), 'UI tests must use the production supporting-copy component');
const dashboard = fs.readFileSync(path.join(sourceDir,'NavigationDashboard.swift'),'utf8');
assert.ok(!/Text\(data\.(turn|next)\)/.test(dashboard), 'Maneuver text must pass through the shared concise label');
for (const [file, expression] of [['DestinationSearchView.swift','Text(place.address)'],['ManagementViews.swift','Text(link.status)'],['HomeViews.swift','Text(saved.displaySubtitle)']]) {
  const source=fs.readFileSync(path.join(sourceDir,file),'utf8'), index=source.indexOf(expression);
  assert.ok(index>=0, 'Missing reviewed dynamic field: '+expression);
  assert.ok(!source.slice(index,index+230).includes('.lineLimit('), 'Do not truncate important address/status text: '+file);
}
console.log('PASS: '+scanned+' Swift sources scanned; long inline-copy guard, shared detail, full address/status and concise guidance');
