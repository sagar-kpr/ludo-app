import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {createServer} from 'node:net';
import {mkdirSync,readFileSync} from 'node:fs';
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
const port=await freePort(), previewPort=await freePort();
const children=[];
let browser;
try {
  children.push(await service(['--import','tsx','apps/game-server/src/index.ts'],{PORT:String(port),SUPABASE_SERVICE_ROLE_KEY:''},'listening'));
  children.push(await service(['scripts/preview-godot.mjs'],{PORT:String(previewPort),RALLY_PREVIEW_REALTIME_URL:`ws://127.0.0.1:${port}`},'preview:'));
  browser=await chromium.launch({executablePath:process.env.CHROME_PATH||'/usr/bin/google-chrome',headless:true,args:['--enable-unsafe-swiftshader','--use-angle=swiftshader']});
  const context=await browser.newContext({viewport:{width:393,height:852},deviceScaleFactor:3,hasTouch:true,isMobile:true});
  await context.addInitScript(()=>{
    // Safari keeps its layout viewport tall while its visual viewport shrinks/pans.
    const viewport=new EventTarget();
    Object.assign(viewport,{width:393,height:852,pageLeft:0,pageTop:0,offsetLeft:0,offsetTop:0,scale:1});
    Object.defineProperty(window,'visualViewport',{get:()=>viewport});
    window.__keyboardViewport=values=>{Object.assign(viewport,values);viewport.dispatchEvent(new Event('resize'));viewport.dispatchEvent(new Event('scroll'));};
    const Original=window.WebSocket;
    window.__events=[];
    window.WebSocket=class extends Original { constructor(...args){super(...args);this.addEventListener('message',event=>window.__events.push(JSON.parse(event.data)));} };
  });
  const page=await context.newPage();
  const errors=[];
  page.on('pageerror',error=>errors.push(error.message));
  page.on('console',message=>{if(message.type()==='error') errors.push(message.text());});
  await page.goto(`http://127.0.0.1:${previewPort}`);
  await page.waitForFunction(()=>document.querySelector('#rally-name')&&!document.querySelector('#status'),null,{timeout:45000});
  await page.waitForFunction(()=>window.__events.some(event=>event.type==='CONNECTED'));
  await page.evaluate(()=>{const update=window.__rallyNativeInputs;window.__rallyNativeInputs=data=>{window.__formData=structuredClone(data);return update(data);};});
  const baseline=await page.locator('#rally-name').boundingBox();
  assert(baseline.height>=44,'Normal name field has a usable touch height');

  async function aligned(focused) {
    await page.waitForFunction(id=>{
      const data=window.__formData,canvas=document.querySelector('#canvas'),stage=document.querySelector('#rally-stage');
      if(!data||!canvas||!stage)return false;
      const bounds=canvas.getBoundingClientRect(),view=stage.getBoundingClientRect();
      for(const field of data.fields){
        const input=document.getElementById(field.id),rect=input.getBoundingClientRect();
        if(Math.abs(rect.x-(bounds.x+field.rect[0]*bounds.width/data.width))>1.5)return false;
        if(Math.abs(rect.y-(bounds.y+field.rect[1]*bounds.height/data.height))>1.5)return false;
        if(field.id===id&&(rect.top<view.top||rect.bottom>view.bottom||rect.height<44))return false;
      }
      return !id||document.activeElement?.id===id;
    },focused,{timeout:12000});
    assert.equal(await page.locator('#rally-input-layer input').count(),2,'Only one visible field pair exists');
  }

  await page.locator('#rally-name').fill('Mobile Player');
  await page.evaluate(()=>window.__keyboardViewport({height:420,pageTop:100,offsetTop:100}));
  await aligned('rally-name');
  assert(Math.abs((await page.locator('#rally-name').boundingBox()).height-baseline.height)<2,'Keyboard does not shrink the form controls');
  mkdirSync('test-results',{recursive:true});
  await page.screenshot({path:'test-results/keyboard-name.png'});
  await page.locator('#rally-name').press('Enter');
  await aligned('rally-code');
  await page.locator('#rally-code').fill('ABCD-EF12');
  await page.evaluate(()=>window.__keyboardViewport({height:370,pageTop:180,offsetTop:180}));
  await aligned('rally-code');
  assert.equal(await page.locator('#rally-name').inputValue(),'Mobile Player');
  await page.screenshot({path:'test-results/keyboard-code.png'});

  await page.setViewportSize({width:852,height:393});
  await page.evaluate(()=>window.__keyboardViewport({width:852,height:260,pageTop:40,offsetTop:40}));
  await aligned('rally-code');
  await page.locator('#rally-code').press('Enter');
  await page.setViewportSize({width:393,height:852});
  await page.evaluate(()=>window.__keyboardViewport({width:393,height:852,pageTop:0,offsetTop:0}));
  await aligned('');
  await page.waitForFunction(y=>Math.abs(document.querySelector('#rally-name').getBoundingClientRect().y-y)<2,baseline.y);
  await page.screenshot({path:'test-results/keyboard-dismissed.png'});
  assert.equal(await page.locator('#rally-code').inputValue(),'ABCD-EF12','Room code survives keyboard changes');

  // Tap the real canvas button while a browser input still has focus.
  await page.locator('#rally-name').focus();
  await page.evaluate(()=>window.__keyboardViewport({height:420,pageTop:60,offsetTop:60}));
  await aligned('rally-name');
  const button=await page.evaluate(()=>{
    const data=window.__formData,field=data.fields.find(field=>field.id==='rally-name'),bounds=document.querySelector('#canvas').getBoundingClientRect();
    return {x:bounds.x+(field.rect[0]+field.rect[2]/2)*bounds.width/data.width,y:bounds.y+(field.rect[1]+field.rect[3]+22+30)*bounds.height/data.height};
  });
  await page.touchscreen.tap(button.x,button.y);
  await page.waitForFunction(()=>window.__events.some(event=>event.type==='ROOM_CREATED'),null,{timeout:12000});
  await page.waitForFunction(()=>window.__events.some(event=>event.type==='STATE'&&event.state.players[0]?.name==='Mobile Player'));
  await page.waitForFunction(()=>[...document.querySelectorAll('#rally-input-layer input')].every(input=>input.hidden));
  // Confirm the packaged fallback works if the HTML bootstrap is absent.
  const fallback=await context.newPage();
  fallback.on('pageerror',error=>errors.push(error.message));
  fallback.on('console',message=>{if(message.type()==='error')errors.push(message.text());});
  // This page only tests asset fallback; intercept its socket locally so an
  // intercepted navigation doesn't depend on Chrome's local-network permission.
  await fallback.routeWebSocket(`ws://127.0.0.1:${port}/`,socket=>socket.send(JSON.stringify({type:'CONNECTED',playerId:'fallback'})));
  const bridge=readFileSync('apps/godot/web/native_inputs.js','utf8');
  await fallback.route(`http://127.0.0.1:${previewPort}/`,async route=>{
    const response=await route.fetch();
    const original=await response.text();
    const body=original.replace(bridge,'');
    assert.notEqual(body,original,'Fallback test removes the HTML bootstrap');
    await route.fulfill({response,body});
  });
  await fallback.goto(`http://127.0.0.1:${previewPort}`);
  await fallback.waitForFunction(()=>document.querySelector('#rally-name')&&!document.querySelector('#status'),null,{timeout:45000});
  assert.equal(await fallback.locator('#rally-input-layer input').count(),2,'PCK fallback supplies both inputs');
  assert.deepEqual(errors,[],'No browser or Godot runtime errors');
  console.log('Keyboard browser checks passed: Safari-style visual viewport resize/pan, focus changes, rotation, dismissal, preserved values, and real create-room tap.');
} finally {
  await browser?.close();
  children.forEach(child=>child.kill());
}
