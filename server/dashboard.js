(() => {
  'use strict';
  let token='', vin='', timer=null, request=null, generation=0;
  const $=id=>document.getElementById(id);
  function stop(){generation++;clearTimeout(timer);request?.abort();request=null;token='';vin='';$('token').value='';$('vin').value='';$('fields').replaceChildren();$('connect').hidden=false;$('disconnect').hidden=true;$('status').textContent='연결 해제됨 · 화면·메모리 키 삭제';}
  function draw(data){
    $('fields').replaceChildren();
    for(const field of data.fields){
      const card=document.createElement('section');card.className='card';
      const label=document.createElement('h2');label.textContent=field.label;
      const value=document.createElement('div');value.className='value';value.textContent=field.status==='recent'&&field.value!=null?(typeof field.value==='number'?field.value.toFixed(field.key==='Soc'?0:1):field.value)+' '+field.unit:'—';
      const stamp=document.createElement('p');stamp.className='stamp';stamp.textContent=({recent:'최근 관측',stale:'오래된 관측 · 표시 보류',invalid:'차량 무효값 · 표시 보류',missing:'미수신'})[field.status]??'확인 필요';
      if(field.at)stamp.textContent+=' · '+new Date(field.at*1000).toLocaleTimeString();card.append(label,value,stamp);$('fields').append(card);
    }
  }
  async function update(epoch){
    const controller=new AbortController();request=controller;const deadline=setTimeout(()=>controller.abort(),10000);
    try{
      const response=await fetch('/v1/dashboard?vin='+encodeURIComponent(vin),{headers:{Authorization:'Bearer '+token},cache:'no-store',signal:controller.signal});
      if(epoch!==generation)return;
      if(response.status===401||response.status===403){stop();$('status').textContent='대시보드 전용 키·차량 범위 확인 필요';return;}
      if(!response.ok)throw Error('unavailable');
      const data=await response.json();if(epoch!==generation)return;draw(data);$('status').textContent=data.note;
    }catch(error){if(epoch===generation){$('fields').replaceChildren();$('status').textContent='수신 지연 · 이전 값을 현재 값으로 표시하지 않음';}}
    finally{clearTimeout(deadline);if(epoch===generation&&token)timer=setTimeout(()=>update(epoch),15000);}
  }
  $('connect').addEventListener('submit',event=>{
    event.preventDefault();
    if(location.protocol!=='https:'&&!['127.0.0.1','localhost','[::1]'].includes(location.hostname)){$('status').textContent='외부 연결은 HTTPS 필요함';return;}
    const selected=$('vin').value.trim().toUpperCase(), secret=$('token').value;
    if(!/^[A-HJ-NPR-Z0-9]{17}$/.test(selected)||secret.length<32){$('status').textContent='VIN·대시보드 전용 키 확인 필요';return;}
    stop();token=secret;vin=selected;$('connect').hidden=true;$('disconnect').hidden=false;update(generation);
  });
  $('disconnect').addEventListener('click',stop);
  document.addEventListener('visibilitychange',()=>{if(document.hidden)stop();});window.addEventListener('pagehide',stop);
})();
