// Exercise the real HUD in Chrome: the +N indicator must not kill HandleUpdate.
const {chromium}=require('playwright-core');
const assert=require('node:assert/strict');
(async()=>{
 const b=await chromium.launch({executablePath:process.env.CHROME_PATH||'C:/Program Files/Google/Chrome/Application/chrome.exe',headless:true});
 try{
  const p=await b.newPage(),errors=[];
  p.on('pageerror',e=>errors.push(e.message));
  p.on('console',m=>{if(m.type()==='error')errors.push(m.text())});
  await p.route('**/js/manifest.js',async r=>{
   let s=await(await r.fetch()).text();
   s+='\nDSH.MANIFEST.luaSources.main=DSH.MANIFEST.luaSources.main.replace(/game = Game.New\\(selectedHeroId\\)/g,"game = Game.New(selectedHeroId) _G.__hudRegression = game");';
   await r.fulfill({body:s,contentType:'application/javascript'});
  });
  await p.goto(process.argv[2]||'http://127.0.0.1:8027');
  await p.locator('#menuEndless').click();
  await p.locator('#heroConfirm').click();
  await p.locator('#gameOverlay').waitFor({state:'hidden'});
  const call=async code=>{const r=await p.evaluate(code=>DSH.Engine._fengari.doString('local g=__hudRegression '+code),code);assert(r.ok,r.error);return r.value};
  for(const [width,height,count]of [[1600,900,9],[1600,900,10],[390,844,5],[390,844,6],[1600,900,16]]){
   await p.setViewportSize({width,height});
   await call(`g.buffs={} g.upgrades={} g.player.hp=10000 g.player.maxHp=10000 for i,d in ipairs(require('Buffs').LIST)do if i<=${count}then g.buffs[d.id]=1 end end g.uiRevision=g.uiRevision+1`);
   await p.waitForTimeout(120);const before=await call('return g.time');
   await p.waitForTimeout(350);assert(await call('return g.time')>before+.1,`Update alive at ${count} buffs, ${width}x${height}`);
   if(count===10||count===6||count===16)assert(await p.locator('#hudLayer').getByText('+'+(count-(width===390?5:9)),{exact:true}).count());
  }
  assert.deepEqual(errors,[]);console.log('PASS: desktop 9/10/16 and portrait 5/6 buffs; +N visible and game clock continues');
 }finally{await b.close()}
})().catch(e=>{console.error(e);process.exitCode=1});
