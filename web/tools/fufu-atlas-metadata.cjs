// Read-only measurements of original imagegen PNGs; writes metadata and a standalone viewer.
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { chromium } = require('playwright-core');
const web = path.resolve(__dirname, '..');
const folder = path.join(web, 'assets/image/fufu');
const destination = path.resolve(web, '../../evidence/fufu-art-2026-11-07');
const actorStates = ['idle','walk','downWalk','upWalk','summon','bulbThrow','hurt','cheer'];
const summonStates = ['idle','walk','downWalk','upWalk','attack','defeat'];
const sheets = [
  {id:'fufu',cols:4,rows:8,group:'actors',names:actorStates},
  ...['maple','water','dan','cat','dog'].map(id=>({id,cols:4,rows:6,group:'summons',names:summonStates})),
  {id:'items',cols:4,rows:2,group:'icons'},
  {id:'effects',cols:4,rows:8,group:'effects',names:['summon','claw','water','electric','flash','glass','guard','depart']},
  {id:'buffs',cols:3,rows:4,group:'icons',ids:['snack','checkup','claws','maple','livingWater','protection','teething','waterproof','link','blink','blanket','onDuty']},
  {id:'portrait',cols:4,rows:1,group:'portraits'},
  {id:'status',cols:4,rows:4,group:'effects',names:['wet','bleed','stun','replacement']}
];
function lua(v) {
  if (v === null) return 'nil';
  if (typeof v === 'boolean' || typeof v === 'number') return String(v);
  if (typeof v === 'string') return JSON.stringify(v);
  if (Array.isArray(v)) return '{'+v.map(lua).join(',')+'}';
  return '{'+Object.entries(v).filter(([key])=>!['sha256','hash'].includes(key)).map(([key,val])=>'['+JSON.stringify(key)+']='+lua(val)).join(',')+'}';
}
function viewer(data) {
  return `<!doctype html><html lang="zh-CN"><meta charset="utf-8"><title>符符美术包 · 独立验收预览</title>
<style>*{box-sizing:border-box}body{margin:0;background:#18202b;color:#e9eff5;font:15px system-ui,"Microsoft YaHei",sans-serif;padding:24px}h1{font-size:26px;margin:0 0 8px}p{line-height:1.6;max-width:1100px}label{display:inline-flex;gap:12px;align-items:center;margin:0 24px 18px 0}section{display:grid;grid-template-columns:repeat(auto-fill,minmax(275px,1fr));gap:14px}article{padding:12px;border:1px solid #516076;border-radius:8px;background:#232e3d}h2{font-size:16px;margin:0 0 10px}canvas{image-rendering:pixelated;background:repeating-conic-gradient(#293747 0 25%,#394759 0 50%) 50%/16px 16px}small{display:block;color:#bed0dd;line-height:1.5}.warning{color:#ffcf79}.stage{display:flex;align-items:flex-end;gap:16px}.strip{margin-top:8px;display:flex;gap:3px}.strip canvas{width:48px;height:48px}.group{grid-column:1/-1;margin-top:18px}#status{color:#9ae6bb}</style>
<h1>符符美术包 · 独立验收预览</h1><p>原始 PNG 不改图。动画默认 8 帧／秒，左边为放大检查，右边为游戏小尺寸参考；下方四张是原网格帧。透明背景用棋盘格显示。这里只检查素材与裁切，没有接入战斗；文件非空、帧不同不代表动画连续性已经合格。</p>
<label>播放速度 <input id="fps" type="range" min="2" max="16" value="8"><span id="fpsText">8 帧／秒</span></label><label><input id="play" type="checkbox" checked>播放动画</label><div id="status">正在加载…</div><p class="warning" id="warnings"></p><section id="grid"></section>
<script>const metadata=${JSON.stringify(data).replace(/</g,'\\u003c')};
const names={fufu:'符符',maple:'枫叶',water:'水',dan:'丹',cat:'猫',dog:'狗',items:'物品图标',effects:'技能特效',buffs:'增益图标',portrait:'角色头像（批准图首姿势）',status:'状态特效'};
const actions={idle:'待机',walk:'横向行走',attack:'攻击',skill:'技能',downIdle:'朝下待机',downWalk:'朝下行走',upIdle:'朝上待机',upWalk:'朝上行走',snack:'加餐',checkup:'体检',claws:'爪牙',maple:'枫叶',livingWater:'活水',protection:'守护',teething:'磨牙',waterproof:'防水',link:'串联',blink:'眨眼',blanket:'毯子',onDuty:'值班',bulbThrow:'抛灯泡',hurt:'受伤',cheer:'开心',defeat:'消失／退场',summon:'召唤',claw:'爪击',water:'水花',electric:'电击',flash:'闪光',glass:'玻璃',guard:'守护',depart:'离场',wet:'潮湿',bleed:'流血',stun:'眩晕',replacement:'替换',portrait:'头像（首格）',hudPortrait:'HUD 头像裁切'};
const cards=[],images={};const grid=document.getElementById('grid');let runningFrame=0;
function draw(ctx,image,frame,size,reference,actor,original,referenceWidth){ctx.clearRect(0,0,size,size);ctx.imageSmoothingEnabled=false;const f=original&&frame.cell?frame.cell:frame;if(original){const k=Math.min((size-4)/f.w,(size-4)/f.h);ctx.drawImage(image,f.x,f.y,f.w,f.h,(size-f.w*k)/2,(size-f.h*k)/2,f.w*k,f.h*k);return}const scale=actor?Math.min((size-12)/reference,(size-12)/(referenceWidth||reference)):Math.min((size-12)/f.w,(size-12)/f.h);const x=actor?size/2-(f.anchorX||f.w/2)*scale:(size-f.w*scale)/2;const y=actor?size-6-f.h*scale:(size-f.h*scale)/2;ctx.drawImage(image,f.x,f.y,f.w,f.h,x,y,f.w*scale,f.h*scale);}
function canvas(size){const c=document.createElement('canvas');c.width=size;c.height=size;return c}
(async()=>{for(const [id,d]of Object.entries(metadata.sheets)){const im=new Image();im.src='../assets/'+d.path;await im.decode();images[id]=im;const heading=document.createElement('h2');heading.className='group';heading.dataset.sheet=id;heading.textContent=(names[id]||id)+' · '+d.width+' × '+d.height+' · 透明像素 '+Math.round(d.transparentFraction*100)+'%';grid.appendChild(heading);for(const [state,list]of Object.entries(d.portraitRegion?Object.assign({},d.frames,{hudPortrait:d.portraitRegion}):d.frames)){const frames=Array.isArray(list)?list:[list];const drawDefinition=state==='hudPortrait'?Object.assign({},d,{actor:false,effect:false}):d;const article=document.createElement('article');article.dataset.sheet=id;const title=document.createElement('h2');title.textContent=actions[state]||state.replace(/^item/,'物品 ').replace(/^buff/,'增益 ');article.appendChild(title);const stage=document.createElement('div');stage.className='stage';const large=canvas(160),small=canvas(64);stage.append(large,small);article.appendChild(stage);const text=document.createElement('small');text.textContent=frames.length+' 帧 · 实际参考64px · '+(drawDefinition.actor?'脚底对齐、统一比例':drawDefinition.effect?'固定原网格比例':'内容框等比缩放');article.appendChild(text);const strip=document.createElement('div');strip.className='strip';for(const f of frames){const c=canvas(48);draw(c.getContext('2d'),im,f,48,d.referenceHeight,d.actor,true);strip.appendChild(c)}article.appendChild(strip);grid.appendChild(article);cards.push({im,frames,large,small,d:drawDefinition})}}document.getElementById('warnings').textContent=metadata.warnings.length?metadata.warnings.length+' 条自动检查提示：'+metadata.warnings.slice(0,6).map(x=>x.sheet+' '+x.code).join('；'):'未发现自动几何检查警告；视觉连续性仍需人工判断。';document.getElementById('status').textContent='已加载 '+Object.keys(images).length+' 张原图；'+metadata.errors.length+' 条阻塞问题';window.FUFU_REVIEW={ready:true,cards:cards.length,errors:metadata.errors,warnings:metadata.warnings};document.body.dataset.ready='true';requestAnimationFrame(loop)})().catch(e=>{document.getElementById('status').textContent=String(e);window.FUFU_REVIEW={ready:false,error:String(e)}});
function loop(now){const fps=Number(document.getElementById('fps').value);document.getElementById('fpsText').textContent=fps+' 帧／秒';if(document.getElementById('play').checked)runningFrame=Math.floor(now*fps/1000);for(const c of cards){const f=c.frames[runningFrame%c.frames.length];draw(c.large.getContext('2d'),c.im,f,160,c.d.referenceHeight,c.d.actor,c.d.effect,c.d.referenceWidth);draw(c.small.getContext('2d'),c.im,f,64,c.d.referenceHeight,c.d.actor,c.d.effect,c.d.referenceWidth)}requestAnimationFrame(loop)}
</script></html>`;
}
(async()=>{
  fs.mkdirSync(folder,{recursive:true});fs.mkdirSync(destination,{recursive:true});
  const result={schemaVersion:1,stage:process.argv.includes('--final')?'candidate-for-review':'preflight',note:'Original PNG only; geometry checks are not proof of visual animation continuity.',sheets:{},errors:[],warnings:[]};
  const browser=await chromium.launch({executablePath:process.env.CHROME_PATH||'C:/Program Files/Google/Chrome/Application/chrome.exe',headless:true});
  try{
    let page=await browser.newPage();
    for(const cfg of sheets){
      const file=path.join(folder,cfg.id+'.png');
      if(!fs.existsSync(file)){result.errors.push({sheet:cfg.id,code:'missing_file'});continue}
      const bytes=fs.readFileSync(file);
      const measured=await page.evaluate(async cfg=>{
        const im=new Image();im.src='data:image/png;base64,'+cfg.base64;await im.decode();
        const c=document.createElement('canvas');c.width=im.width;c.height=im.height;const ctx=c.getContext('2d',{willReadFrequently:true});ctx.drawImage(im,0,0);
        const pixels=ctx.getImageData(0,0,im.width,im.height).data;let transparent=0,partial=0;
        for(let i=3;i<pixels.length;i+=4){if(pixels[i]<8)transparent++;else if(pixels[i]<248)partial++}
        const frames=[],rowBounds=[0],adaptive=cfg.group==='actors'||cfg.group==='summons'||cfg.group==='effects'||cfg.id==='buffs',seamAlpha=cfg.group==='effects'?224:16;
        for(let row=1;row<cfg.rows;row++){
          const expected=Math.round(row*im.height/cfg.rows),radius=Math.round(im.height/cfg.rows*(cfg.group==='effects'?.48:.32));
          if(!adaptive){rowBounds.push(expected);continue}
          const counts=[];let minimum=Infinity;
          for(let yy=Math.max(1,expected-radius);yy<Math.min(im.height-1,expected+radius);yy++){
            let count=0;for(let xx=0;xx<im.width;xx++)if(pixels[(yy*im.width+xx)*4+3]>seamAlpha)count++;
            counts.push({y:yy,count});minimum=Math.min(minimum,count);
          }
          const runs=[];let start=-1;
          for(let i=0;i<=counts.length;i++){if(i<counts.length&&counts[i].count===minimum){if(start<0)start=i}else if(start>=0){runs.push({start:counts[start].y,end:counts[i-1].y});start=-1}}
          runs.sort((a,b)=>(b.end-b.start)-(a.end-a.start)||Math.abs((a.start+a.end)/2-expected)-Math.abs((b.start+b.end)/2-expected));
          rowBounds.push(Math.round((runs[0].start+runs[0].end)/2));
        }
        rowBounds.push(im.height);
        const columnBounds=[];
        for(let row=0;row<cfg.rows;row++){
          const bounds=[0];
          for(let col=1;col<cfg.cols;col++){
            const expected=Math.round(col*im.width/cfg.cols),radius=Math.round(im.width/cfg.cols*.3);
            if(!adaptive){bounds.push(expected);continue}
            const counts=[];let minimum=Infinity;
            for(let xx=Math.max(1,expected-radius);xx<Math.min(im.width-1,expected+radius);xx++){
              let count=0;for(let yy=rowBounds[row];yy<rowBounds[row+1];yy++)if(pixels[(yy*im.width+xx)*4+3]>seamAlpha)count++;
              counts.push({x:xx,count});minimum=Math.min(minimum,count);
            }
            const runs=[];let start=-1;
            for(let i=0;i<=counts.length;i++){if(i<counts.length&&counts[i].count===minimum){if(start<0)start=i}else if(start>=0){runs.push({start:counts[start].x,end:counts[i-1].x});start=-1}}
            runs.sort((a,b)=>(b.end-b.start)-(a.end-a.start)||Math.abs((a.start+a.end)/2-expected)-Math.abs((b.start+b.end)/2-expected));
            bounds.push(Math.round((runs[0].start+runs[0].end)/2));
          }
          bounds.push(im.width);columnBounds.push(bounds);
        }
        for(let row=0;row<cfg.rows;row++)for(let col=0;col<cfg.cols;col++){
          const x=columnBounds[row][col],y=rowBounds[row],w=columnBounds[row][col+1]-x,h=rowBounds[row+1]-y;
          let l=w,t=h,r=-1,b=-1,count=0,edgePixels=0,hash=2166136261;
          for(let yy=0;yy<h;yy++)for(let xx=0;xx<w;xx++){
            const i=((y+yy)*im.width+x+xx)*4;
            if(pixels[i+3]>16){l=Math.min(l,xx);r=Math.max(r,xx);t=Math.min(t,yy);b=Math.max(b,yy);count++;if(xx===0||yy===0||xx===w-1||yy===h-1)edgePixels++}
            for(let k=0;k<4;k++)hash=Math.imul(hash^(pixels[i+3]<8?0:pixels[i+k]),16777619)>>>0;
          }
          let footL=w,footR=-1;
          if(count)for(let yy=Math.max(t,b-Math.round((b-t+1)*.1));yy<=b;yy++)for(let xx=l;xx<=r;xx++)if(pixels[((y+yy)*im.width+x+xx)*4+3]>16){footL=Math.min(footL,xx);footR=Math.max(footR,xx)}
          frames.push({x:x+(count?l:0),y:y+(count?t:0),w:count?r-l+1:0,h:count?b-t+1:0,anchorX:count?(footL+footR+1)/2-l:0,anchorY:count?b-t+1:0,cell:{x,y,w,h},opaquePixels:count,edgePixels,hash});
        }
        return{width:im.width,height:im.height,transparentFraction:transparent/(im.width*im.height),partialAlphaFraction:partial/(im.width*im.height),rowBounds,columnBounds,frames};
      },{...cfg,base64:bytes.toString('base64')});
      const d={key:cfg.id,path:'image/fufu/'+cfg.id+'.png',cols:cfg.cols,rows:cfg.rows,width:measured.width,height:measured.height,transparentFraction:measured.transparentFraction,partialAlphaFraction:measured.partialAlphaFraction,rowBounds:measured.rowBounds,columnBounds:measured.columnBounds,gridMethod:(cfg.group==='actors'||cfg.group==='summons'||cfg.group==='effects'||cfg.id==='buffs')?'alpha-projection-row-and-column-seams':'uniform',actor:cfg.group==='actors'||cfg.group==='summons',effect:cfg.group==='effects',sha256:crypto.createHash('sha256').update(bytes).digest('hex'),frames:{}};
      if(d.transparentFraction<.1)result.errors.push({sheet:cfg.id,code:'insufficient_transparency',fraction:d.transparentFraction});
      for(let i=0;i<measured.frames.length;i++){
        const f=measured.frames[i];
        if(f.opaquePixels<12)result.errors.push({sheet:cfg.id,code:'empty_cell',row:Math.floor(i/cfg.cols)+1,col:i%cfg.cols+1});
        if(f.edgePixels>2&&!(cfg.id==='portrait'&&i>0))result.warnings.push({sheet:cfg.id,code:'content_touches_cell_boundary',severity:cfg.id==='effects'?'soft_glow_review':'review',row:Math.floor(i/cfg.cols)+1,col:i%cfg.cols+1,edgePixels:f.edgePixels});
        if(f.x<0||f.y<0||f.x+f.w>d.width||f.y+f.h>d.height)result.errors.push({sheet:cfg.id,code:'out_of_bounds',frame:i+1});
      }
      if(cfg.names){
        for(let row=0;row<cfg.rows;row++){
          const frames=measured.frames.slice(row*cfg.cols,(row+1)*cfg.cols);d.frames[cfg.names[row]]=frames;
          if(new Set(frames.map(f=>f.hash)).size<2)result.warnings.push({sheet:cfg.id,code:'identical_animation_frames',state:cfg.names[row]});
          const heights=frames.map(f=>f.h);if(!['defeat','flash','depart','guard','glass'].includes(cfg.names[row])&&Math.max(...heights)>Math.max(1,Math.min(...heights))*1.3)result.warnings.push({sheet:cfg.id,code:'height_variation_above_30_percent',expectedEffectGrowth:cfg.group==='effects',state:cfg.names[row],heights});
        }
      }else if(cfg.id==='portrait'){d.frames.portrait=measured.frames[0];d.sourcePoseCount=4;d.note='Approved four-pose source; only the first cell is the portrait.';}else measured.frames.forEach((f,i)=>d.frames[cfg.ids?cfg.ids[i]:(cfg.id==='items'?'item':'buff')+String(i+1).padStart(2,'0')]=f);
      d.referenceHeight=Math.round((d.frames.idle||measured.frames).reduce((sum,f)=>sum+f.h,0)/(d.frames.idle||measured.frames).length);
      if(cfg.id==='fufu'){d.frames.skill=d.frames.summon;d.frames.attack=d.frames.bulbThrow;d.frames.upIdle=[d.frames.upWalk[0]];d.animationAliases={skill:'summon',attack:'bulbThrow',upIdle:'upWalk:firstFrame'};d.note='No independent back idle sequence; upIdle reuses first back-walk frame.';}
      if(cfg.id==='dan'){d.frames.guard=d.frames.attack;d.animationAliases={guard:'attack'};}
      if(cfg.group==='summons')d.portraitRegion={...d.frames.idle[0],note:'Runtime crop of first idle frame; no new bitmap.'};
      if(cfg.id==='portrait'){const f=d.frames.portrait;d.portraitRegion={x:f.x,y:f.y,w:f.w,h:Math.round(f.h*.43),note:'Manually reviewed head box: upper 43 percent of approved first pose; no PNG edits.'};}
      d.referenceWidth=Math.max(...measured.frames.map(f=>f.w));
      result.sheets[cfg.id]=d;
      console.log(cfg.id, d.width+'x'+d.height, 'transparent='+d.transparentFraction.toFixed(3));
    }
    fs.writeFileSync(path.join(folder,'atlas-metadata.json'),JSON.stringify(result,null,2));
    fs.writeFileSync(path.join(web,'lua/FufuArt.lua'),'-- Measured original fufu PNG regions. Regenerate via tools/fufu-atlas-metadata.cjs.\nreturn '+lua(result)+'\n');
    fs.mkdirSync(path.join(web,'dev'),{recursive:true});
    fs.writeFileSync(path.join(web,'dev/fufu-preview.html'),viewer(result));
    fs.writeFileSync(path.join(destination,'geometry-report.json'),JSON.stringify({sheets:Object.keys(result.sheets),errors:result.errors,warnings:result.warnings},null,2));
    if(process.argv.includes('--capture')){
      await page.close();
      const captureContext=await browser.newContext({viewport:{width:1600,height:1100},recordVideo:{dir:destination,size:{width:1600,height:1100}}});page=await captureContext.newPage();
      const errors=[];page.on('pageerror',error=>errors.push(String(error)));await page.setViewportSize({width:1600,height:1100});
      await page.goto('file:///'+path.join(web,'dev/fufu-preview.html').replace(/\\/g,'/'));await page.waitForFunction(()=>window.FUFU_REVIEW&&window.FUFU_REVIEW.ready,null,{timeout:15000});
      await page.screenshot({path:path.join(destination,'符符美术包-动画与小尺寸.png'),fullPage:true});
      for(const id of Object.keys(result.sheets)){
        const bounds=await page.evaluate(id=>{
          const elements=Array.from(document.querySelectorAll('[data-sheet="'+id+'"]'));
          const rects=elements.map(e=>e.getBoundingClientRect());
          const y=Math.max(0,Math.floor(Math.min(...rects.map(r=>r.y))+window.scrollY-8));
          const bottom=Math.ceil(Math.max(...rects.map(r=>r.bottom))+window.scrollY+8);
          return{x:0,y,width:1600,height:bottom-y};
        },id);
        const scroll=await page.evaluate(y=>{window.scrollTo(0,y);return window.scrollY},bounds.y);
        const top=bounds.y-scroll;
        await page.screenshot({path:path.join(destination,id+'-预览.png'),clip:{x:0,y:top,width:1600,height:Math.min(1100-top,bounds.height)}});
      }
      fs.writeFileSync(path.join(destination,'browser-report.json'),JSON.stringify({review:await page.evaluate(()=>window.FUFU_REVIEW),browserErrors:errors},null,2));
      for(const id of ['fufu','maple','dan','dog','cat','effects','status']){await page.locator('h2[data-sheet="'+id+'"]').scrollIntoViewIfNeeded();await page.waitForTimeout(1800)}
      const video=page.video();await captureContext.close();await video.saveAs(path.join(destination,'符符美术包-8帧每秒.webm'));
    }
    console.log('sheets='+Object.keys(result.sheets).length+' errors='+result.errors.length+' warnings='+result.warnings.length);
    if(result.errors.length&&!process.argv.includes('--allow-partial'))process.exitCode=2;
  }finally{await browser.close()}
})().catch(error=>{console.error(error);process.exitCode=1});
