(function () {
  'use strict';
  window.DSH=window.DSH||{};
  var root=document.documentElement, pending=false;
  // Cache event-driven viewport measurements; Lua reads this without layout work.
  function update(){
    pending=false;var v=window.visualViewport;
    var w=Math.round(v?v.width:window.innerWidth),h=Math.round(v?v.height:window.innerHeight);
    var active=document.activeElement,editing=active&&/^(INPUT|TEXTAREA)$/.test(active.tagName);
    var keyboard=!!(editing&&h<window.innerHeight*.78);
    var old=window.DSH.Viewport,next={width:w,height:h,left:v?v.offsetLeft:0,top:v?v.offsetTop:0,keyboardOpen:keyboard};
    window.DSH.Viewport=next;
    root.style.setProperty('--game-width',w+'px');root.style.setProperty('--game-height',h+'px');
    root.style.setProperty('--game-left',(v?v.offsetLeft:0)+'px');root.style.setProperty('--game-top',(v?v.offsetTop:0)+'px');
    root.classList.toggle('native-keyboard-open',keyboard);
    root.classList.toggle('mobile-landscape',w>h);
    if(!old||old.width!==w||old.height!==h||old.left!==next.left||old.top!==next.top)window.dispatchEvent(new CustomEvent('gameviewportchange'));
  }
  function schedule(){if(!pending){pending=true;requestAnimationFrame(update);}}
  update();window.addEventListener('resize',schedule);window.addEventListener('orientationchange',schedule);
  document.addEventListener('focusin',schedule);document.addEventListener('focusout',schedule);
  if(window.visualViewport){visualViewport.addEventListener('resize',schedule);visualViewport.addEventListener('scroll',schedule);}
  var button=document.createElement('button');button.id='mobileDisplayButton';button.type='button';
  button.textContent='横屏 / 全屏';button.setAttribute('aria-label','尝试全屏横屏显示');
  var hint=document.createElement('div');hint.id='mobileDisplayHint';hint.hidden=true;hint.setAttribute('role','status');
  var text=document.createElement('p'),close=document.createElement('button');close.type='button';close.textContent='知道了';
  close.addEventListener('click',function(){hint.hidden=true;});hint.appendChild(text);hint.appendChild(close);
  document.body.appendChild(button);document.body.appendChild(hint);
  function show(message){text.textContent=message;hint.hidden=false;}
  button.addEventListener('click',async function(){
    hint.hidden=true;var app=document.getElementById('app');
    // The fullscreen request starts synchronously inside this user gesture.
    try {
      if(!document.fullscreenElement){
        if(!app.requestFullscreen)throw new Error('unsupported_fullscreen');
        await app.requestFullscreen();
      }
      if(!screen.orientation||!screen.orientation.lock)throw new Error('unsupported_orientation');
      await screen.orientation.lock('landscape');
      show('已请求横屏。退出全屏可使用浏览器的返回或退出全屏操作。');
    }catch(e){
      show('浏览器未能自动横屏。请关闭手机的竖屏方向锁定，再把手机横过来。仍不能横屏时，请在系统浏览器打开试玩链接。');
    }
    schedule();
  });
  // Keep the control available after #app enters fullscreen (outside nodes hide).
  document.addEventListener('fullscreenchange',function(){
    var host=document.fullscreenElement||document.body;host.appendChild(button);host.appendChild(hint);schedule();
  });
})();
