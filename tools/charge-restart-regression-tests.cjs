const assert = require('node:assert/strict');
const {Engine} = require('../TeslaLocal.swiftpm/Sources/AppModule/Resources/analysis.js');
const vin='5YJYGDEE0LF000001', t=Date.now()-86400000;
// The archive accepts paired SOC/energy up to 120 seconds before ChargeState.
// Its own saved output must remain loadable after an app restart.
for(const age of [0,15000,15001,60000,120000]) {
  const e=new Engine(); e.state.settings.vin=vin;
  e.state.trips=[{id:'historical-trip',start:t-40*86400000,end:t-40*86400000+600000,distanceKm:20,startSOC:80,endSOC:70}];
  const rows=[{at:t-age,field:'Soc',number:80},{at:t-age,field:'DCChargingEnergyIn',number:15},
    {at:t,field:'ChargeState',text:'{"stringValue":"Complete"}'}];
  e.ingestArchive({vin,rows});
  assert.equal(e.state.charges.length,1);
  assert.equal(e.state.charges[0].observedStartTelemetryAt,t-age);
  e.state.charges[0].cost=4200; e.state.charges[0].receiptText='preserved receipt';
  const saved=JSON.stringify(e.state), restored=new Engine();
  assert.doesNotThrow(()=>restored.load(JSON.parse(saved)),`archive/restart age=${age}`);
  assert.equal(restored.state.trips[0].id,'historical-trip');
  for(const key of ['id','at','end','observedStartSOC','observedStartAddedKWh','observedStartTelemetryAt','cost','receiptText'])
    assert.deepEqual(restored.state.charges[0][key],e.state.charges[0][key],key);
  const again=new Engine(); assert.doesNotThrow(()=>again.load(JSON.parse(JSON.stringify(restored.state))));
  const invalid=JSON.parse(saved); invalid.charges[0].observedStartTelemetryAt=t-120001;
  assert.throws(()=>new Engine().load(invalid),/충전 관측 구간 오류/,'out-of-contract times must still fail');
  const invalidEnd=JSON.parse(saved); invalidEnd.charges[0].observedEndTelemetryAt=t-120001;
  assert.throws(()=>new Engine().load(invalidEnd),/충전 관측 종료 오류/);
  const invalidSOC=JSON.parse(saved); invalidSOC.charges[0].observedStartSOC=101;
  assert.throws(()=>new Engine().load(invalidSOC),/충전 관측 구간 오류/);
}
console.log('PASS: archive-produced charge observation windows restart without dropping historical trips or receipt evidence');
