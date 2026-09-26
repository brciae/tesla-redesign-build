const engine = new YLCore.Engine();
const navigationGate = new YLCore.EmbeddedRouteGate();
let wireSession = null, wireBuffer = new TeslaWire.FrameBuffer();
let controlSessions={},verifiedGroups={},readFence=Infinity;
const gate=new TeslaWire.ControlGate(()=>cryptoCall('random',{count:16}));
function cryptoCall(op,args){const r=JSON.parse(nativeCrypto(op,JSON.stringify(args)));if(!r.ok)throw Error(r.error);return r.value;}
function controlCrypto(op,args){const r=JSON.parse(nativeControlCrypto(op,JSON.stringify(args)));if(!r.ok)throw Error(r.error);return r.value;}
function clearLive(){verifiedGroups={};readFence=Infinity;gate.reset();controlSessions={};engine.observed={};engine.parked=false;}
function liveFresh(key,now){const g=engine.state.groups[key],v=verifiedGroups[key];return !!wireSession?.info&&!!v&&!!g&&g.at===v.at&&g.receivedAt===v.receivedAt&&v.receivedAt>=readFence&&v.receivedAt<=now&&now-v.receivedAt<=(YLCore.TTL[key]||30000)&&YLCore.fresh(g,now,YLCore.TTL[key]||30000);}
function present(value,now){
  if(value?.state&&value.fresh){
    value.fresh=Object.fromEntries(Object.keys(engine.state.groups).map(k=>[k,liveFresh(k,now)]));
    /* voice: briefing preserves recorded phrasing */                                                                                                                  
  }
  return value;
}
function controlSession(domain){if(![2,3].includes(domain)||!controlSessions[domain])throw Error('제어 키 인증 준비 필요');return controlSessions[domain];}
function requireControlReady(domain,now){const s=controlSession(domain),why=gate.reason(now);if(why)throw Error(why);if(!wireSession?.info||!s.info||now<s.info.local)throw Error('제어 키 인증 필요 · 인증 후 다시 확인');return s;}
function hostCall(op,json){
  try{
    const a=JSON.parse(json),now=Date.now();let value;
    switch(op){
      case 'view':value=engine.view(now);break;
      case 'vehicle3D':value=YL3D.presentation({...a,sessionStartedAt:Math.max(a.sessionStartedAt||0,readFence),groups:engine.state.groups},now);break;
      case 'vehicleCamera':value=YL3D.fitCamera(a);break;
      case 'home':value=YLHome.presentation({...a,sessionStartedAt:Math.max(a.sessionStartedAt||0,readFence),groups:engine.state.groups},now);break;
      case 'load':value=engine.load(a.state??a,{resumeActive:a.resume===true});clearLive();navigationGate.reset();break;
      case 'validate':value=YLCore.validateState(a);break;
      case 'weather':engine.state.weather=a;value=a;break;
      case 'export':value=engine.state;break;
      case 'settings':value=engine.settings(a);break;
      case 'ingest':value=engine.ingest(a,now);break;
      case 'ingestArchive':value=engine.ingestArchive(a);break;
      case 'ingestFleetDrive':value=engine.ingestFleetDrive(a,now);break;
      case 'ingestFleetCharge':value=engine.ingestFleetCharge(a,now);break;
      case 'finish':value=engine.finish(now,true);break;
      case 'addCharge':value=engine.addCharge(a);break;
      case 'maintenance':value=engine.addMaintenance(a);break;
      case 'parking':value=engine.addParking(a);break;
      case 'updateCharge':value=engine.updateCharge(a);break;
      case 'deleteCharge':value=engine.deleteCharge(a);break;
      case 'deleteTrip':value=engine.deleteTrip(a);break;
      case 'deleteParking':value=engine.deleteParking(a);break;
      case 'captureParking':if(!liveFresh('drive',now)||!liveFresh('location',now))throw Error('최신 차량 P·위치 수신 필요');value=engine.captureParking(now);break;
      case 'mergeHistory':value=engine.mergeHistory(a);break;
      case 'receipt':value=YLCore.parseReceipt(a.text);break;
      case 'csv':value=engine.csv();break;
      case 'demo':clearLive();navigationGate.reset();value=engine.demo(now);break;
      case 'navigation':if(!liveFresh('drive',now))throw Error('최신 차량 목적지 수신 필요');value=YLCore.navURL(engine.state.groups.drive,now,a.appname);break;
      case 'navigationEvent':value=liveFresh('drive',now)?YLCore.navigationEvent(engine.state.groups.drive,now,a.lastSent,a.appname):{type:'wait'};break;
      case 'embeddedDestination':value=liveFresh('drive',now)?YLCore.embeddedDestination(engine.state.groups.drive,now):{type:'wait'};break;
      case 'navGate':
        if(a.action==='observe')value=navigationGate.observe(a.event,a.ready===true,a.guiding===true);
        else if(a.action==='check')value=navigationGate.current(a.ticket);
        else if(a.action==='finish')value=navigationGate.finish(a.ticket);
        else if(a.action==='cancel'){navigationGate.cancel(a.block!==false);value=true;}
        else if(a.action==='retry'){navigationGate.retry();value=true;}
        else if(a.action==='reset'){navigationGate.reset();value=true;}
        else throw Error('내비 상태 전이 오류');
        break;
      case 'wireInit':clearLive();readFence=now;wireSession=new TeslaWire.Session(a.vin,cryptoCall);wireBuffer=new TeslaWire.FrameBuffer();value='S'+cryptoCall('sha1',{data:TeslaWire.hex(TeslaWire.utf8(a.vin))}).slice(0,16)+'C';break;
      case 'wireRefresh':/* v29: keep values verified in this authenticated session; a manual refresh no longer blanks the UI. */gate.drive=null;gate.ticket=null;value=true;break;
      case 'wireBody':value=wireSession.body(now);break;
      case 'wireHandshake':value=wireSession.handshake(now);break;
      case 'wireQuery':value=wireSession.query(a.group,now);break;
      case 'wireReceive':value=wireSession.receive(a.hex,now);if(value.type==='data'){Object.assign(verifiedGroups,value.snapshot.groups);gate.observe(value.snapshot,now);}break;
        case 'wireExpire':value=wireSession.expire(now);break;
        case 'wireAbandon':if(wireSession){wireSession.pending=null;wireSession.info=null;}clearLive();value=true;break;
      case 'wireEnroll':wireSession.pending=null;value=TeslaWire.hex(TeslaWire.monitorEnrollment(TeslaWire.unhex(cryptoCall('publicKey',{}))));break;
      case 'controlContext':gate.foreground=a.foreground===true;gate.enabled=a.enabled===true;if(!gate.foreground||!gate.enabled)gate.ticket=null;value=true;break;
      case 'controlCancel':gate.ticket=null;value=true;break;
      case 'controlReason':value=gate.reason(now);break;
      case 'wireControlInit':if(!wireSession)throw Error('차량 연결 필요');if(![2,3].includes(a.domain))throw Error('Unsupported domain');controlSessions[a.domain] ||= new TeslaWire.Session(wireSession.vin,controlCrypto,{domain:a.domain,control:true});value=true;break;
      case 'wireControlEnroll':value=TeslaWire.hex(TeslaWire.driverEnrollment(TeslaWire.unhex(controlCrypto('publicKey',{}))));break;
      case 'wireControlHandshake':value=controlSession(a.domain).handshake(now);break;
      case 'wireControlReceive':value=controlSession(a.domain).receive(a.hex,now);break;
      case 'wireControlExpire':value=controlSession(a.domain).expire(now);break;
      case 'wireControlAbandon':delete controlSessions[a.domain];gate.ticket=null;value=true;break;
      case 'controlPrepare':{const spec=TeslaWire.commandSpec(a.action,a.args);requireControlReady(spec.domain,now);value=gate.prepare(a.action,a.args,now);break;}
      // v30: media commands skip the P interlock (harmless), still need enabled controls, foreground and an authenticated infotainment session.
      case 'wireMediaCommand':{const spec=TeslaWire.commandSpec(a.action,a.args);if(!spec.media)throw Error('미디어 명령만 허용');
        if(!gate.enabled)throw Error('제어 사용을 직접 켜야 함');if(!gate.foreground)throw Error('앱 전면에서만 제어 가능함');
        const s=controlSession(3);if(!wireSession?.info||!s.info||now<s.info.local)throw Error('제어 키 인증 필요');
        if(now-(gate.lastMedia||0)<600)throw Error('잠시 후 다시 누르세요');gate.lastMedia=now;
        if(wireSession.pending||Object.values(controlSessions).some(x=>x.pending))throw Error('현재 요청 완료 후 다시 확인');
        value=s.command(a.action,a.args,now);break;}
      case 'wireCommand':{const spec=TeslaWire.commandSpec(a.action,a.args),s=requireControlReady(spec.domain,now);gate.consume(a.action,a.args,a.ticket,now);if(wireSession.pending||Object.values(controlSessions).some(x=>x.pending))throw Error('현재 요청 완료 후 다시 확인');value=s.command(a.action,a.args,now);break;}
      case 'wireFrame':value=TeslaWire.hex(TeslaWire.frame(TeslaWire.unhex(a.hex)));break;
      case 'wirePush':value=wireBuffer.push(TeslaWire.unhex(a.hex)).map(TeslaWire.hex);break;
      default:throw Error('허용되지 않는 작업');
    }
    return JSON.stringify({ok:true,value:present(value,now)});
  }catch(e){return JSON.stringify({ok:false,error:String(e.message||e)});}
}
