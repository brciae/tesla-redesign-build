const assert=require('node:assert/strict');
const {Engine}=require('../TeslaLocal.swiftpm/Sources/AppModule/Resources/analysis.js');
const now=Date.now(),DAY=86400000,vin='5YJYGDEE0LF000001',t=now-10*DAY;
const row=(at,field,value)=>({at,field,number:typeof value==='number'?value:null,text:JSON.stringify({value}),invalid:false});
{
 const e=new Engine();
 const packet=(at,gear,soc)=>e.ingest({groups:{drive:{at,receivedAt:at,gear,speedKmh:0},charge:{at,receivedAt:at,soc,charging:2}}},at);
 packet(t,'P',80);packet(t+3*3600000,'D',79);
 const p=e.parkingSummary(now);assert.equal(p.count,1);assert.equal(p.rows[0].evidence,'P 상태 관측 기반');assert.equal(p.medianPerDay,8);
 e.state.trips=[{id:'overlap',start:t+10000,end:t+60000}];assert.equal(e.parkingSummary(now).count,0);
 e.state.trips=[];e.state.parkingPeriods[0].startOdo=100;e.state.parkingPeriods[0].endOdo=102;assert.equal(e.parkingSummary(now).count,0,'known movement cannot use gear-only fallback');
 e.state.parkingPeriods[0].startOdo=null;e.state.parkingPeriods[0].endOdo=null;e.state.parkingPeriods[0].startGear='D';assert.equal(e.parkingSummary(now).count,0,'stopped D never becomes parking');
}
{
 const e=new Engine();e.state.charges=Array.from({length:6},(_,i)=>({id:'c'+i,at:t+i*DAY,end:t+i*DAY+3600000,startSOC:20,endSOC:100,vehicleReportedKWh:i<3?64:60,complete:true,startSOCObserved:true,endSOCObserved:true,source:'manual',chargeReviewConfirmed:true}));
 const h=e.healthIndex(now);assert.equal(h.baselineCapacityKWh,80);assert.equal(h.recentCapacityKWh,75);assert.equal(h.degradationPercent,6.3);assert.equal(h.provisional,true);
 e.state.charges=e.state.charges.slice(0,1);e.settings({healthReferenceMethod:'chargeUsable',healthReferenceKWh:80});assert.equal(e.healthIndex(now).degradationPercent,0);assert.equal(e.healthIndex(now).provisionalCapacity,true);
}
{
 const e=new Engine();const records=(at,soc,miles)=>[row(at,'Soc',soc),row(at,'RatedRange',miles),row(at,'DetailedChargeState','Complete')];
 e.ingestArchive({vin,rows:records(t,100,310)});assert.equal(e.healthIndex(now).fullChargeRange.count,1);assert.equal(e.healthIndex(now).fullChargeRange.changePercent,null);assert.equal(e.healthIndex(now).capacityMedianKWh,null);
 e.ingestArchive({vin,rows:records(t+DAY,100,300)});let h=e.healthIndex(now);assert.equal(h.fullChargeRange.count,2);assert.equal(h.fullChargeRange.changePercent,-3.2);assert.equal(h.degradationPercent,null,'range must not create kWh degradation');
 e.ingestArchive({vin,rows:records(t+DAY,100,300)});assert.equal(e.healthIndex(now).fullChargeRange.count,2,'same observation is idempotent');
 e.ingestArchive({vin,rows:records(t+2*DAY,80,250)});assert.equal(e.healthIndex(now).fullChargeRange.count,2,'80% completed charge is not full');
 e.ingestArchive({vin,rows:[row(t+3*DAY,'RatedRange',280),row(t+3*DAY+600000,'Soc',100),row(t+3*DAY+600000,'DetailedChargeState','Complete')]});assert.equal(e.healthIndex(now).fullChargeRange.count,2,'stale range excluded');
 const restored=new Engine();restored.load(JSON.parse(JSON.stringify(e.state)));assert.equal(restored.healthIndex(now).fullChargeRange.count,2);
}
{
 const e=new Engine();
 e.ingest({groups:{charge:{at:t,receivedAt:t,soc:100,charging:6,rangeKm:480}}},t);
 assert.equal(e.healthIndex(now).fullChargeRange.count,1,'live complete full range persists');
 assert.equal(e.healthIndex(now).capacityMedianKWh,null,'rated range does not create capacity');
 e.ingest({groups:{charge:{at:t+DAY,receivedAt:t+DAY,soc:80,charging:6,rangeKm:380}}},t+DAY);
 assert.equal(e.healthIndex(now).fullChargeRange.count,1);
}
console.log('PASS: gear-only parking with movement guards, six-charge relative comparison, single reference estimate, full-charge range persistence and no invented capacity');
