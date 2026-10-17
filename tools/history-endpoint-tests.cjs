const assert=require('node:assert/strict');
const C=require('../TeslaLocal.swiftpm/Sources/AppModule/Resources/analysis.js');
const vin='5YJYGDEE0LF000001',t=Date.now()-86400000;
const r=(dt,field,value)=>({at:t+dt,field,number:typeof value==='number'?value:undefined,text:JSON.stringify({stringValue:value}),invalid:false});
const rows=[r(-3600000,'ChargeState','Disconnected'),r(0,'ChargeState','Charging'),r(0,'Soc',36),r(0,'ChargeEnergyAdded',0),r(3600000,'Soc',52),r(3600000,'ChargeEnergyAdded',13.48),r(3601000,'ChargeState','Stopped')];
{
 const e=new C.Engine();e.state.settings.vin=vin;
 e.ingestFleetCharge({vin,at:t+5000,charging:5,soc:36,addedKWh:0},t+5000);
 const id=e.state.activeCharge.id;
 e.ingestArchive({vin,rows,replayFrom:t});
 assert.equal(e.state.activeCharge,null,'NAS stop must close overlapping phone active charge');
 assert.equal(e.state.charges.length,1);const c=e.state.charges[0];
 assert.equal(c.id,id);assert.equal(c.end,t+3601000);assert.equal(c.startTimeObserved,true,'old seed state still establishes the recorded Charging transition');
 assert.equal(c.endTimeObserved,true);assert.equal(c.startSOC,36);assert.equal(c.startSOCEstimated,false);
 assert.equal(c.endSOC,52);assert.equal(c.vehicleReportedKWh,13.48);
 e.ingestArchive({vin,rows,replayFrom:t});assert.equal(e.state.charges.length,1,'reimport must be idempotent after active ID reconciliation');
 assert.equal(e.state.charges[0].id,id);
}
{
 const e=new C.Engine();e.state.settings.vin=vin;
 e.ingestArchive({vin,rows});const old=e.state.charges[0];old.startTimeObserved=false;old.endTimeObserved=false;old.cost=1200;old.note='preserve';
 e.ingestArchive({vin,rows});assert.equal(e.state.charges[0].startTimeObserved,true);assert.equal(e.state.charges[0].endTimeObserved,true);
 assert.equal(e.state.charges[0].cost,1200);assert.equal(e.state.charges[0].note,'preserve');
}
{
 const e=new C.Engine();
 e.ingestFleetDrive({vin,drive:{at:t,gear:'D',speedKmh:20,odometerKm:100},charge:{at:t,soc:80}},t);
 e.ingestFleetDrive({vin,drive:{at:t+1000,gear:'D',speedKmh:20,odometerKm:100.1},charge:{at:t+1000}},t+1000);
 e.ingestFleetDrive({vin,drive:{at:t+2000,gear:'P',odometerKm:100.2},charge:{at:t+2000,soc:null}},t+2000);
 assert.equal(e.state.trips[0].endSOC,80,'missing SOC must not erase observed last SOC');
}
{
 const e=new C.Engine();e.state.settings.vin=vin;
 e.state.trips=[{id:'phone',start:t,end:t+3600000,startSOC:null,endSOC:null,distanceKm:25,points:[]}];
 e.ingestArchive({vin,rows:[r(1000,'Soc',80),r(3601000,'BatteryLevel',75)]});
 assert.equal(e.state.trips[0].startSOC,80);assert.equal(e.state.trips[0].endSOC,75);
 const copy=JSON.parse(JSON.stringify(e.state));const restored=new C.Engine();restored.load(copy);
 assert.equal(restored.state.trips[0].endSOC,75,'backfill survives upgrade/reload');
 const f=new C.Engine();f.state.settings.vin=vin;f.state.trips=[{id:'unknown',start:t,end:t+3600000,points:[]}];
 f.ingestArchive({vin,rows:[r(300000,'Soc',80),r(3601000,'Soc',75),{...r(3602000,'Soc',75),invalid:true}]});
 assert.equal(f.state.trips[0].startSOC,undefined);assert.equal(f.state.trips[0].endSOC,undefined,'invalid near endpoint prevents inference');
}
console.log('PASS: active NAS completion, recorded transition timestamps, stale-flag upgrade, non-erasing SOC, raw endpoint backfill/reload/invalid guards');
{
 const e=new C.Engine();e.state.settings.vin=vin;
 e.ingestArchive({vin,rows:[r(-3600000,'ChargeState','Disconnected'),r(0,'ChargeState','Charging'),r(0,'Soc',60),r(0,'ChargeEnergyAdded',15),r(3600000,'ChargeState','Stopped'),r(3600000,'Soc',80),r(3600000,'ChargeEnergyAdded',30)]});
 const c=e.state.charges[0];assert.equal(c.startSOCEstimated,true,'first observation after energy has already accumulated cannot become a measured start SOC');
 assert.equal(e.capacitySamples().length,0,'late start observation must not create false health evidence');
}
