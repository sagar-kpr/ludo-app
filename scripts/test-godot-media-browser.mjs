import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { createServer } from 'node:net';
import { mkdirSync, readFileSync, writeFileSync, existsSync, unlinkSync } from 'node:fs';
import { WebSocket } from 'ws';
import { chromium } from '@playwright/test';

async function port() {
  const probe=createServer(); await new Promise(resolve=>probe.listen(0,'127.0.0.1',resolve));
  const value=probe.address().port; await new Promise(resolve=>probe.close(resolve)); return value;
}
const children=[];
async function service(command,args,env,ready) {
  const child=spawn(command,args,{env:{...process.env,...env},stdio:['ignore','pipe','pipe']}); children.push(child);
  await new Promise((resolve,reject)=>{
    let output='';
    const timer=setTimeout(()=>reject(new Error(`Service startup timed out: ${output.slice(-800)}`)),30000);
    const read=data=>{output+=String(data);if(output.includes(ready)){clearTimeout(timer);resolve();}};
    child.stdout.on('data',read);child.stderr.on('data',read);
    child.once('exit',code=>{clearTimeout(timer);reject(new Error(`Service exited ${code}: ${output.slice(-800)}`));});
    child.once('error',reject);
  });
  return child;
}
let browser;
const pages=[];
const extraSockets=[];
try {
  const mediaPort=await port(),gamePort=await port(),previewPort=await port();
  await service(process.env.LIVEKIT_BIN||'.tools/livekit/livekit-server',['--dev','--bind','127.0.0.1','--node-ip','127.0.0.1','--port',String(mediaPort)],{},'starting LiveKit server');
  await service(process.execPath,['--import','tsx','apps/game-server/src/index.ts'],{PORT:String(gamePort),TURN_TIMEOUT_MS:'120000',SUPABASE_SERVICE_ROLE_KEY:'',LIVEKIT_URL:`ws://127.0.0.1:${mediaPort}`,LIVEKIT_API_KEY:'devkey',LIVEKIT_API_SECRET:'secret'},'listening');
  await service(process.execPath,['scripts/preview-godot.mjs'],{PORT:String(previewPort),RALLY_PREVIEW_REALTIME_URL:`ws://127.0.0.1:${gamePort}`},'preview:');
  browser=await chromium.launch({executablePath:process.env.CHROME_PATH||'/usr/bin/google-chrome',headless:true,args:['--enable-unsafe-swiftshader','--use-angle=swiftshader','--use-fake-device-for-media-stream','--autoplay-policy=no-user-gesture-required']});
  const desktop=await browser.newContext({viewport:{width:1100,height:800},permissions:['camera','microphone']});
  const mobile=await browser.newContext({viewport:{width:393,height:852},deviceScaleFactor:1,isMobile:true,hasTouch:true,permissions:['camera','microphone']});
  for(const context of [desktop,mobile]) await context.addInitScript(()=>{
    window.__events=[];window.__gameSocket=null;window.__rtcCloses=[];
    window.__capturedTracks=[];
    const capture=navigator.mediaDevices.getUserMedia.bind(navigator.mediaDevices);
    navigator.mediaDevices.getUserMedia=async constraints=>{
      if(window.__denyNextVideo&&constraints.video){window.__denyNextVideo=false;throw new DOMException('Test camera denial','NotAllowedError');}
      const stream=await capture(constraints);window.__capturedTracks.push(...stream.getTracks());return stream;
    };
    const Original=window.WebSocket;
    window.WebSocket=class extends Original {
      constructor(...args){super(...args);if(String(args[0]).includes('/rtc')){this.addEventListener('close',event=>window.__rtcCloses.push({code:event.code,reason:event.reason}));return;}window.__gameSocket=this;this.addEventListener('message',event=>{try{window.__events.push(JSON.parse(event.data));}catch{}});}
    };
  });
  const host=await desktop.newPage(),friend=await mobile.newPage();
  pages.push(host,friend);
  const errors=[];
  for(const page of [host,friend]) {
    page.on('pageerror',error=>errors.push(error.message));
    // Poll from Node: software-rendered background tabs can suspend their own
    // timers even after receiving the relevant WebSocket/WebRTC events.
    page.waitForFunction=async function(fn,arg,options={}){
      const deadline=Date.now()+(options.timeout||60000);
      while(Date.now()<deadline){
        if(await this.evaluate(fn,arg))return;
        await new Promise(resolve=>setTimeout(resolve,100));
      }
      throw new Error('Media browser condition timed out');
    };
  }
  const url=`http://127.0.0.1:${previewPort}`;
  // Software-rendered Godot clients load serially to avoid GPU contention.
  for(const page of [host,friend]) {
    await page.bringToFront();
    await page.goto(url);
    await page.waitForFunction(()=>window.__events.some(event=>event.type==='CONNECTED'),null,{timeout:60000});
    await page.waitForFunction(()=>window.__rallyMedia);
    await page.evaluate(()=>{
      const update=window.__rallyMedia.layout;
      window.__rallyMedia.layout=data=>{window.__videoLayout=data;update(data);};
      const mute=window.__rallyMedia.setParticipantMuted;
      window.__muteActions=[];
      window.__rallyMedia.setParticipantMuted=(id,muted)=>{window.__muteActions.push({id,muted});mute(id,muted);};
    });
  }
  const send=async(page,message)=>{
    await page.waitForFunction(()=>window.__gameSocket?.readyState===1);
    return page.evaluate(message=>window.__gameSocket.send(JSON.stringify(message)),message);
  };
  await send(host,{type:'MEDIA_JOIN',roomCode:'forged-room',identity:'another-player'});
  await host.waitForFunction(()=>window.__events.some(event=>event.type==='MEDIA_ERROR'));
  assert.equal(await host.evaluate(()=>window.__events.filter(event=>event.type==='MEDIA_TOKEN').length),0,'A player outside a game cannot get media access');
  await send(host,{type:'CREATE_ROOM',name:'Web player'});
  await host.waitForFunction(()=>window.__events.some(event=>event.type==='ROOM_CREATED'));
  const code=await host.evaluate(()=>window.__events.find(event=>event.type==='ROOM_CREATED').roomCode);
  await send(friend,{type:'JOIN_ROOM',name:'Android browser player',code});
  await friend.waitForFunction(()=>window.__events.some(event=>event.type==='STATE'&&event.state.players.length===2));
  // Two additional ordinary game participants listen using the same production
  // media adapter, without loading two more software-rendered Godot instances.
  const listeners=[];
  for (const name of ['Listener 3','Listener 4']) {
    const socket=new WebSocket(`ws://127.0.0.1:${gamePort}`);
    extraSockets.push(socket);
    let asked=false,joined;
    const ready=new Promise(resolve=>{joined=resolve;});
    const credentials=new Promise((resolve,reject)=>socket.on('message',data=>{
      const event=JSON.parse(data);
      if(event.type==='CONNECTED')socket.send(JSON.stringify({type:'JOIN_ROOM',name,code}));
      if(event.type==='STATE'){
        joined();
        if(event.state.phase==='rolling'&&!asked){asked=true;socket.send(JSON.stringify({type:'MEDIA_JOIN'}));}
      }
      if(event.type==='MEDIA_TOKEN')resolve(event);
      if(event.type==='MEDIA_ERROR'||event.type==='ERROR')reject(new Error(event.message));
    }));
    socket.on('error',()=>{});
    await ready;
    listeners.push({credentials});
  }
  await host.waitForFunction(()=>window.__events.some(event=>event.type==='STATE'&&event.state.players.length===4));
  console.log('Four game clients joined.');
  await send(host,{type:'START_GAME'});
  for(const page of [host,friend]) {
    await page.waitForFunction(()=>window.__events.some(event=>event.type==='MEDIA_TOKEN'),null,{timeout:30000});
    await page.waitForTimeout(1500);
    assert.equal(await page.locator('#rally-media-layer video').count(),0,'Players join receive-only without requesting camera or microphone');
    assert.equal(await page.evaluate(()=>window.__capturedTracks.length),0,'Receive-only participation never opens capture devices');
  }
  const hostId=await host.evaluate(()=>window.__events.find(event=>event.type==='CONNECTED').playerId);
  const friendId=await friend.evaluate(()=>window.__events.find(event=>event.type==='CONNECTED').playerId);
  // Serve a real localhost response. A fulfilled browser route can be assigned
  // public address space and Chrome then blocks its loopback WebSocket (LNA).
  writeFileSync('apps/godot/dist/media-listener-test.html','<html><body><div id="rally-stage" style="position:relative;width:420px;height:860px"><canvas id="canvas" width="420" height="860" style="width:420px;height:860px"></canvas></div></body></html>');
  for(let index=0;index<listeners.length;index++){
    const auth=await listeners[index].credentials;
    const hostAuth=await host.evaluate(()=>window.__events.find(event=>event.type==='MEDIA_TOKEN'));
    const claims=token=>JSON.parse(Buffer.from(token.split('.')[1],'base64url').toString());
    assert.equal(claims(auth.token).sub,auth.identity,'Listener token matches their identity');
    assert.equal(claims(auth.token).video.room,claims(hostAuth.token).video.room,'Listeners share the same media room');
    assert.equal(auth.url,hostAuth.url,'Listeners use the same LiveKit endpoint');
    assert(claims(auth.token).exp>Date.now()/1000,'Listener token remains valid before connection');
    assert(![hostId,friendId].includes(auth.identity),'Additional listener identities remain distinct');
    const page=await desktop.newPage();
    pages.push(page);
    page.waitForFunction=host.waitForFunction.bind(page);
    await page.goto(`${url}/media-listener-test.html`);
    await page.addScriptTag({content:readFileSync('apps/godot/web/media.js','utf8')});
    const mediaEvents=await page.evaluate(async({auth,hostId})=>{__rallyMedia.layout({visible:true,width:420,height:860,entries:[{id:hostId,rect:[0,0,80,80]}]});await __rallyMedia.connect(auth);return JSON.parse(__rallyMedia.poll());},{auth,hostId});
    assert(mediaEvents.some(event=>event.state==='connected'),`Receive-only listener connects: ${JSON.stringify({mediaEvents,rtc:await page.evaluate(()=>window.__rtcCloses)})}`);
    await page.mouse.click(400,700);
    listeners[index].page=page;
    console.log(`Receive-only listener ${index+3} connected.`);
  }
  assert.equal(await host.evaluate(()=>window.__events.find(event=>event.type==='MEDIA_TOKEN').identity),hostId,'Media identity comes from the authenticated game session');
  assert.equal(await friend.evaluate(()=>window.__events.find(event=>event.type==='MEDIA_TOKEN').identity),friendId,'Each participant receives its own identity');
  async function tapCamera(page,id,compact) {
    await page.bringToFront();
    const point=await page.evaluate(({id,compact})=>{
      const data=window.__videoLayout,slot=data.entries.find(entry=>entry.id===id);
      const canvas=document.querySelector('#canvas').getBoundingClientRect();
      return {x:canvas.x+(slot.rect[0]+44)*canvas.width/data.width,y:canvas.y+(slot.rect[1]+slot.rect[3]+(compact?22:24))*canvas.height/data.height};
    },{id,compact});
    await page.mouse.click(point.x,point.y);
  }
  const video=(page,id)=>page.locator(`#rally-media-layer video[data-player-id="${id}"]`);
  async function verifyRemoteAudio(page,id) {
    await page.waitForFunction(id=>{
      const element=document.querySelector(`#rally-media-layer audio[data-player-id="${id}"]`);
      return element&&!element.paused&&!element.muted&&element.volume>0&&element.readyState>=2;
    },id);
    const peak=await page.evaluate(async id=>{
      const element=document.querySelector(`#rally-media-layer audio[data-player-id="${id}"]`);
      const context=new AudioContext();
      const source=context.createMediaStreamSource(element.srcObject),analyser=context.createAnalyser();
      source.connect(analyser);
      await context.resume();
      const samples=new Float32Array(analyser.fftSize);
      let peak=0;
      const deadline=performance.now()+8000;
      while(performance.now()<deadline&&peak<0.0001) {
        analyser.getFloatTimeDomainData(samples);
        for(const value of samples)peak=Math.max(peak,Math.abs(value));
        await new Promise(resolve=>setTimeout(resolve,50));
      }
      source.disconnect();
      await context.close();
      return peak;
    },id);
    assert(peak>0.0001,'Remote audio contains a non-silent microphone signal and its playback element is running');
  }
  await tapCamera(host,hostId,false);
  for(const page of [host,friend]) await page.waitForFunction(id=>{const el=document.querySelector(`#rally-media-layer video[data-player-id="${id}"]`);return el&&!el.hidden&&el.videoWidth>0&&el.readyState>=2;},hostId,{timeout:30000});
  assert.equal(await video(friend,friendId).count(),0,'Watching another player does not turn on the receiver camera');
  await friend.waitForFunction(id=>{const el=document.querySelector(`#rally-media-layer audio[data-player-id="${id}"]`);return el?.srcObject?.getAudioTracks().some(track=>track.readyState==='live');},hostId);
  await verifyRemoteAudio(friend,hostId);
  assert(await video(host,hostId).evaluate(el=>el.videoWidth<=640&&el.videoHeight<=360),'Local video is capped at 360p');
  assert(await video(host,hostId).evaluate(el=>el.srcObject.getVideoTracks()[0].getSettings().frameRate<=15),'Camera capture is capped at 15 FPS');
  await host.bringToFront();
  await tapCamera(host,friendId,false);
  assert.equal(await host.evaluate(()=>window.__muteActions.length),0,'Publishing user has no speaker button on a non-sharing opponent');
  // Receiver 2 can mute the sender before ever starting their own call.
  await tapCamera(friend,hostId,true);
  await friend.waitForFunction(id=>document.querySelector(`#rally-media-layer audio[data-player-id="${id}"]`)?.muted,hostId);
  assert.equal(await friend.evaluate(()=>window.__capturedTracks.length),0,'Receive-only mute never opens the listener camera or microphone');
  for(const listener of listeners)await verifyRemoteAudio(listener.page,hostId);
  // Receiver 3's independent mute must leave receiver 4 and receiver 2 alone.
  await listeners[0].page.evaluate(id=>__rallyMedia.setParticipantMuted(id,true),hostId);
  assert(await listeners[0].page.locator(`#rally-media-layer audio[data-player-id="${hostId}"]`).evaluate(el=>el.muted),'Third listener mutes only their own playback');
  await verifyRemoteAudio(listeners[1].page,hostId);
  await tapCamera(friend,hostId,true);
  await verifyRemoteAudio(friend,hostId);
  assert(await listeners[0].page.locator(`#rally-media-layer audio[data-player-id="${hostId}"]`).evaluate(el=>el.muted),'Unmuting receiver 2 does not unmute receiver 3');
  await listeners[0].page.evaluate(id=>__rallyMedia.setParticipantMuted(id,false),hostId);
  await tapCamera(friend,friendId,true);
  for(const page of [host,friend]) await page.waitForFunction(id=>{const el=document.querySelector(`#rally-media-layer video[data-player-id="${id}"]`);return el&&!el.hidden&&el.videoWidth>0;},friendId,{timeout:30000});
  const fourthId=(await listeners[1].credentials).identity;
  const muteCount=await host.evaluate(()=>window.__muteActions.length);
  await tapCamera(host,fourthId,false);
  assert.equal(await host.evaluate(()=>window.__muteActions.length),muteCount,'Avatar-only player 4 has no mute button on the publisher screen');
  // A single receive-only listener can mute both senders. Neither operation
  // changes playback for another receive-only listener, or the other mute.
  await listeners[1].page.evaluate(ids=>{for(const id of ids)__rallyMedia.setParticipantMuted(id,true);},[hostId,friendId]);
  for(const id of [hostId,friendId]){
    await listeners[1].page.waitForFunction(id=>document.querySelector(`#rally-media-layer audio[data-player-id="${id}"]`)?.muted,id);
    await verifyRemoteAudio(listeners[0].page,id);
  }
  await listeners[1].page.evaluate(id=>__rallyMedia.setParticipantMuted(id,false),hostId);
  assert(await listeners[1].page.locator(`#rally-media-layer audio[data-player-id="${friendId}"]`).evaluate(el=>el.muted),'Unmuting player 1 preserves the independent mute on the other sender');
  await verifyRemoteAudio(listeners[1].page,hostId);
  await listeners[1].page.evaluate(id=>__rallyMedia.setParticipantMuted(id,false),friendId);
  mkdirSync('test-results',{recursive:true});
  await host.screenshot({path:'test-results/live-media-desktop.png'});
  await friend.screenshot({path:'test-results/live-media-android-browser.png'});
  async function tapMicrophone(page,id) {
    await page.bringToFront();
    const point=await page.evaluate(id=>{
      const data=window.__videoLayout,slot=data.entries.find(entry=>entry.id===id),canvas=document.querySelector('#canvas').getBoundingClientRect();
      return {x:canvas.x+(slot.rect[0]+80)*canvas.width/data.width,y:canvas.y+(slot.rect[1]+slot.rect[3]+22)*canvas.height/data.height};
    },id);
    await page.mouse.click(point.x,point.y);
  }
  const remoteAudio=(page,id)=>page.locator(`#rally-media-layer audio[data-player-id="${id}"]`);
  // The speaker button is alongside the remote emoji. This changes playback on
  // just the receiver, without stopping the sender's microphone or their video.
  await tapCamera(host,friendId,false);
  await host.waitForFunction(id=>document.querySelector(`#rally-media-layer audio[data-player-id="${id}"]`)?.muted,friendId);
  assert(await video(host,friendId).isVisible(),'Muting another player preserves their video');
  assert(await friend.evaluate(()=>window.__capturedTracks.some(t=>t.kind==='audio'&&t.readyState==='live')),'Receiver mute never disables the sender microphone');
  await tapCamera(host,friendId,false);
  await host.waitForFunction(id=>document.querySelector(`#rally-media-layer audio[data-player-id="${id}"]`)?.muted===false,friendId);
  await verifyRemoteAudio(host,friendId);
  // Own microphone switches independently, and the remote camera must remain.
  await tapMicrophone(host,hostId);
  await friend.waitForFunction(id=>!document.querySelector(`#rally-media-layer audio[data-player-id="${id}"]`),hostId);
  for(const listener of listeners){
    await listener.page.waitForFunction(id=>!document.querySelector(`#rally-media-layer audio[data-player-id="${id}"]`),hostId);
    assert(await video(listener.page,hostId).isVisible(),'Sender microphone mute preserves video for every listener');
  }
  assert(await video(friend,hostId).isVisible(),'Muting own microphone preserves remote video');
  await tapMicrophone(host,hostId);
  await friend.waitForFunction(id=>document.querySelector(`#rally-media-layer audio[data-player-id="${id}"]`)?.srcObject?.getAudioTracks().some(t=>t.readyState==='live'),hostId);
  await verifyRemoteAudio(friend,hostId);
  for(const listener of listeners)await verifyRemoteAudio(listener.page,hostId);
  // Retain the real tracks to verify the camera/microphone are actually released.
  await host.evaluate(()=>{window.__oldMediaTracks=[...window.__capturedTracks];});
  await tapCamera(host,hostId,false);
  await host.waitForFunction(id=>!document.querySelector(`#rally-media-layer video[data-player-id="${id}"]`),hostId);
  await friend.waitForFunction(id=>!document.querySelector(`#rally-media-layer video[data-player-id="${id}"]`),hostId);
  assert(await host.evaluate(()=>window.__oldMediaTracks.filter(track=>track.kind==='video').every(track=>track.readyState==='ended')),'Hiding video releases local camera capture');
  await verifyRemoteAudio(friend,hostId);
  assert(await host.evaluate(()=>window.__capturedTracks.some(track=>track.kind==='audio'&&track.readyState==='live')),'Camera off preserves audio-only capture');
  // A denied camera retry must leave the working microphone untouched.
  await host.evaluate(()=>{window.__denyNextVideo=true;});
  await tapCamera(host,hostId,false);
  await host.waitForFunction(()=>!window.__denyNextVideo);
  await host.waitForTimeout(500);
  await host.keyboard.press('Enter');
  await verifyRemoteAudio(friend,hostId);
  assert.equal(await video(friend,hostId).count(),0,'Denied camera stays hidden while audio continues');
  await tapMicrophone(host,hostId);
  await friend.waitForFunction(id=>!document.querySelector(`#rally-media-layer audio[data-player-id="${id}"]`),hostId);
  assert(await host.evaluate(()=>window.__capturedTracks.every(track=>track.readyState==='ended')),'Switching both devices off releases all capture');
  // Controls remain available at zero capture; mic can restart without camera.
  await tapMicrophone(host,hostId);
  await verifyRemoteAudio(friend,hostId);
  assert.equal(await video(friend,hostId).count(),0,'Restarting microphone does not open the camera');
  await tapMicrophone(host,hostId);
  assert(await video(host,friendId).isVisible(),'A camera-off player still receives the other player video');
  await host.waitForFunction(id=>document.querySelector(`#rally-media-layer audio[data-player-id="${id}"]`)?.srcObject?.getAudioTracks().some(track=>track.readyState==='live'),friendId);
  await verifyRemoteAudio(host,friendId);
  // Closing a broadcasting tab must remove media without waiting for the
  // separate game reconnect grace period or touching other participants.
  await friend.close();
  await host.waitForFunction(id=>!document.querySelector(`#rally-media-layer video[data-player-id="${id}"]`),friendId,{timeout:15000});
  await host.waitForFunction(id=>!document.querySelector(`#rally-media-layer audio[data-player-id="${id}"]`),friendId,{timeout:15000});
  assert.deepEqual(errors,[],'No JavaScript runtime errors during mixed-device calls');
  console.log('Live media passed: receive-only join, two-way camera/audio, local-only receiver mute/unmute, independent microphone, audio-only mode, capture release, continued receiving and leave cleanup.');
} catch(error) {
  for(const page of pages) console.error('Media test diagnostics:',await page.evaluate(()=>({socket:window.__gameSocket?.readyState,events:window.__events.slice(-12).map(event=>({type:event.type,message:event.message,players:event.state?.players?.length,phase:event.state?.phase})),audio:[...document.querySelectorAll('audio')].map(el=>({id:el.dataset.playerId,paused:el.paused,muted:el.muted,ready:el.readyState})),media:window.__rallyMedia?.poll()})).catch(()=>({pageClosed:true})));
  throw error;
} finally {
  if(existsSync('apps/godot/dist/media-listener-test.html'))unlinkSync('apps/godot/dist/media-listener-test.html');
  for(const socket of extraSockets)socket.close();
  await browser?.close(); children.forEach(child=>child.kill());
}
