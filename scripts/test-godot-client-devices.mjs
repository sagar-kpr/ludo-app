import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {createServer} from 'node:net';
import {mkdirSync} from 'node:fs';
import {chromium} from '@playwright/test';

async function freePort() {
  const probe=createServer();
  await new Promise(resolve=>probe.listen(0,'127.0.0.1',resolve));
  const port=probe.address().port;
  await new Promise(resolve=>probe.close(resolve));
  return port;
}
async function service(args,env,ready) {
  const child=spawn(process.execPath,args,{env:{...process.env,...env},stdio:['ignore','pipe','pipe']});
  await new Promise((resolve,reject)=>{
    const timer=setTimeout(()=>{child.kill();reject(new Error('Service startup timed out'));},15000);
    child.stdout.on('data',data=>{if(String(data).includes(ready)){clearTimeout(timer);resolve();}});
    child.once('error',error=>{clearTimeout(timer);reject(error);});
  });
  return child;
}
const port=await freePort(),previewPort=await freePort(),children=[];
let browser;
try {
  children.push(await service(['--import','tsx','apps/game-server/src/index.ts'],{PORT:String(port),TURN_TIMEOUT_MS:'60000',SUPABASE_SERVICE_ROLE_KEY:''},'listening'));
  children.push(await service(['scripts/preview-godot.mjs'],{PORT:String(previewPort),RALLY_PREVIEW_REALTIME_URL:`ws://127.0.0.1:${port}`},'preview:'));
  browser=await chromium.launch({executablePath:process.env.CHROME_PATH||'/usr/bin/google-chrome',headless:true,args:['--enable-unsafe-swiftshader','--use-angle=swiftshader','--autoplay-policy=document-user-activation-required']});
  const context=await browser.newContext({viewport:{width:420,height:860}});
  await context.addInitScript(()=>{
    window.__events=[];window.__sockets=[];
    const WS=window.WebSocket;
    window.WebSocket=class extends WS {constructor(...args){super(...args);window.__sockets.push(this);this.addEventListener('message',e=>window.__events.push(JSON.parse(e.data)));}};
    // Observe real browser audio scheduling and master output, not GDScript flags.
    window.__audioProbe={starts:[],meters:[],energy:0,contexts:[]};
    const connect=AudioNode.prototype.connect;
    AudioNode.prototype.connect=function(destination,...args){
      const result=connect.call(this,destination,...args);
      if(destination===this.context.destination){
        const analyser=this.context.createAnalyser();analyser.fftSize=2048;
        connect.call(this,analyser);window.__audioProbe.meters.push(analyser);
      }
      return result;
    };
    const Native=window.AudioContext;
    window.AudioContext=class extends Native {constructor(...args){
      super(...args);window.__audioProbe.contexts.push(this);
      const create=this.createBufferSource.bind(this);
      this.createBufferSource=()=>{
        const source=create(),start=source.start.bind(source);
        source.start=(...args)=>{
          const data=source.buffer?.getChannelData(0),rms=data?Math.sqrt(data.reduce((sum,x)=>sum+x*x,0)/data.length):0;
          window.__audioProbe.starts.push({duration:source.buffer?.duration,rms,state:this.state});
          return start(...args);
        };
        return source;
      };
    }};
    const data=new Float32Array(2048);
    setInterval(()=>{for(const analyser of window.__audioProbe.meters){analyser.getFloatTimeDomainData(data);const rms=Math.sqrt(data.reduce((sum,x)=>sum+x*x,0)/data.length);window.__audioProbe.energy=Math.max(window.__audioProbe.energy,rms);}},10);
  });
  const pages=[await context.newPage(),await context.newPage()];
  const errors=[];
  for(const page of pages){
    page.on('pageerror',e=>errors.push(e.message));
    await page.goto(`http://127.0.0.1:${previewPort}`);
    await page.waitForFunction(()=>!document.querySelector('#status')&&window.__events.some(e=>e.type==='CONNECTED'),null,{timeout:45000});
    await page.mouse.click(5,5); // Real gesture on each player's own browser.
  }
  const [host,friend]=pages;
  const send=(page,event)=>page.evaluate(event=>window.__sockets.at(-1).send(JSON.stringify(event)),event);
  await send(host,{type:'CREATE_ROOM',name:'Host'});
  await host.waitForFunction(()=>window.__events.some(e=>e.type==='ROOM_CREATED'));
  const code=await host.evaluate(()=>window.__events.find(e=>e.type==='ROOM_CREATED').roomCode);
  await send(friend,{type:'JOIN_ROOM',name:'Guest',code});
  await host.waitForFunction(()=>window.__events.some(e=>e.type==='STATE'&&e.state.players.length===2));
  await send(host,{type:'START_GAME'});
  await host.waitForFunction(()=>window.__events.some(e=>e.type==='STATE'&&e.state.phase==='rolling'));
  const baseline=await host.evaluate(()=>structuredClone(window.__events.filter(e=>e.type==='STATE').at(-1)));
  baseline.state.version+=100;baseline.state.currentPlayer=baseline.state.players[0].id;
  baseline.state.phase='moving';baseline.state.dice=3;
  const token=baseline.state.tokens.find(t=>t.color===baseline.state.players[0].color);
  token.position=1;
  const inject=(page,event)=>page.evaluate(event=>window.__sockets.at(-1).dispatchEvent(new MessageEvent('message',{data:JSON.stringify(event)})),event);
  for(const page of pages){await inject(page,baseline);await page.waitForTimeout(300);await page.evaluate(()=>{window.__audioProbe.starts=[];window.__audioProbe.energy=0;});}
  const after=structuredClone(baseline);after.state.version++;after.state.tokens.find(t=>t.id===token.id).position=4;after.state.phase='rolling';after.state.dice=null;
  for(const page of pages){
    await inject(page,{type:'TOKEN_MOVED',tokenId:token.id,from:1,to:4,durationMs:720,captured:[],version:after.state.version});
    await inject(page,after);
  }
  for(const [index,page] of pages.entries()){
    try {
      await page.waitForFunction(()=>window.__audioProbe.starts.length>=3,null,{timeout:20000});
    } catch(error) {
      console.error('Playback diagnostics:',await page.evaluate(()=>({starts:window.__audioProbe.starts,states:window.__audioProbe.contexts.map(c=>c.state),energy:window.__audioProbe.energy,events:window.__events.slice(-5).map(e=>({type:e.type,phase:e.state?.phase,version:e.state?.version})),visibility:document.visibilityState})));
      throw error;
    }
    await page.waitForTimeout(200);
    const audio=await page.evaluate(()=>({starts:window.__audioProbe.starts,energy:window.__audioProbe.energy,states:window.__audioProbe.contexts.map(c=>c.state)}));
    console.log(index===0?'Host audio:':'Guest audio:',JSON.stringify(audio));
    assert.equal(audio.starts.length,3,'Each client schedules one sound for each of three pawn steps');
    assert(audio.energy>0.00001,'Movement reaches the browser master audio output');
    assert(audio.starts.every(s=>s.rms>0&&s.state==='running'),'Both clients play non-silent audio in a running context');
  }
  mkdirSync('test-results',{recursive:true});
  for(const size of [{width:1366,height:768},{width:1366,height:600},{width:1920,height:507},{width:390,height:844},{width:640,height:360}]){
    await friend.setViewportSize(size);await friend.waitForTimeout(500);
    const png=await friend.screenshot({path:`test-results/device-layout-${size.height}.png`});
    const redYardWidth=await friend.evaluate(async data=>{
      const image=new Image();image.src='data:image/png;base64,'+data;await image.decode();
      const canvas=document.createElement('canvas');canvas.width=image.width;canvas.height=image.height;
      const ctx=canvas.getContext('2d');ctx.drawImage(image,0,0);
      const pixels=ctx.getImageData(0,0,canvas.width,canvas.height).data;
      let best=0;
      for(let y=0;y<canvas.height;y++){let run=0;for(let x=0;x<canvas.width;x++){const i=(y*canvas.width+x)*4;run=pixels[i]>180&&pixels[i+1]<80&&pixels[i+2]<90?run+1:0;best=Math.max(best,run);}}
      return best;
    },png.toString('base64'));
    assert(redYardWidth>=(size.height<450?70:100),`Board must remain usable at ${size.width}x${size.height}, red yard measured ${redYardWidth}px`);
  }
  assert.deepEqual(errors,[]);
  console.log('Browser clients: host and guest movement audio reaches output; device layouts captured.');
} finally {await browser?.close();for(const child of children)child.kill();}
