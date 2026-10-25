const assert=require('node:assert/strict');
const {Engine}=require('../TeslaLocal.swiftpm/Sources/AppModule/Resources/analysis.js');
const now=Date.now(),H=3600000,t=now-24*H;
const park=(id,start,end,a,b)=>({id,start,end,startSOC:a,endSOC:b,deltaSOC:a-b,startGear:'P',endGear:'D',startOdo:100,endOdo:100,classification:'parking'});
{
 const e=new Engine();e.state.parkingPeriods=[park('after',t+4*H,t+7*H,99.7,98),park('zero',t+8*H,t+10*H,97,97)];
 e.state.charges=[{id:'time-unknown',at:t,startSOC:20,endSOC:100,vehicleReportedKWh:56}];
 const p=e.parkingSummary(now);assert.equal(p.count,2,'a charge without end cannot poison every subsequent parking');assert.equal(p.excludedCount,0);assert.equal(p.rows[1].perDay,0,'zero SOC loss remains valid data');assert.equal(p.medianPerDay,6.8);
 assert.equal(e.state.parkingPeriods.length,2,'derived calculation preserves original records');
 const reload=new Engine();reload.load(JSON.parse(JSON.stringify(e.state)));assert.equal(reload.parkingSummary(now).count,2);
}
{
 const e=new Engine();e.state.parkingPeriods=[park('overnight',t,t+12*H,22,98)];
 e.state.charges=[{id:'real',at:t,end:t+8*H,startSOC:22,endSOC:100,vehicleReportedKWh:55}];
 const p=e.parkingSummary(now);assert.equal(p.count,1);const usable=p.rows.find(x=>x.classification==='parking');
 assert.equal(usable.hours,4);assert.equal(usable.startSOC,100);assert.equal(usable.endSOC,98);assert.equal(usable.perDay,12);
 assert.equal(p.excludedCount,1,'only actual charging segment is excluded');assert.equal(e.state.parkingPeriods.length,1);
 e.state.charges[0].endSOCEstimated=true;assert.equal(e.parkingSummary(now).count,0,'never split using an invented charge endpoint');
}
{
 const e=new Engine();const packet=(at,soc,added,charging)=>e.ingest({groups:{charge:{at,receivedAt:at,soc,addedKWh:added,charging}}},at);
 packet(t,40,14,5);packet(t+H,55,24.5,5);packet(t+H+60000,55,24.5,6);
 const c=e.state.charges[0];assert.equal(c.startSOCEstimated,true);assert.equal(c.observedStartSOC,40);assert.equal(c.observedStartAddedKWh,14);
 const h=e.healthIndex(now);assert.equal(h.sampleCount,1);assert.equal(h.capacityMedianKWh,70,'use observed 15%p and delta kWh, not assumed whole-session SOC');assert.equal(h.degradationPercent,null,'no invented degradation baseline');
 const restored=new Engine();restored.load(JSON.parse(JSON.stringify(e.state)));assert.equal(restored.healthIndex(now).capacityMedianKWh,70);
 c.observedStartSOC=54;assert.equal(e.healthIndex(now).sampleCount,0,'one percent SOC is too coarse for capacity');
}
{
 const e=new Engine();e.state.trips=[{id:'zero',start:t,end:t+60000,distanceKm:0,startSOC:80,endSOC:80,missing:false},{id:'gap',start:t+H,end:t+2*H,startOdo:100,endOdo:110,distanceKm:10,startSOC:80,endSOC:78,missing:true}];
 const b=e.batteryUsage(now);assert.equal(b.tripRows.length,1,'zero-distance observations remain raw but do not clutter trip energy');assert.equal(e.state.trips.length,2);assert.equal(b.socPer100Km,20,'a reception gap does not discard measured distance and SOC');
}
console.log('PASS: bounded unknown charge times, split observed parked charging, zero-loss parking, partial charge observation windows, raw-record preservation and measured partial-trip statistics');
