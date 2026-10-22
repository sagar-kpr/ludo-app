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
    child.once('exit',code=>{clearTimeout(timer);reject(new Error(`Service exited: ${code}`));});
  });
  return child;
}
// Predictable rolls are injected into this test's server process only.
const preload='data:text/javascript;base64,'+Buffer.from("import crypto from 'node:crypto'; import {syncBuiltinESMExports} from 'node:module'; const values=[1,6,6,5]; let index=0; crypto.randomInt=(min,max)=>min===1?Math.min(values[Math.min(index++,3)],max-1):0; syncBuiltinESMExports();").toString('base64');
const port=await freePort(),previewPort=await freePort(),children=[];
let browser;
try {
  children.push(await service(['--import','tsx','--import',preload,'apps/game-server/src/index.ts'],{PORT:String(port),SUPABASE_SERVICE_ROLE_KEY:''},'listening'));
  children.push(await service(['scripts/preview-godot.mjs'],{PORT:String(previewPort),RALLY_PREVIEW_REALTIME_URL:`ws://127.0.0.1:${port}`},'preview:'));
  browser=await chromium.launch({executablePath:process.env.CHROME_PATH||'/usr/bin/google-chrome',headless:true,args:['--enable-unsafe-swiftshader','--use-angle=swiftshader']});
  const context=await browser.newContext({viewport:{width:393,height:852},deviceScaleFactor:3,hasTouch:true,isMobile:true});
  await context.addInitScript(()=>{
    const Original=window.WebSocket;
    window.__events=[];
    window.WebSocket=class extends Original {
      constructor(...args){super(...args);window.__gameSocket=this;this.addEventListener('message',event=>window.__events.push(JSON.parse(event.data)));}
    };
  });
  const page=await context.newPage(),errors=[];
  page.on('pageerror',error=>errors.push(error.message));
  page.on('console',message=>{if(message.type()==='error')errors.push(message.text());});
  await page.goto(`http://127.0.0.1:${previewPort}`);
  await page.waitForFunction(()=>document.querySelector('#rally-name')&&!document.querySelector('#status'),null,{timeout:45000});
  await page.waitForFunction(()=>window.__events.some(event=>event.type==='CONNECTED'));
  assert(await page.locator('#rally-name').isHidden(),'Mode dashboard hides the room form');
  mkdirSync('test-results',{recursive:true});
  await page.screenshot({path:'test-results/computer-mobile-home.png'});
  // Tap the real right-hand AI card, with no name or room fields required.
  await page.touchscreen.tap(290,345);
  await page.waitForFunction(()=>window.__events.some(event=>event.type==='STATE'&&event.state.players.some(player=>player.isComputer)),null,{timeout:15000});
  const match=await page.evaluate(()=>window.__events.find(event=>event.type==='STATE'&&event.state.players.some(player=>player.isComputer)).state);
  assert.equal(match.players.length,2);
  assert.equal(match.phase,'rolling');
  assert.equal(match.players[0].name,'Guest');
  await page.waitForFunction(()=>[...document.querySelectorAll('#rally-input-layer input')].every(input=>input.hidden));
  // The canvas start tap exercises real UI input; subsequent messages exercise
  // the unchanged browser presentation queue with authoritative bot events.
  await page.evaluate(()=>window.__gameSocket.send(JSON.stringify({type:'ROLL_DICE'})));
  await page.waitForFunction(()=>window.__events.filter(event=>event.type==='TOKEN_MOVED').length===3,null,{timeout:25000});
  const rolls=await page.evaluate(id=>window.__events.filter(event=>event.type==='DICE_ROLLED'&&event.playerId===id).map(event=>event.value),match.players[1].id);
  assert.deepEqual(rolls,[6,6,5]);
  await page.waitForTimeout(4000);
  await page.screenshot({path:'test-results/computer-mobile-match.png'});
  await page.evaluate(()=>window.__gameSocket.send(JSON.stringify({type:'LEAVE_GAME'})));
  await page.waitForFunction(()=>window.__events.some(event=>event.type==='LEFT_ROOM'),null,{timeout:15000});
  await page.waitForTimeout(1800);
  assert(await page.locator('#rally-name').isHidden(),'Leaving returns to the mode dashboard');
  await page.touchscreen.tap(100,345);
  await page.locator('#rally-name').waitFor({state:'visible'});
  assert.deepEqual(await page.evaluate(()=>window.__events.filter(event=>event.type==='ERROR')),[]);
  assert.deepEqual(errors,[],'No browser or Godot runtime errors');
  console.log('Computer mobile browser checks passed: real start-button tap, opponent turns, shared dice limit, rendering and return home.');
} finally {
  await browser?.close();
  children.forEach(child=>child.kill());
}
