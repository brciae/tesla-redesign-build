const assert=require('node:assert/strict');
const {Engine}=require('../TeslaLocal.swiftpm/Sources/AppModule/Resources/analysis.js');
const DAY=86400000,now=Date.now(),at=now-12*DAY;
const trip=(id,start=at,extra={})=>({id,start,end:start+600000,distanceKm:20,startSOC:80,endSOC:70,missing:false,points:[],...extra});
{
 const e=new Engine();e.state.trips=[trip('phone'),trip('nas')];
 const b=e.batteryUsage(now,30),v=e.view(now);
 assert.equal(b.distanceKm,20);assert.equal(b.driveSOC,10);assert.equal(b.tripCount,1);
 assert.equal(v.totals.distanceKm,20);assert.equal(v.totals.trips,1);
 const restored=new Engine();restored.load(JSON.parse(JSON.stringify(e.state)));
 assert.equal(restored.state.trips.length,1,'existing duplicate records are consolidated on load');
 restored.load(JSON.parse(JSON.stringify(restored.state)));assert.equal(restored.state.trips.length,1);
}
{
 const e=new Engine();e.state.trips=[trip('first'),trip('next',at+DAY,{startSOC:null,endSOC:null})];
 const before=e.energyEstimates(now).trips.at(-1).estimatedKWh;
 e.state.trips.splice(1,0,trip('overlap',at,{endSOC:76}));
 assert.equal(e.energyEstimates(now).trips.at(-1).estimatedKWh,before,'excluded overlap cannot teach efficiency');
}
{
 const e=new Engine();e.state.charges=Array.from({length:6},(_,i)=>({id:'c'+i,at:at+i*DAY,end:at+i*DAY+3600000,startSOC:20,endSOC:100,vehicleReportedKWh:i<3?64:60,complete:true,startSOCObserved:true,endSOCObserved:true,source:'manual',chargeReviewConfirmed:true}));
 const h=e.healthIndex(now),common=e.health(now);
 assert.equal(h.recentCapacityKWh,75);assert.equal(common.capacity,h.recentCapacityKWh);
 assert.equal(common.baseline,h.baselineCapacityKWh);assert.equal(common.changePercent,h.relativeChangePercent);
 assert.equal(e.energyEstimates(now).capacityKWh,75,'all existing trips recalculate using corrected same-method capacity');
 e.state.charges=[{id:'estimated',at,end:at+3600000,startSOC:20,endSOC:100,estimatedStoredKWh:68,supplyKWh:80,startSOCEstimated:true}];
 assert.equal(e.health().capacity,null,'estimates and grid input must not calibrate capacity');
}
{
 const e=new Engine();e.state.charges=[{id:'partial',at,end:at+600000,startSOC:30,endSOC:70,endSOCLastObserved:true,endSOCEstimated:false,complete:false}];
 assert(!e.batteryUsage(now,30).trend.some(p=>p.id==='partiale'),'last SOC is not a measured session-end SOC');
}
{
 const e=new Engine();const c={id:'one',at,end:at+3600000,startSOC:20,endSOC:80,vehicleReportedKWh:48,supplyKWh:53};
 e.state.charges=[c,{...c,id:'two'}];
 const restored=new Engine();restored.load(JSON.parse(JSON.stringify(e.state)));
 assert.equal(restored.state.charges.length,1,'exact session duplicates corrected in storage');
 assert.equal(restored.chargeSummary().chargedKWh,48,'vehicle kWh remains unmodified by grid amount');
}
console.log('PASS: historical storage reconciliation, unique totals/learning, common capacity calibration, observed endpoints and vehicle kWh');
{
 const e=new Engine();e.state.charges=[50,60].map((k,i)=>({id:'manual'+i,at,end:at+3600000,startSOC:20,endSOC:80,supplyKWh:k,cost:(i+1)*10000,source:'manual',chargeReviewConfirmed:true}));
 const restored=new Engine();restored.load(JSON.parse(JSON.stringify(e.state)));
 assert.equal(restored.state.charges.length,2,'conflicting independent manual sessions cannot be erased as duplicates');
 assert.equal(restored.chargeSummary().cost,30000);
}
