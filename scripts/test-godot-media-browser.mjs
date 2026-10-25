import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { createServer } from 'node:net';
import { mkdirSync } from 'node:fs';
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
try {
  const mediaPort=await port(),gamePort=await port(),previewPort=await port();
  await service(process.env.LIVEKIT_BIN||'.tools/livekit/livekit-server',['--dev','--bind','127.0.0.1','--node-ip','127.0.0.1','--port',String(mediaPort)],{},'starting LiveKit server');
  await service(process.execPath,['--import','tsx','apps/game-server/src/index.ts'],{PORT:String(gamePort),TURN_TIMEOUT_MS:'120000',SUPABASE_SERVICE_ROLE_KEY:'',LIVEKIT_URL:`ws://127.0.0.1:${mediaPort}`,LIVEKIT_API_KEY:'devkey',LIVEKIT_API_SECRET:'secret'},'listening');
  await service(process.execPath,['scripts/preview-godot.mjs'],{PORT:String(previewPort),RALLY_PREVIEW_REALTIME_URL:`ws://127.0.0.1:${gamePort}`},'preview:');
  browser=await chromium.launch({executablePath:process.env.CHROME_PATH||'/usr/bin/google-chrome',headless:true,args:['--enable-unsafe-swiftshader','--use-angle=swiftshader','--use-fake-device-for-media-stream','--autoplay-policy=no-user-gesture-required']});
  const desktop=await browser.newContext({viewport:{width:1100,height:800},permissions:['camera','microphone']});
  const mobile=await browser.newContext({viewport:{width:393,height:852},deviceScaleFactor:1,isMobile:true,hasTouch:true,permissions:['camera','microphone']});
  for(const context of [desktop,mobile]) await context.addInitScript(()=>{
    window.__events=[];window.__gameSocket=null;
    window.__capturedTracks=[];
    const capture=navigator.mediaDevices.getUserMedia.bind(navigator.mediaDevices);
    navigator.mediaDevices.getUserMedia=async constraints=>{
      const stream=await capture(constraints);window.__capturedTracks.push(...stream.getTracks());return stream;
    };
    const Original=window.WebSocket;
    window.WebSocket=class extends Original {
      constructor(...args){super(...args);if(String(args[0]).includes('/rtc'))return;window.__gameSocket=this;this.addEventListener('message',event=>{try{window.__events.push(JSON.parse(event.data));}catch{}});}
    };
  });
  const host=await desktop.newPage(),friend=await mobile.newPage();
  pages.push(host,friend);
  const errors=[];
  for(const page of [host,friend]) {
    page.on('pageerror',error=>errors.push(error.message));
    // Poll from Node: software-rendered background tabs can suspend their own
    // timers even after receiving the relevant WebSocket/WebRTC events.
    page.waitForFunction=async(fn,arg,options={})=>{
      const deadline=Date.now()+(options.timeout||60000);
      while(Date.now()<deadline){
        if(await page.evaluate(fn,arg))return;
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
  await send(host,{type:'START_GAME'});
  for(const page of [host,friend]) {
    await page.waitForFunction(()=>window.__events.some(event=>event.type==='MEDIA_TOKEN'),null,{timeout:30000});
    await page.waitForTimeout(1500);
    assert.equal(await page.locator('#rally-media-layer video').count(),0,'Players join receive-only without requesting camera or microphone');
    assert.equal(await page.evaluate(()=>window.__capturedTracks.length),0,'Receive-only participation never opens capture devices');
  }
  const hostId=await host.evaluate(()=>window.__events.find(event=>event.type==='CONNECTED').playerId);
  const friendId=await friend.evaluate(()=>window.__events.find(event=>event.type==='CONNECTED').playerId);
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
  await tapCamera(friend,friendId,true);
  for(const page of [host,friend]) await page.waitForFunction(id=>{const el=document.querySelector(`#rally-media-layer video[data-player-id="${id}"]`);return el&&!el.hidden&&el.videoWidth>0;},friendId,{timeout:30000});
  mkdirSync('test-results',{recursive:true});
  await host.screenshot({path:'test-results/live-media-desktop.png'});
  await friend.screenshot({path:'test-results/live-media-android-browser.png'});
  // Retain the real tracks to verify the camera/microphone are actually released.
  await host.evaluate(()=>{window.__oldMediaTracks=[...window.__capturedTracks];});
  await tapCamera(host,hostId,false);
  await host.waitForFunction(id=>!document.querySelector(`#rally-media-layer video[data-player-id="${id}"]`),hostId);
  await friend.waitForFunction(id=>!document.querySelector(`#rally-media-layer video[data-player-id="${id}"]`),hostId);
  assert(await host.evaluate(()=>window.__oldMediaTracks.every(track=>track.readyState==='ended')),'Turning off releases local capture');
  assert(await video(host,friendId).isVisible(),'A camera-off player still receives the other player video');
  await host.waitForFunction(id=>document.querySelector(`#rally-media-layer audio[data-player-id="${id}"]`)?.srcObject?.getAudioTracks().some(track=>track.readyState==='live'),friendId);
  await verifyRemoteAudio(host,friendId);
  await send(friend,{type:'LEAVE_GAME'});
  await host.waitForFunction(id=>!document.querySelector(`#rally-media-layer video[data-player-id="${id}"]`),friendId,{timeout:15000});
  assert.deepEqual(errors,[],'No JavaScript runtime errors during mixed-device calls');
  console.log('Live media passed: real LiveKit, desktop and Android-sized browser, receive-only join, two-way camera/audio, avatar placement, camera off, continued receiving and leave cleanup.');
} catch(error) {
  for(const page of pages) console.error('Media test diagnostics:',await page.evaluate(()=>({socket:window.__gameSocket?.readyState,events:window.__events.slice(-12).map(event=>({type:event.type,message:event.message,players:event.state?.players?.length,phase:event.state?.phase}))})).catch(()=>({pageClosed:true})));
  throw error;
} finally {
  await browser?.close(); children.forEach(child=>child.kill());
}
