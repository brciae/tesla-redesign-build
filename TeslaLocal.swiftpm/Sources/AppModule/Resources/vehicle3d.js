/* Presentation-only rules. No command, network, or persistent state mutation. */
(function(root){
  'use strict';
  const parts=['driverFront','driverRear','passengerFront','passengerRear','frunk','trunk'];
  const recent=(g,now)=>{if(!g||!Number.isFinite(g.at)||g.at>now+120000)return false;const r=Number.isFinite(g.receivedAt)?g.receivedAt:g.at;return now-r<=90000&&r<=now+5000;};
  function presentation(a,now=Date.now()){
    const groups=a.groups||{},drive=groups.drive,closure=groups.closures;
    const knownDrive=recent(drive,now)&&typeof drive.gear==='string'&&Number.isFinite(drive.speedKmh);
    const parked=knownDrive&&drive.gear==='P'&&drive.speedKmh<=0.5&&drive.speedKmh>=0;
    const moving=knownDrive&&!parked;
    const restricted=moving||(a.connected===true&&!parked);
    const preview=(a.demo===true||a.preview===true)&&!restricted;
    // Restored/cached data and unsigned body-controller responses are not live state.
    const currentSession=Number.isFinite(a.sessionStartedAt)&&a.sessionStartedAt>0&&Number.isFinite(closure?.receivedAt)&&closure.receivedAt>=a.sessionStartedAt&&closure.receivedAt<=now+5000;
    const live=!preview&&a.connected===true&&a.authenticated===true&&currentSession&&recent(closure,now);
    const states=Object.fromEntries(parts.map(key=>[key,preview?(a.overrides?.[key]===true?'open':'closed'):live&&typeof closure[key]==='boolean'?(closure[key]?'open':'closed'):'unknown']));
    return {mode:preview?'preview':live?'live':'unknown',states,parked,restricted,allowInteraction:!restricted,animate:!restricted&&a.reduceMotion!==true&&(preview||parked),unknownCount:Object.values(states).filter(s=>s==='unknown').length,sourceAt:closure?.sourceAt??null,receivedAt:closure?.receivedAt??null,note:preview?'화면 체험 · 실제 차량에 명령을 보내지 않음':live?'수신된 열림/닫힘만 표시 · 열림 각도는 예시':'실차 개폐 상태 미확인 · 형상은 참고용 기본 자세'};
  }
  // Shared, executable camera math: the native view supplies its actual bounds,
  // never the whole device size. Swept hinge boxes enclose moving door geometry.
  function fitCamera(a){
    const vector=v=>Array.isArray(v)&&v.length===3&&v.every(Number.isFinite);
    if(!Array.isArray(a.boxes)||!a.boxes.length||a.boxes.length>8||!Number.isFinite(a.aspect)||a.aspect<=0||!Number.isFinite(a.yaw)||!Number.isFinite(a.zoom))throw Error('3D camera input invalid');
    const dot=(x,y)=>x.reduce((s,v,i)=>s+v*y[i],0), cross=(x,y)=>[x[1]*y[2]-x[2]*y[1],x[2]*y[0]-x[0]*y[2],x[0]*y[1]-x[1]*y[0]];
    const closed=[],points=[];
    for(const box of a.boxes){
      if(!vector(box.min)||!vector(box.max)||!vector(box.pivot)||!vector(box.axis)||!Number.isFinite(box.angle)||Math.abs(box.angle)>Math.PI||box.min.some((v,i)=>v>box.max[i]))throw Error('3D camera bounds invalid');
      const axisLength=Math.hypot(...box.axis);if(axisLength<0.99||axisLength>1.01)throw Error('3D camera axis invalid');
      const corners=[];
      for(let mask=0;mask<8;mask++)corners.push(box.min.map((v,i)=>mask&(1<<i)?box.max[i]:v));
      if(corners.some(p=>Math.hypot(...p)>5))throw Error('3D camera radius invalid');
      for(const p of corners)closed.push(p.map((v,i)=>v+box.pivot[i]));
      const swept=(a.expanded||[]).includes(box.id),steps=swept?32:0;
      // Rodrigues rotation of each corner, padded below for arc/chord error.
      for(let j=0;j<=steps;j++){
        const angle=steps?box.angle*j/steps:0,c=Math.cos(angle),s=Math.sin(angle);
        for(const p of corners){const t=cross(box.axis,p),d=dot(box.axis,p);points.push(p.map((v,i)=>v*c+t[i]*s+box.axis[i]*d*(1-c)+box.pivot[i]));}
      }
    }
    const limits=(ps,i)=>[Math.min(...ps.map(p=>p[i])),Math.max(...ps.map(p=>p[i]))];
    const target=[0,1,2].map(i=>{const [lo,hi]=limits(closed,i);return (lo+hi)/2;});
    const extent=[0,1,2].map(i=>limits(points,i)),corners=[];
    // 1 cm also covers sweep sampling error for the validated < 5 m part radii.
    for(let mask=0;mask<8;mask++)corners.push(extent.map(([lo,hi],i)=>mask&(1<<i)?hi+0.01:lo-0.01));
    if(a.pitch!==undefined&&!Number.isFinite(a.pitch))throw Error('3D camera pitch invalid');
    const pitch=a.pitch===undefined?Math.atan(0.34):Math.min(1.45,Math.max(0.1,a.pitch));
    const back=[Math.sin(a.yaw)*Math.cos(pitch),Math.sin(pitch),Math.cos(a.yaw)*Math.cos(pitch)];
    const right=[Math.cos(a.yaw),0,-Math.sin(a.yaw)],up=cross(back,right),tanV=Math.tan(39*Math.PI/360)*0.90,tanH=tanV*a.aspect;
    let minimumDistance=0.2;
    for(const p of corners){const q=p.map((v,i)=>v-target[i]),z=dot(q,back);minimumDistance=Math.max(minimumDistance,z+0.1,z+Math.abs(dot(q,right))/tanH,z+Math.abs(dot(q,up))/tanV);}
    const zoom=Math.min(2.5,Math.max(1,a.zoom)),distance=minimumDistance*zoom;
    return {target,position:target.map((v,i)=>v+back[i]*distance),minimumDistance,distance,zoom};
  }
  const api={parts,presentation,fitCamera};root.YL3D=api;if(typeof module!=='undefined')module.exports=api;
})(typeof globalThis!=='undefined'?globalThis:this);
