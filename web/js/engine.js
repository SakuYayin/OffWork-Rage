/*
 * OffWork-Rage web — engine.js
 * Core assembly layer: fengari bootstrapping, require loader, engine globals,
 * event pump, input mapping, asset preload, rAF main loop.
 * Depends (loaded before this file):
 *   window.fengari        (vendor/fengari-web.js 0.1.4)
 *   window.DSH.MANIFEST   ({ luaSources: {name: source}, assets: {images, audio, fonts} })
 *   window.DSH.Nvg        (Canvas2D NanoVG backend)
 *   window.DSH.AudioShim  ({ getResource, Scene, unlock, load })
 *   window.DSH.UrhoxUI    (optional at boot; degraded with a warn if missing)
 * Exposes window.DSH.Engine. ES2020, no build step, no npm deps.
 */
(function () {
  'use strict';

  window.DSH = window.DSH || {};
  if (window.DSH.Engine) { return; } // idempotent double-load guard

  var api = {};
  var TAG = '[Engine] ';

  // ------------------------------------------------------------------ state
  var state = {
    booted: false, stopped: false, autoRan: false,
    rafId: 0, lastTime: 0, loopStarted: false,
    dpr: 1, canvas: null,
    subs: [],            // { eventType, handler, dead }
    keyState: Object.create(null),
    audioUnlocked: false,
    testResult: undefined,
    bootPromise: null
  };

  // ------------------------------------------------- key constants (JS side)
  // Lua receives the SAME numbers through the KEY_* globals defined below.
  var KEY = {
    BACKSPACE: 8, TAB: 9, RETURN: 13, ESCAPE: 27, SPACE: 32, DELETE: 46,
    SHIFT: 16, LSHIFT: 160, RSHIFT: 161,
    CTRL: 17, LCTRL: 162, RCTRL: 163, ALT: 18,
    LEFT: 37, UP: 38, RIGHT: 39, DOWN: 40
  };
  (function () {
    var i;
    for (i = 48; i <= 57; i++) { KEY['KEY_' + String.fromCharCode(i)] = i; } // KEY_0..KEY_9
    for (i = 65; i <= 90; i++) { KEY['KEY_' + String.fromCharCode(i)] = i; } // KEY_A..KEY_Z
  })();
  // friendly aliases used by the contract
  KEY.KEY_1 = 49; KEY.KEY_2 = 50; KEY.KEY_3 = 51;
  KEY.KEY_A = 65; KEY.KEY_C = 67; KEY.KEY_D = 68; KEY.KEY_E = 69;
  KEY.KEY_P = 80; KEY.KEY_R = 82; KEY.KEY_S = 83; KEY.KEY_W = 87;
  KEY.KEY_RETURN = 13; KEY.KEY_ESCAPE = 27; KEY.KEY_SPACE = 32;
  KEY.KEY_LEFT = 37; KEY.KEY_UP = 38; KEY.KEY_RIGHT = 39; KEY.KEY_DOWN = 40;
  KEY.KEY_SHIFT = 16; KEY.KEY_LSHIFT = 160; KEY.KEY_RSHIFT = 161;

  var CODE2KEY = {
    Backspace: [8], Tab: [9], Enter: [13], NumpadEnter: [13], Escape: [27],
    Space: [32], Delete: [46],
    ShiftLeft: [16, 160], ShiftRight: [16, 161],
    ControlLeft: [17, 162], ControlRight: [17, 163], AltLeft: [18], AltRight: [18],
    ArrowLeft: [37], ArrowUp: [38], ArrowRight: [39], ArrowDown: [40]
  };
  (function () {
    var i, c;
    for (i = 0; i <= 9; i++) { CODE2KEY['Digit' + i] = [48 + i]; }
    for (i = 0; i < 26; i++) { c = String.fromCharCode(65 + i); CODE2KEY['Key' + c] = [65 + i]; }
  })();

  // ------------------------------------------------------------ fengari refs
  var F = null, L = null, lua = null, lauxlib = null, interop = null, tl = null;

  function initFengari() {
    F = window.fengari;
    if (!F || !F.L) { throw new Error('window.fengari missing — load vendor/fengari-web.js before engine.js'); }
    L = F.L; lua = F.lua; lauxlib = F.lauxlib; interop = F.interop; tl = F.to_luastring;
  }

  // ------------------------------------------------------- lua helpers
  function jsToLua(L2, v) {
    if (v === undefined || v === null) { lua.lua_pushnil(L2); }
    else if (typeof v === 'number') { lua.lua_pushnumber(L2, v); }
    else if (typeof v === 'string') { lua.lua_pushstring(L2, tl(v)); }
    else if (typeof v === 'boolean') { lua.lua_pushboolean(L2, v ? 1 : 0); }
    else { interop.push(L2, v); }
  }

  function luaRaise(L2, msg) {
    lua.lua_pushstring(L2, tl(String(msg)));
    return lua.lua_error(L2);
  }

  // Wrap a plain JS function as a Lua C function.
  // Lua args -> JS args (interop.tojs). Array return -> multiple Lua returns.
  function makeTrampoline(name, jsFn) {
    return function (L2) {
      var n = lua.lua_gettop(L2), args = new Array(n), i, r;
      for (i = 0; i < n; i++) { args[i] = interop.tojs(L2, i + 1); }
      try { r = jsFn.apply(null, args); }
      catch (e) { return luaRaise(L2, name + ': ' + ((e && e.message) || e)); }
      if (Array.isArray(r)) {
        for (i = 0; i < r.length; i++) { jsToLua(L2, r[i]); }
        return r.length;
      }
      jsToLua(L2, r);
      return 1;
    };
  }

  // C-function method for a native Lua table: Lua colon call obj:m(a, b)
  // arrives as (obj, a, b) — drop the leading self before invoking JS.
  function makeMethodTrampoline(name, jsFn) {
      // cclosure with the owner table as upvalue 1: a colon call obj:m(a)
      // arrives as (obj, a); a dot call obj.m(a) arrives as (a) — rawequal
      // slot 1 against the owner to decide whether to drop it.
      return function (L2) {
        var drop = 0;
        if (lua.lua_gettop(L2) >= 1 && lua.lua_rawequal(L2, 1, lua.lua_upvalueindex(1)) === 1) { drop = 1; }
        var n = lua.lua_gettop(L2), cnt = n - drop, args = new Array(Math.max(0, cnt)), i, r, j;
        for (i = 0; i < cnt; i++) { args[i] = interop.tojs(L2, drop + i + 1); }
        try { r = jsFn.apply(null, args); }
        catch (e) { return luaRaise(L2, name + ': ' + ((e && e.message) || e)); }
        if (Array.isArray(r) && arrayReturns.has(jsFn)) {
          for (j = 0; j < r.length; j++) { jsToLua(L2, r[j]); }
          return r.length;
        }
        jsToLua(L2, r);
        return 1;
      };
  }

  // Install a native Lua table global with cfunction methods + plain props.
  // Native tables make property writes (graphics.windowTitle = x) plain
  // table access and return real nil for JS undefined.
  function pushNativeObj(name, spec) {
    lua.lua_createtable(L, 0, 8);
    var idx = lua.lua_gettop(L);
    var mk = spec.methods ? Object.keys(spec.methods) : [];
    var pk = spec.props ? Object.keys(spec.props) : [];
    var i;
    // each closure carries its owner table as upvalue 1; rawequal slot 1 vs
    // upvalue 1 decides whether the call is a colon call (drop self) or dot
    // call (keep all args)
    for (i = 0; i < mk.length; i++) {
      lua.lua_pushvalue(L, idx);
      lua.lua_pushcclosure(L, makeMethodTrampoline(mk[i], spec.methods[mk[i]]), 1);
      lua.lua_setfield(L, idx, tl(mk[i]));
    }
    for (i = 0; i < pk.length; i++) {
      jsToLua(L, spec.props[pk[i]]);
      lua.lua_setfield(L, idx, tl(pk[i]));
    }
    lua.lua_setglobal(L, tl(name));
  }

  // methods whose JS return (an Array) must expand to multiple Lua returns
  var arrayReturns = new WeakSet();
  // owner-table registry for rawequal self-detection inside makeMethodTrampoline
  var ownerTables = new WeakSet();

  function pushFnGlobal(name, jsFn) {
    lua.lua_pushcfunction(L, makeTrampoline(name, jsFn));
    lua.lua_setglobal(L, tl(name));
  }
  function pushObjGlobal(name, obj) {
    interop.push(L, obj);
    lua.lua_setglobal(L, tl(name));
  }
  function pushNumGlobal(name, n) {
    lua.lua_pushinteger(L, n);
    lua.lua_setglobal(L, tl(name));
  }

  // dostring with proper error reporting. Returns {ok} or {ok:false,error}.
  // With wantValue, returns {ok, value} for the chunk's first return value.
  function doStringProtected(src, chunkName, wantValue) {
    var buf = tl(src);
    var rc = lauxlib.luaL_loadbuffer(L, buf, buf.length, tl('@' + (chunkName || 'engine-chunk')));
    if (rc !== lua.LUA_OK) {
      var le = lua.lua_tojsstring(L, -1); lua.lua_pop(L, 1);
      return { ok: false, error: 'load ' + (chunkName || 'chunk') + ': ' + le };
    }
    rc = lua.lua_pcall(L, 0, wantValue ? 1 : 0, 0);
    if (rc !== lua.LUA_OK) {
      var re = lua.lua_tojsstring(L, -1); lua.lua_pop(L, 1);
      return { ok: false, error: 'run ' + (chunkName || 'chunk') + ': ' + re };
    }
    if (wantValue) {
      var v = interop.tojs(L, -1);
      lua.lua_pop(L, 1);
      return { ok: true, value: v };
    }
    return { ok: true };
  }

    function callGlobalFn(name) {
    var base = lua.lua_gettop(L);
    lua.lua_getglobal(L, tl(name));
    if (lua.lua_type(L, -1) !== lua.LUA_TFUNCTION) {
      lua.lua_settop(L, base);
      return { ok: false, error: 'no global function ' + name + '()' };
    }
    // message handler below the function: debug.traceback(err) keeps Lua frames for JS-thrown errors
    lua.lua_pushcfunction(L, function (Ln) {
      lua.lua_getglobal(Ln, tl('debug'));
      lua.lua_getfield(Ln, -1, tl('traceback'));
      lua.lua_pushvalue(Ln, 1);
      lua.lua_call(Ln, 1, 1);
      lua.lua_remove(Ln, -2);
      return 1;
    });
    lua.lua_insert(L, -2); // [msgh, fn]
    var msgh = lua.lua_gettop(L) - 1;
    var rc = lua.lua_pcall(L, 0, 0, msgh);
    var e = '';
    if (rc !== lua.LUA_OK) { e = lua.lua_tojsstring(L, -1) || 'pcall failed'; }
    lua.lua_settop(L, base); // restore stack no matter what
    if (rc !== lua.LUA_OK) {
      return { ok: false, error: name + '() error: ' + e };
    }
    return { ok: true };
  }

  // ------------------------------------------------------------- event data
  function eventData(props) {
    return {
      GetFloat: function (k) { var v = props[k]; return typeof v === 'number' ? v : undefined; },
      GetInt: function (k) { var v = props[k]; return typeof v === 'number' ? v : undefined; },
      GetBool: function (k) { var v = props[k]; return typeof v === 'boolean' ? v : undefined; },
      GetString: function (k) { var v = props[k]; return typeof v === 'string' ? v : undefined; }
    };
  }

  // ------------------------------------------------------------- event pump
  // sub.handler: {ref:N} registry ref | {global:'Name'} | string name (legacy)
  function jsSubscribe() {
    var a = Array.prototype.slice.call(arguments);
    var eventType = null, fnIdx = -1, name = null;
    function isCallable(v) { return typeof v === 'function' || (v != null && typeof v === 'object'); }
    // shapes: (type, fn) (type, "GlobalName") (target, type, fn) (target, type, "GlobalName")
    if (typeof a[0] === 'string' && (isCallable(a[1]) || typeof a[1] === 'string')) {
      eventType = a[0]; if (isCallable(a[1])) fnIdx = 1; else name = a[1];
    } else if (a.length >= 3 && typeof a[1] === 'string' && (isCallable(a[2]) || typeof a[2] === 'string')) {
      eventType = a[1]; if (isCallable(a[2])) fnIdx = 2; else name = a[2];
    }
    if (!eventType) {
      console.warn(TAG + 'SubscribeToEvent: bad args len=' + a.length + ' [' + a.map(function (x) { return typeof x; }).join(',') + ']');
      return undefined;
    }
    var handler;
    if (fnIdx >= 0) {
      interop.push(L, a[fnIdx]); // Lua function value
      var LX = laux();
      var ref = LX.luaL_ref(L, fengari.core.LUA_REGISTRYINDEX); // pops value
      handler = { ref: ref };
    } else {
      handler = String(name); // resolve global at fire time
    }
    state.subs.push({ eventType: eventType, handler: handler, dead: false });
    return undefined;
  }

    function pushHandler(sub) {
    var h = sub.handler;
    if (h && typeof h === 'object' && typeof h.ref === 'number') {
      var LX = laux();
      LX.lua_rawgeti(L, fengari.core.LUA_REGISTRYINDEX, h.ref);
      return lua.lua_type(L, -1) === lua.LUA_TFUNCTION;
    }
    var name = (h && h.global) || h;
    lua.lua_getglobal(L, tl(String(name)));
    return lua.lua_type(L, -1) === lua.LUA_TFUNCTION;
  }

  function laux() {
    return (fengari.lauxlib && fengari.lauxlib.luaL_ref) ? fengari.lauxlib : fengari;
  }

  function jsUnsubscribeAll() {
    state.subs.length = 0;
    return undefined;
  }

  function fireEvent(type, data) {
    if (state.stopped) { return; }
    var i, sub;
    for (i = 0; i < state.subs.length; i++) {
      sub = state.subs[i];
      if (sub.dead || sub.eventType !== type) { continue; }
      if (!pushHandler(sub)) {
        lua.lua_pop(L, 1);
        sub.dead = true;
        console.warn(TAG + 'handler not found: ' + JSON.stringify(sub.handler) + ' (' + type + ')');
        continue;
      }
      lua.lua_pushstring(L, tl(type));
      interop.push(L, data);
      var rc = lua.lua_pcall(L, 2, 0, 0);
      if (rc !== lua.LUA_OK) {
        var msg = lua.lua_tojsstring(L, -1); lua.lua_pop(L, 1);
        sub.dead = true; // stop per-frame error spam
        console.error(TAG + 'Lua error in ' + sub.handler + ' (' + type + '): ' + msg);
      }
    }
  }

  // ------------------------------------------------------------ input maps
  // Flow-field BFS is hot when the player changes grid cells. Keep topology
  // and reusable scratch buffers in JS, then return ordinary Lua tables so
  // navigation callers and non-browser runtimes retain the same contract.
  function createCollisionGeometry(L2) {
    var obstacles=[],count=lua.lua_rawlen(L2,1);
    for(var i=1;i<=count;i++){
      lua.lua_rawgeti(L2,1,i);var item={};
      ['x','y','w','h'].forEach(function(k){lua.lua_getfield(L2,-1,tl(k));item[k]=lua.lua_tonumber(L2,-1);lua.lua_pop(L2,1);});
      lua.lua_pop(L2,1);obstacles.push(item);
    }
    lua.lua_pushlightuserdata(L2,{obstacles:obstacles});return 1;
  }
  function collisionBlocked(geometry,x,y,r) {
    if(x<48+r||x>992-r||y<142+r||y>628-r)return true;
    for(var i=0;i<geometry.obstacles.length;i++){var o=geometry.obstacles[i],cx=Math.max(o.x,Math.min(x,o.x+o.w)),cy=Math.max(o.y,Math.min(y,o.y+o.h));
      if(r<=0){if(x>=o.x&&x<=o.x+o.w&&y>=o.y&&y<=o.y+o.h)return true;}
      else if((x-cx)*(x-cx)+(y-cy)*(y-cy)<r*r-.000001)return true;
    }return false;
  }
  function nativeCollisionBlocked(L2){lua.lua_pushboolean(L2,collisionBlocked(lua.lua_touserdata(L2,1),lua.lua_tonumber(L2,2),lua.lua_tonumber(L2,3),lua.lua_tonumber(L2,4)));return 1;}
  function axisMove(geometry,pos,cross,delta,r,horizontal){
    var target=Math.max((horizontal?48:142)+r,Math.min((horizontal?992:628)-r,pos+delta));
    for(var i=0;i<geometry.obstacles.length;i++){var o=geometry.obstacles[i],side=horizontal?o.y:o.x,depth=horizontal?o.h:o.w;
      var gap=Math.abs(cross-Math.max(side,Math.min(cross,side+depth)));
      if(gap<r){var padding=Math.sqrt(Math.max(0,r*r-gap*gap)),low=(horizontal?o.x:o.y)-padding,high=(horizontal?o.x+o.w:o.y+o.h)+padding;
        if(delta>0&&pos<=low+.00001&&target>low)target=low;
        else if(delta<0&&pos>=high-.00001&&target<high)target=high;
      }
    }return target;
  }
  function nativeCollisionMove(L2){var geom=lua.lua_touserdata(L2,1),x=lua.lua_tonumber(L2,2),y=lua.lua_tonumber(L2,3),dx=lua.lua_tonumber(L2,4),dy=lua.lua_tonumber(L2,5),r=lua.lua_tonumber(L2,6);
    var steps=Math.max(1,Math.ceil(Math.max(Math.abs(dx),Math.abs(dy))/6)),sx=dx/steps,sy=dy/steps;
    for(var i=0;i<steps;i++){x=axisMove(geom,x,y,sx,r,true);y=axisMove(geom,y,x,sy,r,false);}
    lua.lua_pushnumber(L2,x);lua.lua_pushnumber(L2,y);return 2;
  }
  function nativeCollisionTrace(L2){
    var geom=lua.lua_touserdata(L2,1),ax=lua.lua_tonumber(L2,2),ay=lua.lua_tonumber(L2,3),bx=lua.lua_tonumber(L2,4),by=lua.lua_tonumber(L2,5),r=lua.lua_tonumber(L2,6),dx=bx-ax,dy=by-ay,t=1,hit=false;
    if(ax<48+r||ax>992-r||ay<142+r||ay>628-r){lua.lua_pushnumber(L2,0);lua.lua_pushboolean(L2,true);return 2;}
    [[ax,dx,48+r,992-r],[ay,dy,142+r,628-r]].forEach(function(v){var endValue=v[0]+v[1];if(endValue<v[2]||endValue>v[3]){t=Math.min(t,((endValue<v[2]?v[2]:v[3])-v[0])/v[1]);hit=true;}});
    function slab(pos,d,low,high,enter,leave){if(Math.abs(d)<.0000001)return pos<low||pos>high?null:[enter,leave];var a=(low-pos)/d,b=(high-pos)/d;if(a>b){var tmp=a;a=b;b=tmp;}enter=Math.max(enter,a);leave=Math.min(leave,b);return enter<=leave?[enter,leave]:null;}
    function rectangle(left,top,right,bottom){var x=slab(ax,dx,left,right,0,t);if(!x)return;var y=slab(ay,dy,top,bottom,x[0],x[1]);if(y&&y[0]<=t){t=Math.max(0,y[0]);hit=true;}}
    function corner(cx,cy){var ox=ax-cx,oy=ay-cy,c=ox*ox+oy*oy-r*r,a=dx*dx+dy*dy;if(c<0){t=0;hit=true;return;}if(a<.0000001)return;var dot=ox*dx+oy*dy,discriminant=dot*dot-a*c;if(discriminant<0)return;var at=(-dot-Math.sqrt(discriminant))/a;if(at>=0&&at<=t){t=at;hit=true;}}
    for(var i=0;i<geom.obstacles.length;i++){var o=geom.obstacles[i],left=o.x,top=o.y,right=o.x+o.w,bottom=o.y+o.h;
      if(Math.max(ax,bx)+r>=left&&Math.min(ax,bx)-r<=right&&Math.max(ay,by)+r>=top&&Math.min(ay,by)-r<=bottom){
        rectangle(left-r,top,right+r,bottom);rectangle(left,top-r,right,bottom+r);
        if(r>0){corner(left,top);corner(right,top);corner(left,bottom);corner(right,bottom);}
      }
    }
    lua.lua_pushnumber(L2,Math.max(0,Math.min(1,t)));lua.lua_pushboolean(L2,hit);return 2;
  }
  function createNavigationGraph(L2) {
    var links = [], size = 0;
    lua.lua_getfield(L2, 1, tl('nodes'));
    var nodes = lua.lua_gettop(L2);
    lua.lua_pushnil(L2);
    while (lua.lua_next(L2, nodes)) {
      var id = lua.lua_tointeger(L2, -2);
      lua.lua_getfield(L2, -1, tl('links'));
      var neighbors = [], count = lua.lua_rawlen(L2, -1);
      for (var i = 1; i <= count; i++) {
        lua.lua_rawgeti(L2, -1, i);
        neighbors.push(lua.lua_tointeger(L2, -1));
        lua.lua_pop(L2, 1);
      }
      links[id] = neighbors;
      size = Math.max(size, id + 1);
      lua.lua_pop(L2, 2); // links and node; retain key for lua_next
    }
    interop.push(L2, { links: links, size: size, queue: new Int32Array(size),
      distance: new Int32Array(size), next: new Int32Array(size) });
    return 1;
  }

  function buildNavigationField(L2) {
    var graph = interop.tojs(L2, 1), target = lua.lua_tointeger(L2, 2);
    var distance = graph.distance, next = graph.next, queue = graph.queue;
    distance.fill(-1); next.fill(0);
    var head = 0, tail = 0;
    if (target > 0 && graph.links[target]) { queue[tail++] = target; distance[target] = 0; }
    while (head < tail) {
      var id = queue[head++], neighbors = graph.links[id];
      for (var i = 0; i < neighbors.length; i++) {
        var neighbor = neighbors[i];
        if (distance[neighbor] < 0) {
          distance[neighbor] = distance[id] + 1;
          next[neighbor] = id;
          queue[tail++] = neighbor;
        }
      }
    }
    lua.lua_createtable(L2, graph.size, 0);
    var distances = lua.lua_gettop(L2);
    lua.lua_createtable(L2, graph.size, 0);
    var successors = lua.lua_gettop(L2);
    for (var j = 0; j < tail; j++) {
      var node = queue[j];
      lua.lua_pushinteger(L2, distance[node]); lua.lua_rawseti(L2, distances, node);
      if (next[node]) { lua.lua_pushinteger(L2, next[node]); lua.lua_rawseti(L2, successors, node); }
    }
    return 2;
  }
  var touchPointers = Object.create(null), pendingTouchMoves = Object.create(null), touchRect = null;
  function canvasPoint(e) {
    var r = touchRect || (state.canvas && state.canvas.getBoundingClientRect
      ? state.canvas.getBoundingClientRect()
      : { left: 0, top: 0 });
    return { x: (e.clientX - r.left) * state.dpr, y: (e.clientY - r.top) * state.dpr };
  }

  function onKeyDown(e) {
    if (e.target && e.target.closest && e.target.closest('input,textarea,[contenteditable="true"]')) { return; }
    var mapped = CODE2KEY[e.code];
    if (!mapped) { return; }
    var i;
    for (i = 0; i < mapped.length; i++) { state.keyState[mapped[i]] = true; }
    if (!state.stopped) { e.preventDefault(); }
    unlockAudio();
    if (!state.stopped) {
      fireEvent('KeyDown', eventData({ Key: mapped[0], Repeat: !!e.repeat }));
    }
  }

  function onKeyUp(e) {
    var mapped = CODE2KEY[e.code];
    if (!mapped) { return; }
    var i;
    for (i = 0; i < mapped.length; i++) { state.keyState[mapped[i]] = false; }
  }

  function onPointerDown(e) {
    unlockAudio();
    if (state.stopped) { return; }
    touchRect = state.canvas.getBoundingClientRect();
    var p = canvasPoint(e);
    touchPointers[e.pointerId || 0] = p;
    try { state.canvas.setPointerCapture(e.pointerId); } catch (_) {}
    state.pointerDown = true;
    fireEvent('TouchBegin', eventData({ X: p.x, Y: p.y, TouchID: e.pointerId || 0 }));
  }

  function onPointerMove(e) {
    if (state.stopped || !touchPointers[e.pointerId || 0]) { return; }
    var p = canvasPoint(e);
    touchPointers[e.pointerId || 0] = p;
    pendingTouchMoves[e.pointerId || 0] = p;
  }

  function onPointerUp(e) {
    if (!touchPointers[e.pointerId || 0]) { return; }
    delete touchPointers[e.pointerId || 0];
    delete pendingTouchMoves[e.pointerId || 0];
    state.pointerDown = Object.keys(touchPointers).length > 0;
    var p = canvasPoint(e);
    fireEvent('TouchEnd', eventData({ X: p.x, Y: p.y, TouchID: e.pointerId || 0 }));
  }

  function unlockAudio() {
    if (state.audioUnlocked) { return; }
    var A = window.DSH && window.DSH.AudioShim;
    state.audioUnlocked = true;
    if (A && typeof A.unlock === 'function') {
      try { A.unlock(); } catch (e) { console.warn(TAG + 'AudioShim.unlock failed:', e && e.message); }
    }
  }

  function onVisibility() {
    if (state.stopped) { return; }
    if (document.hidden) {
      resetTouches();
      fireEvent('InputFocus', eventData({ Focus: false }));
    } else {
      state.lastTime = performance.now();
      fireEvent('InputFocus', eventData({ Focus: true }));
    }
  }
  function resetTouches() {
    Object.keys(touchPointers).forEach(function (id) {
      var p = touchPointers[id];
      fireEvent('TouchEnd', eventData({X:p.x,Y:p.y,TouchID:Number(id)}));
    });
    touchPointers=Object.create(null); pendingTouchMoves=Object.create(null); state.pointerDown=false;
  }

  function attachDom() {
    window.addEventListener('keydown', onKeyDown, true);
    window.addEventListener('keyup', onKeyUp, true);
    window.addEventListener('resize', resize);
    window.addEventListener('gameviewportchange', resize);
    // Entering fullscreen (mobile 横屏 button) changes the element box without
    // always firing window.resize, so the backing store would keep the old size.
    document.addEventListener('fullscreenchange', resizeSoon);
    document.addEventListener('webkitfullscreenchange', resizeSoon);
    if (typeof ResizeObserver === 'function') {
      try { state.observer = new ResizeObserver(resize); state.observer.observe(state.canvas); }
      catch (e) { state.observer = null; }
    }
    window.addEventListener('blur', resetTouches);
    document.addEventListener('visibilitychange', onVisibility);
    var c = state.canvas;
    if (c) {
      c.addEventListener('pointerdown', onPointerDown);
      window.addEventListener('pointermove', onPointerMove);
      window.addEventListener('pointerup', onPointerUp);
      window.addEventListener('pointercancel', onPointerUp);
      c.addEventListener('lostpointercapture', onPointerUp);
    }
  }

  function detachDom() {
    window.removeEventListener('keydown', onKeyDown, true);
    window.removeEventListener('keyup', onKeyUp, true);
    window.removeEventListener('resize', resize);
    window.removeEventListener('gameviewportchange', resize);
    document.removeEventListener('fullscreenchange', resizeSoon);
    document.removeEventListener('webkitfullscreenchange', resizeSoon);
    if (state.observer) { try { state.observer.disconnect(); } catch (e) { /* ignore */ } state.observer = null; }
    window.removeEventListener('blur', resetTouches);
    resetTouches();
    document.removeEventListener('visibilitychange', onVisibility);
    var c = state.canvas;
    if (c) {
      c.removeEventListener('pointerdown', onPointerDown);
      window.removeEventListener('pointermove', onPointerMove);
      window.removeEventListener('pointerup', onPointerUp);
      window.removeEventListener('pointercancel', onPointerUp);
      c.removeEventListener('lostpointercapture', onPointerUp);
    }
  }

  // ------------------------------------------------------------------ canvas
  function ensureCanvas() {
    var c = document.getElementById('game-canvas');
    if (!c) {
      c = document.createElement('canvas');
      c.id = 'game-canvas';
      var st = c.style;
      st.position = 'fixed'; st.left = '0'; st.top = '0';
      st.width = '100%'; st.height = '100%';
      st.display = 'block'; st.touchAction = 'none'; st.background = '#0b0e12';
      (document.body || document.documentElement).appendChild(c);
      console.warn(TAG + 'created missing #game-canvas');
    } else if (!c.style.touchAction) {
      c.style.touchAction = 'none';
    }
    state.canvas = c;
    resize();
    return c;
  }

  function resize() {
    var c = state.canvas;
    if (!c) { return; }
    resetTouches();
    touchRect = c.getBoundingClientRect();
    state.dpr = Math.min(window.devicePixelRatio || 1, 2);
    var w = c.clientWidth || window.innerWidth || 320;
    var h = c.clientHeight || window.innerHeight || 240;
    var pw = Math.max(1, Math.round(w * state.dpr));
    var ph = Math.max(1, Math.round(h * state.dpr));
    if (c.width !== pw || c.height !== ph) { c.width = pw; c.height = ph; }
  }

  /* A fullscreen transition can settle one frame later than the event. */
  function resizeSoon() {
    resize();
    if (typeof window.requestAnimationFrame === 'function') window.requestAnimationFrame(resize);
  }

  // ---------------------------------------------------------------- preload
  var loadbarEl = null;
  function showLoadbar() {
    if (document.getElementById('loadbar')) { return; }
    loadbarEl = document.createElement('div');
    loadbarEl.id = 'loadbar';
    var st = loadbarEl.style;
    st.position = 'fixed'; st.left = '0'; st.top = '0';
    st.height = '4px'; st.width = '0%';
    st.background = '#2bd9a2'; st.zIndex = '99999';
    st.transition = 'width 0.12s linear';
    (document.body || document.documentElement).appendChild(loadbarEl);
  }
  function updateLoadbar(done, total) {
    var pct = total > 0 ? Math.round((done / total) * 100) : 100;
    if (loadbarEl) { loadbarEl.style.width = pct + '%'; loadbarEl.title = 'loading ' + pct + '%'; }
  }
  function removeLoadbar() {
    var el = document.getElementById('loadbar');
    if (el && el.parentNode) { el.parentNode.removeChild(el); }
    loadbarEl = null;
  }

  function loadImage(p) {
    return new Promise(function (resolve, reject) {
      var im = new Image();
      im.onload = function () { resolve(im); };
      im.onerror = function () { reject(new Error('image decode failed: ' + p)); };
      im.src = p;
    });
  }

  function loadFont(p) {
    var fam = p.split('/').pop().replace(/\.subset\.ttf$/i, '').replace(/\.ttf$/i, '');
    try {
      var face = new FontFace(fam, "url('" + p + "')");
      document.fonts.add(face);
      return face.load().catch(function (e) {
        console.warn(TAG + 'font load failed (continuing):', p, (e && e.message) || e);
      });
    } catch (e) {
      console.warn(TAG + 'FontFace error (continuing):', p, (e && e.message) || e);
      return Promise.resolve();
    }
  }

  function preloadAssets(report) {
    var M = window.DSH.MANIFEST;
    var A = (M && M.assets) || { images: [], audio: [], fonts: [] };
    var Nvg = window.DSH.Nvg;
    var Audio = window.DSH.AudioShim;
    var total = A.images.length + A.audio.length + A.fonts.length;
    var done = 0;
    function tick() { done++; updateLoadbar(done, total); }

    var jobs = [];

    A.images.forEach(function (p) {
      var job = loadImage(p)
        .then(function (img) {
          if (Nvg && typeof Nvg.registerImage === 'function') { Nvg.registerImage(p, img); }
          else { console.warn(TAG + 'Nvg missing — image not registered:', p); }
        })
        .catch(function (e) {
          console.warn(TAG + String(e && e.message || e) + ' (continuing)');
        })
        .then(tick);
      jobs.push(job);
    });

    A.audio.forEach(function (p) {
      var job = (Audio && typeof Audio.load === 'function')
        ? Audio.load(p).catch(function (e) {
            console.warn(TAG + 'audio decode failed (continuing):', p, (e && e.message) || e);
          })
        : Promise.resolve();
      job = job.then(tick);
      jobs.push(job);
    });

    A.fonts.forEach(function (p) {
      jobs.push(loadFont(p).then(tick));
    });

    updateLoadbar(0, total);
    return Promise.all(jobs);
  }

  // ------------------------------------------------------------- shim init
  function initShims() {
    var D = window.DSH;
    if (D.Nvg && typeof D.Nvg.setCanvas === 'function') {
      D.Nvg.setCanvas(state.canvas);
    } else {
      console.warn(TAG + 'DSH.Nvg missing — rendering disabled (degraded)');
    }
    if (D.UrhoxUI && typeof D.UrhoxUI.Init === 'function') {
      try {
        D.UrhoxUI.Init({
          theme: (D.UrhoxUI.Theme && D.UrhoxUI.Theme.defaultTheme) || undefined,
          scale: 1
        });
      } catch (e) {
        console.warn(TAG + 'UrhoxUI.Init failed:', (e && e.message) || e);
      }
    } else {
      console.warn(TAG + 'DSH.UrhoxUI missing — UI degraded (stub module installed)');
    }
    if (!D.AudioShim) {
      console.warn(TAG + 'DSH.AudioShim missing — audio disabled (degraded)');
    }
  }

  // -------------------------------------------------------------- lua setup
  var BOOTSTRAP_LUA = [
    'local function install(name, src)',
    '  package.preload[name] = function()',
    '    local chunk, err = load(src, "@" .. name)',
    '    if not chunk then error("cannot load module " .. name .. ": " .. tostring(err), 2) end',
    '    return chunk() -- no vararg: moduleName stays nil for tests.* dual-mode files',
    '  end',
    'end',
    'for name, src in pairs(__LUA_SOURCES) do install(name, src) end'
  ].join('\n');

  var UI_STUB_LUA = [
    'local t = {}',
    't.Theme = { defaultTheme = {}, ExtendTheme = function(base, over) return over or base end }',
    't.Scale = { DEFAULT = 1 }',
    'local noop = function() return nil end',
    'for _, n in ipairs({"Init","Shutdown","SetRoot","Panel","ProgressBar","SafeAreaView","Label","Button"}) do',
    '  t[n] = noop',
    'end',
    't.GetViewportSize = function() return 1024, 768 end',
    'return t'
  ].join('\n');

  // Mirror a JS module object into a NATIVE Lua table: functions become
  // cfunction trampolines (exact args, arrays expand to multiple returns),
  // nested objects recurse (dot-called nested fns keep their argument list),
  // arrays become 1-based tables, primitives convert directly.
  function pushModuleValue(v, depth) {
    var i2, idx2, k2;
    if (typeof v === 'function') {
      lua.lua_pushcfunction(L, makeTrampoline('module-fn', v));
      return;
    }
    if (v && typeof v === 'object' && depth < 4) {
      if (Array.isArray(v)) {
        lua.lua_createtable(L, v.length, 0);
        idx2 = lua.lua_gettop(L);
        for (i2 = 0; i2 < v.length; i2++) {
          lua.lua_pushinteger(L, i2 + 1);
          pushModuleValue(v[i2], depth + 1);
          lua.lua_rawset(L, idx2);
        }
        return;
      }
      var keys = Object.keys(v);
      lua.lua_createtable(L, 0, keys.length);
      idx2 = lua.lua_gettop(L);
      for (k2 = 0; k2 < keys.length; k2++) {
        lua.lua_pushstring(L, tl(keys[k2]));
        pushModuleValue(v[keys[k2]], depth + 1);
        lua.lua_rawset(L, idx2);
      }
      return;
    }
    jsToLua(L, v);
  }

  function installRequireLoader() {
    var M = window.DSH.MANIFEST;
    if (!M || !M.luaSources) {
      throw new Error('DSH.MANIFEST.luaSources missing');
    }
    pushModuleValue(M.luaSources, 0);
    lua.lua_setglobal(L, tl('__LUA_SOURCES'));
    var r = doStringProtected(BOOTSTRAP_LUA, 'engine-bootstrap');
    if (!r.ok) { throw new Error('require loader bootstrap failed: ' + r.error); }
    lua.lua_pushnil(L);
    lua.lua_setglobal(L, tl('__LUA_SOURCES'));

    // virtual module urhox-libs/UI — mirrored into a native Lua table so
    // dot-called nested functions (UI.Theme.ExtendTheme(a, b)) keep exact
    // arguments (interop objects would shift the first argument into `this`).
    var U = window.DSH.UrhoxUI;
    if (U) {
      pushModuleValue(U, 0);
      lua.lua_setglobal(L, tl('__URHOX_UI'));
      r = doStringProtected(
        "local __U = __URHOX_UI\n__URHOX_UI = nil\npackage.preload['urhox-libs/UI'] = function() return __U end",
        'engine-ui-module'
      );
      if (!r.ok) { throw new Error('urhox-libs/UI preload install failed: ' + r.error); }
    } else {
      r = doStringProtected(
        "package.preload['urhox-libs/UI'] = function()\n" + UI_STUB_LUA + '\nend',
        'engine-ui-stub'
      );
      if (!r.ok) { throw new Error('UI stub install failed: ' + r.error); }
    }
  }

  function installEngineGlobals() {
    var D = window.DSH;

    // graphics / input / cache / events: native Lua tables with cfunction
    // methods — colon calls drop the self arg; property writes are plain
    // table access; misses return real nil.
    pushNativeObj('graphics', {
      props: { windowTitle: '', mouseMode: '' },
      methods: {
        GetDPR: function () { return state.dpr; },
        GetWidth: function () { return state.canvas ? state.canvas.width : 0; },
        GetHeight: function () { return state.canvas ? state.canvas.height : 0; }
      }
    });

    pushNativeObj('input', {
      props: { mouseMode: '' },
      methods: {
        GetKeyDown: function (k) { return !!state.keyState[k]; },
        ResetGameKeys: function () { state.keyState = Object.create(null); }
      }
    });

    pushNativeObj('cache', {
      methods: {
        GetResource: function (type, path) {
          if (type === 'Sound') {
            var A = window.DSH.AudioShim;
            if (A && typeof A.getResource === 'function') { return A.getResource(path); }
            console.warn(TAG + 'AudioShim missing — GetResource(Sound,' + path + ') -> nil');
            return undefined;
          }
          console.warn(TAG + 'cache:GetResource unsupported type: ' + type + ' ' + path);
          return undefined;
        }
      }
    });

    // events table + global functions
    pushNativeObj('events', {
      methods: {
        SubscribeToEvent: jsSubscribe,
        UnsubscribeFromAllEvents: jsUnsubscribeAll
      }
    });
    pushFnGlobal('SubscribeToEvent', jsSubscribe);
    pushFnGlobal('UnsubscribeFromAllEvents', jsUnsubscribeAll);
    lua.lua_pushcfunction(L, createNavigationGraph);
    lua.lua_setglobal(L, tl('__OfficeNavCreateGraph'));
    lua.lua_pushcfunction(L, buildNavigationField);
    lua.lua_setglobal(L, tl('__OfficeNavBuildField'));
    lua.lua_pushcfunction(L,createCollisionGeometry);lua.lua_setglobal(L,tl('__OfficeNavCreateCollision'));
    lua.lua_pushcfunction(L,nativeCollisionBlocked);lua.lua_setglobal(L,tl('__OfficeNavBlocked'));
    lua.lua_pushcfunction(L,nativeCollisionMove);lua.lua_setglobal(L,tl('__OfficeNavMove'));
    lua.lua_pushcfunction(L,nativeCollisionTrace);lua.lua_setglobal(L,tl('__OfficeNavTrace'));

    // Scene() -> AudioShim.Scene()
    pushFnGlobal('Scene', function () {
      var A = window.DSH.AudioShim;
      if (!A || typeof A.Scene !== 'function') {
        throw new Error('Scene(): DSH.AudioShim missing');
      }
      return A.Scene();
    });

    // nvg* functions + NVG_* constants from the gfx shim
    if (D.Nvg) {
      Object.keys(D.Nvg).forEach(function (k) {
        var v = D.Nvg[k];
        if (/^nvg/.test(k) && typeof v === 'function') {
          pushFnGlobal(k, v);
        } else if (/^NVG_/.test(k) && typeof v === 'number') {
          pushNumGlobal(k, v);
        }
      });
    }

    // constants
    Object.keys(KEY).forEach(function (k) { pushNumGlobal(k, KEY[k]); });
    pushNumGlobal('MM_ABSOLUTE', 1);
    pushNumGlobal('SOUND_EFFECT', 0);
    pushNumGlobal('SOUND_MUSIC', 1);
    pushNumGlobal('REMOVE_DISABLED', 0);

    // ---------------------------------------------------- storage / net (S0-5)
    // localStorage bridge for Leaderboard.Store. Every call is guarded: on any
    // throw (private mode, quota, disabled storage) it degrades to a no-op so
    // the Lua side can keep running against its in-memory fallback table.
    pushFnGlobal('StorageGet', function (key) {
      try {
        var v = window.localStorage.getItem(String(key));
        return v === null ? null : v;
      } catch (e) { return null; }
    });
    pushFnGlobal('StorageSet', function (key, value) {
      try { window.localStorage.setItem(String(key), String(value)); return true; }
      catch (e) { return false; }
    });
    pushFnGlobal('StorageRemove', function (key) {
      try { window.localStorage.removeItem(String(key)); return true; }
      catch (e) { return false; }
    });

    // Nonblocking score bridge. Rendering only reads a small cached snapshot.
    var score = { revision: 0, state: 'idle', rank: 0, error: '', wire: '',
      online: window.OFFWORK_API_ENABLED === true, mode: 'endless', busy: false };
    var scoreVersion = 'office-expansion-v3', scoreRuleset = 'balance-2026-11-07-v2';
    // score.error crosses into Lua and gets printed verbatim on the result sheet,
    // so it must stay a stable machine code. Localized text lives in Lua
    // (main.lua ScoreErrorText), because the font subset is built from Lua only.
    function scoreErrorCode(error) {
      if (error && error.name === 'AbortError') return 'timeout';
      var raw = String((error && error.message) || '');
      // Server errors arrive as snake_case codes (invalid_name, score_mismatch,
      // rate_limited...). Pass them through unchanged; Lua owns the wording and
      // falls back to a generic message for codes it does not know.
      if (/^[a-z][a-z0-9_]{2,40}$/.test(raw)) return raw;
      return 'network_error';
    }
    function scoreRequest(mode, payload) {
      if (!score.online || score.busy || typeof window.fetch !== 'function') return false;
      score.busy = true; score.mode = mode; score.error = ''; score.rank = 0;
      if (!payload) score.wire = '';
      score.state = payload ? 'submitting' : 'loading'; score.revision++;
      var controller = new AbortController();
      var timer = window.setTimeout(function () { controller.abort(); }, 10000);
      var url = '/api/leaderboard?mode=' + encodeURIComponent(mode) +
        '&version=' + encodeURIComponent(scoreVersion) + '&ruleset=' + encodeURIComponent(scoreRuleset);
      var options = { signal: controller.signal, cache: 'no-store', credentials: 'same-origin' };
      if (payload) {
        url = '/api/leaderboard'; options.method = 'POST';
        options.headers = { 'Content-Type': 'application/json' };
        options.body = JSON.stringify(Object.assign({}, payload,
          { version: scoreVersion, ruleset: scoreRuleset, balanceVersion: scoreRuleset }));
      }
      window.fetch(url, options).then(function (response) {
        return response.json().then(function (data) {
          if (!response.ok || data.ok !== true) throw new Error(data.error || 'http_' + response.status);
          return data;
        });
      }).then(function (data) {
        score.wire = typeof data.wire === 'string' ? data.wire : '';
        score.rank = Number(data.rank) || 0;
        score.state = payload ? 'success' : 'idle';
      }).catch(function (error) {
        score.error = scoreErrorCode(error);
        score.state = 'error';
      }).finally(function () {
        window.clearTimeout(timer); score.busy = false; score.revision++;
      });
      return true;
    }
    pushFnGlobal('ScoreRefresh', function (mode) {
      return scoreRequest(mode === 'campaign' ? 'campaign' : 'endless', null);
    });
    pushFnGlobal('ScoreSubmit', function (body) {
      try { var entry = JSON.parse(String(body)); return scoreRequest(entry.mode, entry); }
      catch (e) { return false; }
    });
    pushFnGlobal('ScorePoll', function () {
      return [score.revision, score.state, score.rank, score.error, score.wire, score.online];
    });
    pushFnGlobal('ScoreNewRunId', function () {
      if (window.crypto && typeof window.crypto.randomUUID === 'function') return window.crypto.randomUUID();
      var bytes = new Uint8Array(16); window.crypto.getRandomValues(bytes);
      bytes[6] = (bytes[6] & 15) | 64; bytes[8] = (bytes[8] & 63) | 128;
      var hex = Array.from(bytes, function (v) { return v.toString(16).padStart(2, '0'); }).join('');
      return hex.slice(0,8)+'-'+hex.slice(8,12)+'-'+hex.slice(12,16)+'-'+hex.slice(16,20)+'-'+hex.slice(20);
    });
    // Legacy calls fail immediately; synchronous XHR must never stall combat.
    pushFnGlobal('NetGet', function () { return [false, 'async_required']; });
    pushFnGlobal('NetPost', function () { return [false, 'async_required']; });

  }

  // ------------------------------------------------------------ boot & loop
  function runMain() {
    var src = window.DSH.MANIFEST.luaSources['main'];
    if (typeof src !== 'string') {
      throw new Error('MANIFEST.luaSources["main"] missing');
    }
    var r = doStringProtected(src, 'main');
    if (!r.ok) { throw new Error(r.error); }
    var s = callGlobalFn('Start');
    if (!s.ok) { console.warn(TAG + s.error); }
  }

  function runTest(name) {
    var mod = 'tests.' + name;
    var src = window.DSH.MANIFEST.luaSources[mod];
    if (typeof src !== 'string') {
      throw new Error('no test module ' + mod + ' in MANIFEST.luaSources');
    }
    var r = doStringProtected("require('" + mod + "')", 'engine-test');
    if (!r.ok) { throw new Error(r.error); }
    var s = callGlobalFn('Start');
    if (!s.ok) { throw new Error(s.error); }
    api.testResult = { ok: true, msg: 'test ' + mod + ' started' };
    console.log(TAG + 'test ' + mod + ' started ok');
  }

  function frame(now) {
    if (state.stopped) { return; }
    state.rafId = window.requestAnimationFrame(frame);
    var dt = (now - state.lastTime) / 1000;
    state.lastTime = now;
    if (dt < 0) { dt = 0; }
    if (dt > 0.05) { dt = 0.05; }
    var moves=pendingTouchMoves; pendingTouchMoves=Object.create(null);
    Object.keys(moves).forEach(function (id) {
      var p=moves[id]; fireEvent('TouchMove',eventData({X:p.x,Y:p.y,TouchID:Number(id)}));
    });
    fireEvent('Update', eventData({ TimeStep: dt }));
    fireEvent('NanoVGRender', eventData({}));
  }

  function startLoop() {
    if (state.loopStarted) { return; }
    state.loopStarted = true;
    state.lastTime = performance.now();
    state.rafId = window.requestAnimationFrame(frame);
  }

  function boot() {
    if (state.bootPromise) { return state.bootPromise; }
    var params = new URLSearchParams(window.location.search || '');
    var testName = params.get('test');
    var assemblyOnly = params.get('boot') === 'off' || window.DSH_ENGINE_BOOT === 'off';

    state.bootPromise = Promise.resolve().then(function () {
      initFengari();
      if (!window.DSH.MANIFEST) {
        throw new Error('DSH.MANIFEST missing — include js/manifest.js before engine.js');
      }
      ensureCanvas();
      showLoadbar();
      return preloadAssets().then(function () {
        removeLoadbar();
        initShims();
        installRequireLoader();
        installEngineGlobals();
        attachDom();
        if (assemblyOnly) {
          console.log(TAG + 'assembly-only boot (no main/test script, no loop)');
        } else if (testName) { runTest(testName); }
        else { runMain(); startLoop(); }
        state.booted = true;
        console.log(TAG + (assemblyOnly ? 'booted (assembly)' : testName ? 'booted (test=' + testName + ')' : 'booted'));
      });
    }).catch(function (e) {
      removeLoadbar();
      var msg = (e && e.message) || String(e);
      console.error(TAG + 'boot failed: ' + msg);
      if (e && e.stack) { console.error(String(e.stack).split('\n').slice(0, 12).join('\n')); }
      if (testName) {
        console.error('TEST FAILED — ' + msg);
        api.testResult = { ok: false, msg: msg };
      }
      throw e;
    });
    return state.bootPromise;
  }

  function stop() {
    if (state.stopped) { return; }
    state.stopped = true;
    if (state.rafId) { window.cancelAnimationFrame(state.rafId); }
    state.loopStarted = false;
    detachDom();
    state.subs.length = 0;
  }

  // ------------------------------------------------------------------- api
  api.version = 'engine/1.0 (fengari 0.1.4)';
  api.boot = boot;
  api.stop = stop;
  api.resize = resize;
  api.testResult = undefined;
  Object.defineProperty(api, 'testResult', {
    get: function () { return state.testResult; },
    set: function (v) { state.testResult = v; },
    configurable: true
  });
  // dev/debug surface (used by web/dev/engine-core/test.html)
  api.startLoop = startLoop;
  api._fengari = {
    L: function () { return L; },
    doString: function (code) { return doStringProtected(String(code), 'engine-api', true); }
  };

  window.DSH.Engine = api;

  function autoBoot() {
    if (state.autoRan) { return; }
    state.autoRan = true;
    boot().catch(function () { /* already logged */ });
  }
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', autoBoot);
  } else {
    autoBoot();
  }
})();
