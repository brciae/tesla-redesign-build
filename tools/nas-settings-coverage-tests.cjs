const fs = require('fs');
const path = require('path');
const assert = require('assert/strict');
const root = path.resolve(__dirname, '../TeslaLocal.swiftpm/Sources/AppModule');
const vault = fs.readFileSync(path.join(root, 'NASConfigurationVault.swift'), 'utf8');
const catalog = vault.slice(vault.indexOf('static let preferences ='), vault.indexOf('static func allowedPreference'));
const allowed = new Set([...catalog.matchAll(/"([^"\n]+)"/g)].map(m => m[1]));
const exceptions = new Map([
  ['automationSpeech.aiEnabled', 'Paid external AI must be enabled explicitly on the restored device'],
]);
const missing = [];
let count = 0;
for (const name of fs.readdirSync(root).filter(n => n.endsWith('.swift'))) {
  const source = fs.readFileSync(path.join(root, name), 'utf8');
  for (const match of source.matchAll(/@AppStorage\("([^"\n]+)"\)/g)) {
    count++;
    if (!allowed.has(match[1]) && !exceptions.has(match[1])) missing.push(`${name}: ${match[1]}`);
  }
}
assert.deepEqual(missing, [], 'Every UI input must be synchronized or have an explicit device-only reason');
for (const key of ['navigation.home', 'charging.favorites.v1', 'cost.gasoline', 'warranty.start.', 'vehicle.reference.', 'appearance.v1.', 'automationAPI.model.']) {
  assert(allowed.has(key), 'Missing independently persisted entered data: ' + key);
}
assert(vault.includes('"setting."'), 'Tariff tables, home geofences and battery references must be included per field');
const model = fs.readFileSync(path.join(root, 'AppModel.swift'), 'utf8');
assert(model.includes('automation.rules') && model.includes('appearance.asset.'), 'Rule files and referenced appearance assets must be included');
console.log(`PASS: ${count} UI setting declarations covered; tariffs, addresses, favorites, warranty, automation and appearance assets included`);
