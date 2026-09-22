// v29 regression tests: route gate (stop / jitter / absence) and per-group freshness.
const path = require('path');
const C = require(path.join(__dirname, '../TeslaLocal.swiftpm/Sources/AppModule/Resources/analysis.js'));
const assert = (c, m) => { if (!c) { console.error('FAIL: ' + m); process.exit(1); } };
const g = new C.EmbeddedRouteGate();
const ev = (lat, at, name = 'A') => ({ type: 'route', name, latitude: lat, longitude: 127, at, receivedAt: at, token: name + lat });
let r = g.observe(ev(37.5, 1000), true, false); assert(r.type === 'start', 'first start');
r = g.observe(ev(37.50001, 2000, 'A (renamed)'), true, true); assert(r.type === 'refresh', 'coordinate jitter/rename keeps guidance');
for (let i = 0; i < 5; i++) { r = g.observe({ type: 'absent', at: 3000 + i * 5000, receivedAt: 3000 + i * 5000 }, true, true); assert(r.type === 'wait', 'stop-time absence tolerated'); }
r = g.observe(ev(37.5, 40000), false, true); assert(r.type === 'refresh', 'background refresh keeps guidance');
let cleared = false;
for (let i = 0; i < 7; i++) { r = g.observe({ type: 'absent', at: 50000 + i * 9000, receivedAt: 50000 + i * 9000 }, true, true); cleared = cleared || r.type === 'clear'; }
assert(cleared, 'sustained absence clears');
r = g.observe(ev(37.6, 200000), true, false); assert(r.type === 'start', 'new destination');
g.finish(r.ticket); r = g.observe(ev(37.6, 201000), true, false); assert(r.type === 'wait', 'finished destination blocked');
g.retry(); r = g.observe(ev(37.6, 202000), true, false); assert(r.type === 'start', 'manual retry');
const now = Date.now();
assert(C.fresh({ at: now - 600000, receivedAt: now - 1000 }, now, C.TTL.charge), 'old source stamp, fresh receipt');
assert(!C.fresh({ at: now - 1000, receivedAt: now - 200000 }, now, C.TTL.charge), 'stale receipt');
assert(!C.fresh({ at: now + 300000, receivedAt: now }, now, C.TTL.drive), 'future source stamp');
console.log('PASS: route gate + freshness');

// New receipts with an unchanged vehicle timestamp must still confirm route cancellation.
const parkedGate = new C.EmbeddedRouteGate();
parkedGate.observe(ev(37.5, 1000), true, false);
const absent = receipt => ({type:'absent', at:1000, receivedAt:receipt, parked:true});
assert(parkedGate.observe(absent(2000), true, true).type === 'wait', 'first parked absence');
for(let i=0;i<4;i++) assert(parkedGate.observe(absent(2000), true, true).type === 'wait', 'cached receipt cannot count');
assert(parkedGate.observe(absent(7000), true, true).type === 'wait', 'second parked absence');
assert(parkedGate.observe(absent(12000), true, true).type === 'clear', 'fixed source clock clears after new receipts');
parkedGate.reset(); parkedGate.observe(ev(37.5, 1000), true, false);
parkedGate.observe({...absent(2000), parked:false},true,true);
parkedGate.observe({...absent(7000), parked:false},true,true);
assert(parkedGate.observe(absent(12000),true,true).type==='wait','entering P resets confirmation');
assert(parkedGate.observe(ev(37.5,15000),true,true).type==='refresh','P alone does not cancel a valid route');
assert(parkedGate.absence===null,'route restoration resets absence');
parkedGate.cancel();
assert(parkedGate.observe(ev(37.5,16000),true,false).type==='wait','manual route stop blocks old destination while freely driving');
assert(parkedGate.observe(ev(37.6,17000),true,false).type==='start','new destination can start after manual stop');
assert(C.embeddedDestination({at:now,receivedAt:now,destination:'',destinationLat:37.5,destinationLng:127,arrivalMinutes:5},now).type==='wait','empty name with retained active route must not clear');
console.log('PASS: parked route termination, repeated receipts, partial route protection');

// v35: a receipt photo must fill the whole charge form, not just kWh and cost.
const gs = C.parseReceipt(['GS칼텍스 강남충전소', '2026.09.14 14:23', '충전량 32.5 kWh', '단가 347원/kWh', '결제금액 11,278원', '시작 45% → 80%', '충전시간 42분'].join('\n'));
assert(gs.supplyKWh === 32.5 && gs.cost === 11278 && gs.unitPrice === 347, 'receipt kWh/cost/unit price');
assert(gs.startSOC === 45 && gs.endSOC === 80 && gs.minutes === 42, 'receipt SOC range and duration');
assert(gs.dateText === '2026-09-14' && gs.timeText === '14:23' && gs.place.includes('강남충전소'), 'receipt date, time, place');
assert(gs.filledCount === 9 && !gs.ambiguous, 'receipt fills every field without guessing');
const tesla = C.parseReceipt(['슈퍼차저 서울성수', '2026/09/15 09:05', '추가된 충전량', '41.2 kWh', '비용 14,420원', '80%'].join('\n'));
assert(tesla.supplyKWh === 41.2 && tesla.cost === 14420 && tesla.endSOC === 80, 'in-car screen with value on the next line');
const messy = C.parseReceipt(['누적 120 kWh', '12 kWh', '3,000원', '5,000원'].join('\n'));
assert(messy.supplyKWh === 12 && messy.ambiguous, 'cumulative line ignored, guess flagged');
const derived = C.parseReceipt(['충전 32 kWh', '단가 300 원/kWh'].join('\n'));
assert(derived.cost === 9600, 'cost derived from unit price');
console.log('PASS: receipt parsing');
