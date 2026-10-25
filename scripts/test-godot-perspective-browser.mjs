import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {createServer} from 'node:net';
import {mkdirSync} from 'node:fs';
import {chromium} from '@playwright/test';

const children=[];
async function port(){const server=createServer();await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));const value=server.address().port;await new Promise(resolve=>server.close(resolve));return value;}
async function service(args,env,ready){
  const child=spawn(process.execPath,args,{env:{...process.env,...env},stdio:['ignore','pipe','pipe']});children.push(child);
  await new Promise((resolve,reject)=>{const timer=setTimeout(()=>reject(new Error('Service startup timeout')),20000);child.stdout.on('data',data=>{if(String(data).includes(ready)){clearTimeout(timer);resolve();}});child.once('error',reject);child.once('exit',code=>{clearTimeout(timer);reject(new Error(`Service exited ${code}`));});});
}
// Poll from Node: a background software-rendered Godot tab can suspend the
// renderer's own timers even after WebSocket messages have arrived.
async function waitFor(page,predicate,arg,options={}){
  const deadline=Date.now()+(options.timeout||60000);
  while(Date.now()<deadline){
    if(await page.evaluate(predicate,arg))return;
    await new Promise(resolve=>setTimeout(resolve,100));
  }
  throw new Error('Perspective browser condition timed out');
}
let browser;
const pages=[];
try {
  const gamePort=await port(),previewPort=await port();
  await service(['--import','tsx','apps/game-server/src/index.ts'],{PORT:String(gamePort),SUPABASE_SERVICE_ROLE_KEY:'',LIVEKIT_URL:'',LIVEKIT_API_KEY:'',LIVEKIT_API_SECRET:'',TURN_TIMEOUT_MS:'120000'},'listening');
  await service(['scripts/preview-godot.mjs'],{PORT:String(previewPort),RALLY_PREVIEW_REALTIME_URL:`ws://127.0.0.1:${gamePort}`},'preview:');
  browser=await chromium.launch({executablePath:process.env.CHROME_PATH||'/usr/bin/google-chrome',headless:true,args:['--enable-unsafe-swiftshader','--use-angle=swiftshader','--disable-background-timer-throttling','--disable-renderer-backgrounding','--disable-backgrounding-occluded-windows']});
  const contexts=[await browser.newContext({viewport:{width:1000,height:760}}),await browser.newContext({viewport:{width:393,height:852},hasTouch:true,isMobile:true})];
  const errors=[];
  for(const context of contexts){
    await context.addInitScript(()=>{window.__events=[];const Original=window.WebSocket;window.WebSocket=class extends Original{constructor(...args){super(...args);if(String(args[0]).includes('/rtc'))return;window.__gameSocket=this;this.addEventListener('message',event=>{try{window.__events.push(JSON.parse(event.data));}catch{}});}};});
    const page=await context.newPage();pages.push(page);page.on('pageerror',error=>errors.push(error.message));page.on('console',message=>{if(message.type()==='error')errors.push(message.text());});
    await page.bringToFront();
    await page.goto(`http://127.0.0.1:${previewPort}`);
    await waitFor(page,()=>window.__events.some(event=>event.type==='CONNECTED')&&document.querySelector('#rally-name')&&!document.querySelector('#status'),null,{timeout:90000,polling:100});
  }
  const [host,friend]=pages;
  mkdirSync('test-results',{recursive:true});
  await friend.screenshot({path:'test-results/perspective-pawn-selector.png'});
  // The selector sits in the same logical field column as the native name input.
  async function choose(page,index){
    await page.bringToFront();
    const point=await page.evaluate(index=>{const field=document.querySelector('#rally-name').getBoundingClientRect(),scale=innerWidth/Math.max(420,innerWidth);return {x:field.x+(19+index*44)*scale,y:field.bottom+81*scale};},index);
    await page.mouse.click(point.x,point.y);
    // Godot flushes preferences to IndexedDB asynchronously. Read only the
    // preferred_color entry, never connection tokens or other stored data.
    await waitFor(page,async expected=>{
      for(const info of await indexedDB.databases()){
        const db=await new Promise((resolve,reject)=>{const request=indexedDB.open(info.name);request.onsuccess=()=>resolve(request.result);request.onerror=()=>reject(request.error);});
        try{
          for(const store of db.objectStoreNames){
            const rows=await new Promise((resolve,reject)=>{const request=db.transaction(store,'readonly').objectStore(store).getAll();request.onsuccess=()=>resolve(request.result);request.onerror=()=>reject(request.error);});
            for(const row of rows){if(!row?.contents)continue;const text=new TextDecoder().decode(new Uint8Array(row.contents));if(text.includes(`preferred_color="${expected}"`))return true;}
          }
        }finally{db.close();}
      }
      return false;
    },['coral','sun','violet','mint'][index],{polling:200,timeout:15000});
  }
  for(const index of [1,2,3,0])await choose(friend,index);
  await choose(host,0);
  await friend.screenshot({path:'test-results/perspective-pawn-selector-selected.png'});
  const send=async(page,message)=>{
    await page.bringToFront();
    await page.waitForTimeout(200);
    await waitFor(page,()=>window.__gameSocket?.readyState===1,null,{polling:100});
    return page.evaluate(message=>window.__gameSocket.send(JSON.stringify(message)),message);
  };
  await send(host,{type:'CREATE_ROOM',name:'Desktop Red'});
  await waitFor(host,()=>window.__events.some(event=>event.type==='ROOM_CREATED'),null,{polling:100});
  const code=await host.evaluate(()=>window.__events.find(event=>event.type==='ROOM_CREATED').roomCode);
  await send(friend,{type:'JOIN_ROOM',code,name:'Mobile Red'});
  await waitFor(friend,()=>window.__events.some(event=>event.type==='STATE'&&event.state.players.length===2),null,{polling:100});
  await waitFor(host,()=>window.__events.some(event=>event.type==='STATE'&&event.state.players.length===2),null,{polling:100});
  await send(host,{type:'START_GAME'});
  for(const page of pages){
    await page.bringToFront();
    await waitFor(page,()=>window.__events.some(event=>event.type==='STATE'&&event.state.phase==='rolling'),null,{polling:100});
    await page.waitForTimeout(600);
    await page.evaluate(()=>{const update=window.__rallyMedia.layout;window.__rallyMedia.layout=data=>{window.__videoLayout=data;update(data);};});
    await waitFor(page,()=>window.__videoLayout?.entries.length===2,null,{polling:100});
    const positions=await page.evaluate(()=>{const own=window.__events.find(event=>event.type==='CONNECTED').playerId;const entries=window.__videoLayout.entries;return {own:entries.find(entry=>entry.id===own).rect,other:entries.find(entry=>entry.id!==own).rect};});
    assert(positions.own[0]<positions.other[0]&&positions.own[1]>positions.other[1],'Each client sees its own avatar bottom-left and the opponent opposite');
  }
  const serverStates=await Promise.all(pages.map(page=>page.evaluate(()=>window.__events.findLast(event=>event.type==='STATE'&&event.state.phase==='rolling').state)));
  assert.deepEqual(serverStates[0],serverStates[1],'Independent Red preferences do not change the synchronized server state');
  assert.deepEqual(serverStates[0].players.map(player=>player.color),['coral','mint'],'Server logical colors remain unique even though both clients choose Red');
  await host.screenshot({path:'test-results/perspective-desktop-red.png'});
  await friend.screenshot({path:'test-results/perspective-mobile-red.png'});
  assert.deepEqual(errors,[],'No browser or Godot runtime errors');
  console.log('Browser perspective passed: all four real pawn choices save, two independent Red selections share identical authoritative state, own avatar bottom-left on desktop/mobile.');
}catch(error){
  for(const page of pages)console.error('Perspective test diagnostics:',await page.evaluate(()=>({socket:window.__gameSocket?.readyState,events:window.__events.slice(-12).map(event=>({type:event.type,message:event.message,phase:event.state?.phase,players:event.state?.players?.length}))})).catch(()=>({closed:true})));
  throw error;
}finally{await browser?.close();for(const child of children)child.kill();}
