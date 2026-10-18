const assert=require('node:assert/strict');
const C=require('../TeslaLocal.swiftpm/Sources/AppModule/Resources/analysis.js');
const vin='5YJYGDEE0LF000001', t=Date.now()-86400000;
const fix=(at,n=0)=>({at,receivedAt:at,gpsAt:at,latitude:37.5+n*0.000001,longitude:127.1});
const drive=(at,n=0,gear='D')=>({at,receivedAt:at,gear,speedKmh:gear==='P'?0:40,odometerKm:100+n*0.01});
{
 const e=new C.Engine();e.state.settings.vin=vin;
 for(let i=0;i<=2400;i++){
  const at=t+i*1000;
  e.ingest({groups:{location:fix(at,i),charge:{at,receivedAt:at,soc:i===0?80:75},drive:drive(at,i)}},at);
 }
 const at=t+2401000;e.ingest({groups:{location:fix(at,2401),drive:drive(at,2401,'P')}},at);
 const trip=e.state.trips[0];
 assert.equal(e.state.activeTrip,null);assert.equal(trip.startSOC,80);assert.equal(trip.endSOC,75);
 assert.equal(trip.points[0].at,t);assert.equal(trip.points.at(-1).at,at);
 assert.ok(trip.points.length<=2000&&trip.routeSampled&&trip.observedPointCount===2402);
 assert.ok(!trip.destination,'Free drive never needs a destination');
 const endpoints=[trip.points[0].lat,trip.points[0].lng,trip.points.at(-1).lat,trip.points.at(-1).lng];
 const places={vin,id:trip.id,endpoints,startAddress:'출발 주소',endAddress:'도착 주소'};
 assert.equal(e.updateTripPlaces(places).changed,true);
 assert.equal(e.updateTripPlaces(places).changed,false);
 assert.throws(()=>e.updateTripPlaces({...places,vin:'other'}));
 assert.throws(()=>e.updateTripPlaces({...places,endpoints:[0,0,0,0]}));
 const restored=new C.Engine();restored.load(JSON.parse(JSON.stringify(e.state)));
 assert.equal(restored.state.trips[0].startAddress,'출발 주소');assert.equal(restored.state.trips[0].points.at(-1).at,at);
}
{
 const e=new C.Engine();e.state.settings.vin=vin;
 e.ingest({groups:{location:fix(t),drive:drive(t)}},t);
 e.ingest({groups:{location:fix(t+1000,1)}},t+1000);
 assert.equal(e.state.activeTrip.points.length,2,'Location packets alone advance the active trip');
 const restored=new C.Engine();restored.load(JSON.parse(JSON.stringify(e.state)));
 assert.equal(restored.state.trips[0].points.length,2,'Restart closure must preserve observed route');
 assert.ok(restored.state.trips[0].recovered&&restored.state.trips[0].routeIncomplete);
}
{
 const e=new C.Engine();e.state.settings.vin=vin;
 const rows=[];
 function add(dt,field,value){rows.push({at:t+dt,field,invalid:false,...(typeof value==='number'?{number:value}:{text:JSON.stringify({[field==='Location'?'locationValue':'stringValue']:value})})});}
 add(0,'Gear','D');add(0,'VehicleSpeed',25);add(0,'Odometer',100);add(0,'Soc',80);add(0,'Location',{latitude:37.5,longitude:127.1});
 add(10000,'Location',{latitude:37.51,longitude:127.11});add(10000,'Odometer',100.2);
 add(20000,'Location',{latitude:37.52,longitude:127.12});add(20000,'Odometer',100.4);add(20000,'Soc',79);add(20000,'Gear','P');add(20000,'VehicleSpeed',0);
 e.ingestArchive({vin,rows});
 assert.equal(e.state.trips.length,1);const trip=e.state.trips[0];
 assert.equal(trip.points.length,3);assert.equal(trip.points.at(-1).lat,37.52);
 const endpoints=[37.5,127.1,37.52,127.12];e.updateTripPlaces({vin,id:trip.id,endpoints,startAddress:'출발',endAddress:'도착'});
 trip.note='keep';e.ingestArchive({vin,rows});
 assert.equal(e.state.trips.length,1);assert.equal(e.state.trips[0].endAddress,'도착');assert.equal(e.state.trips[0].note,'keep');
 assert.equal(e.state.trips[0].points.length,3);
 // Replay may improve an older machine row; it must not freeze stale timing/distance.
 e.state.trips[0].end=t+10000;e.state.trips[0].distanceKm=0.1;
 e.ingestArchive({vin,rows});
 assert.equal(e.state.trips[0].end,t+20000);assert.ok(e.state.trips[0].distanceKm>0.1);
 assert.equal(e.state.trips[0].endAddress,'도착');assert.equal(e.state.trips[0].note,'keep');
}
console.log('PASS: destination-free drive, bounded full-span route, location-only samples, durable addresses/restart, NAS route replay and idempotent preservation');
