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
  function initial(){return {schema:1,settings:{name:'Model Y',model:'Model Y L',vin:'',reserveSOC:20,dailyLimit:null,tariff:null,plannedKm:null},batteryBaseline:null,groups:{},trips:[],charges:[],maintenance:[],parkingNotes:[],parkingPeriods:[],tires:[],activeTrip:null,activeCharge:null,lastPark:null,navSent:null,weather:null,lastBrief:'차량에 연결하면 최신 상태를 안내함.'};}
  // Two parking records describe the same spot when they are within ~35 m.
  function nearby(a,b){
    if(!validCoordinates(a?.latitude,a?.longitude)||!validCoordinates(b?.latitude,b?.longitude))return false;
    const dLat=(a.latitude-b.latitude)*111320,dLng=(a.longitude-b.longitude)*111320*Math.cos(a.latitude*Math.PI/180);
    return Math.sqrt(dLat*dLat+dLng*dLng)<=35;
  }
  function validCoordinates(lat,lng){return num(lat,-90,90)&&num(lng,-180,180)&&!(lat===0&&lng===0);}
  const freshLocation=(g,now)=>fresh(g,now)&&validCoordinates(g.latitude,g.longitude)&&(!g.positionStatus||g.positionStatus==='available')&&g.estimatedGPSValid!==false;
  function navURL(drive,now,appname){
    if(!fresh(drive,now))throw Error('목적지 데이터가 오래됨. 차량에서 다시 수신해야 함.');
    if(!drive.destination?.trim())throw Error('활성 목적지가 없음. 차량 내비에 목적지를 설정해야 함.');
    if(!validCoordinates(drive.destinationLat,drive.destinationLng))throw Error('목적지 좌표 미수신. 네이버에서 장소를 직접 확인해야 함.');
    if(!num(drive.destinationLat,31.43,44.35)||!num(drive.destinationLng,122.37,132))throw Error('네이버 문서의 국내 좌표 범위 밖임.');
    if(typeof appname!=='string'||!appname.trim())throw Error('앱 식별자 없음');
    const q={dlat:drive.destinationLat,dlng:drive.destinationLng,dname:drive.destination,appname};
    return 'nmap://navigation?'+Object.keys(q).map(k=>k+'='+encodeURIComponent(q[k])).join('&');
  }
  function navigationEvent(drive,now,lastSent,appname){
    if(!fresh(drive,now)||!Number.isFinite(drive.receivedAt)||now-drive.receivedAt>30000||drive.receivedAt>now)return {type:'wait'};
    if(!drive.destination?.trim())return {type:'clear'};
    const url=navURL(drive,now,appname);
    const token=JSON.stringify([drive.destination.trim(),Number(drive.destinationLat.toFixed(5)),Number(drive.destinationLng.toFixed(5))]);
    return {type:token===lastSent?'same':'route',token,url};
  }
  function embeddedDestination(drive,now){
    if(!fresh(drive,now)||!Number.isFinite(drive.receivedAt)||drive.receivedAt>now||now-drive.receivedAt>30000)return {type:'wait'};
    // A complete, fresh drive response with every route field absent needs repeated confirmation.
    if(drive.routeFieldsAbsent===true)return {type:'absent',at:drive.at,receivedAt:drive.receivedAt};
    // An arbitrary partial group is not a vehicle destination-clear event.
    if(typeof drive.destination!=='string')return {type:'wait'};
    const name=drive.destination.trim();
    if(!name)return {type:'clear'};
    if(!validCoordinates(drive.destinationLat,drive.destinationLng))return {type:'wait'};
    return {type:'route',name:name.slice(0,300),latitude:drive.destinationLat,longitude:drive.destinationLng,
      at:drive.at,receivedAt:drive.receivedAt,token:JSON.stringify([name.slice(0,300),Number(drive.destinationLat.toFixed(5)),Number(drive.destinationLng.toFixed(5))])};
  }
  // Memory-only lifecycle. Never exported with vehicle records or restored on launch.
  // v29: a destination is identified by position (<=200 m), not by the exact float/name token.
  // Tesla re-reports float32 coordinates and renames POIs while stopped; that must not restart guidance.
  const sameSpot=(a,b)=>{if(!a||!b)return false;const dy=(a.lat-b.lat)*111320,dx=(a.lng-b.lng)*111320*Math.cos(a.lat*Math.PI/180);return Math.hypot(dx,dy)<=200;};
  class EmbeddedRouteGate{
    constructor(){this.generation=0;this.active=null;this.blocked=null;this.absence=null;this.lastObservation=0;}
    observe(event,ready,guiding){
      if(event.type==='clear'){this.cancel(false);this.blocked=null;return {type:'clear'};}
      if(event.type==='absent'){
        if(!Number.isFinite(event.at)||!Number.isFinite(event.receivedAt)||event.at<=this.lastObservation)return {type:'wait'};
        this.lastObservation=event.at;
        const previous=this.absence;
        this.absence=previous&&event.receivedAt>previous.last&&event.receivedAt-previous.last<=20000?
          {first:previous.first,last:event.receivedAt,count:previous.count+1}:{first:event.receivedAt,last:event.receivedAt,count:1};
        // Established guidance tolerates transient empty route groups (stops, Tesla re-routing, BLE partials). 
        const need=this.active&&guiding?{count:6,span:45000}:{count:3,span:3000};
        if(this.absence.count>=need.count&&this.absence.last-this.absence.first>=need.span){
          this.cancel(false);this.blocked=null;return {type:'clear',reason:'vehicleRouteAbsent'};
        }
        return {type:'wait'};
      }
      if(event.type!=='route')return {type:'wait'};
      this.absence=null;this.lastObservation=Math.max(this.lastObservation,event.at||0);
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
    reset(){this.cancel(false);this.blocked=null;this.lastObservation=0;}
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
    return {supplyKWh,cost,unitPrice,startSOC,endSOC,place,minutes,
      dateText:date?`${date[1]}-${date[2].padStart(2,'0')}-${date[3].padStart(2,'0')}`:null,
      timeText:time?`${String(time[1]).padStart(2,'0')}:${time[2]}`:null,
      filled,filledCount:filled.length,
      ambiguous:guessed||(kwhAll.length>1&&supplyKWh==null)||(wonAll.length>1&&cost==null),raw:s};
  }
  function validateState(s,opts={}){
    if(!s||s.schema!==1||typeof s.settings!=='object'||!s.groups||typeof s.groups!=='object')throw Error('지원하지 않는 백업 형식');
    const checkIds=(a,name)=>{if(!Array.isArray(a)||a.length>10000)throw Error(name+' 자료 크기 초과');const seen=new Set();for(let i=0;i<a.length;i++){const r=a[i];if(!r||typeof r!=='object'){a.splice(i,1);i--;continue;}if(typeof r.id!=='string'||!r.id||r.id.length>100||seen.has(r.id)){r.id=id();}seen.add(r.id);}};
    for(const name of ['trips','charges','maintenance','parkingNotes','parkingPeriods','tires'])checkIds(s[name],name);
    if(typeof s.settings.vin!=='string'||(s.settings.vin&&!/^[A-HJ-NPR-Z0-9]{17}$/.test(s.settings.vin)))throw Error('백업 VIN 오류');
    if(!num(s.settings.reserveSOC,0,80)||!optional(s.settings.assumedCapacityKWh,20,200)||!optional(s.settings.dailyLimit,1,100)||!optional(s.settings.tariff,0,10000)||!optional(s.settings.plannedKm,0,3000))throw Error('백업 설정 수치 오류');
    for(const t of s.trips){if(!num(t.start,0,1e14)||!num(t.end,t.start,1e14)||!optional(t.distanceKm,0,100000)||!optional(t.startSOC,0,100)||!optional(t.endSOC,0,100)||!optional(t.observedMotorUsedKWh,0,1e5)||!optional(t.observedMotorRecoveredKWh,0,1e5)||!optional(t.observedMotorNetKWh,-1e5,1e5)||!optional(t.observedMotorDistanceKm,0,100000)||!optional(t.observedMotorWhPerKm,-1e6,1e6))throw Error('운행 기록 수치 오류');}
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
    if(s.activeCharge){const c={...s.activeCharge,source:'BLE 복구',complete:false,storedKWh:null,supplyKWh:null,cost:null};validateCharge(c);if(typeof c.id!=='string'||!c.id)c.id=id();if(!clean.charges.some(x=>x.id===c.id))append(clean.charges,c);}
    // v30: a trip interrupted by an app restart within 30 min continues (odometer continuity is re-checked on the next sample).
    if(!(opts.resumeActive===true&&clean.activeTrip&&s.activeTrip&&clean.activeTrip.id===s.activeTrip.id))clean.activeTrip=null;
    clean.activeCharge=null;clean.navSent=null;clean.weather=null;
    return clean;
  }
  function validateCharge(c){
    if(!num(c.at,0,1e14)||!optional(c.startSOC,0,100)||!optional(c.endSOC,0,100)||!optional(c.supplyKWh,0,300)||!optional(c.storedKWh,0,300)||!optional(c.cost,0,10000000))throw Error('충전 기록 수치 오류');
    if(c.startSOC!=null&&c.endSOC!=null&&c.endSOC<c.startSOC)throw Error('충전 종료 잔량이 시작보다 작음');
  }
  class Engine{
    constructor(){this.state=initial();this.lastDrive=null;this.lastCharge=null;this.lastTireAt=0;this.parked=false;this.parkTransition=null;this.observed={};this.ensureBatteryBaseline(Date.now());}
    ensureBatteryBaseline(now){if(!this.state.batteryBaseline)this.state.batteryBaseline={at:now,healthPercent:100,source:'assumedNew',capacityKWh:null,referenceIds:[]};}
    load(s,opts={}){this.state=validateState(s,opts);this.ensureBatteryBaseline(Date.now());this.lastDrive=null;this.lastCharge=null;this.parked=false;this.parkTransition=null;this.observed={};return this.view(Date.now());}
    settings(v){
      const s={...this.state.settings};
      for(const k of ['name','model'])if(k in v)s[k]=text(v[k],80);
      if('vin'in v){if(typeof v.vin!=='string')throw Error('VIN 형식 오류');const vin=v.vin.trim().toUpperCase();if(vin&&!/^[A-HJ-NPR-Z0-9]{17}$/.test(vin))throw Error('VIN은 I/O/Q를 제외한 영문·숫자 17자리임');const recorded=['trips','charges','maintenance','parkingNotes','parkingPeriods','tires'].some(k=>this.state[k].length)||Object.keys(this.state.groups).length;if(this.state.settings.vin&&vin!==this.state.settings.vin&&recorded)throw Error('기존 기록의 차량과 VIN이 다름. 먼저 백업하고 새 프로필이 필요함.');s.vin=vin;}
      for(const [k,lo,hi]of [['assumedCapacityKWh',20,200],['reserveSOC',0,80],['dailyLimit',1,100],['tariff',0,10000],['plannedKm',0,3000]])if(k in v){if(!optional(v[k],lo,hi)||(k==='reserveSOC'&&v[k]==null))throw Error('설정 범위를 확인해야 함: '+k);s[k]=v[k]??null;}
      this.state.settings=s;return s;
    }
    ingest(snapshot,now=Date.now()){
      if(!snapshot?.groups)throw Error('상태 형식 오류');
      for(const name of ['charge','drive','climate','tire','location','closures','media','mediaDetail']){
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
        if(name==='drive')this.drive(g,now);
        if(name==='charge')this.charge(g,now);
        if(name==='tire'&&g.at-this.lastTireAt>=60000){this.state.tires.push({id:id(),at:g.at,values:g.values,seenAt:g.seenAt});this.state.tires=this.state.tires.slice(-2000);this.lastTireAt=g.at;}
      }
      const d=this.state.groups.drive,l=this.state.groups.location;
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
    drive(g,now){
      if(!fresh(g,now)||this.lastDrive&&g.at<=this.lastDrive.at)return;
      const s=this.state,prev=this.lastDrive,c=fresh(s.groups.charge,now,TTL.charge)?s.groups.charge:null;
      // Resume after disconnect in P: close the previous trip before a new drive starts.
      if(s.activeTrip?.parkAt!=null&&g.at-s.activeTrip.parkAt>=45000)this.finish(s.activeTrip.parkAt,false);
      const moving=['D','R'].includes(g.gear)&&num(g.speedKmh,1,350);
      if(moving&&!s.activeTrip){
        s.activeTrip={id:id(),start:g.at,startSOC:c?.soc??null,lastSOC:c?.soc??null,startOdo:g.odometerKm,lastOdo:g.odometerKm,distanceKm:0,missing:false,observedStart:!!prev&&prev.gear==='P'&&g.at-prev.at<=15000,socUnknown:c==null,gaps:0,gapSeconds:0,lastAt:g.at,parkAt:null,points:[]};
        if(s.lastPark&&c){const parkedDistance=num(s.lastPark.odometerKm,0,1e7)&&num(g.odometerKm,0,1e7)?g.odometerKm-s.lastPark.odometerKm:null;append(s.parkingPeriods,{id:id(),start:s.lastPark.at,end:g.at,startSOC:s.lastPark.soc,endSOC:c.soc,deltaSOC:s.lastPark.soc==null||c.soc==null?null:round(s.lastPark.soc-c.soc),startOdo:s.lastPark.odometerKm??null,endOdo:g.odometerKm??null,classification:parkedDistance!=null&&parkedDistance>=0&&parkedDistance<=0.2?'parking':'unclassified',note:'양 끝 주행거리로 주차 추정 · 미관측 충전·온도 영향 가능'});s.lastPark=null;}
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
        const loc=s.groups.location;if(freshLocation(loc,now)&&t.points.length<2000)t.points.push({at:g.at,lat:loc.latitude,lng:loc.longitude});
        if(g.gear==='P'){if(t.parkAt==null)t.parkAt=g.at;if(g.at-t.parkAt>=45000)this.finish(g.at,false);}else t.parkAt=null;
      }
      this.lastDrive=g;
    }
    finish(now=Date.now(),manual=true){
      const s=this.state,t=s.activeTrip;if(!t)throw Error('진행 중인 운행이 없음');
      const end=t.parkAt??t.lastAt;
      const motorObserved=t.powerSeconds>0&&num(t.powerUsedKWh,0,1e5)&&num(t.powerRecoveredKWh,0,1e5),motorDistance=motorObserved&&num(t.powerDistanceKm,0,100000)?t.powerDistanceKm:null;
      const motorNet=motorObserved?t.powerUsedKWh-t.powerRecoveredKWh:null;
      const trip={id:t.id,start:t.start,end:Math.max(end,t.start),startSOC:t.startSOC,endSOC:t.lastSOC,distanceKm:round(t.distanceKm,2),missing:!!t.missing,manualEnd:!!manual,gaps:t.gaps||0,gapSeconds:round(t.gapSeconds||0,0),points:t.points,
        powerUsedKWh:motorObserved?t.powerUsedKWh:null,powerRecoveredKWh:motorObserved?t.powerRecoveredKWh:null,powerSeconds:t.powerSeconds??0,powerDurationSeconds:Math.max(0,(t.lastAt-t.start)/1000),
        observedMotorUsedKWh:motorObserved?round(t.powerUsedKWh,3):null,observedMotorRecoveredKWh:motorObserved?round(t.powerRecoveredKWh,3):null,
        observedMotorNetKWh:motorObserved?round(motorNet,3):null,observedMotorDistanceKm:motorDistance==null?null:round(motorDistance,3),
        observedMotorWhPerKm:motorDistance>0?round(motorNet/motorDistance*1000,1):null};
      append(s.trips,trip);s.activeTrip=null;
      s.lastPark={at:end,soc:t.lastSOC,odometerKm:t.lastOdo};
      const delta=trip.startSOC!=null&&trip.endSOC!=null?round(trip.startSOC-trip.endSOC):null;
      s.lastBrief=`이번 운행 거리는 ${trip.distanceKm} km, 소요 시간은 ${Math.round((trip.end-trip.start)/60000)}분입니다. `+(delta==null?'배터리 사용량은 확인되지 않았습니다.':`배터리 잔량은 ${Math.abs(delta)} 퍼센트포인트 ${delta>=0?'감소':'증가'}했습니다.`)+(trip.missing?' 일부 구간은 확인되지 않아 추정값으로 안내합니다.':'');
      return trip;
    }
    charge(g,now){
      if(!fresh(g,now)||this.lastCharge&&g.at<=this.lastCharge.at)return;
      const s=this.state,prev=this.lastCharge;
      if(s.activeCharge&&(!prev||g.at-prev.at>30000))s.activeCharge.partial=true;
      if(g.charging===5){
        if(!s.activeCharge)s.activeCharge={id:id(),at:g.at,startSOC:g.soc,endSOC:g.soc,lastAdded:g.addedKWh,vehicleReportedKWh:g.addedKWh,partial:!prev||prev.charging===5};
        const c=s.activeCharge;if(g.addedKWh!=null&&c.lastAdded!=null&&g.addedKWh<c.lastAdded)c.partial=true;
        c.endSOC=g.soc??c.endSOC;c.lastAt=g.at;
        if(num(g.addedKWh,0,300)){c.lastAdded=g.addedKWh;c.vehicleReportedKWh=Math.max(c.vehicleReportedKWh??0,g.addedKWh);}
      }else if(s.activeCharge&&[2,6,7].includes(g.charging)){
        const c=s.activeCharge;c.endSOC=g.soc??c.endSOC;c.end=g.at;c.source='BLE';c.storedKWh=null;c.supplyKWh=null;c.cost=null;c.complete=!c.partial;
        if(num(g.addedKWh,0,300))c.vehicleReportedKWh=Math.max(c.vehicleReportedKWh??0,g.addedKWh);
        append(s.charges,c);s.activeCharge=null;
      }
      this.lastCharge=g;
    }
    addCharge(v){
      const c={id:id(),at:v.at??Date.now(),startSOC:v.startSOC??null,endSOC:v.endSOC??null,supplyKWh:v.supplyKWh??null,storedKWh:v.storedKWh??null,cost:v.cost??null,source:v.source==='OCR'?'OCR 확인':'수동',place:text(v.place,120),note:text(v.note),complete:v.complete===true,storageVerified:v.storageVerified===true,comparable:v.comparable===true};
      validateCharge(c);if(c.storedKWh!=null&&!c.storageVerified)throw Error('저장 에너지로 확인된 자료만 입력해야 함. 영수증은 공급량 칸 사용.');
      c.receiptText=text(v.receiptText,20000);c.estimatedCost=c.cost==null&&c.supplyKWh!=null&&this.state.settings.tariff!=null?round(c.supplyKWh*this.state.settings.tariff,0):null;
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
      validateCharge(c);if(c.storedKWh!=null&&!c.storageVerified)throw Error('저장 에너지로 확인된 자료만 입력해야 함. 영수증은 공급량 칸 사용.');
      c.estimatedCost=c.cost==null&&c.supplyKWh!=null&&this.state.settings.tariff!=null?round(c.supplyKWh*this.state.settings.tariff,0):null;
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
      this.state.charges=this.state.charges.filter(c=>c.id!==key);
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
    healthIndex(now=Date.now()){
      const b=this.state.batteryBaseline??{at:Date.now(),source:'assumedNew'};
      const samples=this.state.charges.filter(c=>num(c.at,b.at,now)&&c.complete&&c.storageVerified&&c.comparable&&num(c.storedKWh,1,200)&&num(c.startSOC,0,100)&&num(c.endSOC,0,100)&&c.endSOC-c.startSOC>=20)
        .map(c=>({id:c.id,at:c.at,kwh:c.storedKWh/((c.endSOC-c.startSOC)/100)})).filter(c=>num(c.kwh,20,200)).sort((a,b)=>a.at-b.at);
      const first=samples.slice(0,5),later=samples.slice(5).slice(-5);
      const baseline=b.capacityKWh??(first.length===5?median(first.map(c=>c.kwh)):null);
      const recent=later.length===5?median(later.map(c=>c.kwh)):null;
      const ratio=baseline&&recent?recent/baseline*100:null;
      const baselineSpread=first.length===5?Math.max(...first.map(c=>c.kwh))-Math.min(...first.map(c=>c.kwh)):null;
      const spread=later.length===5?Math.max(...later.map(c=>c.kwh))-Math.min(...later.map(c=>c.kwh)):null;
      const comparable=ratio!==null&&baselineSpread/baseline<=0.15&&spread/recent<=0.15;
      const history=samples.slice(-30),span=history.length>1?(history.at(-1).at-history[0].at)/DAY:0,slopes=[];
      if(comparable&&history.length>=10&&span>=90){for(let i=0;i<history.length;i++)for(let j=i+1;j<history.length;j++){const days=(history[j].at-history[i].at)/DAY;if(days>=14)slopes.push((history[j].kwh-history[i].kwh)/baseline*100/days);}}
      const slope=slopes.length?Math.min(0,median(slopes)):null;
      const uncertainty=comparable?Math.max(1,(baselineSpread/baseline+spread/recent)*100):null;
      const forecast=slope==null?null:round(Math.max(0,Math.min(100,ratio)+slope*180),1);
      return {baselineAt:b.at,baselineSource:b.source,baselineSOH:100,soh:comparable?round(Math.min(100,ratio),1):100,
        uncertaintyPercent:uncertainty==null?null:round(uncertainty,1),forecastSOH180:forecast,forecastDegradation180:forecast==null?null:round(100-forecast,1),calibrationSpanDays:round(span,0),calibrationMethod:'동일 조건 용량 중앙값·Theil–Sen 추세',
        degradationPercent:comparable?round(Math.max(0,100-ratio),1):0,estimated:comparable,initial:!comparable,
        capacityRatioPercent:ratio===null?null:round(ratio,1),baselineCapacityKWh:round(baseline,1),recentCapacityKWh:round(recent,1),sampleCount:samples.length,
        note:comparable?'초기 관측용량 대비 최근 관측용량 비율의 상대 추정. 신차 실측 SOH·보증 진단 아님.':'신차 기준 SOH 100%·열화 0%는 초기 가정값. 비교 가능한 초기 5회와 이후 5회 이상의 저장에너지·SOC 자료 수집 중. 사용 패턴만으로 임의의 열화율을 차감하지 않음.',
        forecastNote:forecast==null?'초기 기준 100%. 비교 가능한 용량 관측 10회·90일 이후 개인 용량 추세로 180일 전망 보정. 미래 열화의 실측값이나 보증 진단이 아님.':'검증된 저장에너지·SOC로 구한 개인 용량 추세의 180일 외삽. 미래 온도·사용 패턴 변화 미반영; 오차 범위는 관측 산포이며 통계적 신뢰구간이 아님.'};
    }
    health(){
      const good=this.state.charges.filter(c=>c.complete&&c.storageVerified&&c.comparable&&num(c.storedKWh,1,200)&&num(c.startSOC,0,100)&&num(c.endSOC,0,100)&&c.endSOC-c.startSOC>=20).map(c=>({at:c.at,capacity:c.storedKWh/((c.endSOC-c.startSOC)/100)})).filter(c=>num(c.capacity,20,200)).sort((a,b)=>a.at-b.at);
      const value=good.length>=5?median(good.slice(-10).map(c=>c.capacity)):null;
      const baseline=good.length>=10?median(good.slice(0,5).map(c=>c.capacity)):null;
      const recent=good.length>=10?median(good.slice(-5).map(c=>c.capacity)):null;
      return {count:good.length,capacity:round(value),baseline:round(baseline),changePercent:baseline?round((recent/baseline-1)*100):null,minimum:good.length?round(Math.min(...good.map(c=>c.capacity))):null,maximum:good.length?round(Math.max(...good.map(c=>c.capacity))):null,note:'선별된 회차의 관측 기반 추정. 최소 5회는 임시 품질 기준이며 정확도를 보장하지 않음. 신차 대비 열화율·수명 진단 아님.'};
    }
    energyEstimates(now=Date.now(),from=0,to=now){
      // Estimates are derived views: never overwrite observed evidence or historical records.
      const s=this.state,health=this.health(),capacity=health.capacity??s.settings.assumedCapacityKWh??75;
      const capacityAssumed=health.capacity==null,overlap=(a,b,c,d)=>a<d&&c<b;
      const charges=s.charges.filter(c=>num(c.at,0,now)),all=s.trips.filter(t=>num(t.start,0,now)&&num(t.end,t.start,now)&&num(t.distanceKm,0,100000)).sort((a,b)=>a.start-b.start);
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
        const row={...t,duplicate,estimatedKWh:round(kwh,3),estimatedKmPerKWh:km>0?round(1000/rate,2):null,estimatedWhPerKm:km>0?round(rate,1):null,estimateMethod:method,estimateLowKWh:round(Math.max(0,kwh*(1-uncertainty)),3),estimateHighKWh:round(kwh*(1+uncertainty),3),capacityKWh:capacity,capacityAssumed,estimated:true};
        if(t.end>=from&&t.end<=to)rows.push(row);
      }
      let parkingKWh=0,unclassifiedKWh=0,parkingCount=0,parkingEnd=-1;
      for(const p of [...s.parkingPeriods].sort((a,b)=>a.start-b.start)){
        if(!num(p.start,0,now)||!num(p.end,p.start,now)||p.end<from||p.end>to||p.start<parkingEnd)continue;
        parkingEnd=p.end;
        if(all.some(t=>overlap(p.start,p.end,t.start,t.end)))continue;
        const delta=num(p.deltaSOC,0,100)?p.deltaSOC:0,kwh=delta/100*capacity;
        const mixed=charges.some(c=>overlap(p.start,p.end,c.at,c.end??c.at+1));
        if(p.classification==='parking'&&!mixed){parkingKWh+=kwh;parkingCount++;}else unclassifiedKWh+=kwh;
      }
      const unique=rows.filter(t=>!t.duplicate),distance=unique.reduce((n,t)=>n+t.distanceKm,0),driving=unique.reduce((n,t)=>n+t.estimatedKWh,0),total=driving+parkingKWh+unclassifiedKWh;
      return {trips:rows,totalDistanceKm:round(distance,2),drivingKWh:round(driving,3),parkingKWh:round(parkingKWh,3),unclassifiedKWh:round(unclassifiedKWh,3),totalKWh:round(total,3),drivingKmPerKWh:driving>0?round(distance/driving,2):null,overallKmPerKWh:total>0?round(distance/total,2):null,parkingCount,duplicateCount,capacityKWh:capacity,capacityAssumed,note:'추정값 포함 · 기간은 운행/주차 종료일 기준. 종합 전비에는 주차·미분류 잔량 감소 포함. 기본 용량 75 kWh와 기본 전비 180 Wh/km는 차량 제원이 아닌 조정 가능한 계산 가정. 구동계 기반 추정에는 보조 소비가 빠질 수 있음.'};
    }
    target(){
      const s=this.state,ratios=s.trips.filter(t=>!t.missing&&t.distanceKm>=5&&num(t.startSOC,0,100)&&num(t.endSOC,0,100)&&t.startSOC-t.endSOC>=1).slice(-20).map(t=>(t.startSOC-t.endSOC)/t.distanceKm);
      const rate=ratios.length>=5?median(ratios):null,k=s.settings.plannedKm;
      if(rate==null||!num(k,1,3000))return {targetSOC:null,note:'완전한 운행 5회와 예정 거리 입력 후 추정 가능함.'};
      const need=Math.ceil(rate*k+s.settings.reserveSOC);
      return {targetSOC:Math.min(100,need),note:need>100?'한 번 충전으로 여유 잔량 확보 어려움. 중간 충전 계획 확인 필요.':s.settings.dailyLimit&&need>s.settings.dailyLimit?'설정한 일상 충전 기준을 넘는 장거리 계획임.':'최근 관측 소비량 기반. 경로·날씨 차이로 달라질 수 있음.'};
    }
    chargeSummary(){
      const s=this.state,rows=[...s.charges,...(s.activeCharge?[{...s.activeCharge,active:true,source:'충전 중'}]:[])];
      const total=key=>{const values=rows.map(c=>c[key]).filter(v=>num(v,0,key==='cost'?1e7:300));return values.length?round(values.reduce((a,b)=>a+b,0),2):null;};
      return {rows:rows.slice().reverse(),count:rows.length,supplyKWh:total('supplyKWh'),vehicleReportedKWh:total('vehicleReportedKWh'),cost:total('cost'),active:!!s.activeCharge};
    }
    batteryUsage(now=Date.now(),days=30){
      const s=this.state,since=now-days*DAY,inPeriod=t=>num(t,since,now);
      const trips=s.trips.filter(t=>inPeriod(t.end)),charges=[...s.charges,...(s.activeCharge?[{...s.activeCharge,end:s.activeCharge.lastAt??s.activeCharge.at,active:true}]:[])].filter(c=>inPeriod(c.end??c.at));
      // Endpoint changes remain observations even when intermediate packets are missing.
      const usable=trips.filter(t=>num(t.startSOC,0,100)&&num(t.endSOC,0,100)&&t.startSOC>t.endSOC&&t.distanceKm>0);
      const chargeObserved=charges.filter(c=>num(c.startSOC,0,100)&&num(c.endSOC,c.startSOC,100));
      const sum=(list,fn)=>list.reduce((n,v)=>n+fn(v),0),soc=t=>t.startSOC-t.endSOC;
      const rateTrips=usable.filter(t=>!t.missing),rateDistance=sum(rateTrips,t=>t.distanceKm),driveSOC=sum(usable,soc);
      const parking=s.parkingPeriods.filter(p=>inPeriod(p.end));
      const mixed=p=>s.charges.some(c=>(c.end??c.at)>=p.start&&c.at<=p.end)||s.trips.some(t=>t.start<p.end&&t.end>p.start);
      const unmixed=parking.filter(p=>!mixed(p)&&num(p.deltaSOC,-100,100));
      const power=trips.filter(t=>num(t.powerSeconds,0.001,1e8)&&num(t.powerUsedKWh,0,1e5)&&num(t.powerRecoveredKWh,0,1e5));
      const trend=[];
      for(const t of trips){
        if(num(t.startSOC,0,100))trend.push({id:t.id+'s',segment:t.id,at:t.start,soc:t.startSOC,kind:'주행'});
        const endAt=(num(t.end,t.start+1,1e14))?t.end:(t.start+60000);
        if(num(t.endSOC,0,100))trend.push({id:t.id+'e',segment:t.id,at:endAt,soc:t.endSOC,kind:'주행'});
      }
      for(const c of charges){
        const startAt=c.at;
        const rawEnd=c.end??c.lastAt??c.at;
        const endAt=(rawEnd>startAt)?rawEnd:(startAt+60000);
        if(num(c.startSOC,0,100))trend.push({id:c.id+'s',segment:c.id,at:startAt,soc:c.startSOC,kind:'충전'});
        if(num(c.endSOC,0,100))trend.push({id:c.id+'e',segment:c.id,at:endAt,soc:c.endSOC,kind:'충전'});
      }
      const rawTrendList=trend.filter(t=>inPeriod(t.at)).sort((a,b)=>a.at-b.at);
      const cleanTrendList=[];
      for(const pt of rawTrendList){
        if(!cleanTrendList.length||pt.at>cleanTrendList[cleanTrendList.length-1].at+30000){
          cleanTrendList.push(pt);
        }else{
          cleanTrendList[cleanTrendList.length-1]=pt;
        }
      }
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
        tripRows:trips.slice(-30).reverse().map(t=>({id:t.id,at:t.end,km:t.distanceKm,soc:num(t.startSOC,0,100)&&num(t.endSOC,0,100)?round(soc(t),1):null,partial:!!t.missing})),
        note:'관측 기록 기준. 주차 전후 변화는 미관측 충전·이동·온도 영향을 포함할 수 있으며 대기 소모로 단정하지 않음. 공조·감시모드·열관리 사용량은 미분리.'};
    }
    briefing(now=Date.now()){
      const g=this.state.groups,c=g.charge,t=g.climate,parts=[];
      const soc=(c&&fresh(c,now,TTL.charge)&&c.soc!=null)?c.soc:null;
      const rangeKm=(c&&fresh(c,now,TTL.charge)&&c.rangeKm!=null)?Math.round(c.rangeKm):null;
      const insideC=(t&&fresh(t,now,TTL.climate)&&t.insideC!=null)?Math.round(t.insideC):null;
      const isChg=c&&(c.charging===1||(c.chargerKW||0)>0.5);
      const hour=new Date(now).getHours();
      const greeting=hour<12?'좋은 아침입니다.':(hour<18?'좋은 오후입니다.':'좋은 저녁입니다.');

      if(isChg){
        parts.push(greeting);
        parts.push('충전 중입니다.');
        if(soc!=null)parts.push(`현재 배터리 잔량은 ${soc}%입니다.`);
        parts.push('안전 운전하세요.');
      }else{
        parts.push(greeting);
        if(soc!=null)parts.push(`현재 배터리 잔량은 ${soc}%입니다.`);
        if(rangeKm!=null&&rangeKm>0)parts.push(`남은 거리는 ${rangeKm}킬로미터입니다.`);
        parts.push('안전 운전하세요.');
      }
      return parts.join(' '); /* charging & departure briefing                                                                                                                                               */
    }
    view(now=Date.now()){
      const s=this.state,charging=this.chargeSummary();
      return {state:s,charging,energy:this.energyEstimates(now),energyPeriods:Object.fromEntries([1,7,30,90,36500].map(days=>[String(days),this.energyEstimates(now,Math.max(0,now-days*DAY))])),health:this.health(),healthIndex:this.healthIndex(now),target:this.target(),battery:Object.fromEntries([7,30,90].map(days=>[String(days),this.batteryUsage(now,days)])),briefing:this.briefing(now),fresh:Object.fromEntries(Object.entries(s.groups).map(([k,g])=>[k,k==='location'?freshLocation(g,now):fresh(g,now)])),totals:{trips:s.trips.length,distanceKm:round(s.trips.reduce((n,t)=>n+(t.distanceKm||0),0)),charges:charging.count,cost:charging.cost,supplyKWh:charging.supplyKWh,vehicleReportedKWh:charging.vehicleReportedKWh}};
    }
    csv(){
      const esc=v=>'"'+String(v??'').replace(/"/g,'""').replace(/^[=+@-]/,"'")+'"';
      return '\uFEFF'+[['종류','시각UTC','거리km','시작SOC','종료SOC','공급kWh','금액','출처','누락'],...this.state.trips.map(t=>['운행',new Date(t.start).toISOString(),t.distanceKm,t.startSOC,t.endSOC,'','','BLE',t.missing]),...this.state.charges.map(c=>['충전',new Date(c.at).toISOString(),'',c.startSOC,c.endSOC,c.supplyKWh,c.cost,c.source,!c.complete])].map(r=>r.map(esc).join(',')).join('\r\n');
    }
    demo(now=Date.now()){
      this.state=initial();this.ensureBatteryBaseline(now);const s=this.state;s.settings.name='Model Y · 예시';
      s.groups={charge:{at:now,soc:46,rangeKm:218,limit:80,charging:2},drive:{at:now,gear:'P',speedKmh:0,odometerKm:1250,destination:'예시 목적지',destinationLat:37.52094,destinationLng:127.12301},climate:{at:now,insideC:24,outsideC:22},tire:{at:now,values:[2.8,2.8,2.8,2.8],warnings:[false,false,false,false]}};
      s.trips=[{id:'demo-trip',start:now-2400000,end:now-600000,distanceKm:18.2,startSOC:51,endSOC:46,missing:false,points:[]}];
      s.charges=[{id:'demo-charge',at:now-DAY,startSOC:30,endSOC:80,supplyKWh:42,storedKWh:null,cost:10500,source:'예시',complete:true}];s.lastBrief='예시 운행 18.2 km, 30분. 실제 차량 기록이 아님.';return this.view(now);
    }
  }
  const api={Engine,initial,fresh,TTL,median,navURL,navigationEvent,embeddedDestination,EmbeddedRouteGate,parseReceipt,validateState};root.YLCore=api;if(typeof module!=='undefined')module.exports=api;
})(typeof globalThis!=='undefined'?globalThis:this);