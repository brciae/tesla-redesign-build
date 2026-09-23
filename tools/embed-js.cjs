// Re-encodes the Resources/*.js assets into EmbeddedAppResources.swift in place.
// Run after every edit under Sources/AppModule/Resources. Binary assets (vehicle3d.json) are left alone.
const fs = require('fs'), path = require('path');
const root = path.join(__dirname, '..', 'TeslaLocal.swiftpm', 'Sources', 'AppModule');
const file = path.join(root, 'EmbeddedAppResources.swift');
let swift = fs.readFileSync(file, 'utf8').replace(/\r\n/g, '\n');
const map = { 'protocol.js': 'asset0', 'analysis.js': 'asset1', 'vehicle3d.js': 'asset2', 'home.js': 'asset3', 'bridge.js': 'asset4' };
let changed = 0;
for (const [name, asset] of Object.entries(map)) {
    const raw = Buffer.from(fs.readFileSync(path.join(root, 'Resources', name), 'utf8').replace(/\r\n/g, '\n'));
    const body = (raw.toString('base64').match(/.{1,120}/g) || ['']).map(l => '    ' + l).join('\n');
    const marker = `    private static let ${asset} = """\n`;
    const start = swift.indexOf(marker);
    if (start < 0) throw new Error('asset block missing: ' + asset);
    const from = start + marker.length;
    const end = swift.indexOf('\n    """', from);
    if (end < 0) throw new Error('asset block unterminated: ' + asset);
    const current = swift.slice(from, end);
    if (current !== body) { swift = swift.slice(0, from) + body + swift.slice(end); changed++; }
}
if (process.argv.includes('--check')) {
    if (changed) { console.error('FAIL: EmbeddedAppResources.swift is stale — run `node tools/embed-js.cjs`'); process.exit(1); }
    console.log('PASS: embedded JS assets match Resources');
} else {
    fs.writeFileSync(file, swift);
    console.log('PASS: re-embedded JS assets (' + changed + ' changed)');
}
