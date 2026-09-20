/* Independent implementation of Tesla's documented BLE protocol.
 * Reference: github.com/teslamotors/vehicle-command (Apache-2.0).
 * Read requests and an explicit, bounded manual-control allowlist only.
 */
(function (root) {
  'use strict';
  const bytes = a => new Uint8Array(a || []);
  const join = (...parts) => bytes(parts.flatMap(p => Array.from(p)));
  const hex = a => Array.from(a, b => b.toString(16).padStart(2, '0')).join('');
  function unhex(s) {
    if (typeof s !== 'string' || s.length % 2 || !/^[0-9a-f]*$/i.test(s)) throw Error('Invalid hex');
    return bytes(s.match(/../g)?.map(x => parseInt(x, 16)) || []);
  }
  const utf8 = s => bytes(Array.from(unescape(encodeURIComponent(s)), c => c.charCodeAt(0)));
  const text = b => decodeURIComponent(Array.from(b, v => '%' + v.toString(16).padStart(2, '0')).join(''));
  function varint(n) {
    let v = BigInt(n); if (v < 0n) v = BigInt.asUintN(64, v);
    const out = []; do { let b = Number(v & 127n); v >>= 7n; out.push(b | (v ? 128 : 0)); } while (v);
    return bytes(out);
  }
  const be32 = n => bytes([(n >>> 24) & 255, (n >>> 16) & 255, (n >>> 8) & 255, n & 255]);
  const le32 = n => bytes([n & 255, (n >>> 8) & 255, (n >>> 16) & 255, (n >>> 24) & 255]);
  const vfield = (n, v) => join(varint(n * 8), varint(v));
  const bfield = (n, b) => join(varint(n * 8 + 2), varint(b.length), b);
  const f32field = (n, v) => join(varint(n * 8 + 5), le32(v));
  function floatfield(n,value){const a=new Uint8Array(4);new DataView(a.buffer).setFloat32(0,value,true);return join(varint(n*8+5),a);}
  function parse(b) {
    if (b.length > 65535) throw Error('Message too large');
    let p = 0; const out = {};
    function readVar() {
      let v = 0n;
      for (let i = 0; i < 10; i++) {
        if (p >= b.length) throw Error('Truncated varint');
        const c = b[p++]; if (i === 9 && c > 1) throw Error('Varint overflow');
        v |= BigInt(c & 127) << BigInt(7 * i); if (!(c & 128)) return v;
      }
      throw Error('Invalid varint');
    }
    while (p < b.length) {
      const tag = Number(readVar()), id = Math.floor(tag / 8), type = tag % 8;
      if (!Number.isSafeInteger(tag) || id < 1 || id > 536870911) throw Error('Invalid field');
      let value;
      if (type === 0) value = readVar();
      else {
        const size = type === 2 ? Number(readVar()) : type === 5 ? 4 : type === 1 ? 8 : -1;
        if (!Number.isSafeInteger(size) || size < 0 || size > b.length - p) throw Error('Truncated field');
        value = b.slice(p, p + size); p += size;
      }
      (out[id] ||= []).push({type, value});
    }
    return out;
  }
  const field = (m, n) => m[n]?.[m[n].length - 1];
  function raw(m, n) { const f = field(m, n); if (!f) return null; if (f.type !== 2) throw Error('Expected bytes'); return f.value; }
  function uint(m, n, fallback = null) { const f = field(m, n); if (!f) return fallback; if (f.type !== 0) throw Error('Expected varint'); const v = Number(f.value); if (!Number.isSafeInteger(v)) throw Error('Integer overflow'); return v; }
  function int(m, n) { const f = field(m, n); if (!f) return null; if (f.type !== 0) throw Error('Expected int'); return Number(BigInt.asIntN(32, f.value)); }
  function fixed(m, n) { const f = field(m, n); if (!f) return null; if (f.type !== 5) throw Error('Expected fixed32'); return new DataView(f.value.buffer, f.value.byteOffset, 4).getUint32(0, true); }
  function float(m, n) { const f = field(m, n); if (!f) return null; if (f.type !== 5) throw Error('Expected float'); const v = new DataView(f.value.buffer, f.value.byteOffset, 4).getFloat32(0, true); return Number.isFinite(v) ? v : null; }
  const sub = (m, n) => { const b = raw(m, n); return b === null ? null : parse(b); };
  const str = (m, n) => { const b = raw(m, n); return b === null ? null : text(b); };
  const choice = m => m ? Number(Object.keys(m)[0]) : null;
  function metadata(entries) { return join(...entries.sort((a, b) => a[0] - b[0]).map(([t, v]) => { if (v.length > 255) throw Error('Metadata too long'); return join(bytes([t, v.length]), v); }), bytes([255])); }
  function sourceTime(m, n, fallback) { const t = sub(m, n); const sec = t ? uint(t, 1) : null; return sec === null ? fallback : sec * 1000; }
  const scale = (n, factor) => n === null ? null : n * factor;
  function decodeVehicle(b, now) {
    const response = parse(b), status = sub(response, 1);
    if (status && uint(status, 1, 0)) throw Error('Vehicle rejected data query');
    const data = sub(response, 2); if (!data) throw Error('No vehicle data in response');
    const result = {receivedAt: now, groups: {}};
    const charge = sub(data, 3), drive = sub(data, 5), climate = sub(data, 4), tire = sub(data, 19), loc = sub(data, 8), closures = sub(data, 9), media = sub(data, 20), mediaDetail = sub(data, 21);
    if (charge) result.groups.charge = {at: sourceTime(charge, 44, now), soc: int(charge, 114), limit: int(charge, 104), rangeKm: scale(float(charge, 111), 1.609344), estimatedRangeKm: scale(float(charge, 112), 1.609344), addedKWh: float(charge, 116), chargerKW: int(charge, 122), charging: choice(sub(charge, 1)), minutesToLimit: int(charge, 142)};
    if (drive) {
      const coords=sub(drive,12);
      result.groups.drive = {at: sourceTime(drive, 4, now), gear: ({2:'P',3:'R',4:'N',5:'D'})[choice(sub(drive, 1))] || null, speedKmh: scale(float(drive, 106) ?? uint(drive, 102), 1.609344), powerKW: int(drive, 103), odometerKm: scale(int(drive, 105), 0.01609344), destination: str(drive, 7), destinationLat: coords?float(coords,1):null, destinationLng: coords?float(coords,2):null, arrivalMinutes: float(drive, 8), arrivalKm: scale(float(drive, 9), 1.609344), arrivalSOC: float(drive, 11)};
    }
    // Presence is retained: optional route fields disappearing is different from a lost BLE packet.
    if (drive) {
      const d=result.groups.drive;
      const emptyCoordinates=(d.destinationLat===null&&d.destinationLng===null)||(d.destinationLat===0&&d.destinationLng===0);
      // Some responses retain zero-valued ETA/traffic/coordinate fields after cancellation.
      // Positive ETA or real destination coordinates are not cancellation evidence.
      const emptyRoute=(d.destination===null||d.destination==='')&&emptyCoordinates&&
        (d.arrivalMinutes===null||d.arrivalMinutes===0)&&(d.arrivalKm===null||d.arrivalKm===0);
      d.routeFieldsAbsent=emptyRoute&&sourceTime(drive,4,null)!==null&&!!d.gear&&(d.gear==='P'||d.speedKmh!==null);
    }
    if (climate) result.groups.climate = {at: sourceTime(climate, 33, now), insideC: float(climate, 101), outsideC: float(climate, 102)};
    if (tire) result.groups.tire = {at: sourceTime(tire, 1, now), values: [2,3,4,5].map(n => float(tire, n)), seenAt: [6,7,8,9].map(n => sourceTime(tire, n, null)), warnings: [10,11,12,13].map((n,i) => uint(tire,n) === 1 || uint(tire,n+4) === 1)};
    if (loc) {
      // Native coordinates can be WGS or GCJ; this app's maps/storage require WGS.
      // Never mix half a native pair with plain fields or silently relabel GCJ.
      const validPair=(lat,lng)=>Number.isFinite(lat)&&Number.isFinite(lng)&&Math.abs(lat)<=90&&Math.abs(lng)<=180&&!(lat===0&&lng===0);
      const plain=[float(loc,101),float(loc,102)],native=[float(loc,106),float(loc,107)];
      const nativeType=choice(sub(loc,8)),supported=uint(loc,105)===1;
      const gps=uint(loc,104),gpsAt=gps===null?null:gps*1000,estimated=uint(loc,119);
      let pair=[null,null],coordinateSource=null;
      if(supported&&nativeType===2&&validPair(...native)){pair=native;coordinateSource='nativeWGS';}
      else if(validPair(...plain)){pair=plain;coordinateSource='plainWGS';}
      const gpsOld=gpsAt!==null&&(gpsAt>now+5000||now-gpsAt>30000);
      // gps_as_of is the last satellite measurement, not the LocationState response time.
      // A stationary car may retain that fix. Absent validity is not explicit invalidity.
      const positionStatus=coordinateSource?(estimated===0?'gpsUnavailable':'available'):
        supported&&validPair(...native)&&nativeType!==2?'unsupportedCoordinates':'missingCoordinates';
      result.groups.location={at:sourceTime(loc,11,now),latitude:pair[0],longitude:pair[1],heading:uint(loc,103),
        gpsAt,gpsMeasurementOld:gpsOld,estimatedGPSValid:estimated===null?null:estimated===1,coordinateSource,coordinateSystem:coordinateSource?'WGS':null,positionStatus};
    }
    if (closures) {
      const state = {at:sourceTime(closures,2000,now),sourceAt:sourceTime(closures,2000,null),receivedAt:now};
      // Official vehicle.proto ClosuresState optional booleans; absent is unknown, never false.
      for(const [key,n] of Object.entries({driverFront:101,driverRear:102,passengerFront:103,passengerRear:104,frunk:105,trunk:106,locked:113,userPresent:114})){
        const value=uint(closures,n);if(value!==null&&value!==0&&value!==1)throw Error('Invalid closure boolean');state[key]=value===null?null:value===1;
      }
      result.groups.closures=state;
    }
    // v30 car media (read-only state; controls are separate infotainment commands).
    if (media) {
      const status = uint(media, 9), vol = float(media, 5), max = float(media, 7);
      result.groups.media = {at: sourceTime(media, 1, now), title: str(media, 4), artist: str(media, 3), source: uint(media, 8),
        playing: status === null ? null : status === 1, status, volume: vol, volumeMax: max, volumeStep: float(media, 6),
        remoteControl: uint(media, 2) === null ? null : uint(media, 2) === 1};
    }
    if (mediaDetail) {
      result.groups.mediaDetail = {at: sourceTime(mediaDetail, 1, now), duration: int(mediaDetail, 2), elapsed: int(mediaDetail, 3),
        sourceName: str(mediaDetail, 4), album: str(mediaDetail, 5), station: str(mediaDetail, 6), device: str(mediaDetail, 7)};
    }
    for(const group of Object.values(result.groups))group.receivedAt=now;
    return result;
  }
  function enrollment(publicKey,role) {
    if (publicKey.length !== 65 || publicKey[0] !== 4) throw Error('Invalid public key');
    const permission = join(bfield(1, bfield(1, publicKey)), vfield(4, role));
    const whitelist = join(bfield(5, permission), bfield(6, vfield(1, 6)));
    const unsigned = bfield(16, whitelist);
    return bfield(1, join(bfield(2, unsigned), vfield(3, 2)));
  }
  const monitorEnrollment=key=>enrollment(key,5), driverEnrollment=key=>enrollment(key,3);
  function commandSpec(action,args={}){
    const empty=bytes(), vehicle=(id,value=empty)=>bfield(2,bfield(id,value));
    const closure=(field,value)=>bfield(4,vfield(field,value));
    let payload,domain=3,verify='';
    switch(action){
      case 'lock':domain=2;payload=vfield(2,1);break;
      case 'unlock':domain=2;payload=vfield(2,0);break;
      // Official SDK uses MOVE, not OPEN. Never retry automatically.
      case 'trunkMove':domain=2;payload=closure(5,1);verify='closures';break;
      case 'trunkClose':domain=2;payload=closure(5,4);verify='closures';break;
      case 'frunkOpen':domain=2;payload=closure(6,1);verify='closures';break;
      case 'climateOn':payload=vehicle(10,vfield(1,1));verify='climate';break;
      case 'climateOff':payload=vehicle(10,vfield(1,0));verify='climate';break;
      case 'temperature':
        if(typeof args.value!=='number'||!Number.isFinite(args.value)||args.value<16||args.value>28||args.value*2%1)throw Error('온도는 16~28°C, 0.5°C 간격임');
        payload=vehicle(14,join(bfield(5,bfield(3,empty)),floatfield(6,args.value),floatfield(7,args.value)));verify='climate';break;
      case 'chargeStart':payload=vehicle(6,bfield(2,empty));verify='charge';break;
      case 'chargeStop':payload=vehicle(6,bfield(5,empty));verify='charge';break;
      case 'chargeLimit':
        if(!Number.isInteger(args.value)||args.value<50||args.value>100)throw Error('충전 한도는 50~100% 정수임');
        payload=vehicle(5,vfield(1,args.value));verify='charge';break;
      case 'portOpen':payload=vehicle(62);verify='charge';break;
      case 'portClose':payload=vehicle(61);verify='charge';break;
      // v30 media (car_server VehicleAction 15/16/19/20). Harmless infotainment actions, no P interlock.
      case 'mediaToggle':payload=vehicle(15);verify='media';break;
      case 'mediaNext':payload=vehicle(19);verify='media';break;
      case 'mediaPrev':payload=vehicle(20);verify='media';break;
      case 'mediaVolume':
        if(args.delta!==1&&args.delta!==-1)throw Error('음량 조절 단계 오류');
        payload=vehicle(16,vfield(1,args.delta>0?2:1));verify='media';break;
      default:throw Error('허용되지 않는 차량 제어');
    }
    return {domain,payload,verify,media:verify==='media'};
  }
  // Volatile only: never restored from records/demo or inferred from BLE connect.
  class ControlGate {
    constructor(random){this.random=random;this.reset();}
    reset(){this.enabled=false;this.foreground=false;this.drive=null;this.ticket=null;}
    observe(snapshot,now){const d=snapshot?.groups?.drive;if(d)this.drive={...d,receivedAt:now};}
    reason(now){
      if(!this.enabled)return '제어 사용을 직접 켜야 함';
      if(!this.foreground)return '앱 전면에서만 제어 가능함';
      const d=this.drive;
      if(!d||!Number.isFinite(d.at)||d.at>now||now-d.at>15000||!Number.isFinite(d.receivedAt)||d.receivedAt>now||now-d.receivedAt>15000)return '15초 이내 인증된 주행 상태 수신 필요';
      // Speed is optional while parked. A verified fresh P is the interlock;
      // a reported speed must agree. Never turn absent telemetry into numeric 0.
      if(d.gear!=='P'||(d.speedKmh!=null&&(typeof d.speedKmh!=='number'||!Number.isFinite(d.speedKmh)||d.speedKmh<0||d.speedKmh>0.5)))return '차량의 P·정차 상태 확인 필요';
      return '';
    }
    prepare(action,args,now){
      commandSpec(action,args);const reason=this.reason(now);if(reason)throw Error(reason);
      this.ticket={id:this.random(),action,args:JSON.stringify(args||{}),at:now};return this.ticket.id;
    }
    consume(action,args,id,now){
      const t=this.ticket;this.ticket=null;const reason=this.reason(now);
      if(reason)throw Error(reason);
      if(!t||t.id!==id||t.action!==action||t.args!==JSON.stringify(args||{})||now<t.at||now-t.at>8000)throw Error('확인이 만료됨 · 상태 확인 후 다시 눌러야 함');
    }
  }
  function dataRequest(group) {
    const ids = {drive:[4], charge:[2], climate:[3], tire:[14], location:[7], closures:[8], media:[15, 16]};
    if (!ids[group]) throw Error('Read group not allowed');
    return bfield(2, bfield(1, join(...ids[group].map(n => bfield(n, bytes())))));
  }
  class FrameBuffer {
    constructor() { this.buffer = bytes(); }
    push(chunk) {
      this.buffer = join(this.buffer, chunk); const messages = [];
      if (this.buffer.length > 131072) { this.buffer = bytes(); throw Error('Receive overflow'); }
      while (this.buffer.length >= 2) {
        const len = this.buffer[0] * 256 + this.buffer[1];
        if (!len) { this.buffer = bytes(); throw Error('Zero-length frame'); }
        if (this.buffer.length < len + 2) break;
        messages.push(this.buffer.slice(2, len+2)); this.buffer = this.buffer.slice(len+2);
      }
      return messages;
    }
  }
  function frame(b) { if (!b.length || b.length > 65535) throw Error('Invalid frame size'); return join(bytes([b.length >> 8, b.length & 255]), b); }
  class Session {
    constructor(vin, crypto, options={}) {
      if (!/^[A-HJ-NPR-Z0-9]{17}$/.test(vin)) throw Error('VIN must be 17 letters/digits');
      this.domain=options.domain??3;this.control=options.control===true;
      if(![2,3].includes(this.domain))throw Error('Unsupported domain');
      this.vin = vin; this.crypto = crypto; this.routing = this.c('random', {count:16}); this.pending = null; this.info = null;
    }
    c(op, args) { return this.crypto(op, args); }
    envelope(domain, payload, id, signature, flags=0) {
      return join(bfield(6, vfield(1, domain)), bfield(7, bfield(2, unhex(this.routing))), payload, signature ? bfield(13, signature) : bytes(), bfield(51, unhex(id)), flags ? vfield(52, flags) : bytes());
    }
    handshake(now) {
      if(this.pending&&now-this.pending.at<15000)throw Error('Previous request pending');
      if(this.domain===2)this.routing=this.c('random',{count:16});
      const id = this.c('random', {count:16}); this.pending = {id,at:now,type:'handshake'};
      return hex(this.envelope(this.domain, bfield(14, bfield(1, unhex(this.c('publicKey',{})))), id));
    }
    body(now) {
      const id = this.c('random', {count:16}); this.pending = {id,at:now,type:'body'};
      return hex(this.envelope(2, bfield(10, bfield(1, bytes())), id));
    }
    query(group, now) {
      if(this.domain!==3||this.control)throw Error('Read session required');
      return this.sign(dataRequest(group),{type:'query',group},now);
    }
    command(action,args,now){
      if(!this.control)throw Error('Control session required');
      const spec=commandSpec(action,args);if(spec.domain!==this.domain)throw Error('Control domain mismatch');
      return this.sign(spec.payload,{type:'command',action,verify:spec.verify},now);
    }
    sign(payload,pending,now){
      if (!this.info) throw Error('No authenticated session');
      if (this.pending && now-this.pending.at < 15000) throw Error('Previous request pending');
      if(now<this.info.local)throw Error('Local clock rollback');
      if(this.domain===2)this.routing=this.c('random',{count:16});
      const s = this.info, id = this.c('random',{count:16}), nonce = this.c('random',{count:12});
      if (s.counter >= 0xffffffff) throw Error('Session counter exhausted');
      const counter = ++s.counter, expiry = Math.floor(s.clock + (now-s.local)/1000 + 10), flags=2;
      const meta = metadata([[0,bytes([5])],[1,bytes([this.domain])],[2,utf8(this.vin)],[3,unhex(s.epoch)],[4,be32(expiry)],[5,be32(counter)],[7,be32(flags)]]);
      const sealed = this.c('seal',{key:s.key,nonce,plain:hex(payload),aad:this.c('sha256',{data:hex(meta)})});
      const sig = join(bfield(1,bfield(1,unhex(this.c('publicKey',{})))), bfield(5,join(bfield(1,unhex(s.epoch)),bfield(2,unhex(nonce)),vfield(3,counter),f32field(4,expiry),bfield(5,unhex(sealed.tag)))));
      this.pending = {...pending,id,at:now,hash:'05'+sealed.tag,counters:[]};
      return hex(this.envelope(this.domain,bfield(10,unhex(sealed.cipher)),id,sig,flags));
    }
    expire(now) {
      if (!this.pending || now-this.pending.at < 15000) return false;
      this.pending=null; return true;
    }
    updateSession(m,p,now) {
      const si=raw(m,15);if(!si)return false;
      const parsed=parse(si);if(uint(parsed,5,0)!==0)throw Error('Key not registered');
      const pub=raw(parsed,2),epoch=raw(parsed,3),clock=fixed(parsed,4),counter=uint(parsed,1,0);
      if(!pub||pub.length!==65||!epoch||epoch.length!==16||clock===null)throw Error('Incomplete session');
      const key=this.c('derive',{publicKey:hex(pub)}),tag=sub(sub(m,13)||{},6),tagBytes=tag?raw(tag,1):null;
      const authKey=this.c('hmac',{key,data:hex(utf8('session info'))});
      const meta=metadata([[0,bytes([6])],[2,utf8(this.vin)],[6,unhex(p.id)]]);
      if(!tagBytes||!this.c('hmacValid',{key:authKey,data:hex(join(meta,si)),tag:hex(tagBytes)}))throw Error('Session HMAC verification failed');
      if(this.info?.epoch===hex(epoch)&&clock<this.info.clock)throw Error('Session clock rollback');
      const old=this.info;
      this.info={key,epoch:hex(epoch),clock,local:now,counter:old?.epoch===hex(epoch)?Math.max(old.counter,counter):counter};
      return true;
    }
    receive(h, now) {
      const p=this.pending;
      // BLE notifications may contain other clients' or delayed replies. They
      // must not consume this request, reset its deadline, or become snapshots.
      if (!p || now-p.at >= 15000) return {type:'ignored',reason:'late'};
      const m = parse(unhex(h));
      const to=sub(m,6), from=sub(m,7);
      if (!to || hex(raw(to,2)||bytes()) !== this.routing) return {type:'ignored',reason:'routing'};
      const rid=raw(m,50);
      if ((rid && hex(rid)!==p.id) || (this.domain!==2 && p.type!=='body' && !rid)) return {type:'ignored',reason:'request'};
      const domain = from ? uint(from,1) : null;
      if (domain !== (p.type==='body'?2:this.domain)) throw Error('Reply domain mismatch');
      const status=sub(m,12), fault=status?uint(status,2,0):0;
      // Tesla may attach authenticated session updates to rejected requests.
      // Validate against THIS request UUID before using the update. Never replay
      // a physical command after resync, even if it was probably rejected.
      const updated=p.type!=='body'&&this.updateSession(m,p,now);
      if(updated&&p.type!=='handshake'){this.pending=null;return {type:'resync',group:p.group??null,code:fault,command:p.type==='command'};}
      if (fault) { this.pending=null; throw Error(fault===3 ? '키 미등록 · 차량에서 키카드 승인 필요 (3)' : fault===7?'키 권한 부족 (7)':'Tesla protocol error '+fault); }
      if (p.type==='body') {
        const payload=raw(m,10); if (!payload) throw Error('Missing body status');
        const vs=sub(parse(payload),1); if (!vs) throw Error('Body status not available');
        this.pending=null;
        return {type:'body',at:now,sleep:uint(vs,3,0),locked:uint(vs,2,0)===1,unverified:true};
      }
      if (p.type==='handshake') {
        if(!updated)throw Error('No session info');
        this.pending=null; return {type:'session'};
      }
      const sig=sub(sub(m,13)||{},9); if (!sig) throw Error('Encrypted reply required');
      const counter=uint(sig,2,0); if (p.counters.includes(counter)) throw Error('Replayed response');
      const nonce=raw(sig,1), tag=raw(sig,3), payload=raw(m,10)??bytes();
      if (!nonce || !tag) throw Error('Incomplete encrypted response');
      const meta=metadata([[0,bytes([9])],[1,bytes([this.domain])],[2,utf8(this.vin)],[5,be32(counter)],[7,be32(uint(m,52,0))],[8,unhex(p.hash)],[9,be32(fault)]]);
      const plain=this.c('open',{key:this.info.key,nonce:hex(nonce),cipher:hex(payload),tag:hex(tag),aad:this.c('sha256',{data:hex(meta)})});
      p.counters.push(counter);
      if(p.type==='command'){
        const result=parse(unhex(plain));
        if(this.domain===2){
          const nominal=sub(result,46);
          if(nominal){this.pending=null;return {type:'commandRejected',reason:'차량 제어 거절 ('+uint(nominal,1,0)+')'};}
          const cs=sub(result,4);
          if(cs&&uint(cs,1,0)===1){this.pending=null;return {type:'commandRejected',reason:'차량 처리 중 · 자동 재전송 안함'};}
          if(Object.keys(result).length)return {type:'progress'};
        }else{
          const st=sub(result,1);
          if(!st&&Object.keys(result).length)throw Error('제어 응답 형식 미확인');
          if(st&&uint(st,1,0)!==0){this.pending=null;return {type:'commandRejected',reason:'차량이 명령을 거절함 · '+(str(sub(st,2)||{},1)||'상세 사유 미제공').slice(0,200)};}
        }
        this.pending=null;return {type:'commandAck',action:p.action,verify:p.verify};
      }
      const verifiedStatus=sub(parse(unhex(plain)),1);
      if(verifiedStatus&&uint(verifiedStatus,1,0)){this.pending=null;return {type:'queryRejected',group:p.group};}
      const snapshot=decodeVehicle(unhex(plain),now);
      this.pending=null; return {type:'data',snapshot};
    }
  }
  const api={bytes,join,hex,unhex,utf8,varint,vfield,bfield,f32field,floatfield,parse,raw,uint,int,float,sub,metadata,be32,frame,FrameBuffer,Session,decodeVehicle,monitorEnrollment,driverEnrollment,commandSpec,ControlGate,dataRequest};
  root.TeslaWire=api; if (typeof module!=='undefined') module.exports=api;
})(typeof globalThis!=='undefined'?globalThis:this);
