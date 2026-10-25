const assert=require('node:assert/strict');
const C=require('../TeslaLocal.swiftpm/Sources/AppModule/Resources/analysis.js');
const t=Date.now()-2*86400000,vin='5YJYGDEE0LF000001';
const r=(dt,field,v)=>({at:t+dt,field,number:typeof v==='number'?v:undefined,text:JSON.stringify({stringValue:v}),invalid:false});
{
 const e=new C.Engine();e.state.settings.vin=vin;
 e.state.parkingPeriods=[{id:'preserve',start:t,end:t+3600000,startSOC:null,endSOC:null,deltaSOC:null,classification:'unclassified',note:'preserve'}];
 e.ingestArchive({vin,rows:[r(0,'Soc',80),r(0,'Odometer',100),r(3600000,'Soc',79),r(3600000,'Odometer',100)]});
 let p=e.state.parkingPeriods[0];assert.equal(p.startSOC,80);assert.equal(p.endSOC,79);assert.equal(p.classification,'parking');assert.equal(p.note,'preserve');
 assert.equal(e.parkingSummary().count,1);assert.equal(e.batteryUsage().parking.count,1);
 e.state.charges=[{id:'adjacent',at:t-3600000,end:t,startSOC:50,endSOC:80,vehicleReportedKWh:20,complete:true}];
 assert.equal(e.parkingSummary().count,1);assert.equal(e.batteryUsage().parking.count,1,'charge ending at parking start is not overlapping');
 e.state.charges[0].end=t+60000;const split=e.batteryUsage().parking;assert.equal(split.count,1,'non-charging remainder uses observed charge end');assert(split.rows.some(p=>p.exclusionReason.includes('충전')),'actual charge interval remains excluded');
 const raw=JSON.parse(JSON.stringify(e.state));const restored=new C.Engine();restored.load(raw);
 assert.equal(restored.state.parkingPeriods[0].endSOC,79,'repaired endpoint persists');
}
{
 const rows=[r(0,'Gear','P'),r(0,'Soc',80),r(0,'Odometer',100),r(3600000,'Gear','D'),r(3600000,'Soc',79),r(3600000,'Odometer',100)];
 const e=new C.Engine();e.state.settings.vin=vin;e.ingestArchive({vin,rows,replayFrom:t+3600000});
 assert.equal(e.state.parkingPeriods.length,1,'P seed survives incremental boundary');assert.equal(e.parkingSummary().count,1);
 e.ingestArchive({vin,rows,replayFrom:t+3600000});assert.equal(e.state.parkingPeriods.length,1,'incremental replay stays idempotent');
 const f=new C.Engine();f.state.settings.vin=vin;f.state.parkingPeriods=[{id:'invalid',start:t,end:t+3600000,classification:'unclassified'}];
 f.ingestArchive({vin,rows:[{...r(0,'Soc',80),invalid:true},r(3600000,'Soc',79)]});assert.equal(f.state.parkingPeriods[0].startSOC,undefined,'invalid endpoint not backfilled');
}
{
 const e=new C.Engine();e.state.settings.vin=vin;
 e.ingestArchive({vin,rows:[r(0,'Gear','P'),r(0,'Odometer',100),r(1000,'Soc',80),r(3600000,'Gear','D'),r(3600000,'Odometer',100),r(3601000,'Soc',79)]});
 assert.equal(e.state.parkingPeriods.length,1,'P before the first SOC packet must still establish the parking boundary');
 assert.equal(e.parkingSummary().count,1,'late asynchronous endpoint SOC is observed and repaired');
}
{
 const e=new C.Engine();e.state.settings.vin=vin;
 e.state.charges=[{id:'one',at:t,end:t+3600000,startSOC:30,endSOC:60,vehicleReportedKWh:24,complete:true},{id:'small',at:t+7200000,end:t+7300000,startSOC:60,endSOC:65,vehicleReportedKWh:4,complete:true}];
 const h=e.healthIndex();assert.equal(h.qualifiedChargeCount,1);assert.equal(h.capacityMedianKWh,80);assert.equal(h.degradationPercent,null,'one observation is a reference capacity, not a degradation result');
 assert(h.excludedChargeReasons.some(r=>r.reason.includes('10%p')&&r.count===1));
}
{
 const g=new C.EmbeddedRouteGate();g.observe({type:'route',at:1000,receivedAt:1000,latitude:37.5,longitude:127},true,false);
 const absent=(at,receivedAt=at)=>({type:'absent',at,receivedAt,confirmed:true,parked:false});
 assert.equal(g.observe(absent(2000),true,true).type,'wait');assert.equal(g.observe(absent(2000,4000),true,true).type,'wait','cached vehicle clock cannot confirm');
 assert.equal(g.observe(absent(5000),true,true).type,'wait');assert.equal(g.observe(absent(8000),true,true).type,'clear','fresh complete vehicle end syncs while D');
 assert.equal(g.current(1),false);
 const f=new C.EmbeddedRouteGate();f.observe({type:'route',at:1000,receivedAt:1000,latitude:37.5,longitude:127},true,false);
 for(let i=0;i<10;i++)assert.equal(f.observe({type:'absent',at:2000+i*5000,receivedAt:2000+i*5000},true,true).type,'wait','partial/GPS/network omission cannot end route');
}
console.log('PASS: parking endpoint recovery/boundaries/incremental replay, health evidence reasons, confirmed vehicle termination with missing-packet protection');
