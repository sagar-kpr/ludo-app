import { chromium } from '@playwright/test';
import { spawn } from 'node:child_process';
import { createServer } from 'node:net';
import { mkdirSync } from 'node:fs';

async function freePort() {
  const probe = createServer();
  await new Promise(resolve => probe.listen(0,'127.0.0.1',resolve));
  const port = probe.address().port;
  await new Promise(resolve => probe.close(resolve));
  return port;
}
async function service(script,env,ready) {
  const child = spawn(process.execPath,script,{env:{...process.env,...env},stdio:['ignore','pipe','pipe']});
  await new Promise((resolve,reject) => {
    const timer = setTimeout(()=>reject(new Error('Browser test service startup timed out')),15000);
    child.stdout.on('data',data=>{if(String(data).includes(ready)){clearTimeout(timer);resolve();}});
    child.once('error',error=>{clearTimeout(timer);reject(error);});
    child.once('exit',code=>{clearTimeout(timer);reject(new Error(`Service exited ${code}`));});
  });
  return child;
}
const port=await freePort();
const previewPort=await freePort();
const profilesOnly=process.argv.includes('--profiles-only');
// Software WebGL screenshots can stall the render loop; timeout behavior is
// tested separately with a real 1-second deadline in the server integration test.
const gameServer=await service(['--import','tsx','apps/game-server/src/index.ts'],{PORT:String(port),TURN_TIMEOUT_MS:'60000',SUPABASE_SERVICE_ROLE_KEY:'',RECONNECT_GRACE_MS:'5000'},'listening');
let preview;
let browser;
try {
  preview=await service(['scripts/preview-godot.mjs'],{PORT:String(previewPort),RALLY_PREVIEW_REALTIME_URL:`ws://127.0.0.1:${port}`},'preview:');
  browser=await chromium.launch({executablePath:process.env.CHROME_PATH||'/usr/bin/google-chrome',headless:true,args:['--enable-unsafe-swiftshader','--use-angle=swiftshader']});
  const context=await browser.newContext({viewport:{width:420,height:860},hasTouch:true,isMobile:true});
  await context.addInitScript(()=>{
    const Original=window.WebSocket;
    window.__ludoSockets=[];window.__ludoEvents=[];
    window.WebSocket=class extends Original {
      constructor(...args) {
        super(...args);window.__ludoSockets.push(this);
		 super.addEventListener('message',event=>{if(window.__dropRallySocket===this)event.stopImmediatePropagation();});
        this.addEventListener('message',event=>{try{window.__ludoEvents.push(JSON.parse(event.data));}catch{}});
      }
    };
  });
  const errors=[];
  const host=await context.newPage();const friend=await context.newPage();
  for(const page of [host,friend]) {
    page.on('pageerror',error=>errors.push(error.message));
    page.on('console',message=>{if(message.type()==='error')errors.push(message.text());});
    await page.goto(`http://127.0.0.1:${previewPort}`);
    await page.waitForFunction(()=>!document.querySelector('#status'),null,{timeout:45000});
    await page.waitForFunction(()=>window.__ludoEvents.some(event=>event.type==='CONNECTED'));
    const connectedUrl=await page.evaluate(()=>window.__ludoSockets[0].url);
    if(connectedUrl!==`ws://127.0.0.1:${port}/`)throw new Error(`Preview connected to wrong server: ${connectedUrl}`);
  }
  mkdirSync('test-results',{recursive:true});
  await host.screenshot({path:'test-results/godot-home.png'});
  // Tap the actual canvas field on a touch device and type through the browser input.
  await host.touchscreen.tap(180,305);
  await host.waitForFunction(()=>['INPUT','TEXTAREA'].includes(document.activeElement?.tagName));
  await host.locator('input:focus,textarea:focus').fill('Mobile Maya');
  await host.touchscreen.tap(180,385);
  await host.waitForFunction(()=>window.__ludoEvents.some(event=>event.type==='ROOM_CREATED'));
  await host.waitForFunction(()=>window.__ludoEvents.some(event=>event.type==='STATE'&&event.state.players[0]?.name==='Mobile Maya'));
  // Network interception is test-only; the production client exposes no hooks.
  async function intent(page,event) {
    await page.evaluate(event=>window.__ludoSockets.at(-1).send(JSON.stringify(event)),event);
  }
  const code=await host.evaluate(()=>window.__ludoEvents.find(event=>event.type==='ROOM_CREATED').roomCode);
  await friend.locator('#rally-name').fill('Arjun');
  await friend.locator('#rally-code').tap();
  await friend.locator('#rally-code').fill(code.toLowerCase());
  await friend.touchscreen.tap(180,550);
  await host.waitForFunction(()=>window.__ludoEvents.some(event=>event.type==='STATE'&&event.state.players.length===2));
  await host.waitForTimeout(300);
  await host.screenshot({path:'test-results/godot-lobby.png'});
  await intent(host,{type:'START_GAME'});
  for(const page of [host,friend])await page.waitForFunction(()=>window.__ludoEvents.some(event=>event.type==='STATE'&&event.state.phase==='rolling'));
  await host.waitForTimeout(600);
  await host.screenshot({path:'test-results/godot-board.png'});
  const originalId=await host.evaluate(()=>window.__ludoEvents.find(event=>event.type==='CONNECTED').playerId);
  await host.evaluate(()=>window.__ludoSockets.at(-1).close());
  await host.waitForFunction(id=>window.__ludoEvents.some(event=>event.type==='CONNECTED'&&event.resumed&&event.playerId===id),originalId);
  await host.waitForFunction(()=>window.__ludoEvents.some(event=>event.type==='STATE'&&event.recovered&&event.state.players.length===2));
  await host.waitForTimeout(400);
  await host.evaluate(()=>window.__ludoSockets.at(-1).send(JSON.stringify({type:'CHAT',text:'Recovered chat'})));
  await friend.waitForFunction(()=>window.__ludoEvents.some(event=>event.type==='CHAT'&&event.text==='Recovered chat'));
  await host.evaluate(()=>{ window.dispatchEvent(new Event('online')); document.dispatchEvent(new Event('visibilitychange')); });
  await host.waitForFunction(()=>window.__ludoEvents.filter(event=>event.type==='STATE'&&event.recovered).length>=2);
  const resumes=await host.evaluate(()=>window.__ludoEvents.filter(event=>event.type==='CONNECTED'&&event.resumed).length);
  await host.evaluate(()=>{window.__dropRallySocket=window.__ludoSockets.at(-1);});
  await host.waitForFunction(count=>window.__ludoEvents.filter(event=>event.type==='CONNECTED'&&event.resumed).length>count,resumes,{timeout:30000});
  await host.waitForTimeout(400);
  await host.screenshot({path:'test-results/godot-before-recovered-tap.png'});
  await host.touchscreen.tap(115,140);
  await host.waitForFunction(()=>window.__ludoEvents.some(event=>event.type==='DICE_ROLLED'));
  await host.waitForTimeout(1600);
  const target=await friend.evaluate(()=>window.__ludoEvents.find(event=>event.type==='CONNECTED').playerId);
  await intent(host,{type:'SEND_STICKER',targetPlayerId:target,sticker:'CLAP'});
  await friend.waitForFunction(()=>window.__ludoEvents.some(event=>event.type==='STICKER'&&event.sticker==='CLAP'));
  await host.screenshot({path:'test-results/godot-recovered.png'});
  if(profilesOnly) {
    const snapshot=await host.evaluate(()=>structuredClone(window.__ludoEvents.filter(event=>event.type==='STATE').at(-1)));
    const bounds=[];
    for(const player of snapshot.state.players) {
      const fixture=structuredClone(snapshot);
      fixture.state.currentPlayer=player.id;
      fixture.state.phase='rolling';fixture.state.dice=null;
      fixture.serverTime=Date.now();fixture.turnDeadline=Date.now()+60000;
      await host.evaluate(event=>window.__ludoSockets.at(-1).dispatchEvent(new MessageEvent('message',{data:JSON.stringify(event)})),fixture);
      await host.waitForTimeout(300);
      const png=await host.screenshot({path:`test-results/godot-board-turn-${bounds.length}.png`});
      bounds.push(await host.evaluate(async data=>{
        const image=new Image();image.src='data:image/png;base64,'+data;await image.decode();
        const canvas=document.createElement('canvas');canvas.width=image.width;canvas.height=image.height;
        const context=canvas.getContext('2d');context.drawImage(image,0,0);
        const pixels=context.getImageData(0,0,canvas.width,canvas.height).data;
        let best={x:0,y:0,width:0,height:0},run=0,start=0,left=canvas.width,right=0;
        for(let y=0;y<canvas.height;y++) {
          let count=0,rowLeft=canvas.width,rowRight=0;
          for(let x=0;x<canvas.width;x++){const i=(y*canvas.width+x)*4;if(pixels[i]>190&&pixels[i+1]<65&&pixels[i+2]<75){count++;rowLeft=Math.min(rowLeft,x);rowRight=Math.max(rowRight,x);}}
          if(count>60){if(!run){start=y;left=rowLeft;right=rowRight;}run++;left=Math.min(left,rowLeft);right=Math.max(right,rowRight);if(run>best.height)best={x:left,y:start,width:right-left+1,height:run};}
          else run=0;
        }
        return best;
      },png.toString('base64')));
    }
    if(!bounds[0].height||JSON.stringify(bounds[0])!==JSON.stringify(bounds[1]))throw new Error('Board shifts when the dice switches players: '+JSON.stringify(bounds));
    await host.evaluate(event=>window.__ludoSockets.at(-1).dispatchEvent(new MessageEvent('message',{data:JSON.stringify(event)})),snapshot);
    console.log('Board rectangle stays identical across both players’ turns.');
  }
  await friend.screenshot({path:'test-results/godot-profile-owner-friend.png'});
  if(profilesOnly) {
    for(const size of [{width:320,height:640},{width:390,height:844},{width:844,height:390},{width:1280,height:900},{width:1920,height:507}]) {
      await host.setViewportSize(size);
      await host.waitForTimeout(500);
      await host.screenshot({path:`test-results/godot-profiles-${size.width}.png`});
    }
  } else {
  await intent(host,{type:'ROLL_DICE'});
  await friend.waitForFunction(()=>window.__ludoEvents.some(event=>event.type==='DICE_ROLLED'));
  await host.waitForTimeout(1600);
  await host.screenshot({path:'test-results/godot-dice.png'});
  await intent(host,{type:'CHAT',text:'Nice move! Your turn.'});
  await friend.waitForFunction(()=>window.__ludoEvents.some(event=>event.type==='CHAT'));
  await friend.waitForTimeout(250);
  await friend.screenshot({path:'test-results/godot-chat-popup.png'});
  const stickerTarget = await friend.evaluate(()=>window.__ludoEvents.find(event=>event.type==='CONNECTED').playerId);
  await intent(host,{type:'SEND_STICKER',targetPlayerId:stickerTarget,sticker:'HAMMER'});
  for(const page of [host,friend])await page.waitForFunction(()=>window.__ludoEvents.some(event=>event.type==='STICKER'&&event.sticker==='HAMMER'));
  await friend.waitForTimeout(750);
  await friend.screenshot({path:'test-results/godot-hammer-sticker.png'});
  for(const sticker of ['GIFT','FIRE','LOVE','PUNCH','CROWN']) {
    await intent(host,{type:'SEND_STICKER',targetPlayerId:stickerTarget,sticker});
    await friend.waitForFunction(sticker=>window.__ludoEvents.some(event=>event.type==='STICKER'&&event.sticker===sticker),sticker);
    await friend.waitForTimeout(900);
    await friend.screenshot({path:`test-results/godot-sticker-${sticker.toLowerCase()}.png`});
  }
  for(const size of [{width:320,height:640},{width:1280,height:900}]) {
    await host.setViewportSize(size);
    await host.waitForTimeout(300);
    await host.screenshot({path:`test-results/godot-board-${size.width}.png`});
  }
  // Capture a real six/selection state, not a fabricated visual snapshot.
  const hostId=await host.evaluate(()=>window.__ludoEvents.find(event=>event.type==='CONNECTED').playerId);
  let selection;
  for(let attempt=0;attempt<30;attempt++) {
    const snapshot=await host.evaluate(()=>window.__ludoEvents.filter(event=>event.type==='STATE').at(-1).state);
    const actor=snapshot.currentPlayer===hostId?host:friend;
    if(snapshot.phase==='moving') {selection=actor;break;}
    await intent(actor,{type:'ROLL_DICE'});
    await host.waitForFunction(version=>window.__ludoEvents.some(event=>event.type==='STATE'&&event.state.version>version),snapshot.version);
    await actor.waitForTimeout(1450);
  }
  if(!selection)throw new Error('No legal selection state reached');
  await selection.setViewportSize({width:420,height:860});
  await selection.waitForTimeout(5500);
  await selection.screenshot({path:'test-results/godot-legal-moves.png'});
  // Client-only presentation fixtures: no board injection or debug API exists
  // on the production server. These exercise dense stacks and results visuals.
  const fixture=await host.evaluate(()=>structuredClone(window.__ludoEvents.filter(event=>event.type==='STATE').at(-1)));
  fixture.state.currentPlayer=hostId;
  fixture.state.phase='moving';fixture.state.dice=6;fixture.state.version+=10;
  for(const token of fixture.state.tokens)token.position=token.color===fixture.state.players[0].color?1:27;
  await host.evaluate(event=>window.__ludoSockets.at(-1).dispatchEvent(new MessageEvent('message',{data:JSON.stringify(event)})),fixture);
  await host.setViewportSize({width:420,height:860});
  await host.waitForTimeout(6000);
  await host.screenshot({path:'test-results/godot-stacked-tokens.png'});
  // Top-edge pins previously escaped the viewport behind the profile cards.
  for(const token of fixture.state.tokens)token.position={coral:11,sun:50,mint:37,violet:24}[token.color];
  fixture.state.version++;
  await host.evaluate(event=>window.__ludoSockets.at(-1).dispatchEvent(new MessageEvent('message',{data:JSON.stringify(event)})),fixture);
  for(const size of [{width:320,height:640},{width:420,height:860},{width:1280,height:900}]) {
    await host.setViewportSize(size);
    await host.waitForTimeout(500);
    await host.screenshot({path:`test-results/godot-top-edge-${size.width}.png`});
  }
  await host.setViewportSize({width:420,height:860});
  fixture.state.phase='finished';fixture.state.dice=null;fixture.state.version++;
  fixture.state.finishOrder=fixture.state.players.map(player=>player.id);
  fixture.state.winner=hostId;
  for(const token of fixture.state.tokens)if(token.color===fixture.state.players[0].color)token.position=57;
  for(const page of [host,friend]) {
    await page.evaluate(event=>window.__ludoSockets.at(-1).dispatchEvent(new MessageEvent('message',{data:JSON.stringify(event)})),fixture);
    await page.waitForTimeout(1200);
    await page.screenshot({path:`test-results/godot-results-${page===host?'host':'friend'}.png`});
  }
  }
  if(errors.length)throw new Error(errors.join('\n'));
  if(profilesOnly) {
    await friend.close();
    await host.waitForFunction(()=>window.__ludoEvents.some(event=>event.type==='STATE'&&event.state.phase==='finished'&&event.state.players.length===1&&event.state.tokens.length===4));
    await host.setViewportSize({width:420,height:860});
    await host.waitForTimeout(500);
    await host.screenshot({path:'test-results/godot-opponent-left.png'});
    if(errors.length)throw new Error(errors.join('\n'));
  }
  console.log(profilesOnly?'Godot profile browser smoke passed: two clients, owner/opponent controls, mobile and desktop screenshots, no runtime errors.':'Godot browser smoke passed: two web clients, shared room, match start, dice, responsive screenshots, no runtime errors.');
} finally {
  await browser?.close();preview?.kill();gameServer.kill();
}
