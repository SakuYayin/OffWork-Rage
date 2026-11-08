const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict'),{chromium}=require('playwright-core');
(async()=>{const b=await chromium.launch({executablePath:process.env.CHROME_PATH||'C:/Program Files/Google/Chrome/Application/chrome.exe',headless:true});try{
 const dir=path.resolve('../evidence/balance-server-2026-11-07');fs.mkdirSync(dir,{recursive:true});const p=await b.newPage(),errors=[];
 p.on('pageerror',e=>errors.push(e.message));p.on('console',m=>{if(m.type()==='error'&&!m.text().includes('404'))errors.push(m.text())});
 await p.route('**/js/manifest.js',async r=>{let s=await(await r.fetch()).text();s+='\nDSH.MANIFEST.luaSources.main=DSH.MANIFEST.luaSources.main.replace(/game = Game.New\\(selectedHeroId\\)/g,"game = Game.New(selectedHeroId) _G.__resultsTest = game");';await r.fulfill({body:s,contentType:'application/javascript'})});
 await p.goto(process.argv[2]||'http://127.0.0.1:8031');await p.locator('#menuEndless').click();await p.locator('#heroConfirm').click();
 const call=async s=>{const r=await p.evaluate(s=>DSH.Engine._fengari.doString('local g=__resultsTest '+s),s);assert(r.ok,r.error);return r.value};
 await call('g.time=500 g.kills=200 g.level=10 g.endless.wave=12 g.endless.bossLevel=4 require("Endless").OnDeath(g) g.mode="endlessResult" g.nickDraft="" g.uiRevision=g.uiRevision+1');await p.locator('#scoreNameInput').waitFor();
 const name='下班玩家 Abc123 测试中文昵称超过十二位';await p.locator('#scoreNameInput').fill(name);assert.equal(await call('return g.nickDraft'),name);assert.equal(await p.locator('#scoreNameInput').getAttribute('maxlength'),null);
 await p.locator('#scoreNameInput').evaluate(el=>{el.dispatchEvent(new CompositionEvent('compositionstart',{bubbles:true,data:''}));el.value='输入法组合';el.dispatchEvent(new InputEvent('input',{bubbles:true,data:'输入法组合',isComposing:true}));});assert.equal(await call('return g.nickDraft'),name,'IME draft not prematurely consumed');
 await p.locator('#scoreNameInput').evaluate(el=>el.dispatchEvent(new CompositionEvent('compositionend',{bubbles:true,data:'输入法组合'})));assert.equal(await call('return g.nickDraft'),'输入法组合');
 await p.locator('#scoreNameInput').fill(name);await p.keyboard.press('Enter');assert.equal(await call('return g.scoreSubmitted==true'),false,'Enter in input must not submit or restart');
 const report={errors,agentAutomation:true,headlessChrome:true,fixture:'Injected end-of-run values in local test server; not a natural completed run',nativeInput:true,compositionEvents:true,compositionEventsAreSynthetic:true,physicalMobileKeyboardTested:false,noTwelveCharacterLimit:true,viewports:[]};
 for(const [w,h,label]of[[1600,900,'电脑'],[390,844,'手机竖屏'],[320,650,'小屏'],[844,390,'手机横屏']]){await p.setViewportSize({width:w,height:h});await p.waitForTimeout(150);for(const id of['endlessLeaderboard','endlessAgain','endlessMenu']){const r=await p.locator('#'+id).boundingBox();assert(r&&r.x>=0&&r.y>=0&&r.x+r.width<=w+1&&r.y+r.height<=h+1,id+' visible '+label);}await p.locator('#scoreSubmit').scrollIntoViewIfNeeded();await p.screenshot({path:path.join(dir,label+'-原生昵称结算.png')});const form=await p.locator('#scoreSubmit').boundingBox();assert(form&&form.y>=0&&form.y+form.height<=h+1,'Confirmation accessible '+label);report.viewports.push({w,h,label,confirmVisible:true});}
 if(process.env.TEST_SCORE_SUBMIT==='1'){
  assert.equal(await call('return require("Leaderboard").MODE'),'server','real backend must be enabled');
  await p.route('**/api/leaderboard',async r=>{if(r.request().method()==='POST'){await r.fulfill({status:503,contentType:'application/json',body:'{"error":"测试连接中断"}'});await p.unroute('**/api/leaderboard');}else await r.continue()});
  await p.locator('#scoreNameInput').fill(name);await p.locator('#scoreSubmit').click();await p.locator('#scoreSubmitMessage').filter({hasText:/测试连接中断|503|失败/}).waitFor();
  assert.equal(await call('return g.scoreSubmitted==true'),false);assert.equal(await p.locator('#scoreNameInput').inputValue(),name);report.failurePreservesDraft=true;
  // The deliberate 503 is an expected network error, not an application exception.
  errors.splice(0,errors.length,...errors.filter(e=>!e.includes('503')));
  await p.locator('#scoreSubmit').click();await p.locator('#scoreSubmitMessage').filter({hasText:/已上榜|成绩已记录/}).waitFor({timeout:20000});assert.equal(await call('return g.scoreSubmitted'),true);report.realSubmit=true;
  await p.locator('#endlessLeaderboard').click();await p.locator('#lbCampaignTab').waitFor();await p.waitForTimeout(150);await p.locator('#lbCampaignTab').click();await p.waitForTimeout(200);await p.locator('#lbClose').click();await p.locator('#resultSheet').waitFor();assert.equal(await call('return g.mode'),'endlessResult');
  await p.locator('#endlessMenu').click();await p.locator('#menuStart').click();await p.locator('#heroConfirm').click();
  await call('g.time=321.9 g.kills=123 g.level=8 g.roomsCleared=14 g.bossesDefeated=3 g.mode="won" g.uiRevision=g.uiRevision+1');await p.locator('#scoreNameInput').fill('战役测试 眼镜妹 2026');
  const req=p.waitForRequest(r=>r.url().endsWith('/api/leaderboard')&&r.method()==='POST');await p.locator('#scoreSubmit').click();const payload=(await req).postDataJSON();assert.equal(payload.mode,'campaign');assert.equal(payload.time,321);assert.equal(payload.score,1000*14+1500*3+12*123+40*8+3*321);
  await p.locator('#scoreSubmitMessage').filter({hasText:/已上榜|成绩已记录/}).waitFor();report.campaignSubmit=true;
  await p.locator('#endlessLeaderboard').click();await p.locator('#lbClose').click();await p.locator('#resultSheet').waitFor();assert.equal(await call('return g.mode'),'won');report.resultsReturnPreserved=true;
 }
 assert.deepEqual(errors,[]);fs.writeFileSync(path.join(dir,'native-input-ui.json'),JSON.stringify(report,null,2));console.log('PASS: native Unicode/IME entry, explicit confirmation and fixed responsive actions');
}finally{await b.close()}})().catch(e=>{console.error(e);process.exitCode=1});
