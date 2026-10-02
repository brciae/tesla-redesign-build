const assert = require('node:assert/strict');
const {Engine} = require('../TeslaLocal.swiftpm/Sources/AppModule/Resources/analysis.js');
const t=Date.now()-86400000;
const row=(id,extra={})=>({id,at:t,supplyKWh:20,source:'manual',chargeReviewConfirmed:true,...extra});
const priced=(e,id)=>e.chargeSummary().rows.find(r=>r.id===id);
{
 const e=new Engine();e.settings({tariff:180,fastTariff:400,superchargerTariff:450,homePoint:{latitude:37,longitude:127}});
 e.state.charges=[row('home',{place:'집',chargeType:'ac'}),row('ac',{chargeType:'ac'}),row('dc',{chargeType:'dc'}),row('super',{chargeType:'supercharger'}),row('gps',{latitude:37,longitude:127}),row('unknown'),row('paid',{chargeType:'ac',cost:1200}),row('free',{chargeType:'dc',cost:0})];
 assert.equal(priced(e,'home').estimatedCost,3600);assert.equal(priced(e,'ac').estimatedCost,3600);
 assert.equal(priced(e,'dc').estimatedCost,8000);assert.equal(priced(e,'super').estimatedCost,9000);
 assert.equal(priced(e,'gps').estimatedCost,3600);assert.equal(priced(e,'unknown').estimatedCost,null);
 assert.equal(priced(e,'paid').estimatedCost,null);assert.equal(priced(e,'free').cost,0);
 assert.equal(e.chargeSummary().cost,1200);assert.equal(e.chargeSummary().estimatedCost,27800);
 e.settings({tariff:200});assert.equal(priced(e,'home').estimatedCost,4000,'past unpriced rows refresh without replay');
 assert.equal(e.state.charges[0].cost,undefined,'derived cost never becomes a payment');
}
{
 const e=new Engine();e.settings({tariff:200,chargeRates:[{scope:'operator',match:'채비',kind:'dc',rate:390},{scope:'place',match:'채비 A점',kind:'any',rate:300}]});
 e.state.charges=[row('place',{place:'채비 A점',chargeType:'dc'}),row('operator',{place:'채비 B점',chargeType:'dc'}),row('ac',{place:'채비 C점',chargeType:'ac'}),row('temp',{chargeType:'supercharger'})];
 assert.equal(priced(e,'place').estimatedCost,6000);assert.equal(priced(e,'operator').estimatedCost,7800);
 assert.equal(priced(e,'ac').estimatedCost,4000,'DC tariff must not leak into AC');
 assert.equal(priced(e,'temp').estimatedCost,7000);assert.match(priced(e,'temp').costRateSource,/임시/);
}
{
 const e=new Engine();e.settings({tariff:200});
 e.state.charges=[row('receipt',{at:t-1000,place:'집',chargeType:'ac',cost:5000}),row('new',{place:'집',chargeType:'ac'}),row('future',{at:t+1000,place:'집',chargeType:'ac',cost:1000}),row('estimated',{at:t-500,place:'집',chargeType:'ac',estimatedCost:100}),row('other',{place:'타지역',chargeType:'dc'})];
 assert.equal(priced(e,'new').estimatedCost,5000,'only past confirmed payment is learned');
 assert.equal(priced(e,'other').estimatedCost,7000,'home history cannot leak to public DC');
}
{
 const e=new Engine();e.settings({tariff:200});
 e.state.charges=[row('battery',{supplyKWh:null,vehicleReportedKWh:10,chargeType:'ac'}),row('none',{supplyKWh:null,chargeType:'ac'})];
 assert.equal(priced(e,'battery').estimatedCost,2000);assert.match(priced(e,'battery').costBasis,/손실 미포함/);
 assert.equal(priced(e,'none').estimatedCost,null);
 assert.throws(()=>e.settings({chargeRates:[{scope:'operator',match:'bad',kind:'dc',rate:-1}]}));
 assert.throws(()=>e.settings({fastTariff:Infinity}));
 const backup=JSON.parse(JSON.stringify(e.state));backup.settings.chargeRates=[{scope:'place',match:'bad',kind:'any',rate:-1}];assert.throws(()=>e.load(backup));
}
{
 const e=new Engine();e.settings({tariff:200});
 e.state.charges=Array.from({length:36},(_,i)=>row('duplicate-'+i,{at:t+i*60000,end:t+i*60000,source:'NAS',chargeReviewConfirmed:false,supplyKWh:40.36,vehicleReportedKWh:40.36,endSOC:80-i*.11,collectedAfterEnd:true}));
 assert.equal(e.chargeSummary().estimatedCost,8072,'quarantined duplicates must never inflate estimated costs');
 assert.equal(e.chargeSummary().estimatedCount,1);
}
{
 const e=new Engine(),vin='5YJYGDEE0LF000001';
 e.ingestFleetCharge({vin,at:t,charging:5,soc:30,addedKWh:0,chargeType:'supercharger',chargeOperator:'Tesla'},t);
 e.ingestFleetCharge({vin,at:t+60000,charging:6,soc:60,addedKWh:20},t+60000);
 assert.equal(e.chargeSummary().rows[0].chargeTypeLabel,'슈퍼차저');
 assert.equal(e.chargeSummary().estimatedCost,7000);
 const restored=new Engine();restored.load(JSON.parse(JSON.stringify(e.state)));assert.equal(restored.chargeSummary().estimatedCost,7000);
}
console.log('PASS: charge cost defaults, site/operator priority, paid/free preservation, historical rates, missing inputs, duplicate exclusion and restart');

{
 const e=new Engine(),vin='5YJYGDEE0LF000001';
 const r=(at,field,value)=>({at,field,number:typeof value==='number'?value:null,text:JSON.stringify({value}),invalid:false});
 e.settings({tariff:200,fastTariff:400});
 e.ingestArchive({vin,rows:[r(t,'DetailedChargeState','Charging'),r(t,'Soc',30),r(t,'DCChargingPower',100),r(t,'DCChargingEnergyIn',1),r(t,'ACChargingEnergyIn',43),r(t+60000,'DetailedChargeState','Complete'),r(t+60000,'Soc',60),r(t+60000,'DCChargingEnergyIn',20)]});
 const c=e.chargeSummary().rows[0];assert.equal(c.chargeType,'dc');assert.equal(c.supplyKWh,null,'AC counters are ignored during proven DC charging');assert.equal(c.estimatedCost,8000);
 console.log('PASS: NAS DC power identifies rapid charging without using AC supply counter');
}
