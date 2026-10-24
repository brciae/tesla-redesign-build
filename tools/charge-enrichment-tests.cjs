const assert=require('node:assert/strict');
const {Engine}=require('../TeslaLocal.swiftpm/Sources/AppModule/Resources/analysis.js');
const t=Date.now()-86400000,vin='5YJYGDEE0LF000001';
const session=(id='vehicle',extra={})=>({id,at:t,end:t+3600000,source:'NAS',startSOC:40,endSOC:60,vehicleReportedKWh:14,supplyKWh:16,startTimeObserved:true,endTimeObserved:true,...extra});
const receipt=(id='receipt',extra={})=>({id,at:t,end:t+3600000,source:'OCR 확인',supplyKWh:16,cost:0,...extra});
for(const order of [false,true]){
 const e=new Engine();e.state.charges=order?[receipt(),session()]:[session(),receipt()];
 const s=e.chargeSummary();assert.equal(s.count,1);assert.equal(s.chargedKWh,14);assert.equal(s.combinedCost,0);
 assert.equal(s.rows[0].startSOC,40);assert.equal(s.rows[0].endSOC,60);assert.equal(e.state.charges.length,2,'raw evidence retained');
 assert.equal(e.batteryUsage(Date.now(),30).chargeCount,1);
 assert.equal((e.csv().match(/"충전"/g)||[]).length,1,'CSV same session once');
 const restored=new Engine();restored.load(JSON.parse(JSON.stringify(e.state)));assert.equal(restored.chargeSummary().count,1);
 e.deleteCharge({id:'receipt'});assert.equal(e.chargeSummary().count,0,'delete removes linked session as a unit');
}
{
 const e=new Engine();e.state.charges=[receipt(),session(),session('other',{at:t+60000,end:t+3660000})];
 assert.equal(e.chargeSummary().count,3,'ambiguous candidates never linked');
 e.state.charges=[receipt('receipt',{endSOC:80}),session()];assert.equal(e.chargeSummary().count,2,'SOC conflict');
 e.state.charges=[receipt('receipt',{at:t+86400000,end:t+90000000}),session()];assert.equal(e.chargeSummary().count,2,'different day');
}
{
 const e=new Engine();e.settings({assumedCapacityKWh:75});
 e.state.charges=[receipt('soc',{startSOC:40,endSOC:60}),receipt('supply',{at:t+7200000,end:t+10800000})];
 assert.equal(e.chargeSummary().chargedKWh,15,'SOC battery energy despite receipt supply');
 assert.equal(e.chargeSummary().rows.find(c=>c.id==='soc').chargeEnergyEstimated,true);
 assert.equal(e.chargeSummary().rows.find(c=>c.id==='supply').chargedKWh,null,'grid energy is not battery energy');
 assert.equal(e.health().capacity,null,'SOC estimate cannot measure its own capacity');
}
{
 const e=new Engine();e.state.settings.vin=vin;e.state.charges=[receipt()];
 const rows=[{at:t,soc:40},{at:t+3600000,soc:60}];
 e.enrichChargeSOC({vin:'OTHER',rows});assert.equal(e.state.charges[0].startSOC,undefined);
 e.enrichChargeSOC({vin,rows:rows.map(r=>({...r,at:r.at+300000}))});assert.equal(e.state.charges[0].startSOC,undefined,'stale samples ignored');
 e.enrichChargeSOC({vin,rows:[...rows,{at:t+1000,invalid:true}]});assert.equal(e.state.charges[0].startSOC,undefined,'invalid local sample blocks inference');
 e.enrichChargeSOC({vin,rows});assert.equal(e.state.charges[0].startSOC,40);assert.equal(e.state.charges[0].endSOC,60);
 e.enrichChargeSOC({vin,rows:[{at:t,soc:41}]});assert.equal(e.state.charges[0].startSOC,40,'existing SOC preserved');
 assert.throws(()=>e.addCharge({at:t,end:t-1}));
}
console.log('PASS: receipt/session order independence, ambiguity protection, SOC enrichment, VIN/freshness, unified cost and battery energy');
