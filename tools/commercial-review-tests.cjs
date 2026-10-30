const assert = require('node:assert/strict');
const { Engine } = require('../TeslaLocal.swiftpm/Sources/AppModule/Resources/analysis.js');
const kst = value => Date.parse(value + '+09:00');
const start = kst('2026-10-30T23:00:00');
const charge = (extra={}) => ({ at:start,end:start+2*3600000,supplyKWh:20,chargeType:'ac',place:'집',note:'Tesla 요청 자료',...extra });
const band = (fromMinute,toMinute,rate,extra={}) => ({ id:Math.random().toString(36),scope:'home',match:'',kind:'any',timezone:'Asia/Seoul',months:[10,11],days:[0,1,2,3,4,5,6],fromMinute,toMinute,rate,effectiveFrom:0,...extra });
{
 const e = new Engine(); e.settings({tariff:250,chargeTariffSchedules:[band(0,720,100),band(720,1440,300)]});
 e.addCharge(charge()); let row=e.chargeSummary().rows[0];
 assert.equal(row.estimatedCost,4000); assert.match(row.costRateSource,/시간 비례 추정/);
 e.state.charges[0].cost=0; assert.equal(e.chargeSummary().rows[0].totalCost,0);
 e.state.charges[0].cost=1234; assert.equal(e.chargeSummary().rows[0].totalCost,1234);
 const original=JSON.stringify(e.state.settings);
 assert.throws(()=>e.settings({chargeTariffSchedules:[band(0,800,10),band(700,1440,20)]}),/겹침/);
 assert.equal(JSON.stringify(e.state.settings),original,'invalid tariff cannot partially replace settings');
}
{
 const e=new Engine(); e.settings({tariff:250,chargeTariffSchedules:[band(0,1440,0,{effectiveTo:start+3600000}),band(0,1440,400,{effectiveFrom:start+3600000})]});
 e.addCharge(charge()); assert.equal(e.chargeSummary().rows[0].estimatedCost,4000);
}
{
 const e=new Engine(); e.settings({tariff:250,chargeTariffSchedules:[band(0,60,100),band(120,1440,300)]});
 e.addCharge(charge({at:kst('2026-10-31T00:00:00'),end:kst('2026-10-31T03:00:00')}));
 assert.equal(e.chargeSummary().rows[0].estimatedCost,null,'missing rate interval must not silently use default');
}
{
 const e=new Engine(); e.settings({tariff:250,chargeTariffSchedules:[band(0,1440,100,{days:[5]}),band(0,1440,200,{days:[6]})]});
 e.addCharge(charge()); assert.equal(e.chargeSummary().rows[0].estimatedCost,3000,'Friday to Saturday uses local calendar');
}
{
 const e=new Engine(); e.addCharge(charge()); const before=JSON.stringify(e.state.charges);
 assert.throws(()=>e.importCharges({rows:[] })); assert.equal(JSON.stringify(e.state.charges),before);
 assert.throws(()=>e.importCharges({rows:[charge({at:start+86400000}),charge({at:-1})]}));
 assert.equal(JSON.stringify(e.state.charges),before,'invalid later row rolls back the entire import');
 const first=e.importCharges({rows:[charge({at:start+86400000,end:start+86400000+3600000,importedEnergyKWh:25,supplyKWh:null,importedAmount:9,importedCurrency:'USD'})]});
 assert.equal(first.added,1); assert.equal(e.state.charges.length,2);
 const imported=e.state.charges.find(c=>c.at===start+86400000);
 assert.equal(imported.importedEnergyKWh,25); assert.equal(imported.storedKWh,null); assert.equal(imported.cost,null);assert.equal(imported.importedCurrency,'USD');
 e.importCharges({rows:[charge({at:start+86400000,end:start+86400000+3600000,supplyKWh:30,cost:6000})]});
 assert.equal(e.state.charges.length,2,'repeat import updates matched import only');
 assert(e.state.charges.some(c=>c.at===start),'older imported sessions absent from the new file are preserved');
 const saved=JSON.parse(JSON.stringify(e.state));const restored=new Engine();restored.load(saved);
 assert.equal(restored.state.charges.length,2);
}
{ const e=new Engine(); assert.throws(()=>e.settings({chargeTariffSchedules:[band(0,1440,100,{scope:'operator',match:'플러그링크'}),band(0,1440,200,{scope:'operator',match:'pluglink'})]}),/겹침/); }
{
 const e=new Engine();e.addCharge(charge({cost:6000}));const old=e.state.charges[0];old.photoName='receipt.jpg';old.receiptText='confirmed receipt';const id=old.id;
 const outcome=e.importCharges({rows:[charge({cost:null,supplyKWh:25})]});
 assert.equal(outcome.preservedCosts,1);assert.equal(e.state.charges[0].id,id);assert.equal(e.state.charges[0].cost,6000);assert.equal(e.state.charges[0].photoName,'receipt.jpg');assert.equal(e.state.charges[0].receiptText,'confirmed receipt');assert.equal(e.state.charges[0].supplyKWh,25);
 e.importCharges({rows:[charge({cost:9999})]});assert.equal(e.state.charges[0].cost,6000,'reimport cannot replace a confirmed amount');
 const zero=new Engine();zero.addCharge(charge({cost:0}));zero.importCharges({rows:[charge({cost:1234})]});assert.equal(zero.state.charges[0].cost,0,'free confirmed payment is preserved');
}
{
 const e=new Engine();e.addCharge(charge());const seed=e.state.charges[0];e.state.charges=Array.from({length:10000},(_,i)=>({...seed,id:'record-'+i,at:start+i*60000}));const before=e.state.charges;
 assert.throws(()=>e.importCharges({rows:[charge({at:start+10001*60000,end:start+10002*60000})]}),/10,000/);assert.equal(e.state.charges,before,'capacity failure preserves the original collection');
}
console.log('PASS: atomic import rollback, preserved old records, unclassified units/currency, timezone/weekday/version tariffs, gaps and paid amounts');
