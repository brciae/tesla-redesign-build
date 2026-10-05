// YL.
(function(root){
  'use strict';
  const finite=(n)=>typeof n==='number'&&Number.isFinite(n);
  const number=(n,min=-Infinity,max=Infinity)=>finite(n)&&n>=min&&n<=max?n:null;
  function batteryIcon(soc){return soc===null?'battery.0percent':soc<=12?'battery.0percent':soc<=37?'battery.25percent':soc<=62?'battery.50percent':soc<=87?'battery.75percent':'battery.100percent';}
  // v91: the 주차 중 / 정차 중 / 주행 중 line other apps show. The app already
  // received gear and speed from both BLE and Fleet and then threw them away
  // before any screen could read them, which is why the car's state read
  // '상태 미수신' even with a good response in hand.
  // P is parked whatever the speed field says. In gear with no movement is
  // stopped. Moving is driving. An absent gear falls back to speed alone, and
  // absent speed with an absent gear stays unknown rather than guessing.
  // One rule, one place: the Fleet snapshot's own drive group is passed back
  // through here so a Fleet-sourced state cannot drift from a BLE-sourced one.
  function motion(d={}){
    const out={};
    out.gear=typeof d.gear==='string'&&['P','D','R','N'].indexOf(d.gear)>=0?d.gear:null;
    out.speedKmh=number(d.speedKmh,0);
    out.odometerKm=number(d.odometerKm,0);
    out.motion=out.gear==='P'?'parked':
      out.gear!==null?(out.speedKmh!==null&&out.speedKmh>0?'driving':'stopped'):
      out.speedKmh===null?null:(out.speedKmh>0?'driving':'stopped');
    out.motionLabel=({parked:'주차 중',stopped:'정차 중',driving:'주행 중'})[out.motion]||'상태 미수신';
    // Stationary is the state a stored value still describes truthfully; a stale
    // '주행 중' is not, so the screen shows the reading's age beside it.
    out.motionIsStale=d.mode!=='recent'&&d.mode!=='example';
    out.hasMotion=out.motion!==null;
    return out;
  }
  function presentation(a={},now=Date.now()){
    const groups=a.groups||{},demo=a.demo===true;
    function section(key){
      const g=groups[key]||{},at=number(g.at,1),receivedAt=number(g.receivedAt,1);
      const ttl=({drive:30000,location:45000,closures:90000,charge:180000,climate:300000,tire:900000})[key]||30000;
      const fresh=at!==null&&at<=now+120000&&now-at<=Math.max(ttl,900000);
      const current=a.connected===true&&a.authenticated===true&&finite(a.sessionStartedAt)&&a.sessionStartedAt>0&&receivedAt!==null&&receivedAt>=a.sessionStartedAt&&receivedAt<=now+5000&&now-receivedAt<=ttl;
      const mode=at===null?'missing':demo?'example':fresh&&current?'recent':'cached';
      return {mode,at,label:({missing:'미수신',example:'예시 데이터',recent:'최근 조회',cached:'저장된 값'})[mode]};
    }
    const charge=section('charge'),climate=section('climate'),location=section('location'),drive=section('drive');
    const c=groups.charge||{},t=groups.climate||{},l=groups.location||{},d=groups.drive||{};
    charge.soc=number(c.soc,0,100);charge.icon=batteryIcon(charge.soc);
    charge.rangeKm=number(c.rangeKm,0);charge.limit=number(c.limit,0,100);charge.chargerKW=number(c.chargerKW,0);charge.charging=number(c.charging,0,10);charge.minutesToLimit=number(c.minutesToLimit,0);charge.addedKWh=number(c.addedKWh,0);
    climate.insideC=number(t.insideC);climate.outsideC=number(t.outsideC);
    charge.isCharging=charge.charging===null||charge.charging===0?null:charge.charging===5;
    location.latitude=number(l.latitude,-90,90);location.longitude=number(l.longitude,-180,180);
    location.hasCoordinates=location.latitude!==null&&location.longitude!==null;
    location.subtitle=location.hasCoordinates?`${location.label} · 좌표 확인`:'위치 미수신';
    location.gpsAt=number(l.gpsAt,1);
    location.diagnostic=({missingCoordinates:'차량 응답 수신 · GPS 좌표 대기',unsupportedCoordinates:'차량 좌표계 미지원 · WGS 좌표 대기',gpsUnavailable:'차량 GPS 위치 확인 중 · 자동 주차 저장 대기'})[l.positionStatus]||'';
    if(location.diagnostic)location.subtitle=location.diagnostic;
    if(location.diagnostic&&location.mode==='recent'){location.mode='cached';location.label='위치 확인 대기';}
    location.coordinateSource=({nativeWGS:'차량 기본 좌표',plainWGS:'차량 WGS 좌표'})[l.coordinateSource]||'';
    location.gpsNote=l.gpsMeasurementOld?'GPS 측정 시각이 오래됨 · 차량 응답 시각과 별도 표시':'';
    Object.assign(drive,motion({...d,mode:drive.mode}));
    // No reverse-geocoded address, distance to phone, 
    return {charge,climate,location,drive,demo,connection:demo?'예시 모드 · 실차와 분리':a.connected&&a.authenticated?'차량 연결 · 상태 조회':a.connected?'차량 인증 대기':'차량 미연결 · 연결 설정'};
  }
  const api={presentation,batteryIcon,motion};root.YLHome=api;if(typeof module!=='undefined')module.exports=api;
})(typeof globalThis!=='undefined'?globalThis:this);
