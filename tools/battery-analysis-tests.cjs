const assert=require('node:assert/strict');
const {Engine}=require('../TeslaLocal.swiftpm/Sources/AppModule/Resources/analysis.js');
const DAY=86400000,now=Date.now(),t=now-20*DAY,vin='5YJYGDEE0LF000001';
const charge=(id,at=t,extra={})=>({id,at,end:at+3600000,startSOC:30,endSOC:60,vehicleReportedKWh:21,complete:true,startSOCObserved:true,endSOCObserved:true,source:'manual',chargeReviewConfirmed:true,...extra});
{
 const e=new Engine();e.settings({homePoint:{latitude:37.5,longitude:127.1},tariff:200});
 e.state.charges=[charge('inside',t,{latitude:37.504,longitude:127.1,chargeType:'ac'}),charge('outside',t+DAY,{latitude:37.507,longitude:127.1,chargeType:'ac'}),charge('dc',t+2*DAY,{latitude:37.5,longitude:127.1,chargeType:'dc'})];
 const rows=e.chargeSummary().rows;assert.equal(rows.find(c=>c.id==='inside').chargeTypeLabel,'집 완속');assert.notEqual(rows.find(c=>c.id==='outside').chargeTypeLabel,'집 완속');assert.notEqual(rows.find(c=>c.id==='dc').chargeTypeLabel,'집 완속');
 const split=t+10*DAY;
 e.settings({homeRegions:[{latitude:37.5,longitude:127.1,radius:600,start:0,end:split},{latitude:37.6,longitude:127.2,radius:800,start:split}],homePoint:{latitude:37.6,longitude:127.2}});
 e.state.charges=[charge('old',t,{latitude:37.5,longitude:127.1}),charge('new',split,{latitude:37.6,longitude:127.2}),charge('old-after-move',split+DAY,{latitude:37.5,longitude:127.1})];
 assert.equal(e.chargeSummary().rows.find(c=>c.id==='old').chargeTypeLabel,'집 완속');assert.equal(e.chargeSummary().rows.find(c=>c.id==='new').chargeTypeLabel,'집 완속');assert.notEqual(e.chargeSummary().rows.find(c=>c.id==='old-after-move').chargeTypeLabel,'집 완속');
 const restored=new Engine();restored.load(JSON.parse(JSON.stringify(e.state)));assert.equal(restored.chargeSummary().rows.find(c=>c.id==='old').chargeTypeLabel,'집 완속');
 assert.throws(()=>e.settings({homeRadiusM:5000}));
}
{
 const e=new Engine();e.state.charges=Array.from({length:7},(_,i)=>charge('c'+i,t+i*DAY));
 const h=e.healthIndex(now);assert.equal(h.sampleCount,7,'imports before app install must count');assert.equal(h.capacityMedianKWh,70);assert.equal(h.degradationPercent,null,'75kWh assumption is not an SOH reference');
 e.settings({healthReferenceMethod:'chargeUsable',healthReferenceKWh:80});assert.equal(e.healthIndex(now).degradationPercent,12.5);
 e.state.charges.push(charge('circular',t+8*DAY,{startSOCEstimated:true}));assert.equal(e.healthIndex(now).sampleCount,7);
 e.state.charges.push(charge('missing-end',t+9*DAY,{endSOCEstimated:true}));assert.equal(e.healthIndex(now).sampleCount,7);
 e.settings({healthBatteryStartAt:t+5*DAY});assert.equal(e.healthIndex(now).sampleCount,2);
}
{
 const e=new Engine();e.state.settings.vin=vin;
 const rows=Array.from({length:3},(_,i)=>({at:now-(3-i)*DAY,field:'NominalFullPackEnergyKwh',number:76,invalid:false}));
 rows.push({...rows[0],at:rows[0].at+60000,number:76});
 e.ingestArchive({vin,rows});assert.equal(e.healthIndex(now).method,'bmsNominal');assert.equal(e.healthIndex(now).sampleCount,3,'same-day polling is one sample');
 e.settings({healthReferenceMethod:'chargeUsable',healthReferenceKWh:80});assert.equal(e.healthIndex(now).degradationPercent,null,'nominal and usable references must not mix');
 e.settings({healthReferenceMethod:'bmsNominal',healthReferenceKWh:80});assert.equal(e.healthIndex(now).degradationPercent,5);
 const restored=new Engine();restored.load(JSON.parse(JSON.stringify(e.state)));assert.equal(restored.healthIndex(now).degradationPercent,5);
 e.ingestArchive({vin,rows:[{at:now,field:'NominalFullPackEnergyKwh',number:0,invalid:true}]});assert.equal(e.healthIndex(now).capacityMedianKWh,76);
}
{
 const e=new Engine(),at=now-3600000;
 const packet=(time,gear,soc,odo=100)=>e.ingest({groups:{drive:{at:time,receivedAt:time,gear,speedKmh:0,odometerKm:odo},charge:{at:time,receivedAt:time,soc,charging:2}}},time);
 packet(at,'D',60);packet(at+60000,'D',60);assert.equal(e.state.parkingPeriods.length,0,'stopped in D is not parking');
 packet(at+120000,'P',60);packet(at+420000,'D',59);const p=e.parkingSummary(now).rows[0];assert.equal(p.classification,'parking');assert.equal(p.hours,.08);assert.equal(p.precisionLimited,true,'short P parking is retained, not discarded');
 e.state.parkingPeriods=[{id:'high',start:now-12*3600000,end:now-3600000,startSOC:90,endSOC:80,deltaSOC:10,classification:'parking'}];e.state.lastPark=null;
 assert.equal(e.parkingSummary(now).count,1);assert.equal(e.parkingSummary(now).rows[0].highLoss,true,'high loss is not silently hidden');
 e.state.charges=[charge('during',now-10*3600000)];assert.equal(e.parkingSummary(now).rows[0].classification,'unclassified');assert.match(e.parkingSummary(now).rows[0].exclusionReason,/충전/);
}
{
 const e=new Engine();const rows=[];
 for(const [at,gear,soc,odo] of [[t,'P',80,100],[t+60000,'D',80,100],[t+3600000,'P',75,110],[t+12*3600000,'D',74,110],[t+13*3600000,'P',70,120]]) {
  for(const [field,value] of Object.entries({Gear:gear,Soc:soc,Odometer:odo,VehicleSpeed:gear==='D'?30:0}))rows.push({at,field,number:typeof value==='number'?value:null,text:JSON.stringify({value}),invalid:false});
 }
 e.ingestArchive({vin,rows});assert.ok(e.state.parkingPeriods.length>0,'archive parking reconstruction must be merged');
 const count=e.state.parkingPeriods.length;e.ingestArchive({vin,rows});assert.equal(e.state.parkingPeriods.length,count,'archive parking replay is idempotent');
}
console.log('PASS: dated home geofence, source-separated battery health, measured SOC only, P versus stopped D, short/high-loss parking and NAS replay');
