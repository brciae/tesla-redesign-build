/* YL */
(function(root){
  'use strict';
  const DAY=86400000;
  // v29: freshness = time since THIS app received the sample (receivedAt), with a per-group TTL that match
  // BLE read cadence. Vehicle source time (at) only rejects clock-skewed future data or very old samples;
  // Tesla keeps slow-changing groups (charge/climate/tire) with older source stamps while values are unchanged.
  const TTL={drive:30000,location:45000,closures:90000,charge:180000,climate:300000,tire:900000,media:60000,mediaDetail:60000};
  const fresh=(g,now,age=30000)=>{if(!g||!Number.isFinite(g.at)||g.at>now+120000)return false;const r=Number.isFinite(g.receivedAt)?g.receivedAt:g.at;return r<=now+5000&&now-r<=age&&now-g.at<=Math.max(age,900000);};
  const num=(v,min,max)=>typeof v==='number'&&Number.isFinite(v)&&v>=min&&v<=max;
  const optional=(v,min,max)=>v===null||v===undefined||num(v,min,max);
  const median=a=>{if(!a.length)return null;const b=[...a].sort((x,y)=>x-y),m=Math.floor(b.length/2);return b.length%2?b[m]:(b[m-1]+b[m])/2;};
  const round=(v,d=1)=>v==null?null:Math.round(v*10**d)/10**d;
  const id=()=>Date.now().toString(36)+'-'+Math.random().toString(36).slice(2,12);
  const append=(list,value)=>{if(list.length>=10000)throw Error('기록 10,000건 한도. 원본을 유지하며 내보내기 후 관리가 필요함.');list.push(value);};
  const text=(v,max=300)=>typeof v==='string'?v.slice(0,max):'';
  function initial(){return {schema:1,settings:{name:'Model Y',model:'Model Y L',vin:'',reserveSOC:20,dailyLimit:null,tariff:null,plannedKm:null},batteryBaseline:null,batteryObservations:[],groups:{},trips:[],charges:[],maintenance:[],parkingNotes:[],parkingPeriods:[],tires:[],activeTrip:null,activeCharge:null,lastPark:null,navSent:null,weather:null,lastBrief:'차량에 연결하면 최신 상태를 안내함.'};}
  // Two parking records describe the same spot when they are within ~35 m.
  function nearby(a,b,r=35){
    if(!validCoordinates(a?.latitude,a?.longitude)||!validCoordinates(b?.latitude,b?.longitude))return false;
    const dLat=(a.latitude-b.latitude)*111320,dLng=(a.longitude-b.longitude)*111320*Math.cos(a.latitude*Math.PI/180);
    // v1.41: a geocoded home address can sit 50-150 m from the actual parking bay (apartment complexes).
    return Math.sqrt(dLat*dLat+dLng*dLng)<=r;
  }
  function validCoordinates(lat,lng){return num(lat,-90,90)&&num(lng,-180,180)&&!(lat===0&&lng===0);}
  const freshLocation=(g,now)=>{
    if(!fresh(g,now,TTL.location)||!validCoordinates(g.latitude,g.longitude)||
       (g.positionStatus&&g.positionStatus!=='available')||g.estimatedGPSValid===false)return false;
    const measured=Number.isFinite(g.gpsAt)?g.gpsAt:g.at;
    return measured<=now+5000&&now-measured<=TTL.location;
  };
  // Match the Fleet drive source-age limit; slow-changing charge/climate groups retain their own rules.
  const freshNavigation=(g,now)=>fresh(g,now)&&g.at<=now+5000&&now-g.at<=120000;
  function navURL(drive,now,appname){
    if(!freshNavigation(drive,now))throw Error('목적지 데이터가 오래됨. 차량에서 다시 수신해야 함.');
    if(!drive.destination?.trim())throw Error('활성 목적지가 없음. 차량 내비에 목적지를 설정해야 함.');
    if(!validCoordinates(drive.destinationLat,drive.destinationLng))throw Error('목적지 좌표 미수신. 네이버에서 장소를 직접 확인해야 함.');
    if(!num(drive.destinationLat,31.43,44.35)||!num(drive.destinationLng,122.37,132))throw Error('네이버 문서의 국내 좌표 범위 밖임.');
    if(typeof appname!=='string'||!appname.trim())throw Error('앱 식별자 없음');
    const q={dlat:drive.destinationLat,dlng:drive.destinationLng,dname:drive.destination,appname};
    return 'nmap://navigation?'+Object.keys(q).map(k=>k+'='+encodeURIComponent(q[k])).join('&');
  }
  function navigationEvent(drive,now,lastSent,appname){
    if(!freshNavigation(drive,now)||!Number.isFinite(drive.receivedAt)||now-drive.receivedAt>30000||drive.receivedAt>now)return {type:'wait'};
    if(!drive.destination?.trim())return {type:'clear'};
    const url=navURL(drive,now,appname);
    const token=JSON.stringify([drive.destination.trim(),Number(drive.destinationLat.toFixed(5)),Number(drive.destinationLng.toFixed(5))]);
    return {type:token===lastSent?'same':'route',token,url};
  }
  function embeddedDestination(drive,now){
    if(!freshNavigation(drive,now)||!Number.isFinite(drive.receivedAt)||drive.receivedAt>now||now-drive.receivedAt>30000)return {type:'wait'};
    // A complete, fresh drive response with every route field absent needs repeated confirmation.
    if(drive.routeFieldsAbsent===true)return {type:'absent',at:drive.at,receivedAt:drive.receivedAt,parked:drive.gear==='P'};
    // An arbitrary partial group is not a vehicle destination-clear event.
    if(typeof drive.destination!=='string')return {type:'wait'};
    const name=drive.destination.trim();
    if(!name)return {type:'wait'};
    if(!validCoordinates(drive.destinationLat,drive.destinationLng))return {type:'wait'};
    return {type:'route',name:name.slice(0,300),latitude:drive.destinationLat,longitude:drive.destinationLng,
      at:drive.at,receivedAt:drive.receivedAt,token:JSON.stringify([name.slice(0,300),Number(drive.destinationLat.toFixed(5)),Number(drive.destinationLng.toFixed(5))])};
  }
  // Memory-only lifecycle. Never exported with vehicle records or restored on launch.
  // Match coordinate storage precision, not an invented geographic radius.
  // Renaming a POI at the same coordinates must not restart guidance.
  const sameSpot=(a,b)=>!!a&&!!b&&Math.fround(a.lat)===Math.fround(b.lat)&&Math.fround(a.lng)===Math.fround(b.lng);
  class EmbeddedRouteGate{
    constructor(){this.generation=0;this.active=null;this.blocked=null;this.absence=null;this.lastObservation=0;this.lastSource=0;}
    observe(event,ready,guiding){
      if(event.type==='route'||event.type==='absent'){
        if(!Number.isFinite(event.at)||!Number.isFinite(event.receivedAt)||event.at<this.lastSource||event.receivedAt<this.lastObservation)return {type:'wait'};
        this.lastSource=event.at;
      }
      if(event.type==='clear'){this.cancel(false);this.blocked=null;return {type:'clear'};}
      if(event.type==='absent'){
        if(!Number.isFinite(event.at)||!Number.isFinite(event.receivedAt)||event.receivedAt<=this.lastObservation)return {type:'wait'};
        this.lastObservation=event.receivedAt;
        const previous=this.absence;
        this.absence=previous&&previous.parked===(event.parked===true)&&event.receivedAt>previous.last&&event.receivedAt-previous.last<=75000?
          {first:previous.first,last:event.receivedAt,count:previous.count+1,parked:event.parked===true}:{first:event.receivedAt,last:event.receivedAt,count:1,parked:event.parked===true};
        // Established guidance tolerates transient empty route groups (stops, Tesla re-routing, BLE partials). 
        // Tunnel/GPS/network loss may omit Tesla route fields for minutes. Absence while moving
        // is not a destination cancellation; keep established local guidance until P/explicit end.
        if(this.active&&guiding&&!event.parked)return {type:'wait'};
        const need=event.parked?{count:1,span:0}:{count:3,span:3000};
        if(this.absence.count>=need.count&&this.absence.last-this.absence.first>=need.span){
          this.cancel(false);this.blocked=null;return {type:'clear',reason:'vehicleRouteAbsent'};
        }
        return {type:'wait'};
      }
      if(event.type!=='route')return {type:'wait'};
      this.absence=null;this.lastObservation=Math.max(this.lastObservation,event.receivedAt||0);
      const spot={lat:event.latitude,lng:event.longitude};
      if(this.active&&sameSpot(this.active,spot))return {...event,type:'refresh',ticket:this.generation};
      if(!ready||sameSpot(this.blocked,spot))return {type:'wait'};
      this.active=spot;this.blocked=null;
      return {...event,type:'start',ticket:++this.generation};
    }
    current(ticket){return this.active!==null&&ticket===this.generation;}
    finish(ticket){if(!this.current(ticket))return false;this.cancel(true);return true;}
    cancel(block=true){if(block&&this.active)this.blocked=this.active;this.active=null;this.absence=null;++this.generation;}
    retry(){this.blocked=null;}
    reset(){this.cancel(false);this.blocked=null;this.lastObservation=0;this.lastSource=0;}
  }
  // v35: a receipt or in-car charge screen should fill the whole form, not just two fields.
  // Values are taken from the line that carries their label (and the line after it, since OCR often
  // splits "결제금액" and "12,300원"), so several kWh/won numbers on one receipt no longer give up.
  function parseReceipt(value){
    const s=text(value,20000);
    const lines=s.split(/[\n\r]+/).map(l=>l.trim()).filter(Boolean);
    const digits=t=>Number(String(t).replace(/[,\s]/g,''));
    const findLabeled=(labels,unit,lo,hi,skip)=>{
      for(let i=0;i<lines.length;i++){
        const line=lines[i];
        if(!labels.some(l=>line.includes(l)))continue;
        if(skip&&skip.test(line))continue;
        for(const probe of [line,lines[i+1]||'']){
          const m=probe.match(unit);
          if(m){const v=digits(m[1]);if(num(v,lo,hi))return v;}
        }
      }
      return null;
    };
    // Fallback candidates are collected per line so a cumulative/odometer line cannot win.
    const noise=/누적|잔량|총\s*주행|주행거리|포인트|할인|적립|단가|원\s*\/\s*kWh/;
    const all=(re,lo,hi)=>lines.filter(l=>!noise.test(l))
      .flatMap(l=>[...l.matchAll(re)].map(m=>digits(m[1]))).filter(v=>num(v,lo,hi));
    const kwhRe=/(\d+(?:[.,]\d+)?)\s*kWh/i, wonRe=/([\d,]+)\s*원/;
    const unitPrice=(()=>{
      const m=s.match(/([\d,]+(?:\.\d+)?)\s*원\s*\/\s*kWh/i)||s.match(/단가[^\d]{0,8}([\d,]+(?:\.\d+)?)/);
      const v=m?digits(m[1]):null; return num(v,10,2000)?v:null;
    })();
    const kwhAll=all(/(\d+(?:[.,]\d+)?)\s*kWh/gi,0.1,300);
    const wonAll=all(/([\d,]+)\s*원(?!\s*\/)/g,0,1000000);
    let supplyKWh=findLabeled(['충전량','사용량','전력량','공급량','충전전력','충전 전력','판매량'],kwhRe,0.1,300,/단가|누적|잔량/);
    let guessed=false;
    if(supplyKWh==null&&kwhAll.length){supplyKWh=kwhAll.length===1?kwhAll[0]:Math.max(...kwhAll);guessed=guessed||kwhAll.length>1;}
    let cost=findLabeled(['결제금액','승인금액','총액','합계','총 금액','결제 금액','이용금액','요금','금액','결제'],wonRe,0,1000000,/단가|원\/kWh|포인트|할인/);
    if(cost==null&&wonAll.length){cost=wonAll.length===1?wonAll[0]:Math.max(...wonAll);guessed=guessed||wonAll.length>1;}
    if(cost==null&&unitPrice!=null&&supplyKWh!=null)cost=Math.round(unitPrice*supplyKWh);
    if(supplyKWh==null&&unitPrice!=null&&cost!=null&&cost>0)supplyKWh=round(cost/unitPrice,2);
    const date=s.match(/(20\d{2})[.\-/년\s]+(\d{1,2})[.\-/월\s]+(\d{1,2})/);
    const time=s.match(/(?:^|[^\d:])([01]?\d|2[0-3])\s*[:시]\s*([0-5]\d)/);
    // SOC either as a range ("45% → 80%") or as labelled start/end values.
    const range=s.match(/(\d{1,3})\s*%\s*(?:→|->|~|–|-|>|에서)\s*(\d{1,3})\s*%/);
    let startSOC=range?Number(range[1]):findLabeled(['시작 SOC','시작','충전 시작','개시'],/(\d{1,3})\s*%/,0,100);
    let endSOC=range?Number(range[2]):findLabeled(['종료 SOC','종료','완료','도달','목표'],/(\d{1,3})\s*%/,0,100);
    if(!num(startSOC,0,100))startSOC=null;
    if(!num(endSOC,0,100)||(startSOC!=null&&endSOC<startSOC))endSOC=null;
    if(endSOC==null&&startSOC==null){
      // An in-car screen often shows only the target ("80%"); a single bare percentage is the end SOC.
      const bare=lines.filter(l=>!noise.test(l)).flatMap(l=>[...l.matchAll(/(\d{1,3})\s*%/g)].map(m=>Number(m[1]))).filter(v=>num(v,1,100));
      if(bare.length===1)endSOC=bare[0];
    }
    const minutes=(()=>{
      const h=s.match(/(\d{1,2})\s*시간\s*(\d{1,2})?\s*분?/),m=s.match(/(\d{1,3})\s*분/);
      if(h)return Number(h[1])*60+(h[2]?Number(h[2]):0);
      return m&&num(Number(m[1]),1,600)?Number(m[1]):null;
    })();
    const placeHints=/충전소|스테이션|충전기|슈퍼차저|supercharger|환경부|한국전력|한전|파워큐브|에버온|차지비|채비|플러그링크|이피트|E-?pit|GS|SK|LG|현대|스타필드|이마트|롯데|주차장|지점|점$/i;
    const place=(()=>{
      const hit=lines.find(l=>l.length<=40&&placeHints.test(l));
      if(hit)return text(hit,40);
      const plain=lines.find(l=>l.length>=2&&l.length<=30&&!/\d/.test(l)&&!/영수증|결제|카드|승인|합계|금액/.test(l));
      return plain?text(plain,40):'';
    })();
    const filled=[];
    if(supplyKWh!=null)filled.push('supplyKWh');
    if(cost!=null)filled.push('cost');
    if(date)filled.push('date');
    if(time)filled.push('time');
    if(startSOC!=null)filled.push('startSOC');
    if(endSOC!=null)filled.push('endSOC');
    if(place)filled.push('place');
    if(unitPrice!=null)filled.push('unitPrice');
    if(minutes!=null)filled.push('minutes');
    const timeLine=lines.find(l=>time&&l.includes(time[0].trim()))??'';
    const timeBasis=/시작|개시/.test(timeLine)?'start':/종료|완료/.test(timeLine)?'end':'unknown';
    return {supplyKWh,cost,unitPrice,startSOC,endSOC,place,minutes,timeBasis,
      dateText:date?`${date[1]}-${date[2].padStart(2,'0')}-${date[3].padStart(2,'0')}`:null,
      timeText:time?`${String(time[1]).padStart(2,'0')}:${time[2]}`:null,
      filled,filledCount:filled.length,
      ambiguous:guessed||(kwhAll.length>1&&supplyKWh==null)||(wonAll.length>1&&cost==null),raw:s};
  }
  // Estimates are derived at read time. Never overwrite a paid amount or learn from an estimate.
  const rateKey=v=>String(v??'').toLowerCase().replace(/\s+/g,'').trim();
  // Public standard tariffs checked 2026-10-15. Unknown prices stay null.
  // No inferred roaming direction, card discount, subscription or negotiated site price.
  const tariffCatalog=[
    {operator:'플러그링크',aliases:['pluglink'],kind:'ac',member:292,nonmember:357,from:'2026-08-01',url:'https://pluglink.kr/charge',condition:'완속 40kW 미만 · 비회원 IC 카드 결제 가능 기기 · 별도 협의 장소 제외'},
    {operator:'플러그링크',aliases:['pluglink'],kind:'dc',member:null,nonmember:528,from:'2026-08-01',url:'https://pluglink.kr/charge',condition:'40kW 이상 · 회원가는 출력 구간 확인 필요 · 비회원 IC 카드 결제 가능 기기'},
    {operator:'GS차지비',aliases:['차지비','gschargev','chargev','지에스차지비'],kind:'ac',member:295,nonmember:470,from:'2026-08-01',url:'https://www.gschargev.co.kr/pricing.html',condition:'일반 완속 3kW 초과 30kW 미만 · 서울시 지원사업/과금형 3kW/개별 요금 제외'},
    {operator:'GS차지비',aliases:['차지비','gschargev','chargev','지에스차지비'],kind:'dc',member:null,nonmember:470,from:'2026-08-01',url:'https://www.gschargev.co.kr/pricing.html',condition:'일반 급속 50kW 이상 · 회원가는 커넥터 정격 출력 확인 필요 · 서울시 지원사업 제외'},
    {operator:'볼트업',aliases:['LG유플러스','LG유플러스볼트업','LG U+','voltup','엘지유플러스볼트업'],kind:'ac',member:295,nonmember:null,from:null,url:'https://voltup.kr/',condition:'50kW 미만 · 비회원가 미확인 · 주말/공휴일 프로모션 별도'},
    {operator:'볼트업',aliases:['LG유플러스','LG유플러스볼트업','LG U+','voltup','엘지유플러스볼트업'],kind:'dc',member:350,nonmember:null,from:null,url:'https://voltup.kr/',condition:'50kW 이상 · 비회원가 미확인 · 제휴 충전소 제외'},
    {operator:'해피차저',aliases:['한국전기차충전서비스','한국전기차충전서비스(주)','happecharger','happycharger'],kind:'ac',member:298,nonmember:null,from:null,url:'https://tweb.happecharger.com/happecharger/membership',condition:'해피차저·현대엔지니어링 완속 7kW · 비회원 완속가는 표 구간 확인 필요'},
    {operator:'해피차저',aliases:['한국전기차충전서비스','한국전기차충전서비스(주)','happecharger','happycharger'],kind:'dc',member:398,nonmember:550,from:null,url:'https://tweb.happecharger.com/happecharger/membership',condition:'해피차저·현대엔지니어링 급속 50kW 이상 · 로밍 제외'},
    {operator:'파워큐브',aliases:['파워큐브코리아','powercube','(주)파워큐브코리아'],kind:'ac',member:null,nonmember:null,from:'2025-01-06',url:'https://www.powercube.co.kr/noticedetail.php?idx=13212',condition:'완속 고압 295·저압 309원/kWh · 과금형 콘센트 269원/kWh · 전압/상품/회원 조건 확인 필요'},
    {operator:'채비',aliases:['대영채비','chaevi','채비(주)'],kind:'ac',member:275,nonmember:null,from:'2025-03-20',url:'https://www.chaevi.com/kr/customer/notice.php?bgu=view&idx=496',condition:'2025-03-20 완속 회원 공지 · 중속 30kW 315원/kWh · 비회원가/이후 변경 미확인 · 위탁/구독 할인 제외'}
  ].map((r,i)=>({...r,id:'public-tariff-'+i,checked:'2026-10-15'}));
  const canonicalOperator=value=>{const clean=v=>rateKey(v).replace(/주식회사|\(주\)/g,'');const key=clean(value);return tariffCatalog.find(r=>[r.operator,...r.aliases].some(n=>clean(n)===key))?.operator??String(value??'').trim();};
  const memberPricing=(c,s)=>typeof c.memberPricing==='boolean'?c.memberPricing:(s.chargeMemberOperators??[]).some(x=>rateKey(canonicalOperator(x))===chargeIdentity(c,s).operator);
  function validateRates(s){
    if(s.chargeMemberOperators!=null&&(!Array.isArray(s.chargeMemberOperators)||s.chargeMemberOperators.length>100||s.chargeMemberOperators.some(x=>typeof x!=='string'||x.length>120)))throw Error('회원가 사업자 설정 오류');
    for(const k of ['fastTariff','superchargerTariff'])if(!optional(s[k],0,10000))throw Error('충전 단가 범위 오류');
    if(s.homePoint!=null&&!validCoordinates(s.homePoint.latitude,s.homePoint.longitude))throw Error('집 좌표 오류');
    if(!optional(s.healthReferenceKWh,20,200)||!optional(s.healthBatteryStartAt,0,Date.now()+5000)||(s.healthReferenceMethod!=null&&!['bmsNominal','chargeUsable'].includes(s.healthReferenceMethod)))throw Error('배터리 비교 기준 오류');
    if(!optional(s.homeRadiusM,50,2000))throw Error('집 반경은 50~2000m');
    if(s.homeRegions!=null&&(!Array.isArray(s.homeRegions)||s.homeRegions.length>50))throw Error('집 주소 이력 최대 50개');
    let lastEnd=0;
    for(const h of [...(s.homeRegions??[])].sort((a,b)=>a.start-b.start)){
      if(!validCoordinates(h.latitude,h.longitude)||!num(h.radius,50,2000)||!num(h.start,0,1e14)||!optional(h.end,h.start+1,1e14)||h.start<lastEnd)throw Error('집 주소·반경·적용 기간 오류');
      lastEnd=h.end??1e14;
    }
    if(s.chargeRates!=null&&(!Array.isArray(s.chargeRates)||s.chargeRates.length>100))throw Error('장소·사업자 단가 최대 100개');
    for(const r of s.chargeRates??[])if(!r||typeof r.match!=='string'||!r.match.trim()||r.match.length>120||!['place','operator'].includes(r.scope)||!['any','ac','dc','supercharger'].includes(r.kind)||!num(r.rate,0,10000))throw Error('장소·사업자 단가 형식 오류');
  }
  function chargeIdentity(c,s){
    const place=rateKey(c.place||c.siteMatch?.name), provider=rateKey(canonicalOperator(c.chargeOperator||c.siteMatch?.operator));
    const supercharger=c.chargeType==='supercharger'||/supercharger|슈퍼차저|수퍼차저/.test(place+provider);
    const regions=s.homeRegions?.length?s.homeRegions.filter(h=>c.at>=h.start&&(h.end==null||c.at<h.end)):[{...s.homePoint,radius:s.homeRadiusM??600}];
    const home=(!supercharger&&c.chargeType!=='dc')&&((place&&['집','집완속','자택','home'].includes(place))||regions.some(p=>nearby(c,p,p.radius??600)||(rateKey(p.name).length>=4&&place.includes(rateKey(p.name))))||(!s.homeRegions?.length&&(s.homeSpots??[]).some(p=>nearby(c,p,s.homeRadiusM??600))));
    const kind=supercharger?'supercharger':c.chargeType==='dc'?'dc':c.chargeType==='ac'||home||num(c.nasSupplyKWh,0.01,300)||num(c.supplyKWh,0.01,300)&&c.source==='NAS'?'ac':'unknown';
    const operator=provider||(/채비|chaevi/.test(place)?'채비':/환경부|기후부/.test(place)?'환경부':/한전|한국전력/.test(place)?'한국전력':/에버온/.test(place)?'에버온':/파워큐브/.test(place)?'파워큐브':/차지비/.test(place)?'차지비':/플러그링크/.test(place)?'플러그링크':supercharger?'tesla':'');
    return {place,operator:rateKey(canonicalOperator(operator)),kind,home};
  }
  function costEstimate(c,s,history){
    const identity=chargeIdentity(c,s), {place,operator,kind,home}=identity;
    const kwh=c.supplyKWh??c.nasSupplyKWh??c.vehicleReportedKWh??c.estimatedStoredKWh;
    const basis=c.supplyKWh!=null||c.nasSupplyKWh!=null?'공급량':c.vehicleReportedKWh!=null?'차량 보고량 · 충전 손실 미포함':'SOC 추정량 · 충전 손실 미포함';
    const isMember=memberPricing(c,s);
    const catalog=tariffCatalog.find(r=>rateKey(r.operator)===operator&&r.kind===kind);
    const result={estimatedCost:null,estimatedUnitPrice:null,costBasis:basis,costRateSource:'',memberPricingApplied:isMember,chargeOperator:c.chargeOperator||c.siteMatch?.operator||'',place:c.place||c.siteMatch?.name||'',tariffURL:catalog?.url??'',tariffChecked:catalog?.checked??'',tariffCondition:catalog?.condition??'',chargeTypeLabel:home?'집 완속':({ac:'완속 AC',dc:'급속 DC',supercharger:'슈퍼차저'})[kind]??'충전 방식 미확인'};
    if(num(c.cost,0,1e7)){result.costRateSource='확인 결제액';return result;}
    let rate=null,source='';
    const rules=(s.chargeRates??[]).filter(r=>(r.kind==='any'||r.kind===kind)&&(r.scope==='place'?rateKey(r.match)===place:rateKey(canonicalOperator(r.match))===operator));
    const rule=rules.sort((a,b)=>(a.scope==='place'?0:1)-(b.scope==='place'?0:1)||(a.kind==='any'?1:0)-(b.kind==='any'?1:0))[0];
    if(rule){rate=rule.rate;source=(rule.scope==='place'?'장소':'사업자')+' 등록 단가 · '+rule.match;}
    // Only past confirmed payments with supplied kWh from the same place/operator and charging type.
    if(rate==null){
      const past=list=>(list??[]).find(x=>x.id!==c.id&&x.at<c.at&&c.at-x.at<=180*DAY);
      const eligible=list=>(list??[]).filter(x=>(!catalog||typeof x.memberPricing==='boolean')&&memberPricing(x,s)===isMember&&!!x.roamingPricing===!!c.roamingPricing);
      const previous=past(eligible(history.get(kind+'|place|'+place)))??past(eligible(history.get(kind+'|operator|'+operator)));
      if(previous&&num(previous.cost/previous.supplyKWh,0,10000)){rate=previous.cost/previous.supplyKWh;source='최근 확인 결제 단가 · '+(previous.place||previous.chargeOperator);}
    }
    if(rate==null&&catalog){
      const effective=Date.parse((catalog.from??catalog.checked)+'T00:00:00+09:00');
      const publicRate=isMember?catalog.member:catalog.nonmember;
      const acPower=c.chargerRatedKW??c.siteMatch?.ratedKW;
      const memberPowerUnknown=isMember&&kind==='ac'&&(['GS차지비','채비','해피차저'].includes(catalog.operator))&&!num(acPower,0.1,1000);
      const powerExcluded=kind==='ac'&&num(acPower,0,1000)&&((catalog.operator==='GS차지비'&&(acPower<=3||acPower>=30))||(catalog.operator==='채비'&&acPower>=30)||(catalog.operator==='플러그링크'&&acPower>=40)||(catalog.operator==='볼트업'&&acPower>=50));
      const productMismatch=isMember&&catalog.operator==='해피차저'&&kind==='ac'&&acPower!==7;
      if(c.roamingPricing||c.at<effective||powerExcluded||memberPowerUnknown||productMismatch||!num(publicRate,0,10000)){
        result.costRateSource=c.roamingPricing?'로밍 단가 별도 확인 필요':c.at<effective?'해당 충전일의 사업자 공시 단가 미확인':(powerExcluded||memberPowerUnknown||productMismatch)?'충전기 출력 구간별 단가 확인 필요':(isMember?'회원':'비회원')+' 공시 단가 미확인';
        return result;
      }
      rate=publicRate;source='사업자 공식 '+(isMember?'자체 회원가':'비회원가')+' · '+catalog.checked+' 확인 · 현장 예외 요금 미확인';
    }
    if(rate==null&&home&&s.tariff!=null){rate=s.tariff;source='등록한 집·완속 단가';}
    if(rate==null&&kind==='ac'&&s.tariff!=null){rate=s.tariff;source='등록 완속 기준 · 현장 단가 미확인';}
    if(rate==null&&kind==='supercharger'&&s.superchargerTariff!=null){rate=s.superchargerTariff;source='등록 슈퍼차저 예상 단가';}
    if(rate==null&&['dc','supercharger'].includes(kind)){rate=s.fastTariff??350;source=s.fastTariff!=null?'등록 급속 예상 단가':'급속 임시 계산 기준 350원/kWh';}
    if(rate==null){result.costRateSource='단가 또는 충전 방식 확인 필요';return result;}
    result.estimatedUnitPrice=round(rate,2);result.costRateSource=source;
    if(num(kwh,0,300))result.estimatedCost=round(kwh*rate,0);else result.costRateSource+=' · 충전량 미확인';
    return result;
  }
  function applyChargeMetadata(c,g){
    if(!c)return;
    if(['ac','dc','supercharger'].includes(g.chargeType)&&!c.chargeTypeManual)c.chargeType=g.chargeType;
    if(g.chargeOperator&&!c.chargeOperator)c.chargeOperator=text(g.chargeOperator,120);
    if(g.place&&!c.place)c.place=text(g.place,120);
    if(!c.collectedAfterEnd&&validCoordinates(g.latitude,g.longitude)&&!validCoordinates(c.latitude,c.longitude)){c.latitude=g.latitude;c.longitude=g.longitude;}
  }
  function validateState(s,opts={}){
    if(!s||s.schema!==1||typeof s.settings!=='object'||!s.groups||typeof s.groups!=='object')throw Error('지원하지 않는 백업 형식');
    const checkIds=(a,name)=>{if(!Array.isArray(a)||a.length>10000)throw Error(name+' 자료 크기 초과');const seen=new Set();for(let i=0;i<a.length;i++){const r=a[i];if(!r||typeof r!=='object'){a.splice(i,1);i--;continue;}if(typeof r.id!=='string'||!r.id||r.id.length>100||seen.has(r.id)){r.id=id();}seen.add(r.id);}};
    for(const name of ['trips','charges','maintenance','parkingNotes','parkingPeriods','tires'])checkIds(s[name],name);
    if(typeof s.settings.vin!=='string'||(s.settings.vin&&!/^[A-HJ-NPR-Z0-9]{17}$/.test(s.settings.vin)))throw Error('백업 VIN 오류');
    if(!num(s.settings.reserveSOC,0,80)||!optional(s.settings.assumedCapacityKWh,20,200)||!optional(s.settings.dailyLimit,1,100)||!optional(s.settings.tariff,0,10000)||!optional(s.settings.plannedKm,0,3000))throw Error('백업 설정 수치 오류');
    for(const t of s.trips){if(!num(t.start,0,1e14)||!num(t.end,t.start,1e14)||!optional(t.distanceKm,0,100000)||!optional(t.startSOC,0,100)||!optional(t.endSOC,0,100)||!optional(t.observedMotorUsedKWh,0,1e5)||!optional(t.observedMotorRecoveredKWh,0,1e5)||!optional(t.observedMotorNetKWh,-1e5,1e5)||!optional(t.observedMotorDistanceKm,0,100000)||!optional(t.observedMotorWhPerKm,-1e6,1e6))throw Error('운행 기록 수치 오류');}
    if(s.batteryObservations!=null&&(!Array.isArray(s.batteryObservations)||s.batteryObservations.length>10000||s.batteryObservations.some(p=>p.method!=='bmsNominal'||!num(p.at,0,1e14)||!num(p.value,20,200))))throw Error('배터리 관측 기록 오류');
    validateRates(s.settings);
    for(const c of s.charges)validateCharge(c);
    for(const g of Object.values(s.groups)){if(!g||!num(g.at,0,1e14))throw Error('상태 수신시각 오류');}
    for(const t of s.tires){if(!num(t.at,0,1e14)||!Array.isArray(t.values)||t.values.length!==4||t.values.some(v=>!optional(v,0,8)))throw Error('타이어 기록 오류');}
    for(const m of s.maintenance){if(!num(m.at,0,1e14)||!optional(m.odometerKm,0,10000000)||!optional(m.nextKm,0,10000000)||!optional(m.cost,0,100000000))throw Error('정비 기록 오류');}
    for(const p of s.parkingNotes){if(!optional(p.visits,1,100000)||!num(p.at,0,1e14)||!optional(p.latitude,-90,90)||!optional(p.longitude,-180,180)||typeof p.note!=='string'||typeof p.photoName!=='string'||(p.photoName&&!/^[A-Za-z0-9-]+\.(jpg|png)$/.test(p.photoName)))throw Error('주차 메모 형식 오류');}
    for(const p of s.parkingPeriods){if(!num(p.start,0,1e14)||!num(p.end,p.start,1e14)||!optional(p.deltaSOC,-100,100))throw Error('주차 기간 오류');}
    // Copy only known top-level keys. Never restore running sessions or an active route.
    const clean=initial();for(const k of Object.keys(clean))if(k in s)clean[k]=JSON.parse(JSON.stringify(s[k]));
    if(s.batteryBaseline){const b=s.batteryBaseline;if(!num(b.at,0,1e14)||b.healthPercent!==100||b.source!=='assumedNew'||!optional(b.capacityKWh,20,200))throw Error('배터리 기준 형식 오류');clean.batteryBaseline={at:b.at,healthPercent:100,source:'assumedNew',capacityKWh:b.capacityKWh??null,referenceIds:[]};}
    if(s.activeTrip){const t=s.activeTrip;if(typeof t.id!=='string'||!t.id)t.id=id();if(typeof t.id!=='string'||!num(t.start,0,1e14)||!num(t.lastAt,t.start,1e14)||!optional(t.startSOC,0,100)||!optional(t.lastSOC,0,100)||!num(t.distanceKm,0,100000))throw Error('진행 중 운행 기록 오류');const resume=opts.resumeActive===true&&Date.now()-t.lastAt<=1800000&&num(t.lastOdo,0,1e7);if(resume)clean.activeTrip={...JSON.parse(JSON.stringify(t)),resumed:true,lastPowerKW:null,parkAt:t.parkAt??null,points:Array.isArray(t.points)?t.points.slice(-2000):[]};else if(!clean.trips.some(x=>x.id===t.id))append(clean.trips,{id:t.id,start:t.start,end:t.lastAt,startSOC:t.startSOC??null,endSOC:t.lastSOC??null,distanceKm:t.distanceKm,missing:true,points:[],recovered:true});}
    let resumedCharge=null;
    if(s.activeCharge){const c={...s.activeCharge,complete:false,storedKWh:null,supplyKWh:null,cost:null};validateCharge(c);if(typeof c.id!=='string'||!c.id)c.id=id();const age=Date.now()-(c.lastAt??c.at);if(opts.resumeActive===true&&age>=0&&age<=48*3600000){clean.activeCharge={...c,resumed:true};resumedCharge=clean.activeCharge;}else if(!clean.charges.some(x=>x.id===c.id))append(clean.charges,{...c,end:c.lastAt??c.at,source:c.source??'차량 복구',partial:true});}
    // v30: a trip interrupted by an app restart within 30 min continues (odometer continuity is re-checked on the next sample).
    if(!(opts.resumeActive===true&&clean.activeTrip&&s.activeTrip&&clean.activeTrip.id===s.activeTrip.id))clean.activeTrip=null;
    clean.activeCharge=resumedCharge;clean.navSent=null;clean.weather=null;
    return clean;
  }
  function validateCharge(c){
    for(const key of ['memberPricing','roamingPricing'])if(c[key]!=null&&typeof c[key]!=='boolean')throw Error('충전 회원·로밍 조건 오류');
    if(!num(c.at,0,1e14)||!optional(c.startSOC,0,100)||!optional(c.endSOC,0,100)||!optional(c.supplyKWh,0,300)||!optional(c.storedKWh,0,300)||!optional(c.cost,0,10000000))throw Error('충전 기록 수치 오류');
    if(!optional(c.durationMinutes,0,10080))throw Error('충전 소요시간 오류');
    if(c.end!=null&&!num(c.end,c.at,Math.min(1e14,c.at+7*DAY)))throw Error('충전 종료 시각은 시작 이후 7일 이내여야 합니다.');
    if(c.startSOC!=null&&c.endSOC!=null&&c.endSOC<c.startSOC)throw Error('충전 종료 잔량이 시작보다 작음');
  }
  // Keep original records. A suspected duplicate is excluded, never silently deleted.
  function auditCharges(rows){
    const accepted=[], review=[], boundaries=rows.filter(c=>!c.collectedAfterEnd);
    const energy=c=>c.vehicleReportedKWh??c.nasSupplyKWh??c.supplyKWh;
    const end=c=>c.end??c.lastAt??c.at;
    // Prefer observed intervals to completion-only snapshots, even if NAS arrived later.
    const ordered=[...rows].sort((a,b)=>Number(!!a.collectedAfterEnd)-Number(!!b.collectedAfterEnd)||a.at-b.at);
    for(const c of ordered){
      delete c.chargeExcluded;delete c.chargeReviewReason;delete c.chargeDuplicateOf;
      if(c.chargeCounterConflict&&!c.chargeReviewConfirmed){c.chargeExcluded=true;c.chargeReviewReason='충전 중 누적량 급감 · 회차 경계 확인 필요 · 합계 제외';review.push(c);continue;}
      let duplicate=null;
      if(!c.chargeReviewConfirmed){
        duplicate=accepted.find(p=>{
          const sameEnergy=num(energy(c),0.01,300)&&num(energy(p),0.01,300)&&Math.abs(energy(c)-energy(p))<=Math.max(2,energy(p)*0.1);
          if(!sameEnergy)return false;
          if(c.collectedAfterEnd){
            const elapsed=c.at-end(p);
            const contained=c.at>=p.at&&c.at<=end(p);
            const drift=num(c.endSOC,0,100)&&num(p.endSOC,0,100)&&c.endSOC<=p.endSOC+1;
            const newSession=boundaries.some(n=>n.id!==p.id&&n.id!==c.id&&n.at>end(p)&&n.at<c.at);
            return contained||(!newSession&&elapsed>=0&&elapsed<=48*3600000&&drift);
          }
          // Two independent sources describing the same interval also require review.
          return c.at===p.at&&end(c)===end(p)&&c.startSOC===p.startSOC&&c.endSOC===p.endSOC;
        });
      }
      if(duplicate){c.chargeExcluded=true;c.chargeDuplicateOf=duplicate.id;c.chargeReviewReason='같은 충전의 반복 수집 의심 · 합계에서 제외 · 원본 보존';review.push(c);}
      else accepted.push(c);
    }
    return {accepted,review};
  }
  // Join only unique receipt/session pairs. Raw evidence remains in state for review.
  function reconciledCharges(raw){
    const receipt=c=>/수동|OCR|manual/.test(c.source??'')||!!c.receiptText;
    const receipts=raw.filter(receipt), sessions=raw.filter(c=>!receipt(c)&&!c.collectedAfterEnd&&num(c.end,c.at+1,1e14));
    const matches=(r,c)=>{
      if(r.chargeReviewConfirmed||c.chargeReviewConfirmed||r.atPrecision==='day'||c.chargeCounterConflict)return false;
      for(const key of ['startSOC','endSOC'])if(r[key]!=null&&c[key]!=null&&Math.abs(r[key]-c[key])>2)return false;
      if(r.supplyKWh!=null&&c.supplyKWh!=null&&Math.abs(r.supplyKWh-c.supplyKWh)>Math.max(1,c.supplyKWh*.05))return false;
      const near=(a,b)=>Math.abs(a-b)<=120000;
      if(r.end!=null)return near(r.at,c.at)&&near(r.end,c.end);
      if(r.timeBasis==='start')return near(r.at,c.at);
      if(r.timeBasis==='end')return near(r.at,c.end);
      // Legacy timestamps may mean payment time: require independent energy/SOC evidence.
      const corroborated=(r.endSOC!=null&&c.endSOC!=null)||(r.supplyKWh!=null&&c.supplyKWh!=null);
      return corroborated&&(near(r.at,c.at)||near(r.at,c.end));
    };
    const candidates=new Map(receipts.map(r=>[r.id,sessions.filter(c=>matches(r,c))]));
    const replacements=new Map(),used=new Set();
    for(const r of receipts){
      const list=candidates.get(r.id);if(list.length!==1)continue;const c=list[0];
      if(receipts.filter(x=>candidates.get(x.id).some(y=>y.id===c.id)).length!==1)continue;
      const merged={...c,...r,at:c.at,end:c.end,startTimeObserved:c.startTimeObserved,endTimeObserved:c.endTimeObserved,linkedRecordIDs:[r.id,c.id],receiptAt:r.at};
      for(const key of ['startSOC','endSOC','vehicleReportedKWh','nasSupplyKWh','supplyKWh','chargeType','chargeOperator','latitude','longitude'])if(merged[key]==null&&c[key]!=null)merged[key]=c[key];
      for(const key of ['startSOC','endSOC'])if(r[key]==null){merged[key+'Observed']=c[key+'Observed'];merged[key==='startSOC'?'startSOCEstimated':'endSOCEstimated']=c[key==='startSOC'?'startSOCEstimated':'endSOCEstimated'];}
      merged.source=[r.source,c.source].filter(Boolean).join('+');replacements.set(r.id,merged);used.add(c.id);
    }
    return raw.filter(c=>!used.has(c.id)).map(c=>replacements.get(c.id)??c);
  }
  class Engine{
    constructor(){this.state=initial();this.lastDrive=null;this.lastCharge=null;this.lastTireAt=0;this.parked=false;this.parkTransition=null;this.observed={};this.ensureBatteryBaseline(Date.now());}
    ensureBatteryBaseline(now){if(!this.state.batteryBaseline)this.state.batteryBaseline={at:now,healthPercent:100,source:'assumedNew',capacityKWh:null,referenceIds:[]};}
    load(s,opts={}){this.state=validateState(s,opts);this.ensureBatteryBaseline(Date.now());this.lastDrive=null;this.lastCharge=null;this.completedChargeID=null;this.parked=false;this.parkTransition=null;this.observed={};return this.view(Date.now());}
    settings(v){
      const s={...this.state.settings,homeRegions:this.state.settings.homeRegions?.map(h=>({...h}))};
      for(const k of ['name','model'])if(k in v)s[k]=text(v[k],80);
      if('vin'in v){if(typeof v.vin!=='string')throw Error('VIN 형식 오류');const vin=v.vin.trim().toUpperCase();if(vin&&!/^[A-HJ-NPR-Z0-9]{17}$/.test(vin))throw Error('VIN은 I/O/Q를 제외한 영문·숫자 17자리임');const recorded=['trips','charges','maintenance','parkingNotes','parkingPeriods','tires'].some(k=>this.state[k].length)||Object.keys(this.state.groups).length;if(this.state.settings.vin&&vin!==this.state.settings.vin&&recorded)throw Error('기존 기록의 차량과 VIN이 다름. 먼저 백업하고 새 프로필이 필요함.');s.vin=vin;}
      for(const [k,lo,hi]of [['assumedCapacityKWh',20,200],['reserveSOC',0,80],['dailyLimit',1,100],['tariff',0,10000],['plannedKm',0,3000]])if(k in v){if(!optional(v[k],lo,hi)||(k==='reserveSOC'&&v[k]==null))throw Error('설정 범위를 확인해야 함: '+k);s[k]=v[k]??null;}
      for(const k of ['fastTariff','superchargerTariff','chargeRates','chargeMemberOperators','homePoint','homeRadiusM','homeRegions','healthReferenceMethod','healthReferenceKWh','healthBatteryStartAt'])if(k in v)s[k]=v[k];
      if(v.homePoint&&!('homeRegions'in v)&&(!this.state.settings.homePoint||!nearby(v.homePoint,this.state.settings.homePoint,1))){
        const previous=this.state.settings.homePoint,now=Date.now();
        const history=(this.state.settings.homeRegions??(previous?[{...previous,radius:this.state.settings.homeRadiusM??600,start:0}]:[])).map(h=>h.end==null?{...h,end:now}:h);
        s.homeRegions=[...history,{...v.homePoint,radius:s.homeRadiusM??600,start:history.length?now:0}];
      }
      if(v.homePoint&&s.homeRegions?.length&&!('homeRegions'in v)){const h=s.homeRegions.at(-1);if(nearby(v.homePoint,h,1)){h.name=v.homePoint.name??h.name;h.address=v.homePoint.address??h.address;}}
      validateRates(s);this.state.settings=s;return s;
    }
    ingest(snapshot,now=Date.now()){
      if(!snapshot?.groups)throw Error('상태 형식 오류');
      for(const name of ['location','charge','drive','climate','tire','closures','media','mediaDetail']){
        const g=snapshot.groups[name];if(!g)continue;
        if(!fresh(g,now,300000))continue; // Do not make future or old data current.
        const previous=this.observed[name];
        if(previous&&g.at<previous.at)continue; // Delayed snapshots cannot rewind gear/location.
        if(name==='drive'&&fresh(g,now)){
          if(['D','R','N'].includes(g.gear)){this.parked=false;this.parkTransition=null;}
          else if(g.gear==='P'&&previous&&['D','R','N'].includes(previous.gear))this.parkTransition={at:g.at,receivedAt:g.receivedAt??now};
        }
        this.state.groups[name]=g;
        this.observed[name]=g;
        if(name==='drive')this.drive(g,now,{...this.state.groups,charge:snapshot.groups.charge??this.state.groups.charge});
        if(name==='charge'){const loc=snapshot.groups.location??this.state.groups.location;this.charge({...g,...(freshLocation(loc,now)?{latitude:loc.latitude,longitude:loc.longitude}:{})},now);}
        if(name==='tire'&&g.at-this.lastTireAt>=60000){this.state.tires.push({id:id(),at:g.at,values:g.values,seenAt:g.seenAt});this.state.tires=this.state.tires.slice(-2000);this.lastTireAt=g.at;}
      }
      const d=this.state.groups.drive,l=this.state.groups.location;
      const parkedCharge=this.state.groups.charge;
      if(!this.state.lastPark&&!this.state.activeTrip&&d?.gear==='P'&&fresh(d,now)&&fresh(parkedCharge,now,TTL.charge)&&num(parkedCharge.soc,0,100))this.state.lastPark={at:Math.max(d.at,parkedCharge.at),soc:parkedCharge.soc,odometerKm:d.odometerKm,gear:'P',startObserved:false};
      if(fresh(d,now)&&['D','R'].includes(d.gear))this.parked=false;
      const postPark=!this.parkTransition||(l&&l.at>=this.parkTransition.at&&(l.receivedAt??l.at)>=this.parkTransition.receivedAt&&
        (d.receivedAt??d.at)-this.parkTransition.receivedAt>=3000);
      if(!this.parked&&postPark&&this.observed.drive===d&&this.observed.location===l&&fresh(d,now)&&d.gear==='P'&&freshLocation(l,now)){
        const previous=this.state.parkingNotes.filter(p=>p.automatic).slice(-1)[0];
        if(!previous||now-previous.at>DAY||Math.abs(previous.latitude-l.latitude)>0.0003||Math.abs(previous.longitude-l.longitude)>0.0003)this.captureParking(now);
        this.parked=true;
      }
      return this.view(now);
    }
    drive(g,now,context=this.state.groups){
      if(!fresh(g,now)||this.lastDrive&&g.at<=this.lastDrive.at)return;
      const s=this.state,prev=this.lastDrive,c=fresh(context.charge,now,TTL.charge)&&num(context.charge.soc,0,100)?context.charge:null;
      if(s.lastPark&&['D','R','N'].includes(g.gear)){const parkedDistance=num(s.lastPark.odometerKm,0,1e7)&&num(g.odometerKm,0,1e7)?g.odometerKm-s.lastPark.odometerKm:null;append(s.parkingPeriods,{id:id(),start:s.lastPark.at,end:g.at,startSOC:s.lastPark.soc,endSOC:c?.soc??null,deltaSOC:s.lastPark.soc==null||c?.soc==null?null:round(s.lastPark.soc-c.soc),startGear:'P',endGear:g.gear,startOdo:s.lastPark.odometerKm??null,endOdo:g.odometerKm??null,classification:parkedDistance!=null&&parkedDistance>=0&&parkedDistance<=0.2?'parking':'unclassified',note:'양 끝 주행거리로 주차 추정 · 미관측 충전·온도 영향 가능'});s.lastPark=null;}
      if(!s.lastPark&&!s.activeTrip&&g.gear==='P'&&c&&num(c.soc,0,100))s.lastPark={at:g.at,soc:c.soc,odometerKm:g.odometerKm,gear:'P',startObserved:false};
      const moving=['D','R'].includes(g.gear)&&num(g.speedKmh,1,350);
      if(moving&&!s.activeTrip){
        s.activeTrip={id:id(),start:g.at,startSOC:c?.soc??null,lastSOC:c?.soc??null,startOdo:g.odometerKm,lastOdo:g.odometerKm,distanceKm:0,missing:false,observedStart:!!prev&&prev.gear==='P'&&g.at-prev.at<=15000,socUnknown:c==null,gaps:0,gapSeconds:0,lastAt:g.at,parkAt:null,points:[]};

      }
      let t=s.activeTrip;
      // A trip resumed after an app restart that is first seen parked ended while the app was closed.
      if(t&&t.resumed){t.resumed=false;if(g.gear==='P'){t.parkAt=t.lastAt;this.finish(t.lastAt,false);t=null;}}
      if(t){
        // v30: a BLE gap while driving continues the same trip when the odometer delta is plausible for the gap.
        const dt=(g.at-t.lastAt)/1000;if(dt>15){t.gaps=(t.gaps||0)+1;t.gapSeconds=(t.gapSeconds||0)+dt;if(dt>1800)t.missing=true;}
        if(t.powerSeconds==null||!num(t.powerDistanceKm,0,100000)){t.powerSeconds=0;t.powerUsedKWh=0;t.powerRecoveredKWh=0;t.powerDistanceKm=0;}
        const hasOdometers=num(g.odometerKm,0,1e7)&&num(t.lastOdo,0,1e7),dx=hasOdometers?g.odometerKm-t.lastOdo:null;
        const validDistance=dx!=null&&dx>=0&&dx<=Math.max(dt,0)/3600*350+0.1;
        if(dt>0&&dt<=15&&validDistance&&num(t.lastPowerKW,-500,1500)&&num(g.powerKW,-500,1500)){
          const a=t.lastPowerKW,b=g.powerKW,hours=dt/3600;
          if(a*b<0){
            const split=Math.abs(a)/(Math.abs(a)+Math.abs(b));
            t.powerUsedKWh+=hours*(a>0?a*split:b*(1-split))/2;
            t.powerRecoveredKWh+=hours*(a<0?-a*split:-b*(1-split))/2;
          }else{
            t.powerUsedKWh+=hours*(Math.max(a,0)+Math.max(b,0))/2;
            t.powerRecoveredKWh+=hours*(Math.max(-a,0)+Math.max(-b,0))/2;
          }
          t.powerSeconds+=dt;
          t.powerDistanceKm+=dx;
        }
        t.lastPowerKW=num(g.powerKW,-500,1500)?g.powerKW:null;
        if(hasOdometers){if(validDistance)t.distanceKm+=dx;else t.missing=true;}
        else t.missing=true;
        t.lastAt=g.at;t.lastOdo=g.odometerKm;if(c)t.lastSOC=c.soc;
        const loc=context.location,fixAt=loc?.gpsAt??loc?.at;
        if(freshLocation(loc,now)&&fixAt>=t.start&&fixAt<=g.at+5000&&t.points.length<2000&&
           (!t.points.length||fixAt>t.points[t.points.length-1].at))t.points.push({at:fixAt,lat:loc.latitude,lng:loc.longitude});
        // A fresh explicit P ends an observed drive now; no second packet after exiting is required.
        if(g.gear==='P'&&(g.speedKmh==null||num(g.speedKmh,0,0.5))&&now-g.at<=120000){t.parkAt=g.at;this.finish(g.at,false);}else t.parkAt=null;
      }
      this.lastDrive=g;
    }
    finish(now=Date.now(),manual=true){
      const s=this.state,t=s.activeTrip;if(!t)throw Error('진행 중인 운행이 없음');
      const end=t.parkAt??t.lastAt;
      const motorObserved=t.powerSeconds>0&&num(t.powerUsedKWh,0,1e5)&&num(t.powerRecoveredKWh,0,1e5),motorDistance=motorObserved&&num(t.powerDistanceKm,0,100000)?t.powerDistanceKm:null;
      const motorNet=motorObserved?t.powerUsedKWh-t.powerRecoveredKWh:null;
      const trip={id:t.id,start:t.start,end:Math.max(end,t.start),startSOC:t.startSOC,endSOC:t.lastSOC,startOdo:t.startOdo??null,endOdo:t.lastOdo??null,distanceKm:round(t.distanceKm,2),missing:!!t.missing,manualEnd:!!manual,gaps:t.gaps||0,gapSeconds:round(t.gapSeconds||0,0),points:t.points,
        powerUsedKWh:motorObserved?t.powerUsedKWh:null,powerRecoveredKWh:motorObserved?t.powerRecoveredKWh:null,powerSeconds:t.powerSeconds??0,powerDurationSeconds:Math.max(0,(t.lastAt-t.start)/1000),
        observedMotorUsedKWh:motorObserved?round(t.powerUsedKWh,3):null,observedMotorRecoveredKWh:motorObserved?round(t.powerRecoveredKWh,3):null,
        observedMotorNetKWh:motorObserved?round(motorNet,3):null,observedMotorDistanceKm:motorDistance==null?null:round(motorDistance,3),
        observedMotorWhPerKm:motorDistance>0?round(motorNet/motorDistance*1000,1):null};
      append(s.trips,trip);s.activeTrip=null;
      s.lastPark=t.parkAt!=null?{at:end,soc:t.lastSOC,odometerKm:t.lastOdo,gear:'P'}:null;
      const delta=trip.startSOC!=null&&trip.endSOC!=null?round(trip.startSOC-trip.endSOC):null;
      s.lastBrief=`이번 운행 거리는 ${trip.distanceKm} km, 소요 시간은 ${Math.round((trip.end-trip.start)/60000)}분입니다. `+(delta==null?'배터리 사용량은 확인되지 않았습니다.':`배터리 잔량은 ${Math.abs(delta)} 퍼센트포인트 ${delta>=0?'감소':'증가'}했습니다.`)+(trip.missing?' 일부 구간은 확인되지 않아 추정값으로 안내합니다.':'');
      return trip;
    }
    ingestFleetDrive(input,now=Date.now()){
      if(typeof input.vin!=='string'||!/^[A-HJ-NPR-Z0-9]{17}$/.test(input.vin))throw Error('Fleet 차량 식별값 오류');
      if(this.state.settings.vin&&this.state.settings.vin!==input.vin)throw Error('기록 차량과 Fleet 차량이 다릅니다.');
      if(!this.state.settings.vin){if(this.state.trips.length||this.state.charges.length)throw Error('기존 기록의 차량을 먼저 선택해 주세요.');this.state.settings.vin=input.vin;}
      if(input.drive)this.drive(input.drive,now,{charge:input.charge,location:input.location});
      return this.view(now);
    }
    ingestFleetCharge(input,now=Date.now()){
      if(typeof input.vin!=='string'||!/^[A-HJ-NPR-Z0-9]{17}$/.test(input.vin))throw Error('Fleet 차량 식별값 오류');
      if(this.state.settings.vin&&this.state.settings.vin!==input.vin)throw Error('기록 차량과 Fleet 차량이 다릅니다.');
      if(!this.state.settings.vin){if(this.state.trips.length||this.state.charges.length)throw Error('기존 기록의 차량을 먼저 선택해 주세요.');this.state.settings.vin=input.vin;}
      this.charge({...input,source:'Fleet'},now);return this.view(now);
    }
    charge(g,now){
      if(!fresh(g,now)||this.lastCharge&&g.at<=this.lastCharge.at)return;
      if(this.state.activeCharge?.lastAt!=null&&g.at<=this.state.activeCharge.lastAt)return;
      const s=this.state,prev=this.lastCharge;
      if(s.activeCharge&&(!prev||g.at-prev.at>30000))s.activeCharge.partial=true;
      if(g.charging===5){
        this.completedChargeID=null;
        // A counter correction is not a new start/stop event. Never split a session on kWh alone.
        if(s.activeCharge&&num(g.addedKWh,0,300)&&num(s.activeCharge.lastAdded,0,300)&&s.activeCharge.lastAdded-g.addedKWh>Math.max(2,s.activeCharge.lastAdded*0.25)){s.activeCharge.chargeCounterConflict=true;s.activeCharge.partial=true;}
        if(!s.activeCharge){
        const boundary=!!prev&&[2,3,4,6,7].includes(prev.charging)&&g.at-prev.at<=120000;
          const capacity=this.health().capacity??s.settings.assumedCapacityKWh??75;
          const estimate=num(g.soc,0,100)&&num(g.addedKWh,0,300)?round(Math.max(0,g.soc-g.addedKWh/capacity*100),1):null;
          const start=boundary?(num(prev.soc,0,100)?prev.soc:g.soc):estimate;
          s.activeCharge={id:id(),at:g.at,startTimeObserved:boundary||g.startTransitionObserved===true,startTimeBasis:boundary||g.startTransitionObserved===true?'stateTransition':'firstChargingObservation',initialAddedKWh:g.addedKWh??null,startSOC:num(start,0,100)?start:null,startSOCObserved:boundary&&num(start,0,100),startSOCEstimated:!boundary&&estimate!=null,endSOC:num(g.soc,0,100)?g.soc:null,lastAdded:g.addedKWh,vehicleReportedKWh:g.addedKWh,partial:!boundary,source:g.source??'BLE'};
        }
        const c=s.activeCharge;if(g.addedKWh!=null&&c.lastAdded!=null&&g.addedKWh<c.lastAdded)c.partial=true;
        c.endSOC=num(g.soc,0,100)?g.soc:c.endSOC;c.lastAt=g.at;
        if(num(g.addedKWh,0,300)){c.lastAdded=g.addedKWh;c.vehicleReportedKWh=Math.max(c.vehicleReportedKWh??0,g.addedKWh);}
      }else if(s.activeCharge&&[2,3,4,6,7].includes(g.charging)){
        const c=s.activeCharge;const near=(g.at-(c.lastAt??c.at))<=120000;
        const observedEnd=near&&num(g.soc,0,100)&&(c.startSOC==null||g.soc>=c.startSOC);
        const estimatedEnd=!observedEnd&&g.charging===6&&num(g.limit,1,100)&&g.limit>=(c.endSOC??c.startSOC??0)?g.limit:null;
        c.endSOC=observedEnd?g.soc:estimatedEnd??c.endSOC;c.endSOCObserved=observedEnd;c.endSOCEstimated=estimatedEnd!=null;c.endSOCLastObserved=!observedEnd&&estimatedEnd==null;c.end=near||g.endTransitionObserved===true?g.at:c.lastAt??g.at;c.endTimeObserved=near||g.endTransitionObserved===true;c.source=c.source===g.source||!g.source?c.source:[...new Set((c.source??'BLE').split('+').concat(g.source))].join('+');c.storedKWh=null;c.supplyKWh=null;c.cost=null;c.complete=c.startSOCObserved===true&&observedEnd;
        if(num(g.addedKWh,0,300))c.vehicleReportedKWh=Math.max(c.vehicleReportedKWh??0,g.addedKWh);
        append(s.charges,c);s.activeCharge=null;this.completedChargeID=c.id;
      }
      // A first observation after charging finished still contains the vehicle's session energy.
      // Preserve that session without inventing its start time or claiming a measured start SOC.
      if(!s.activeCharge&&[6,7].includes(g.charging)&&num(g.addedKWh,0.01,300)&&num(g.soc,0,100)){
        const held=s.charges.find(c=>c.id===this.completedChargeID);
        const duplicate=held??[...s.charges].reverse().find(c=>!c.chargeExcluded&&num(c.vehicleReportedKWh,0.01,300)&&Math.abs(c.vehicleReportedKWh-g.addedKWh)<=Math.max(2,c.vehicleReportedKWh*0.1)&&g.soc<=(c.endSOC??-1)+1&&g.at-(c.end??c.at)>=0&&g.at-(c.end??c.at)<48*3600000);
        if(duplicate){
          this.completedChargeID=duplicate.id;
          // Late final counters may enrich a session; later SOC drift must not rewrite its endpoints.
          if(g.at-(duplicate.end??duplicate.at)<=120000)duplicate.vehicleReportedKWh=Math.max(duplicate.vehicleReportedKWh??0,g.addedKWh);
        }
        if(!duplicate){
          const capacity=this.health().capacity??s.settings.assumedCapacityKWh??75;
          append(s.charges,{id:id(),at:g.at,end:g.at,startTimeObserved:false,endTimeObserved:false,startSOC:round(Math.max(0,g.soc-g.addedKWh/capacity*100),1),startSOCEstimated:true,endSOC:g.soc,endSOCObserved:true,vehicleReportedKWh:g.addedKWh,complete:false,partial:true,collectedAfterEnd:true,source:g.source??'BLE',note:'종료 후 수집 · 표시 시각은 수집 시각 · 시작 잔량은 충전량으로 추정'});
          this.completedChargeID=s.charges.at(-1).id;
        }
      }
      applyChargeMetadata(s.activeCharge??s.charges.find(c=>c.id===this.completedChargeID),g);
      this.lastCharge=g;
    }
    confirmSeparateCharge(v){
      const row=this.state.charges.find(c=>c.id===v?.id);
      if(!row||v.confirmed!==true)throw Error('원본 확인 후 별도 충전인지 확인해 주세요.');
      row.chargeReviewConfirmed=true;return this.view();
    }
    enrichChargeSOC(v){
      if(!this.state.settings.vin||v.vin!==this.state.settings.vin)return this.view();
      const samples=(v.rows??[]).filter(r=>num(r.at,0,1e14)).sort((a,b)=>a.at-b.at);
      for(const c of this.state.charges){
        if(c.collectedAfterEnd||c.atPrecision==='day'||!(c.end>c.at))continue;
        for(const [key,time] of [['startSOC',c.at],['endSOC',c.end]]){
          if(c[key]!=null)continue;
          const nearby=samples.filter(r=>Math.abs(r.at-time)<=120000);
          if(!nearby.length||nearby.some(r=>r.invalid||!num(r.soc,0,100)))continue;
          if(Math.max(...nearby.map(r=>r.soc))-Math.min(...nearby.map(r=>r.soc))>2)continue;
          const sample=nearby.sort((a,b)=>Math.abs(a.at-time)-Math.abs(b.at-time))[0];
          if(key==='endSOC'&&c.startSOC!=null&&sample.soc<c.startSOC)continue;
          if(key==='startSOC'&&c.endSOC!=null&&sample.soc>c.endSOC)continue;
          c[key]=sample.soc;c[key+'Observed']=true;c[key+'TelemetryAt']=sample.at;
        }
      }
      return this.view();
    }
    addCharge(v){
      const c={id:id(),at:v.at??Date.now(),startSOC:v.startSOC??null,endSOC:v.endSOC??null,supplyKWh:v.supplyKWh??null,storedKWh:v.storedKWh??null,cost:v.cost??null,source:v.source==='OCR'?'OCR 확인':'수동',place:text(v.place,120),note:text(v.note),complete:v.complete===true,storageVerified:v.storageVerified===true,comparable:v.comparable===true};
      if('end'in v)c.end=v.end;if('timeBasis'in v)c.timeBasis=v.timeBasis;if('durationMinutes'in v)c.durationMinutes=v.durationMinutes;
      validateCharge(c);if(c.storedKWh!=null&&!c.storageVerified)throw Error('저장 에너지로 확인된 자료만 입력해야 함. 영수증은 공급량 칸 사용.');
      c.chargeType=['ac','dc','supercharger'].includes(v.chargeType)?v.chargeType:null;c.chargeTypeManual=!!c.chargeType;c.chargeOperator=text(v.chargeOperator,120);
      if(typeof v.memberPricing==='boolean')c.memberPricing=v.memberPricing;
      if(typeof v.roamingPricing==='boolean')c.roamingPricing=v.roamingPricing;
      c.receiptText=text(v.receiptText,20000);c.estimatedCost=null;
      const duplicate=this.state.charges.some(x=>Math.abs(x.at-c.at)<60000&&x.cost===c.cost&&x.supplyKWh===c.supplyKWh);if(duplicate)throw Error('같은 시각·금액·공급량 기록이 존재함. 중복 확인 필요.');
      append(this.state.charges,c);return c;
    }
    // v37: a mistyped charge record can be corrected in place instead of deleted and re-entered.
    updateCharge(v){
      const key=text(v?.id,80);const row=this.state.charges.find(c=>c.id===key);
      if(!row)throw Error('수정할 기록을 찾을 수 없음');
      const c={...row,at:v.at??row.at,startSOC:v.startSOC??null,endSOC:v.endSOC??null,supplyKWh:v.supplyKWh??null,
        storedKWh:v.storedKWh??null,cost:v.cost??null,place:text(v.place,120),note:text(v.note),
        complete:v.complete===true,storageVerified:v.storageVerified===true,comparable:v.comparable===true};
      if('end'in v)c.end=v.end;if('timeBasis'in v)c.timeBasis=v.timeBasis;
      validateCharge(c);if(c.storedKWh!=null&&!c.storageVerified)throw Error('저장 에너지로 확인된 자료만 입력해야 함. 영수증은 공급량 칸 사용.');
      c.estimatedCost=null;
      if('chargeType'in v){c.chargeType=['ac','dc','supercharger'].includes(v.chargeType)?v.chargeType:null;c.chargeTypeManual=!!c.chargeType;}
      if('chargeOperator'in v)c.chargeOperator=text(v.chargeOperator,120);
      if(typeof v.memberPricing==='boolean')c.memberPricing=v.memberPricing;
      if(typeof v.roamingPricing==='boolean')c.roamingPricing=v.roamingPricing;
      Object.assign(row,c);return row;
    }
    addMaintenance(v){
      const m={id:id(),at:v.at??Date.now(),title:text(v.title,80),odometerKm:v.odometerKm??null,nextKm:v.nextKm??null,cost:v.cost??null,note:text(v.note),tireReset:v.tireReset===true};
      if(!m.title||!num(m.at,0,1e14)||!optional(m.odometerKm,0,1e7)||!optional(m.nextKm,0,1e7)||!optional(m.cost,0,1e8))throw Error('정비 입력 확인 필요');append(this.state.maintenance,m);return m;
    }
    addParking(v){
      const loc=this.state.groups.location,p={id:id(),at:Date.now(),note:text(v.note),photoName:text(v.photoName,100),latitude:loc?.latitude??null,longitude:loc?.longitude??null,locationAt:loc?.at??null};
      if(!p.note&&!p.photoName)throw Error('주차 메모 또는 사진이 필요함');
      // A manual note about the spot the car is already parked at updates that record instead of stacking a new one.
      const last=this.state.parkingNotes[this.state.parkingNotes.length-1];
      if(last&&last.automatic&&nearby(last,p)&&p.at-last.at<12*3600000){
        last.note=p.note||last.note;if(p.photoName)last.photoName=p.photoName;last.automatic=false;return last;
      }
      append(this.state.parkingNotes,p);return p;
    }
    deleteParking(v){
      const key=text(v?.id,80);if(!key)throw Error('삭제할 기록을 찾을 수 없음');
      const before=this.state.parkingNotes.length;
      this.state.parkingNotes=this.state.parkingNotes.filter(p=>p.id!==key);
      if(this.state.parkingNotes.length===before)throw Error('삭제할 기록을 찾을 수 없음');
      return {removed:before-this.state.parkingNotes.length};
    }
    deleteCharge(v){
      const key=text(v?.id,80);if(!key)throw Error('삭제할 기록을 찾을 수 없음');
      const before=this.state.charges.length;
      const linked=this.chargeSummary().rows.find(c=>c.id===key)?.linkedRecordIDs??[key];
      this.state.charges=this.state.charges.filter(c=>!linked.includes(c.id));
      if(this.state.charges.length===before)throw Error('삭제할 기록을 찾을 수 없음');
      if(this.state.batteryBaseline)this.state.batteryBaseline.referenceIds=(this.state.batteryBaseline.referenceIds||[]).filter(x=>x!==key);
      return {removed:1};
    }
    deleteTrip(v){
      const key=text(v?.id,80);if(!key)throw Error('삭제할 기록을 찾을 수 없음');
      const before=this.state.trips.length;
      this.state.trips=this.state.trips.filter(t=>t.id!==key);
      if(this.state.trips.length===before)throw Error('삭제할 기록을 찾을 수 없음');
      return {removed:1};
    }
    captureParking(now=Date.now()){
      const d=this.state.groups.drive,l=this.state.groups.location;
      if(this.observed.drive!==d||this.observed.location!==l||!fresh(d,now)||d.gear!=='P'||!freshLocation(l,now)||
        (this.parkTransition&&(l.at<this.parkTransition.at||(l.receivedAt??l.at)<this.parkTransition.receivedAt||
          (d.receivedAt??d.at)-this.parkTransition.receivedAt<3000)))throw Error('주차 후 차량 위치 확인 중임. 최신 좌표 수신이 필요함.');
      const p={id:id(),at:now,locationAt:l.at,latitude:l.latitude,longitude:l.longitude,note:'차량 주차 좌표 자동 기록',photoName:'',automatic:true};
      // Same spot again (parking at home every night) refreshes the existing record rather than piling up.
      const last=this.state.parkingNotes[this.state.parkingNotes.length-1];
      if(last&&nearby(last,p)&&now-last.at<30*24*3600000){
        last.at=now;last.locationAt=l.at;last.latitude=l.latitude;last.longitude=l.longitude;last.visits=(last.visits||1)+1;return last;
      }
      append(this.state.parkingNotes,p);return p;
    }
    ingestArchive(input){
      const vin=input.vin, rows=input.rows;
      if(typeof vin!=='string'||!/^[A-HJ-NPR-Z0-9]{17}$/.test(vin)||!Array.isArray(rows)||rows.length>50000)throw Error('NAS 기록 형식 오류');
      if(this.state.settings.vin&&this.state.settings.vin!==vin)throw Error('동일 차량의 NAS 기록만 합칠 수 있음');
      if(!this.state.settings.vin){if(this.state.trips.length||this.state.charges.length)throw Error('기존 기록의 차량을 먼저 선택해 주세요.');this.state.settings.vin=vin;}
      // Store one validated BMS capacity observation per Korea calendar day; repeated polling must not dominate the estimate.
      for(const r of rows.filter(r=>r.field==='NominalFullPackEnergyKwh'&&!r.invalid&&num(r.at,1,Date.now()+5000)&&num(r.number,20,200))){
        const key='bms:'+Math.floor((r.at+9*3600000)/DAY),list=this.state.batteryObservations;
        const old=list.findIndex(p=>p.id===key);
        const point={id:key,at:r.at,value:r.number,method:'bmsNominal'};
        if(old<0)append(list,point);else if(r.at>list[old].at)list[old]=point;
      }
      const replay=new Engine();replay.state.settings={...this.state.settings};
      const latest={},byTime=new Map();
      let chargeBegan=null,previousCharge=null,finishedCharge=null;
      for(const r of rows){if(!num(r.at,1,Date.now()+5000)||typeof r.field!=='string')continue;if(!byTime.has(r.at))byTime.set(r.at,[]);byTime.get(r.at).push(r);}
      const scalar=field=>{const r=latest[field];if(!r||r.invalid)return null;if(Number.isFinite(r.number))return r.number;try{return Object.values(JSON.parse(r.text))[0];}catch{return null;}};
      for(const at of [...byTime.keys()].sort((a,b)=>a-b)){
        for(const row of byTime.get(at))latest[row.field]=row;
        if(num(input.replayFrom,1,Date.now()+5000)&&at<input.replayFrom){
          const k=['DetailedChargeState','ChargeState'].filter(k=>latest[k]).sort((a,b)=>latest[b].at-latest[a].at)[0];
          previousCharge={Disconnected:2,NoPower:3,Starting:4,Charging:5,Complete:6,Stopped:7}[String(scalar(k)??'').replace('DetailedChargeState','')];
          continue;
        }
        const fields=new Set(byTime.get(at).map(r=>r.field));
        const socField=['Soc','BatteryLevel'].filter(k=>latest[k]).sort((a,b)=>latest[b].at-latest[a].at)[0];
        const soc=socField&&at-latest[socField].at<=180000?scalar(socField):null,odo=scalar('Odometer'),speed=scalar('VehicleSpeed');
        const gear=String(scalar('Gear')??'').replace('ShiftState','');
        const stateFields=['DetailedChargeState','ChargeState'].filter(k=>latest[k]).sort((a,b)=>latest[b].at-latest[a].at);
        const detail=String(scalar(stateFields[0])??'').replace('DetailedChargeState','');
        const charging={Disconnected:2,NoPower:3,Starting:4,Charging:5,Complete:6,Stopped:7}[detail];
        if(charging===5&&previousCharge!==5){chargeBegan=at;finishedCharge=null;}
        // DCChargingEnergyIn measures battery input on both AC and DC charging.
        // ACChargingEnergyIn is grid-side supply: retain it separately, never add counters.
        const validEnergy=k=>latest[k]&&!latest[k].invalid&&num(scalar(k),0,300)&&latest[k].at>=(chargeBegan??at-120000);
        const energyField=['DCChargingEnergyIn','ChargeEnergyAdded'].find(validEnergy);
        const added=energyField?scalar(energyField):null;
        const dc=(latest.DCChargingPower?.at>=(chargeBegan??at)-120000&&num(scalar('DCChargingPower'),0.01,1500))||replay.state.activeCharge?.chargeType==='dc'||finishedCharge?.chargeType==='dc';
        const supply=!dc&&validEnergy('ACChargingEnergyIn')?scalar('ACChargingEnergyIn'):null;
        const chargePacket=[...fields].some(k=>['ChargeState','DetailedChargeState','Soc','BatteryLevel','DCChargingEnergyIn','ACChargingEnergyIn','ChargeEnergyAdded','ChargeLimitSoc','ACChargingPower','DCChargingPower','ChargePower'].includes(k));
        if(charging!==undefined&&chargePacket){
          // A terminal state remains cached for hours. Later SOC drift is not another charge.
          const terminal=[6,7].includes(charging), repeatedEnd=terminal&&[6,7].includes(previousCharge)&&finishedCharge;
          const stateEvent=fields.has(stateFields[0]);
          if(!repeatedEnd)replay.charge({at,charging,soc,addedKWh:added,limit:scalar('ChargeLimitSoc'),source:'NAS',startTransitionObserved:stateEvent&&charging===5&&previousCharge!=null&&previousCharge!==5,endTransitionObserved:stateEvent&&previousCharge===5&&[2,3,4,6,7].includes(charging)},at);
          if(!repeatedEnd&&!replay.state.activeCharge&&terminal&&added==null&&supply>0&&num(soc,0,100)&&!replay.state.charges.some(c=>c.end===at)){
            // A completion-only AC packet still proves supplied energy, but not starting SOC.
            const duplicate=replay.state.charges.some(c=>c.supplyKWh===supply&&c.endSOC===soc&&at-c.end<48*3600000);
            if(!duplicate)append(replay.state.charges,{id:id(),at,end:at,startTimeObserved:false,endTimeObserved:false,startSOC:null,endSOC:soc,endSOCObserved:true,supplyKWh:supply,complete:false,partial:true,collectedAfterEnd:true,source:'NAS'});
          }
          const current=replay.state.activeCharge??replay.state.charges.findLast(c=>c.end===at);
          if(current&&supply!=null)current.supplyKWh=supply;
          const ac=validEnergy('ACChargingEnergyIn')&&supply>0;
          const acPower=latest.ACChargingPower?.at>=(chargeBegan??at)-120000&&num(scalar('ACChargingPower'),0.01,100);
          const location=latest.Location?.at>=(chargeBegan??at)-120000?scalar('Location'):null;
          applyChargeMetadata(current,{chargeType:dc?'dc':ac||acPower?'ac':null,latitude:location?.latitude,longitude:location?.longitude});
          if(terminal&&current)finishedCharge=current;
          // Tesla can send final counters just after Complete, in a separate packet.
          if(repeatedEnd&&at-finishedCharge.end<=120000){
            if(added!=null)finishedCharge.vehicleReportedKWh=Math.max(finishedCharge.vehicleReportedKWh??0,added);
            if(supply!=null)finishedCharge.supplyKWh=Math.max(finishedCharge.supplyKWh??0,supply);
          }
          previousCharge=charging;
        }
        if(['P','D','R','N'].includes(gear)&&['Gear','VehicleSpeed','Odometer'].some(k=>fields.has(k)))replay.drive({at,gear,speedKmh:num(speed,0,220)?speed*1.609344:null,odometerKm:num(odo,0,1e7)?odo*1.609344:null},at,{charge:{at:socField?latest[socField].at:0,soc},location:{}});
      }
      for(const kind of ['trips','charges'])for(const source of replay.state[kind]){
        const start=kind==='trips'?source.start:source.at,end=source.end??start;
        const row={...source,id:'nas:'+vin+':'+kind+':'+start,source:'NAS'};
        const activeKey=kind==='trips'?'activeTrip':'activeCharge',active=this.state[activeKey];
        const activeStart=active&&(kind==='trips'?active.start:active.at);
        // A completed NAS interval can close the same phone session. Do not discard it
        // simply because the phone still has an active row after suspension/restart.
        if(active&&end>start&&activeStart>=start-120000&&activeStart<=end&&
           (active.lastAt??activeStart)<=end+120000){
          row.id=active.id;
          for(const key of ['cost','note','place','chargeOperator','memberPricing','roamingPricing','chargeTypeManual','receiptText','siteMatch'])if(active[key]!=null)row[key]=active[key];
          this.state[activeKey]=null;
        }
        const list=this.state[kind],same=list.findIndex(x=>x.id===row.id);
        if(same>=0){
          const old=list[same];
          if(kind==='charges'){
            // Replaying the archive must not erase receipt/manual additions or earlier evidence.
            const merged={...row,...old};
            if(row.vehicleReportedKWh!=null)merged.vehicleReportedKWh=Math.max(old.vehicleReportedKWh??0,row.vehicleReportedKWh);
            if(row.supplyKWh!=null)merged.nasSupplyKWh=row.supplyKWh;
            // Earlier pages can close a session before its final counters arrive.
            // Only replace machine-derived values; receipt and manual edits stay authoritative.
            for(const key of ['vehicleReportedKWh','supplyKWh'])if(old.source==='NAS'&&old.archiveValues?.[key]===old[key]&&row[key]!=null)merged[key]=Math.max(old[key]??0,row[key]);
            for(const key of ['chargeType','chargeOperator','latitude','longitude','startSOC','endSOC','vehicleReportedKWh','supplyKWh'])if(merged[key]==null&&row[key]!=null)merged[key]=row[key];
            if(!old.startSOCObserved&&row.startSOCObserved){merged.startSOC=row.startSOC;merged.startSOCObserved=true;merged.startSOCEstimated=false;}
            if(!old.endSOCObserved&&row.endSOCObserved){merged.endSOC=row.endSOC;merged.endSOCObserved=true;merged.endSOCEstimated=false;}
            if(!old.startTimeObserved&&row.startTimeObserved){merged.at=row.at;merged.startTimeObserved=true;merged.startTimeBasis=row.startTimeBasis;merged.initialAddedKWh=row.initialAddedKWh;merged.collectedAfterEnd=false;}
            if(!old.endTimeObserved&&row.endTimeObserved){merged.end=row.end;merged.endTimeObserved=true;}
            merged.archiveValues={vehicleReportedKWh:row.vehicleReportedKWh,supplyKWh:row.supplyKWh};list[same]=merged;
          }else list[same]=row;
          continue;
        }
        const overlaps=x=>{const a=kind==='trips'?x.start:x.at,b=x.end??x.lastAt??a;return Math.min(end,b)>=Math.max(start,a);};
        // Prefer existing phone/manual records; never double-count one observed session.
        // Keep receipt originals separate; read-time reconciliation enforces one-to-one matching
        // in either import order instead of merging the first overlapping receipt permanently.
        const candidates=list.filter(x=>overlaps(x)&&!(kind==='charges'&&(/수동|OCR|manual/.test(x.source??'')||x.collectedAfterEnd&&!row.collectedAfterEnd)));
        const existing=candidates.length===1?candidates[0]:null;
        if(existing){
          if(kind==='charges'){
            for(const key of ['chargeType','chargeOperator','latitude','longitude','startSOC','endSOC','vehicleReportedKWh','supplyKWh'])if(existing[key]==null&&row[key]!=null){
              existing[key]=row[key];
              if(key==='startSOC'){existing.startSOCObserved=row.startSOCObserved===true;existing.startSOCEstimated=row.startSOCEstimated===true;}
              if(key==='endSOC'){existing.endSOCObserved=row.endSOCObserved===true;existing.endSOCEstimated=row.endSOCEstimated===true;}
            }
            if(!row.collectedAfterEnd&&row.end>row.at){existing.receiptAt??=existing.at;existing.at=row.at;existing.end=row.end;existing.startTimeObserved=row.startTimeObserved;existing.endTimeObserved=row.endTimeObserved;existing.initialAddedKWh=row.initialAddedKWh;}
            existing.source=[...new Set((existing.source??'차량').split('+').concat('NAS'))].join('+');
            if(!existing.startSOCObserved&&row.startSOCObserved){existing.startSOC=row.startSOC;existing.startSOCObserved=true;existing.startSOCEstimated=false;}
            if(!existing.endSOCObserved&&row.endSOCObserved){existing.endSOC=row.endSOC;existing.endSOCObserved=true;existing.endSOCEstimated=false;}
          }else{
            for(const key of ['startSOC','endSOC'])if(existing[key]==null&&num(row[key],0,100))existing[key]=row[key];
          }
          continue;
        }
        if((kind==='trips'?this.state.activeTrip:this.state.activeCharge)&&overlaps(kind==='trips'?this.state.activeTrip:this.state.activeCharge))continue;
        if(kind==='charges'){row.nasSupplyKWh=row.supplyKWh;row.archiveValues={vehicleReportedKWh:row.vehicleReportedKWh,supplyKWh:row.supplyKWh};}
        append(list,row);list.sort((a,b)=>(a.start??a.at)-(b.start??b.at));
      }
      // Archive replay already reconstructs parking; retain those observations too.
      for(const source of replay.state.parkingPeriods){
        const row={...source,id:'nas:'+vin+':parking:'+source.start,source:'NAS'};
        const index=this.state.parkingPeriods.findIndex(p=>p.id===row.id);
        if(index>=0)this.state.parkingPeriods[index]=row;
        else if(!this.state.parkingPeriods.some(p=>p.start<row.end&&row.start<p.end))append(this.state.parkingPeriods,row);
      }
      this.enrichRecordEndpoints(rows);
      return this.view();
    }
    enrichRecordEndpoints(rows){
      // Nearest real sample in a bounded window, never an SOC interpolated from kWh.
      const samples=rows.filter(r=>['Soc','BatteryLevel'].includes(r.field)&&num(r.at,1,1e14)).sort((a,b)=>a.at-b.at);
      const nearest=time=>{
        let lo=0,hi=samples.length;while(lo<hi){const mid=(lo+hi)>>1;if(samples[mid].at<time-120000)lo=mid+1;else hi=mid;}
        const nearby=[];for(let i=lo;i<samples.length&&samples[i].at<=time+120000;i++)nearby.push(samples[i]);
        const distance=nearby.length?Math.min(...nearby.map(r=>Math.abs(r.at-time))):Infinity;
        const direct=nearby.filter(r=>Math.abs(r.at-time)===distance);
        // An actual endpoint packet is stronger evidence than the wider window.
        // Normal SOC change elsewhere in four minutes must not hide that packet.
        if(distance<=15000&&direct.length){
          if(direct.some(r=>r.invalid||!num(r.number,0,100))||Math.max(...direct.map(r=>r.number))-Math.min(...direct.map(r=>r.number))>1)return null;
          return direct[0];
        }
        if(!nearby.length||nearby.some(r=>r.invalid||!num(r.number,0,100)))return null;
        if(Math.max(...nearby.map(r=>r.number))-Math.min(...nearby.map(r=>r.number))>2)return null;
        return nearby.sort((a,b)=>Math.abs(a.at-time)-Math.abs(b.at-time))[0];
      };
      for(const kind of ['trips','charges'])for(const row of this.state[kind]){
        if(row.collectedAfterEnd||row.atPrecision==='day')continue;
        for(const [key,time] of [['startSOC',kind==='trips'?row.start:row.at],['endSOC',row.end]]){
          if(kind==='charges'&&key==='startSOC'&&row.startTimeObserved===false)continue;
          if(kind==='charges'&&key==='startSOC'&&row.startSOCEstimated&&num(row.initialAddedKWh,0.5,300))continue;
          if(!num(time,1,1e14)||row[key]!=null&&!row[key==='startSOC'?'startSOCEstimated':'endSOCEstimated']&&!(key==='endSOC'&&row.endSOCLastObserved))continue;
          const sample=nearest(time);if(!sample)continue;
          if(kind==='charges'&&((key==='startSOC'&&num(row.endSOC,0,100)&&sample.number>row.endSOC)||(key==='endSOC'&&num(row.startSOC,0,100)&&sample.number<row.startSOC)))continue;
          row[key]=sample.number;row[key+'Observed']=true;row[key+'TelemetryAt']=sample.at;
          row[key==='startSOC'?'startSOCEstimated':'endSOCEstimated']=false;
          if(key==='endSOC')row.endSOCLastObserved=false;
        }
        if(kind==='charges'&&row.startSOCObserved===true&&row.endSOCObserved===true&&row.endTimeObserved===true)row.complete=true;
      }
    }
    mergeHistory(value){
      const source=validateState(value),target=this.state;
      if(!target.settings.vin||source.settings.vin!==target.settings.vin)throw Error('동일 VIN의 기록만 합칠 수 있음');
      const staged={trips:[...target.trips],charges:[...target.charges]},counts={trips:0,charges:0,duplicates:0};
      for(const kind of ['trips','charges'])for(const row of source[kind]){
        const exact=staged[kind].find(x=>x.id===row.id);
        if(exact){if(JSON.stringify(exact)!==JSON.stringify(row))throw Error('같은 ID의 내용이 다름 · 원본을 유지함');counts.duplicates++;continue;}
        const same=staged[kind].some(x=>kind==='trips'?x.start===row.start&&x.end===row.end&&x.distanceKm===row.distanceKm:x.at===row.at&&x.startSOC===row.startSOC&&x.endSOC===row.endSOC&&x.supplyKWh===row.supplyKWh&&x.cost===row.cost);
        if(same){counts.duplicates++;continue;}
        append(staged[kind],row);counts[kind]++;
      }
      target.trips=staged.trips.sort((a,b)=>a.start-b.start);target.charges=staged.charges.sort((a,b)=>a.at-b.at);return counts;
    }
    auditedCharges(){return this._viewAudit??auditCharges(reconciledCharges(this.state.charges));}
    chargeTariffQuote(c){return costEstimate(c,this.state.settings,new Map());}
    enrichChargeSites(v){
      if(!this.state.settings.vin||v.vin!==this.state.settings.vin)return false;
      const sites=(v.sites??[]).slice(0,20000).filter(p=>validCoordinates(p.latitude,p.longitude)&&typeof p.id==='string'&&p.id.length<100&&typeof p.operator==='string'&&p.operator.trim());
      const grid=new Map(),cell=(lat,lon)=>Math.floor(lat*100)+','+Math.floor(lon*100);
      for(const p of sites){const key=cell(p.latitude,p.longitude);if(!grid.has(key))grid.set(key,[]);grid.get(key).push(p);}
      let changed=false;
      for(const c of [...this.state.charges.slice(-1000),this.state.activeCharge].filter(Boolean)){
        if(c.chargeOperator||c.siteMatch||!validCoordinates(c.latitude,c.longitude))continue;
        const local=[];let dense=false;
        for(let y=-1;y<=1;y++)for(let x=-1;x<=1;x++){
          const bucket=grid.get((Math.floor(c.latitude*100)+y)+','+(Math.floor(c.longitude*100)+x))??[];
          if(bucket.length>200){dense=true;continue;}local.push(...bucket);
        }
        if(dense)continue;
        const candidates=local.filter(p=>nearby(c,p,75)&&(!c.chargeType||p.kind===c.chargeType));
        const groups=new Map();for(const p of candidates)groups.set(p.id,p);
        if(groups.size!==1)continue; // Several operators/places in a basement cannot be distinguished by GPS.
        const p=[...groups.values()][0];
        c.siteMatch={id:p.id,name:text(p.name,120),operator:canonicalOperator(p.operator),ratedKW:num(p.ratedKW,0.1,1000)?p.ratedKW:null,matchedAt:Date.now(),source:'공공 충전소 위치 대조 · 추정'};
        if(!c.chargeType&&['ac','dc'].includes(p.kind))c.chargeType=p.kind;
        changed=true;
      }
      return changed;
    }
    capacitySamples(from=0,now=Date.now()){
      // v1.55: verified manual entries plus automatic sessions where the car itself reported the energy added
      // (charge_energy_added) over a ≥20 %p SOC window. Before this, auto sessions never qualified, so the
      // degradation card stayed at "collecting" forever.
      return this.auditedCharges().accepted.filter(c=>!c.active&&!c.startSOCEstimated&&!c.endSOCEstimated&&!c.endSOCLastObserved&&num(c.at,from,now)&&num(c.startSOC,0,100)&&num(c.endSOC,0,100)&&c.endSOC-c.startSOC>=20)
        .map(c=>{const verified=c.complete&&c.storageVerified&&c.comparable&&num(c.storedKWh,1,200);const kwh=verified?c.storedKWh:num(c.vehicleReportedKWh,1,200)?c.vehicleReportedKWh:null;
          return kwh==null?null:{id:c.id,at:c.at,kwh:kwh/((c.endSOC-c.startSOC)/100),verified};})
        .filter(c=>c&&num(c.kwh,20,200)).sort((a,b)=>a.at-b.at);
    }
    healthIndex(now=Date.now()){
      const s=this.state,since=s.settings.healthBatteryStartAt??0;
      const charge=this.capacitySamples(since,now);
      const bms=(s.batteryObservations??[]).filter(p=>p.method==='bmsNominal'&&num(p.at,since,now)&&num(p.value,20,200)).sort((a,b)=>a.at-b.at);
      const direct=bms.length&&bms.at(-1).at>=now-30*DAY;
      const method=direct?'bmsNominal':'chargeUsable';
      const samples=direct?bms.map(p=>({id:p.id,at:p.at,kwh:p.value})):charge;
      const stable=rows=>{if(rows.length<5)return rows;const m=median(rows.map(c=>c.kwh)),mad=median(rows.map(c=>Math.abs(c.kwh-m)));const kept=rows.filter(c=>Math.abs(c.kwh-m)<=Math.max(m*.05,3*mad));return kept.length>=Math.ceil(rows.length*.7)?kept:rows;};
      const first=stable(samples.slice(0,5)),recentSet=stable(samples.slice(-10));
      const recent=recentSet.length>=(direct?1:3)?median(recentSet.map(c=>c.kwh)):null;
      const configured=s.settings.healthReferenceMethod===method&&num(s.settings.healthReferenceKWh,20,200)?s.settings.healthReferenceKWh:null;
      const personal=!configured&&samples.length>=10?median(first.map(c=>c.kwh)):null;
      const baseline=configured??personal;
      // Reference and current values must be the same energy definition. Never use the generic75kWh consumption assumption as SOH.
      const compareSet=personal?stable(samples.slice(5).slice(-10)):recentSet;
      const current=compareSet.length>=3?median(compareSet.map(c=>c.kwh)):null;
      const spread=compareSet.length?Math.max(...compareSet.map(c=>c.kwh))-Math.min(...compareSet.map(c=>c.kwh)):null;
      const comparable=baseline!=null&&current!=null&&spread/current<=.2;
      const ratio=comparable?current/baseline*100:null;
      const reason=samples.length<(direct?1:3)?'시작·종료 SOC와 배터리 충전량을 확인한 20%p 이상 충전 3회 필요':!baseline?'같은 종류의 기준 용량 미등록 · 관측 용량 표시, 기록 10회부터 초기 대비 변화 제공':!current?'비교용 관측 자료 3회 필요':!comparable?'관측 용량 편차가 큼 · 변화율 계산 보류':ratio>100?'기준보다 높은 관측 용량 · 온도·BMS 보정 영향 확인':configured?'등록한 동일 종류 기준 용량 대비 감소 추정':'기록 시작 용량 대비 감소 · 신차 대비 열화율 아님';
      return {method,capacityLabel:direct?'차량 보고 완충 용량':'충전 기반 참고 용량',comparisonLabel:configured?'등록 기준 대비 감소':'기록 시작 대비 감소',
        sampleCount:samples.length,stableSampleCount:compareSet.length,samplesNeeded:baseline?3:10,totalChargeCount:s.charges.length,
        capacityMedianKWh:round(recent,1),recentCapacityKWh:round(recent,1),baselineCapacityKWh:round(baseline,1),capacityMinKWh:recentSet.length?round(Math.min(...recentSet.map(c=>c.kwh)),1):null,capacityMaxKWh:recentSet.length?round(Math.max(...recentSet.map(c=>c.kwh)),1):null,
        initial:!comparable,estimated:comparable,provisional:!configured,soh:ratio==null?null:round(Math.min(100,ratio),1),capacityRatioPercent:round(ratio,1),degradationPercent:ratio==null?null:round(Math.max(0,100-ratio),1),relativeChangePercent:ratio==null?null:round(ratio-100,1),statusReason:reason,
        latestAt:samples.at(-1)?.at??null,baselineSource:configured?'userSameMethod':'initialObservations',forecastSOH180:null,forecastDegradation180:null,uncertaintyPercent:null,
        note:direct?'Tesla가 보고한 NominalFullPackEnergyKwh의 일별 관측 중앙값. 사용 가능 용량·Tesla 상태검사 결과와 같은 값으로 간주하지 않음.':'배터리 충전량 ÷ 직접 확인한 SOC 변화의 참고값. 충전 손실·보조 소비·SOC 비선형·온도 영향이 남아 Tesla BMS 진단과 동일하지 않음.',
        forecastNote:'소수 관측만으로 장기 열화를 외삽하지 않음.'};
    }
    health(){
      const good=this.capacitySamples().map(c=>({at:c.at,capacity:c.kwh}));
      const value=good.length>=3?median(good.slice(-10).map(c=>c.capacity)):null;
      const baseline=good.length>=10?median(good.slice(0,5).map(c=>c.capacity)):null;
      const recent=good.length>=10?median(good.slice(-5).map(c=>c.capacity)):null;
      return {count:good.length,capacity:round(value),baseline:round(baseline),changePercent:baseline?round((recent/baseline-1)*100):null,minimum:good.length?round(Math.min(...good.map(c=>c.capacity))):null,maximum:good.length?round(Math.max(...good.map(c=>c.capacity))):null,note:'선별된 회차의 관측 기반 추정. 최소 5회는 임시 품질 기준이며 정확도를 보장하지 않음. 신차 대비 열화율·수명 진단 아님.'};
    }
    parkingSummary(now=Date.now()){
      const s=this.state,periods=s.parkingPeriods.map(p=>({...p}));
      const d=s.groups.drive,c=s.groups.charge,p=s.lastPark;
      if(p&&d?.gear==='P'&&fresh(d,now)&&fresh(c,now,TTL.charge)&&c.at>p.at&&num(p.soc,0,100)&&num(c.soc,0,100)){
        const dx=num(p.odometerKm,0,1e7)&&num(d.odometerKm,0,1e7)?d.odometerKm-p.odometerKm:null;
        periods.push({id:'current-parking',start:p.at,end:c.at,startSOC:p.soc,endSOC:c.soc,deltaSOC:round(p.soc-c.soc),classification:dx!=null&&dx>=0&&dx<=.2?'parking':'unclassified',ongoing:true});
      }
      const charges=this.auditedCharges().accepted.concat(s.activeCharge?[s.activeCharge]:[]),rows=[];let occupied=-1;
      for(const row of periods.sort((a,b)=>a.start-b.start)){
        if(!num(row.start,0,now)||!num(row.end,row.start+1,now)||row.start<occupied)continue;
        occupied=row.end;const overlap=(a,b)=>row.start<b&&a<row.end;
        const mixed=charges.some(c=>overlap(c.at,c.end??c.lastAt??now)),moved=s.trips.some(t=>overlap(t.start,t.end));
        const hours=(row.end-row.start)/3600000;
        let reason=mixed?'주차 중 충전 포함':moved?'주행과 겹치는 구간':!num(row.deltaSOC,-100,100)?'양 끝 잔량 미확인':row.deltaSOC<0?'잔량 증가 · 온도·BMS 보정 가능':row.classification!=='parking'?'양 끝 주행거리 미확인':'';
        rows.push({...row,hours:round(hours,2),classification:reason?'unclassified':'parking',exclusionReason:reason,precisionLimited:hours<6||Math.abs(row.deltaSOC)<1,perDay:!reason&&hours>=1?round(row.deltaSOC/hours*24,2):null,highLoss:!reason&&row.deltaSOC/hours*24>8});
      }
      const usable=rows.filter(p=>p.classification==='parking'),rates=usable.filter(p=>!p.precisionLimited).map(p=>p.perDay);
      return {rows,count:usable.length,excludedCount:rows.length-usable.length,medianPerDay:round(median(rates),2),lossSOC:usable.length?round(usable.reduce((n,p)=>n+p.deltaSOC,0),1):null};
    }
    energyEstimates(now=Date.now(),from=0,to=now){
      // Estimates are derived views: never overwrite observed evidence or historical records.
      const s=this.state,health=this.health(),capacity=health.capacity??s.settings.assumedCapacityKWh??75;
      const capacityAssumed=health.capacity==null,overlap=(a,b,c,d)=>a<d&&c<b;
      const charges=this.chargeSummary().rows.filter(c=>!c.active&&num(c.at,0,now)),all=s.trips.filter(t=>num(t.start,0,now)&&num(t.end,t.start,now)&&num(t.distanceKm,0,100000)).sort((a,b)=>a.start-b.start);
      const history=[];let occupied=-1,duplicateCount=0;
      const rows=[];
      for(const t of all){
        const duplicate=t.start<occupied;if(duplicate)duplicateCount++;occupied=Math.max(occupied,t.end);
        const km=t.distanceKm,delta=num(t.startSOC,0,100)&&num(t.endSOC,0,100)?t.startSOC-t.endSOC:null;
        const mixed=charges.some(c=>overlap(t.start,t.end,c.at,c.end??c.at+1));
        const observed=num(t.observedMotorDistanceKm,0.05,100000)&&num(t.observedMotorNetKWh,-1e5,1e5)?t.observedMotorNetKWh/t.observedMotorDistanceKm*1000:null;
        const own=observed!=null&&observed>20&&observed<1500?observed:null;
        const personal=median(history.slice(-30));
        let rate=personal??own??180,method=personal!=null?'개인 누적 추정':own!=null?'구동계 기반 추정':'기본값 추정',uncertainty=personal!=null?0.35:own!=null?0.45:0.65;
        if(delta!=null&&delta>=2&&!mixed&&km>0){rate=delta/100*capacity/km*1000;method=capacityAssumed?'SOC·가정 용량 추정':'SOC·관측 용량 추정';uncertainty=Math.min(1,1/delta+(capacityAssumed?0.2:0.1));}
        else if(own!=null&&num(t.observedMotorDistanceKm,km*0.8,km+0.1)){rate=own;method='구동계 기반 추정';uncertainty=0.35;}
        else if(delta!=null&&delta>0&&!mixed&&personal==null&&own==null&&km>0){rate=delta/100*capacity/km*1000;method='SOC·가정 용량 추정';uncertainty=Math.min(1,1/delta+0.2);}
        // A rise in SOC may be regen, temperature or unseen charging; never credit it as negative pack use.
        if(mixed||delta<0){uncertainty=1;method+=' · 혼합';}
        if(!Number.isFinite(rate)||rate<=0||rate>2000){rate=personal??own??180;method='기본값 추정';uncertainty=1;}
        const kwh=km*rate/1000;
        if(!mixed&&delta>=3&&km>=5&&rate>=30&&rate<=1000)history.push(rate);
        const summary=Object.fromEntries(Object.entries(t).filter(([k])=>k!=='points'));
        const row={...summary,duplicate,estimatedKWh:round(kwh,3),estimatedKmPerKWh:km>0?round(1000/rate,2):null,estimatedWhPerKm:km>0?round(rate,1):null,estimateMethod:method,estimateLowKWh:round(Math.max(0,kwh*(1-uncertainty)),3),estimateHighKWh:round(kwh*(1+uncertainty),3),capacityKWh:capacity,capacityAssumed,estimated:true};
        if(t.end>=from&&t.end<=to)rows.push(row);
      }
      let parkingKWh=0,unclassifiedKWh=0,parkingCount=0,parkingEnd=-1;
      for(const p of this.parkingSummary(now).rows){
        if(!num(p.start,0,now)||!num(p.end,p.start,now)||p.end<from||p.end>to||p.start<parkingEnd)continue;
        parkingEnd=p.end;
        if(all.some(t=>overlap(p.start,p.end,t.start,t.end)))continue;
        const delta=num(p.deltaSOC,0,100)?p.deltaSOC:0,kwh=delta/100*capacity;
        const mixed=charges.some(c=>overlap(p.start,p.end,c.at,c.end??c.at+1));
        if(p.classification==='parking'&&!mixed){parkingKWh+=kwh;parkingCount++;}else unclassifiedKWh+=kwh;
      }
      const unique=rows.filter(t=>!t.duplicate),distance=unique.reduce((n,t)=>n+t.distanceKm,0),driving=unique.reduce((n,t)=>n+t.estimatedKWh,0),total=driving+parkingKWh+unclassifiedKWh;
      return {trips:rows,totalDistanceKm:round(distance,2),drivingKWh:round(driving,3),parkingKWh:round(parkingKWh,3),unclassifiedKWh:round(unclassifiedKWh,3),totalKWh:round(total,3),drivingKmPerKWh:driving>0?round(distance/driving,2):null,overallKmPerKWh:total>0?round(distance/total,2):null,parkingCount,duplicateCount,capacityKWh:capacity,capacityAssumed,note:'추정값 포함 · 기간은 운행/주차 종료일 기준. 종합 전비에는 주행 외에 관측된 잔량 감소도 포함. 기본 용량 75 kWh와 기본 전비 180 Wh/km는 차량 제원이 아닌 조정 가능한 계산 가정. 구동계 기반 추정에는 보조 소비가 빠질 수 있음.'};
    }
    target(){
      const s=this.state,ratios=s.trips.filter(t=>!t.missing&&t.distanceKm>=5&&num(t.startSOC,0,100)&&num(t.endSOC,0,100)&&t.startSOC-t.endSOC>=1).slice(-20).map(t=>(t.startSOC-t.endSOC)/t.distanceKm);
      const rate=ratios.length>=5?median(ratios):null,k=s.settings.plannedKm;
      if(rate==null||!num(k,1,3000))return {targetSOC:null,note:'완전한 운행 5회와 예정 거리 입력 후 추정 가능함.'};
      const need=Math.ceil(rate*k+s.settings.reserveSOC);
      return {targetSOC:Math.min(100,need),note:need>100?'한 번 충전으로 여유 잔량 확보 어려움. 중간 충전 계획 확인 필요.':s.settings.dailyLimit&&need>s.settings.dailyLimit?'설정한 일상 충전 기준을 넘는 장거리 계획임.':'최근 관측 소비량 기반. 경로·날씨 차이로 달라질 수 있음.'};
    }
    chargeSummary(){
      const s=this.state,audit=this.auditedCharges(),rows=[...audit.accepted.map(c=>({...c})),...(s.activeCharge?[{...s.activeCharge,active:true,source:'충전 중'}]:[])];
      const total=key=>{const values=rows.map(c=>c[key]).filter(v=>num(v,0,key==='cost'||key==='estimatedCost'?1e7:300));return values.length?round(values.reduce((a,b)=>a+b,0),2):null;};
      const capacity=this.health().capacity??s.settings.assumedCapacityKWh;
      for(const row of rows)if(row.vehicleReportedKWh==null&&num(capacity,20,200)&&num(row.startSOC,0,100)&&num(row.endSOC,row.startSOC,100)){row.estimatedStoredKWh=round((row.endSOC-row.startSOC)/100*capacity,1);}
      const rateHistory=new Map();
      for(const c of audit.accepted.filter(x=>num(x.cost,0.01,1e7)&&num(x.supplyKWh,0.1,300)&&num(x.cost/x.supplyKWh,0,10000)).sort((a,b)=>b.at-a.at)){
        const i=chargeIdentity(c,s.settings);
        for(const scope of ['place','operator'])if(i[scope]){const key=i.kind+'|'+scope+'|'+i[scope];if(!rateHistory.has(key))rateHistory.set(key,[]);rateHistory.get(key).push(c);}
      }
      // v1.42: home = saved home address, any charge the user renamed to 집, or a spot with 4+ mostly overnight AC charges.
      const homeNames=['집','집완속','자택','home'],geo=c=>validCoordinates(c.latitude,c.longitude);
      const ac=rows.filter(c=>geo(c)&&c.chargeType!=='dc'&&c.chargeType!=='supercharger'),night=c=>{const h=new Date(c.at+9*3600000).getUTCHours();return h>=18||h<8;};
      const learned=rows.filter(c=>geo(c)&&homeNames.includes(rateKey(c.place))).map(c=>({latitude:c.latitude,longitude:c.longitude}));
      // Repeated overnight visits alone cannot establish a home address.
      const homeSettings={...s.settings,homeSpots:[s.settings.homePoint,...learned].filter(Boolean)};
      for(const row of rows){
        Object.assign(row,costEstimate(row,homeSettings,rateHistory));
        row.chargedKWh=(row.storageVerified?row.storedKWh:null)??row.vehicleReportedKWh??row.estimatedStoredKWh??null;
        row.chargeEnergyEstimated=row.chargedKWh!=null&&!(row.storageVerified&&row.storedKWh!=null)&&row.vehicleReportedKWh==null;
        row.totalCost=row.cost??row.estimatedCost??null;
      }
      const estimatedRows=rows.filter(c=>!c.active&&c.cost==null&&c.estimatedCost!=null),paidRows=rows.filter(c=>!c.active&&c.cost!=null),pricedSupply=paidRows.filter(c=>num(c.supplyKWh,0.01,300));
      const estimatedCost=estimatedRows.reduce((n,c)=>n+c.estimatedCost,0);
      return {chargedKWh:total('chargedKWh'),energyEstimated:rows.some(c=>c.chargeEnergyEstimated),estimatedCost:estimatedRows.length?estimatedCost:null,estimatedCount:estimatedRows.length,combinedCost:paidRows.length||estimatedRows.length?paidRows.reduce((n,c)=>n+c.cost,0)+estimatedCost:null,averagePaidUnitPrice:pricedSupply.length?pricedSupply.reduce((n,c)=>n+c.cost,0)/pricedSupply.reduce((n,c)=>n+c.supplyKWh,0):null,unpricedCount:rows.filter(c=>!c.active&&c.cost==null&&c.estimatedCost==null).length,rows:rows.slice().sort((a,b)=>(b.end??b.lastAt??b.at)-(a.end??a.lastAt??a.at)),count:rows.length,reviewRows:audit.review,reviewCount:audit.review.length,supplyKWh:total('supplyKWh'),vehicleReportedKWh:total('vehicleReportedKWh'),cost:total('cost'),active:!!s.activeCharge};
    }
    batteryUsage(now=Date.now(),days=30){
      const s=this.state,since=now-days*DAY,inPeriod=t=>num(t,since,now);
      const trips=s.trips.filter(t=>inPeriod(t.end)),charges=this.chargeSummary().rows.filter(c=>inPeriod(c.end??c.lastAt??c.at));
      // Endpoint changes remain observations even when intermediate packets are missing.
      const usable=trips.filter(t=>num(t.startSOC,0,100)&&num(t.endSOC,0,100)&&t.startSOC>t.endSOC&&t.distanceKm>0);
      const chargeObserved=charges.filter(c=>!c.active&&c.complete===true&&!c.startSOCEstimated&&!c.endSOCEstimated&&!c.endSOCLastObserved&&num(c.startSOC,0,100)&&num(c.endSOC,c.startSOC,100));
      const sum=(list,fn)=>list.reduce((n,v)=>n+fn(v),0),soc=t=>t.startSOC-t.endSOC;
      const rateTrips=usable.filter(t=>!t.missing),rateDistance=sum(rateTrips,t=>t.distanceKm),driveSOC=sum(usable,soc);
      const parking=this.parkingSummary(now).rows.filter(p=>inPeriod(p.end));
      const mixed=p=>s.charges.some(c=>!c.chargeExcluded&&(c.end??c.at)>=p.start&&c.at<=p.end)||s.trips.some(t=>t.start<p.end&&t.end>p.start);
      const unmixed=parking.filter(p=>p.classification==='parking'&&!mixed(p)&&num(p.deltaSOC,-100,100));
      const power=trips.filter(t=>num(t.powerSeconds,0.001,1e8)&&num(t.powerUsedKWh,0,1e5)&&num(t.powerRecoveredKWh,0,1e5));
      const trend=[];
      for(const t of trips){
        if(num(t.startSOC,0,100))trend.push({id:t.id+'s',segment:t.id,at:t.start,soc:t.startSOC,kind:'주행'});
        const endAt=t.end;
        if(num(t.endSOC,0,100))trend.push({id:t.id+'e',segment:t.id,at:endAt,soc:t.endSOC,kind:'주행'});
      }
      for(const c of charges){
        const startAt=c.at;
        const rawEnd=c.end??c.lastAt??c.at;
        const endAt=rawEnd;
        if(c.startTimeObserved!==false&&!c.startSOCEstimated&&num(c.startSOC,0,100))trend.push({id:c.id+'s',segment:c.id,at:startAt,soc:c.startSOC,kind:'충전'});
        if(!c.endSOCEstimated&&num(c.endSOC,0,100))trend.push({id:c.id+'e',segment:c.id,at:endAt,soc:c.endSOC,kind:'충전'});
      }
      const rawTrendList=trend.filter(t=>inPeriod(t.at)).sort((a,b)=>a.at-b.at);
      const cleanTrendList=[...new Map(rawTrendList.map(p=>[p.id,p])).values()];
      const observedSeconds=sum(power,t=>t.powerSeconds),duration=sum(trips,t=>t.powerDurationSeconds??Math.max(0,(t.end-t.start)/1000));
      return {days,energy:this.energyEstimates(now,since),tripCount:trips.length,completeTrips:trips.filter(t=>!t.missing).length,excludedRateTrips:trips.length-rateTrips.length,
        observedDischargeCycles:usable.length?round(driveSOC/100,2):null,
        medianDischargeDepth:usable.length?round(median(usable.map(soc)),1):null,
        deepDischargeTrips:usable.filter(t=>soc(t)>=50).length,
        lowEndTrips:usable.filter(t=>t.endSOC<20).length,
        highEndCharges:charges.filter(c=>!c.active&&num(c.endSOC,90,100)).length,
        distanceKm:round(sum(trips,t=>num(t.distanceKm,0,100000)?t.distanceKm:0),1),driveSOC:usable.length?round(driveSOC,1):null,
        socPer100Km:rateDistance>0?round(sum(rateTrips,soc)/rateDistance*100,1):null,
        chargeSOC:chargeObserved.length?round(sum(chargeObserved,c=>c.endSOC-c.startSOC),1):null,
        partialChargeCount:charges.filter(c=>!c.complete).length,
        chargeCount:charges.length,unexplainedParkingSOC:round(sum(unmixed,p=>Math.max(0,p.deltaSOC)),1),mixedParkingCount:parking.length-unmixed.length,
        observedUsedKWh:power.length?round(sum(power,t=>t.powerUsedKWh),2):null,observedRecoveredKWh:power.length?round(sum(power,t=>t.powerRecoveredKWh),2):null,
        powerCoverage:duration>0?round(Math.min(1,observedSeconds/duration)*100,1):null,
        trend:cleanTrendList.slice(-120),
        parking:{rows:parking,count:unmixed.length,excludedCount:parking.length-unmixed.length,medianPerDay:round(median(unmixed.filter(p=>!p.precisionLimited).map(p=>p.perDay)),2)},tripRows:this.energyEstimates(now,since).trips.filter(t=>!t.duplicate).slice(-30).map(t=>({id:t.id,at:t.end,start:t.start,km:t.distanceKm,startSOC:t.startSOC,endSOC:t.endSOC,soc:num(t.startSOC,0,100)&&num(t.endSOC,0,100)?round(soc(t),1):null,kwh:t.estimatedKWh,whPerKm:t.estimatedWhPerKm,kmPerKWh:t.estimatedKmPerKWh,method:t.estimateMethod,partial:!!t.missing})),
        note:'관측 기록 기준. 주차 전후 변화는 미관측 충전·이동·온도 영향을 포함할 수 있으며 대기 소모로 단정하지 않음. 공조·감시모드·열관리 사용량은 미분리.'};
    }
    briefing(now=Date.now()){
      const g=this.state.groups,c=g.charge,t=g.climate,parts=[];
      const soc=(c&&fresh(c,now,TTL.charge)&&c.soc!=null)?c.soc:null;
      const rangeKm=(c&&fresh(c,now,TTL.charge)&&c.rangeKm!=null)?Math.round(c.rangeKm):null;
      const insideC=(t&&fresh(t,now,TTL.climate)&&t.insideC!=null)?Math.round(t.insideC):null;
      const isChg=c&&fresh(c,now,TTL.charge)&&(c.charging>0?c.charging===5:(c.chargerKW||0)>0.5);

      if(isChg){
        parts.push('충전 중입니다.');
        if(soc!=null)parts.push(`현재 배터리 잔량은 ${soc}%입니다.`);
      }else{
        if(soc!=null)parts.push(`현재 배터리 잔량은 ${soc}%입니다.`);
        if(rangeKm!=null&&rangeKm>0)parts.push(`남은 거리는 ${rangeKm}킬로미터입니다.`);
      }
      return parts.length ? parts.join(' ') : '최신 차량 상태 미수신.';
    }
    liveView(now=Date.now()){
      // BLE/background callbacks must never traverse route history or calculate period statistics.
      const s=this.state,history={},state={};
      for(const [key,value] of Object.entries(s)){
        if(Array.isArray(value)){
          const last=value.at(-1);history[key]={count:value.length,rows:last?[key==='trips'?Object.fromEntries(Object.entries(last).filter(([k])=>k!=='points')):last]:[]};
        }else if(key==='activeTrip'&&value){state[key]=Object.fromEntries(Object.entries(value).filter(([k])=>k!=='points'));}
        else state[key]=value;
      }
      return {liveDelta:true,state,history,briefing:this.briefing(now),fresh:Object.fromEntries(Object.entries(s.groups).map(([k,g])=>[k,k==='location'?freshLocation(g,now):fresh(g,now)]))};
    }
    view(now=Date.now()){
      if(this._liveOnly)return this.liveView(now);
      this._viewAudit=auditCharges(reconciledCharges(this.state.charges));
      try {
      const s=this.state,charging=this.chargeSummary();
      return {state:s,charging,parking:this.parkingSummary(now),energy:this.energyEstimates(now),energyPeriods:Object.fromEntries([1,7,30,90,36500].map(days=>[String(days),this.energyEstimates(now,Math.max(0,now-days*DAY))])),health:this.health(),healthIndex:this.healthIndex(now),target:this.target(),battery:Object.fromEntries([7,30,90].map(days=>[String(days),this.batteryUsage(now,days)])),briefing:this.briefing(now),fresh:Object.fromEntries(Object.entries(s.groups).map(([k,g])=>[k,k==='location'?freshLocation(g,now):fresh(g,now)])),totals:{trips:s.trips.length,distanceKm:round(s.trips.reduce((n,t)=>n+(t.distanceKm||0),0)),charges:charging.count,cost:charging.cost,supplyKWh:charging.supplyKWh,vehicleReportedKWh:charging.vehicleReportedKWh}};
      } finally { this._viewAudit=null; }
    }
    csv(){
      const summary=this.chargeSummary(),priced=new Map(summary.rows.map(c=>[c.id,c]));
      const esc=v=>'"'+String(v??'').replace(/"/g,'""').replace(/^[=+@-]/,"'")+'"';
      return '\uFEFF'+[['종류','시각UTC','거리km','시작SOC','종료SOC','공급kWh','금액','출처','누락','집계 검증','예상금액','예상단가','단가근거','배터리충전kWh','충전량추정','총충전비','종료UTC'],...this.state.trips.map(t=>['운행',new Date(t.start).toISOString(),t.distanceKm,t.startSOC,t.endSOC,'','','BLE',t.missing]),...[...summary.rows,...summary.reviewRows].map(c=>['충전',new Date(c.at).toISOString(),'',c.startSOC,c.endSOC,c.supplyKWh,c.cost,c.source,!c.complete,c.chargeExcluded?'제외: '+c.chargeReviewReason:'집계 포함',priced.get(c.id)?.estimatedCost,priced.get(c.id)?.estimatedUnitPrice,priced.get(c.id)?.costRateSource,c.chargedKWh,c.chargeEnergyEstimated,c.totalCost,c.end?new Date(c.end).toISOString():null])].map(r=>r.map(esc).join(',')).join('\r\n');
    }
    demo(now=Date.now()){
      this.state=initial();this.ensureBatteryBaseline(now);const s=this.state;s.settings.name='Model Y · 예시';
      s.groups={charge:{at:now,soc:46,rangeKm:218,limit:80,charging:2},drive:{at:now,gear:'P',speedKmh:0,odometerKm:1250,destination:'예시 목적지',destinationLat:37.52094,destinationLng:127.12301},climate:{at:now,insideC:24,outsideC:22},tire:{at:now,values:[2.8,2.8,2.8,2.8],warnings:[false,false,false,false]}};
      s.trips=[{id:'demo-trip',start:now-2400000,end:now-600000,distanceKm:18.2,startSOC:51,endSOC:46,missing:false,points:[]}];
      s.charges=[{id:'demo-charge',at:now-DAY,startSOC:30,endSOC:80,supplyKWh:42,storedKWh:null,cost:10500,source:'예시',complete:true}];s.lastBrief='예시 운행 18.2 km, 30분. 실제 차량 기록이 아님.';return this.view(now);
    }
  }
  const api={Engine,initial,fresh,TTL,median,navURL,navigationEvent,embeddedDestination,EmbeddedRouteGate,parseReceipt,validateState,tariffCatalog,canonicalOperator};root.YLCore=api;if(typeof module!=='undefined')module.exports=api;
})(typeof globalThis!=='undefined'?globalThis:this);
