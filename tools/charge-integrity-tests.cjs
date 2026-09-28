const assert = require('node:assert/strict');
const C = require('../TeslaLocal.swiftpm/Sources/AppModule/Resources/analysis.js');
const vin='5YJYGDEE0LF000001', t=Date.now()-86400000;
const feed=(e,offset,state,soc,kwh)=>e.ingestFleetCharge({vin,at:t+offset,charging:state,soc,addedKWh:kwh,limit:80},t+offset);
// Reproduced v95 defect: 36 terminal snapshots generated 1,452.96 kWh.
{
 let e=new C.Engine();
 for(let i=0;i<36;i++){
  if(i===18){const restored=new C.Engine();restored.load(JSON.parse(JSON.stringify(e.state)));e=restored;}
  feed(e,i*60000,6,80-i*.11,40.36);
 }
 assert.equal(e.state.charges.length,1);assert.equal(e.chargeSummary().vehicleReportedKWh,40.36);
 assert.equal(e.state.charges[0].endSOC,80,'later drift cannot rewrite final SOC');
 assert.equal(e.state.charges[0].startTimeObserved,false);
}
// Real start/stop boundaries, including a second charge with identical final energy.
{
 const e=new C.Engine();
 feed(e,0,2,30,0);feed(e,1000,5,30,0);feed(e,61000,5,60,22.5);feed(e,121000,6,80,37.5);
 feed(e,181000,6,79.8,37.6);feed(e,241000,7,79.6,37.6);
 assert.equal(e.state.charges.length,1);assert.equal(e.state.charges[0].at,t+1000);
 assert.equal(e.state.charges[0].end,t+121000);assert.equal(e.state.charges[0].vehicleReportedKWh,37.6);
 feed(e,3600000,2,30,0);feed(e,3601000,5,30,0);feed(e,3661000,5,60,22.5);feed(e,3721000,6,80,37.5);
 assert.equal(e.chargeSummary().count,2,'equal kWh must not collapse a proven new session');
}
// A counter dip is not a new session. A large incompatible reset requires review.
{
 const e=new C.Engine();feed(e,0,2,30,0);feed(e,1000,5,30,0);feed(e,61000,5,60,20);
 feed(e,121000,5,60,19.4);feed(e,181000,6,80,37.5);
 assert.equal(e.state.charges.length,1);assert.equal(e.chargeSummary().count,1);
 const conflict=new C.Engine();feed(conflict,0,2,30,0);feed(conflict,1000,5,30,0);feed(conflict,61000,5,60,20);
 feed(conflict,121000,5,60,1);feed(conflict,181000,6,80,18.5);
 assert.equal(conflict.state.charges.length,1);assert.equal(conflict.chargeSummary().reviewCount,1);
}
// Upgrade repairs the aggregate without destroying originals, cost, or receipt evidence.
{
 const old=new C.Engine();old.state.settings.vin=vin;
 old.state.charges=Array.from({length:36},(_,i)=>({id:'legacy-'+i,at:t+i*60000,end:t+i*60000,startSOC:25,endSOC:80-i*.11,vehicleReportedKWh:40.36,collectedAfterEnd:true,source:'Fleet',complete:false}));
 old.state.charges[10].cost=12000;old.state.charges[10].receiptText='preserve receipt';
 const e=new C.Engine();e.load(JSON.parse(JSON.stringify(old.state)));
 assert.equal(e.state.charges.length,36);assert.equal(e.view().charging.reviewCount,35);
 assert.equal(e.view().totals.vehicleReportedKWh,40.36);assert.equal(e.batteryUsage().chargeCount,1);
 assert.equal(e.state.charges[10].cost,12000);assert.equal(e.state.charges[10].receiptText,'preserve receipt');
 assert.match(e.csv(),/제외:/);
 const again=new C.Engine();again.load(JSON.parse(JSON.stringify(e.state)));
 assert.equal(again.view().charging.reviewCount,35);assert.equal(again.view().totals.vehicleReportedKWh,40.36);
 assert.throws(()=>again.confirmSeparateCharge({id:'legacy-10'}));
 again.confirmSeparateCharge({id:'legacy-10',confirmed:true});assert.equal(again.view().charging.count,2);
}
// Later NAS session evidence supersedes completion-only phone snapshots in aggregates.
{
 const e=new C.Engine();feed(e,120000,6,80,37.5);
 const row=(dt,field,value)=>({at:t+dt,field,number:typeof value==='number'?value:undefined,text:JSON.stringify({stringValue:value}),invalid:false});
 const rows=[row(0,'ChargeState','Disconnected'),row(0,'Soc',30),row(1000,'ChargeState','Charging'),row(61000,'Soc',60),row(61000,'DCChargingEnergyIn',22.5),row(120000,'ChargeState','Complete'),row(120000,'Soc',80),row(120000,'DCChargingEnergyIn',37.5)];
 e.ingestArchive({vin,rows});assert.equal(e.chargeSummary().count,1);assert.equal(e.chargeSummary().vehicleReportedKWh,37.5);
 assert.equal(e.chargeSummary().reviewCount,1);
 e.ingestArchive({vin,rows});assert.equal(e.chargeSummary().count,1);assert.equal(e.state.charges.length,2);
}
// Context seed fields are state, not new sessions at their old timestamps.
{
 const e=new C.Engine();
 const rows=[{at:t,field:'ChargeState',text:'{"stringValue":"Complete"}'},{at:t,field:'Soc',number:80},{at:t,field:'DCChargingEnergyIn',number:40},
 {at:t+3600000,field:'Gear',text:'{"stringValue":"ShiftStateP"}'}];
 e.ingestArchive({vin,rows,replayFrom:t+3600000});
 assert.equal(e.state.charges.length,0,'stale energy seed cannot invent a completed session');
}
console.log('PASS: charge integrity, 36x inflation regression, restart, real session boundaries, preserved quarantine and NAS reconciliation');
