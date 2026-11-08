(function () {
"use strict";
if (typeof window === "undefined") return;
window.DSH = window.DSH || {};

/* OffWork-Rage web shim - UrhoxUI bridge (web/js/ui.js).
 * Mounted as window.DSH.UrhoxUI; engine.js registers this object as the Lua
 * require path "urhox-libs/UI" in fengari-web. Lua colon calls arrive as
 * this=<widget>, args shifted by one - factories close over the widget,
 * so method bodies never rely on this.
 * Props are fengari "Fengari object" proxies (function with .get/.has/
 * [Symbol.iterator]); plain JS objects also accepted so the dev test page
 * runs without a Lua VM. All reads go through P().
 * Measured fengari-interop 0.1.4 facts (not guessed):
 * - Lua closure onClick: use cb.call(widget); interop invoke pushes the JS
 *   this as the FIRST Lua arg, so cb(widget) would pass nil as w.
 * - GetViewportSize returns [w,h]; engine-builder must expand it into two
 *   lua_pushnumber returns (interop caps JS calls at 1 return value). */

function isLuaProxy(v) {
  return typeof v === "function" && v[Symbol.toStringTag] === "Fengari object" && typeof v.get === "function";
}
var EMPTY_P = { get: function () { return undefined; }, has: function () { return false; }, keys: function () { return []; }, forEach: function () {} };
function P(raw) {
  if (raw == null) return EMPTY_P;
  if (isLuaProxy(raw)) return raw;
  return {
    get: function (k) { return raw[k]; },
    has: function (k) { return Object.prototype.hasOwnProperty.call(raw, k); },
    keys: function () { return Object.keys(raw); },
    forEach: function (fn) { for (var k in raw) if (Object.prototype.hasOwnProperty.call(raw, k)) fn(k, raw[k]); }
  };
}

/* {r,g,b,a} color table; Lua tuples 1-based, plain arrays 0-based (P.get
 * normalizes both because proxy .get(i) is 1-based Lua and our plain shim
 * stores 0-based arrays - see numAt for the offset rule). Alpha contract is
 * 0-255; a<=1 with rgb>1 is normalized as a 0-1 alpha mis-pass. */
function readColor(v) {
  if (v == null) return null;
  var proxy = isLuaProxy(v);
  var at = proxy ? function (i) { return v.get(i); } : function (i) { return v[i - 1]; };
  var r = at(1), g = at(2), b = at(3), a = at(4);
  if (typeof a !== "number") a = 255;
  if (typeof r !== "number") {
    var c = P(v);
    r = c.get("r"); g = c.get("g"); b = c.get("b"); a = c.get("a");
    if (typeof r !== "number") return null;
    if (typeof a !== "number") a = 1;
  }
  if (a <= 1 && r > 1) a = a * 255;
  function cl(x, d) { x = typeof x === "number" && isFinite(x) ? x : d; return Math.max(0, Math.min(255, Math.round(x))); }
  return { r: cl(r, 0), g: cl(g, 0), b: cl(b, 0), a: cl(a, 255) };
}
function cssColor(v, dflt) {
  var c = readColor(v);
  if (!c) return dflt || "transparent";
  return "rgba(" + c.r + "," + c.g + "," + c.b + "," + (c.a / 255).toFixed(3) + ")";
}
function numAt(v, i, dflt) {
  if (v == null) return dflt;
  var x = isLuaProxy(v) ? v.get(i) : v[i - 1];
  return typeof x === "number" ? x : dflt;
}
function numOr(p, k, d) { var x = p.get(k); return typeof x === "number" && isFinite(x) ? x : d; }
function strOr(p, k, d) { var x = p.get(k); return typeof x === "string" ? x : d; }
function boolOr(p, k, d) { var x = p.get(k); return typeof x === "boolean" ? x : d; }
function eachEntry(tbl, fn) {
  if (tbl == null) return;
  if (isLuaProxy(tbl)) { for (var kv of tbl) fn(kv[0], kv[1]); }
  else { for (var k in tbl) if (Object.prototype.hasOwnProperty.call(tbl, k)) fn(k, tbl[k]); }
}

var state = { scale: 1, theme: null, root: null, canvas: null, inited: false };
function px(n) { return (typeof n === "number" && isFinite(n) ? n : 0) * state.scale; }
/* Length props may be numbers (px), percent strings ("100%"), or "auto".
 * urhox/Yoga accept all three; only scale numbers. Never coerce to 0. */
function cssPx(n) {
  if (typeof n === "number" && isFinite(n)) return (n * state.scale) + "px";
  if (typeof n === "string") {
    var s = n.trim();
    if (/^-?\d+(\.\d+)?%$/.test(s)) return s;            /* "100%" passes through */
    var f = parseFloat(s);
    if (!isNaN(f)) return (f * state.scale) + "px";       /* "46" numeric string */
    return s;                                             /* "auto", "fit-content"… */
  }
  return "0px";
}

var FONT_STACK = '"FusionPixel", monospace';
var FONTS = [
  ["400", "FusionPixel-12px-Prop-zh_hans.subset.ttf"],
  ["700", "FusionPixel-12px-Prop-zh_hans-Bold.subset.ttf"],
  ["400", "FusionPixel-12px-Mono-zh_hans.subset.ttf"]
];
function injectFonts() {
  if (document.getElementById("urhox-fonts")) return;
  var st = document.createElement("style");
  st.id = "urhox-fonts";
  var css = [];
  for (var i = 0; i < FONTS.length; i++) {
    css.push("@font-face{font-family:FusionPixel;font-weight:" + FONTS[i][0] + ";src:url(assets/Fonts/" + FONTS[i][1] + ") format(truetype);font-display:swap;}");
  }
  st.textContent = css.join("\n");
  document.head.appendChild(st);
  if (document.fonts && document.fonts.load) {
    try { document.fonts.load("12px FusionPixel", "\u542f\u4f60\u597d"); } catch (e) {}
    try { document.fonts.load("700 12px FusionPixel", "\u52a0\u73ed"); } catch (e) {}
  }
  /* missing files degrade to monospace via font-display:swap; never block */
}

var DEFAULT_SLICES = { panel: 18, button: 12, frame: 12, computer: [37, 39, 44, 39] };
function defaultTheme() {
  return {
    fonts: { sans: "sans", mono: "mono" },
    colors: {
      bg: [19, 35, 46, 255], navy: [24, 45, 60, 255], surface: [31, 58, 76, 255],
      paper: [235, 228, 214, 255], ink: [24, 24, 24, 255], cream: [244, 238, 224, 255],
      muted: [122, 138, 148, 255], line: [70, 96, 112, 255], wood: [122, 85, 56, 255],
      teal: [60, 160, 150, 255], pink: [222, 110, 130, 255], gold: [230, 180, 84, 255],
      purple: [130, 100, 190, 255], lightMuted: [160, 176, 186, 255]
    },
    slices: JSON.parse(JSON.stringify(DEFAULT_SLICES)),
    borderRadius: { panel: 0, button: 0, frame: 0, card: 0 },
    sizes: { buttonHeight: 46 },
    shadow: { x: 2, y: 3, blur: 0 }
  };
}
/* deep merge src over base; neither mutated; proxy or plain; plain result */
function mergeInto(base, src) {
  var out = {};
  if (base != null && (typeof base === "object" || isLuaProxy(base))) eachEntry(base, function (k, v) { out[k] = v; });
  if (src != null) eachEntry(src, function (k, v) {
    var cur = out[k];
    var curTbl = cur != null && (typeof cur === "object" || isLuaProxy(cur)) && !Array.isArray(cur);
    var vTbl = v != null && (typeof v === "object" || isLuaProxy(v)) && !Array.isArray(v);
    if (curTbl && vTbl) out[k] = mergeInto(cur, v);
    else out[k] = v;
  });
  return out;
}

/* Lua children tables are 1-based arrays (plain or proxy). Adopt them in
 * declaration order so constructor-built trees (main.lua BuildUI) attach. */
function adoptChildren(w, props) {
  if (!props) return;
  var pr = P(props);
  var kids = pr.get ? pr.get("children") : props.children;
  if (!kids) return;
  if (isLuaProxy(kids)) {
    var n = kids.length ? Number(kids.length) : 0;
    if (!n) { for (var i = 1; i <= 64; i++) { var c = kids.get(i); if (c == null || c === undefined) break; w.AddChild(c); n = i; } return; }
    for (var j = 1; j <= n; j++) { var c2 = kids.get(j); if (c2 != null && c2 !== undefined) w.AddChild(c2); }
  } else if (Array.isArray(kids)) {
    for (var k = 0; k < kids.length; k++) if (kids[k]) w.AddChild(kids[k]);
  }
}

/* The UI tree must live inside the fullscreen subtree: mobile-display.js puts
 * #app into fullscreen, and nodes outside it are not rendered by the browser.
 * #ui-root is an inset:0 layer inside #app, so it is also the correct layout
 * origin for GetAbsoluteLayout. */
function canvasHost() {
  var host = document.getElementById("ui-root");
  if (host) return host;
  return state.canvas || document.body;
}
function findChildById(w, id) {
  for (var i = 0; i < w.children.length; i++) {
    var c = w.children[i];
    var cid = c.id != null ? c.id : (c.props ? (P(c.props).get ? P(c.props).get("id") : c.props.id) : null);
    if (String(cid) === String(id)) return c;
    var deep = findChildById(c, id);
    if (deep) return deep;
  }
  return null;
}
function makeWidget(el, props) {
  var widget = { __widget: true, el: el, props: props, children: [] };
  widget.AddChild = function (child) {
    if (!child || !child.el) return widget;
    if (child.__parent === widget) return widget;
    if (child.__parent && child.__parent.RemoveChildSilent) child.__parent.RemoveChildSilent(child);
    child.__parent = widget;
    widget.children.push(child);
    el.appendChild(child.el);
    return widget;
  };
  widget.FindById = function (id) {
    /* fengari interop maps JS null to a TRUTHY js-null userdata, so a null
     * return makes `if w then` pass. Return false (Lua falsy) on miss. */
    var r = null;
    try { r = findChildById(widget, id) || null; }
    catch (e) { /* ignore */ }
    return r || false;
  };
  widget.ClearChildren = function () {
    el.innerHTML = "";   /* single-shot clear per contract */
    widget.children.length = 0;
    return widget;
  };
  widget.RemoveChildSilent = function (child) {
    var i = widget.children.indexOf(child);
    if (i >= 0) widget.children.splice(i, 1);
    if (child.__parent === widget) child.__parent = null;
  };
  widget.Hide = function () {
    if (el.style.display !== "none") widget.__display = el.style.display;
    el.style.display = "none"; return widget;
  };
  widget.Show = function () {
    if (el.style.display === "none") el.style.display = widget.__display || "";
    return widget;
  };
  widget.SetVisible = function (b) {
    try { if (b) widget.Show(); else widget.Hide(); }
    catch (e) { throw e; }
    return widget;
  };
  widget.SetText = function (s) {
    var t = (s == null) ? "" : String(s);
    if (el.tagName === "INPUT" || el.tagName === "TEXTAREA") el.value = t;
    else if (el.textContent !== t) el.textContent = t;
    return widget;
  };
  widget.SetValue = function (n) {
    var v = typeof n === "number" ? n : parseFloat(n);
    if (!isFinite(v)) v = 0;
    widget.__value = v;
    applyValue(widget);
    return widget;
  };
  widget.SetDisabled = function (b) {
    widget.__disabled = !!b;
    el.classList.toggle("is-disabled", !!b);
    if (widget.__kind === "Button") { el.disabled = !!b; applyButtonState(widget); }
    return widget;
  };
  widget.SetFontColor = function (tbl) { el.style.color = cssColor(tbl, ""); return widget; };
  widget.SetStyle = function (tbl) { eachEntry(tbl, function (k, v) { applyOneStyle(widget, k, v); }); return widget; };
  widget.GetAbsoluteLayout = function () {
    var r = el.getBoundingClientRect();
    var host = canvasHost();
    var hr = host.getBoundingClientRect ? host.getBoundingClientRect() : { left: 0, top: 0 };
    return { x: r.left - hr.left, y: r.top - hr.top, w: r.width, h: r.height };
  };
  return widget;
}
function applyValue(w) {
  if (w.__kind !== "ProgressBar" || !w.__fill) return;
  var range = w.__range || 100;
  var t = Math.max(0, Math.min(1, (w.__value || 0) / range));
    w.__fill.style.width = (t * 100).toFixed(1) + "%";
}
function applyOneStyle(w, k, v) {
  var st = w.el.style;
  switch (k) {
    case "width": st.width = cssPx(v); break;
    case "height": st.height = cssPx(v); break;
    case "top": st.top = cssPx(v); break;
    case "left": st.left = cssPx(v); break;
    case "right": st.right = cssPx(v); break;
    case "bottom": st.bottom = cssPx(v); break;
    case "backgroundColor": st.backgroundColor = cssColor(v); break;
    case "borderColor": st.borderColor = cssColor(v); break;
    case "borderWidth": st.borderWidth = cssPx(v); break;
    case "borderRadius": st.borderRadius = cssPx(v); break;
    case "opacity": st.opacity = String(v); break;
    case "fontSize": st.fontSize = cssPx(v); break;
    case "fontColor": st.color = cssColor(v); break;
    case "text": w.SetText(v); break;
    case "visible": w.SetVisible(!!v); break;
    default: break; /* unknown keys ignored; SetStyle is a shim nicety */
  }
}

/* full props application; CSS-flex mapping per contract */
function applyProps(w, rawProps) {
  var p = P(rawProps);
  var st = w.el.style;
  function has(k) { return p.has(k); }
  function get(k) { return p.get(k); }
  if (has("width")) st.width = cssPx(get("width"));
  if (has("height")) st.height = cssPx(get("height"));
  if (has("minWidth")) st.minWidth = cssPx(get("minWidth"));
  if (has("minHeight")) st.minHeight = cssPx(get("minHeight"));
  if (has("maxWidth")) st.maxWidth = cssPx(get("maxWidth"));
  if (has("maxHeight")) st.maxHeight = cssPx(get("maxHeight"));
  if (has("position")) st.position = String(get("position"));
  else st.position = "relative";
  if (has("top")) st.top = cssPx(get("top"));
  if (has("left")) st.left = cssPx(get("left"));
  if (has("right")) st.right = cssPx(get("right"));
  if (has("bottom")) st.bottom = cssPx(get("bottom"));
  /* urhox/Yoga default main axis is COLUMN; CSS default is row. */
  st.flexDirection = has("flexDirection") ? String(get("flexDirection")) : "column";
  if (has("alignItems")) st.alignItems = String(get("alignItems"));
  if (has("justifyContent")) st.justifyContent = String(get("justifyContent"));
  if (has("flexGrow")) st.flexGrow = String(get("flexGrow"));
  if (has("flexShrink")) st.flexShrink = String(get("flexShrink"));
  if (has("flexBasis")) st.flexBasis = cssPx(get("flexBasis"));
  if (has("gap")) st.gap = cssPx(get("gap"));
  if (has("flexWrap")) st.flexWrap = String(get("flexWrap"));
  /* flex containers must actually be flex (div defaults to block) */
  if (has("flexDirection") || has("alignItems") || has("justifyContent") || has("gap")) st.display = "flex";
  var sides = ["Left", "Right", "Top", "Bottom"];
  ["padding", "margin"].forEach(function (m) {
    if (has(m)) st[m] = cssPx(get(m));
    for (var i = 0; i < sides.length; i++) { var k = m + sides[i]; if (has(k)) st[k] = cssPx(get(k)); }
  });
  if (has("backgroundColor")) st.backgroundColor = cssColor(get("backgroundColor"));
  if (has("borderColor")) st.borderColor = cssColor(get("borderColor"));
  if (has("borderWidth")) { st.borderStyle = "solid"; st.borderWidth = cssPx(get("borderWidth")); }
  if (has("borderRadius")) st.borderRadius = cssPx(get("borderRadius"));
  var bgImg = strOr(p, "backgroundImage", null);
  if (bgImg) applyBackgroundImage(w, bgImg);
  if (has("text")) w.SetText(get("text"));
  if (has("fontSize")) st.fontSize = cssPx(get("fontSize"));
  if (has("fontColor")) st.color = cssColor(get("fontColor"));
  if (has("fontFamily")) st.fontFamily = FONT_STACK; /* sans|mono both FusionPixel */
  if (has("fontWeight")) st.fontWeight = String(get("fontWeight"));
  if (has("textAlign")) st.textAlign = String(get("textAlign"));
  if (has("lineHeight")) st.lineHeight = String(get("lineHeight"));
  if (has("letterSpacing")) st.letterSpacing = cssPx(get("letterSpacing"));
  var ws = strOr(p, "whiteSpace", null);
  if (ws) st.whiteSpace = ws;
  var maxLines = numOr(p, "maxLines", 0);
  if (maxLines > 0) {
    st.display = "-webkit-box";
    st.webkitBoxOrient = "vertical";
    st.webkitLineClamp = String(maxLines);
    st.overflow = "hidden";
  }
  var va = strOr(p, "verticalAlign", null);
  if (va === "center" && st.display !== "-webkit-box") { st.display = "flex"; st.alignItems = "center"; }
  else if (va === "bottom") { st.display = st.display === "-webkit-box" ? st.display : "flex"; st.alignItems = "flex-end"; }
  if (has("opacity")) st.opacity = String(get("opacity"));
  if (boolOr(p, "visible", true) === false) w.Hide();
  if (has("disabled")) w.SetDisabled(boolOr(p,"disabled",false));
  var pe = strOr(p, "pointerEvents", null);
  if (pe) {
    w.el.dataset.pointerEvents = pe;
    st.pointerEvents = (pe === "box-none" || pe === "none") ? "none" : "auto";
  }
  if (has("id")) w.el.id = strOr(p, "id", "");
  if (has("className")) w.el.className += " " + strOr(p, "className", "");
  if (has("ariaLabel")) w.el.setAttribute("aria-label", strOr(p,"ariaLabel",""));
  if (has("overflow")) st.overflow = String(get("overflow"));
  if (boolOr(p, "showScrollbar", false)) st.overflowY = "auto";
}

/* backgroundFit: "sliced" -> CSS border-image nine-slice (slice = prop
 * backgroundImageSlice number or 4-tuple, default 12); "contain"/"cover" */
function assetUrl(u) {
  if (typeof u !== "string" || u === "") return u;
  if (/^(data:|https?:|\/)/.test(u)) return u;
  if (/^assets\//.test(u)) return u;
  return "assets/" + u;
}
function applyBackgroundImage(w, url) { url = assetUrl(url);
  var p = P(w.props);
  var st = w.el.style;
  var fit = strOr(p, "backgroundFit", "cover");
  var frame = p.get("backgroundFrame");
  if (frame) {
    var f = P(frame), fw=numOr(f,"w",1), fh=numOr(f,"h",1), aw=numOr(f,"atlasW",fw), ah=numOr(f,"atlasH",fh);
    st.backgroundImage = "url(" + JSON.stringify(url) + ")";
    st.backgroundSize = (aw/fw*100)+"% "+(ah/fh*100)+"%";
    st.backgroundPosition = (aw===fw?0:numOr(f,"x",0)/(aw-fw)*100)+"% "+(ah===fh?0:numOr(f,"y",0)/(ah-fh)*100)+"%";
    st.backgroundRepeat = "no-repeat";
    w.el.dataset.atlasRegion = [numOr(f,"x",0),numOr(f,"y",0),fw,fh].join(",");
    return;
  }
  var sl = p.get("backgroundImageSlice");
  var sliceN = 12;
  if (sl != null) {
    if (typeof sl === "number") sliceN = sl;
    else sliceN = numAt(sl, 1, 0) + " " + numAt(sl, 2, 0) + " " + numAt(sl, 3, 0) + " " + numAt(sl, 4, 0);
  }
  if (fit === "sliced") {
    st.boxSizing = "border-box";
    st.borderStyle = "solid";
    st.borderColor = "transparent";
    st.backgroundImage = "none";
    var fill = cssColor(p.get("backgroundColor"), "transparent");
    if (fill !== "transparent") st.backgroundColor = fill;
    var bw = (typeof sl === "number") ? px(sl) : px(12);
    st.borderWidth = bw + "px";
    /* set as one shorthand so the value chain resolves atomically */
    st.borderImage = 'url("' + url + '") ' + String(sliceN) + " fill / " + bw + "px stretch";
    st.borderImageSlice = String(sliceN);
    st.borderImageRepeat = "stretch";
    st.borderImageWidth = (typeof sl === "number" || typeof sliceN === "number") ? px(12) + "px" : "auto";
    if (typeof sl === "number") st.borderImageWidth = px(sl) + "px";
  } else {
    st.backgroundImage = "url(" + JSON.stringify(url) + ")";
    st.backgroundSize = fit === "contain" ? "contain" : "cover";
    st.backgroundPosition = "center";
    st.backgroundRepeat = "no-repeat";
  }
}

/* Button three-state: hoverBackgroundImage + hoverBackgroundImageOpacity,
 * pressedBackgroundImage, disabledBackgroundImage; nine-slice via the same
 * backgroundFit path. JS state listeners swap the image (border-image source
 * cannot be switched by :hover pseudo-class in a cross-browser way). */
function applyButtonState(w) {
  var el = w.el;
  var p = P(w.props);
  var img = strOr(p, "backgroundImage", null);
  if (!img) return;
  var hov = strOr(p, "hoverBackgroundImage", null);
  var prs = strOr(p, "pressedBackgroundImage", null);
  var dis = strOr(p, "disabledBackgroundImage", null);
  if (w.__disabled) {
    if (dis) applyBackgroundImage(w, dis);
    else el.style.filter = "grayscale(1) brightness(0.75)";
    return;
  }
  el.style.filter = "";
  var cur = (w.__pressed && prs) ? prs : ((w.__hover && hov) ? hov : img);
  applyBackgroundImage(w, cur);
  var op = numOr(p, "hoverBackgroundImageOpacity", 0);
  if ((w.__hover || w.__pressed) && op > 0) {
    el.style.boxShadow = "inset 0 0 0 9999px rgba(255,255,255," + Math.min(1, op).toFixed(3) + ")";
  } else {
    el.style.boxShadow = "";
  }
}
function wireButtonStates(w) {
  var el = w.el;
  el.addEventListener("pointerenter", function () { w.__hover = true; if (!w.__disabled) applyButtonState(w); });
  el.addEventListener("pointerleave", function () { w.__hover = false; w.__pressed = false; applyButtonState(w); });
  el.addEventListener("pointerdown", function () { w.__pressed = true; if (!w.__disabled) applyButtonState(w); });
  /* 移动端多点触控：浏览器只给第一根手指合成 click，第二根手指（按住摇杆的那根之外）点按钮拿不到 click，
     非主指 pointerdown 直接触发 onClick；fireClick 内部已判 __disabled，禁用按钮不受影响。 */
  el.addEventListener("pointerdown", function (e) { if (!e.isPrimary) fireClick(w); });
  function up() { w.__pressed = false; applyButtonState(w); }
  el.addEventListener("pointerup", up);
  el.addEventListener("pointercancel", up);
}
function fireClick(w) {
  if (w.__disabled) return;
  var cb = P(w.props).get("onClick");
  if (!cb) return;
  try {
    if (isLuaProxy(cb)) cb.call(w);            /* Lua closure: thisArg -> Lua arg 1 */
    else if (typeof cb === "function") cb(w);  /* plain JS function */
  } catch (e) {
    if (window.console && console.warn) console.warn("[UrhoxUI] onClick failed:", e);
  }
}

function ensureCss() {
  if (!document.head || document.getElementById("urhox-css")) return;
  var st = document.createElement("style");
  st.id = "urhox-css";
  st.textContent = ".urhox{box-sizing:border-box;image-rendering:pixelated;pointer-events:auto;}"
    + '[data-pointer-events="none"], [data-pointer-events="none"] *, [data-pointer-events="box-only"] *{pointer-events:none!important;}'
    + ".urhox-noscrollbar::-webkit-scrollbar{display:none;}"
    + "button.urhox{border:none;font-family:" + FONT_STACK + ";cursor:pointer;}"
    + "button.urhox:disabled{cursor:default;}";
  document.head.appendChild(st);
}
function baseFactory(kind, tag, props, extra) {
  ensureCss();
  var el = document.createElement(tag);
  el.className = "urhox urhox-" + kind.toLowerCase();
  el.dataset.kind = kind;
  var w = makeWidget(el, props);
  w.__kind = kind;
  if (extra) extra(w, el);
  applyProps(w, props);
  adoptChildren(w, props);
  if (P(props).get("onClick")) {
    if (tag === "div") {
      el.setAttribute("role","button"); el.tabIndex=0;
      el.addEventListener("keydown",function(e){if(e.key==="Enter"||e.key===" "){e.preventDefault();e.stopPropagation();fireClick(w);}});
    }
    el.addEventListener("click", function () { fireClick(w); });
  }
  return w;
}

var UI = {};
UI.Init = function (opts) {
  var o = P(opts);
  var th = o.get("theme");
  state.theme = th ? mergeInto(defaultTheme(), th) : defaultTheme();
  state.scale = numOr(o, "scale", 1) || 1;
  state.inited = true;
  injectFonts();
  return UI;
};
/* Contract: [w,h] as multiple Lua values. engine-builder MUST expand this
 * array into two lua_pushnumber calls (interop caps JS returns at 1). */
UI.GetViewportSize = function () {
  var v=window.DSH.Viewport;return v?[v.width,v.height]:[window.innerWidth,window.innerHeight];
};
UI.IsKeyboardOpen = function () { return !!(window.DSH.Viewport&&window.DSH.Viewport.keyboardOpen); };
UI.GetSafeAreaInsets = function () {
  var t = 0, r = 0, b = 0, l = 0;
  try {
    var cs = getComputedStyle(document.documentElement);
    function gv(n) { var v = cs.getPropertyValue(n); return v ? (parseInt(v, 10) || 0) : 0; }
    t = gv("--safe-top"); r = gv("--safe-right");
    b = gv("--safe-bottom"); l = gv("--safe-left");
  } catch (e) { /* zeros */ }
  return { left: l, right: r, top: t, bottom: b };
};
UI.SetRoot = function (panel, isRoot) {
  if (!panel || !panel.el) return;
  if (isRoot === false) {
    if (panel.el.parentNode) panel.el.parentNode.removeChild(panel.el);
    if (state.root === panel) state.root = null;
    return;
  }
  if (state.root && state.root !== panel && state.root.el.parentNode) {
    state.root.el.parentNode.removeChild(state.root.el);
  }
  /* Root fills the viewport like the real urhox engine: fixed full-screen
   * flex container so 100%/flexGrow chains resolve (body has no layout). */
  var el = panel.el;
  el.style.position = "absolute";
  el.style.left = "0"; el.style.top = "0";
  el.style.width = "100%"; el.style.height = "100%";
  el.style.display = "flex";
  el.style.flexDirection = el.style.flexDirection || "column";
  el.style.zIndex = "5";
  if (el.style.pointerEvents !== "none") el.style.pointerEvents = "none";
  canvasHost().appendChild(el);
  state.root = panel;
};
UI.Shutdown = function () {
  if (state.root && state.root.el && state.root.el.parentNode) state.root.el.parentNode.removeChild(state.root.el);
  state.root = null;
  state.inited = false;
};
UI.Theme = {
  defaultTheme: defaultTheme(), /* must be a theme TABLE for Lua pairs/index, not the factory */
  ExtendTheme: function (theme, overrides) {
    var base = theme ? mergeInto(defaultTheme(), theme) : defaultTheme();
    return mergeInto(base, overrides);
  }
};
UI.Scale = { DEFAULT: 1 };
UI.Panel = function (props) { return baseFactory("Panel", "div", props); };
UI.Card = function (props) { return baseFactory("Card", "div", props); };
UI.SafeAreaView = function (props) {
  return baseFactory("SafeAreaView", "div", props, function (w, el) {
    var sa = UI.GetSafeAreaInsets();
    el.style.paddingTop = cssPx(sa.top);
    el.style.paddingBottom = cssPx(sa.bottom);
    el.style.paddingLeft = cssPx(sa.left);
    el.style.paddingRight = cssPx(sa.right);
    el.style.boxSizing = "border-box";
  });
};
UI.Label = function (props) {
  return baseFactory("Label", "div", props, function (w, el) {
    el.style.fontFamily = FONT_STACK;
  });
};
UI.Button = function (props) {
  var el = document.createElement("button");
  el.type = "button";
  var w = makeWidget(el, props);
  w.__kind = "Button";
  ensureCss();
  el.style.height = cssPx(numOr(P(props), "height", 46)); /* UISkin h46 */
  applyProps(w, props);
  adoptChildren(w, props);
  wireButtonStates(w);
  el.addEventListener("click", function () { fireClick(w); });
  return w;
};
/* Native editable input preserves IME composition and browser text selection.
 * Changes update the Lua draft without rebuilding/focusing the UI every key. */
UI.TextInput = function (props) {
  var w=baseFactory("TextInput","input",props), el=w.el, p=P(props);
  el.type="text"; el.value=strOr(p,"value","");
  el.placeholder=strOr(p,"placeholder","");el.autocomplete="nickname";
  el.setAttribute("aria-label",strOr(p,"ariaLabel","排行榜昵称"));
  el.style.fontFamily=FONT_STACK;el.style.pointerEvents="auto";
  el.style.userSelect="text";el.style.webkitUserSelect="text";
  w.GetText=function(){return el.value;};
  var composing=false;
  function changed(){var fn=p.get("onChange");if(fn)try{if(isLuaProxy(fn))fn.call(w,el.value);else fn(w,el.value);}catch(e){console.error("[UI] input change failed",e);}}
  el.addEventListener("compositionstart",function(){composing=true;});
  el.addEventListener("compositionend",function(){composing=false;changed();});
  el.addEventListener("input",function(){if(!composing)changed();});
  ["keydown","keyup","keypress"].forEach(function(name){el.addEventListener(name,function(e){e.stopPropagation();});});
  return w;
};
UI.ProgressBar = function (props) {
  return baseFactory("ProgressBar", "div", props, function (w, el) {
    var p = P(props);
    el.style.position = "relative";
    el.style.overflow = "hidden";
    var fill = document.createElement("div");
    fill.className = "urhox-progress-fill";
    fill.style.position = "absolute";
    fill.style.top = "0"; fill.style.left = "0";
    fill.style.height = "100%"; fill.style.width = "0%";
    var fc = p.get("fillColor");   /* main.lua hp/xp/rage/time/boss bars */
    if (fc) fill.style.backgroundColor = cssColor(fc);
    el.appendChild(fill);
    w.__fill = fill;
    w.__range = numOr(p, "maxValue", 1) || 1;
    w.__value = numOr(p, "value", 0);
  });
};
UI.ScrollView = function (props) {
  return baseFactory("ScrollView", "div", props, function (w, el) {
    el.style.overflow = "auto";
    el.style.touchAction = "pan-y";
    el.style.webkitOverflowScrolling = "touch";
    // Preserve a picker list while selecting its detail, reset for new choices.
    var p=P(props),key=p.get("scrollKey"),id=p.get("id");
    if(key&&id){
      state.scrollOffsets=state.scrollOffsets||{};var saved=state.scrollOffsets[id];
      var offset=saved&&saved.key===key?saved.top:0;
      state.scrollOffsets[id]={key:key,top:offset};
      el.addEventListener("scroll",function(){state.scrollOffsets[id]={key:key,top:el.scrollTop};},{passive:true});
      requestAnimationFrame(function(){if(el.isConnected)el.scrollTop=offset;});
    }
    if (boolOr(P(props), "bounces", true) === false) el.style.overscrollBehavior = "none";
    if (boolOr(P(props), "showScrollbar", false) === false) {
      el.style.scrollbarWidth = "none";
      el.classList.add("urhox-noscrollbar");
    }
  });
};

/* internals for dev tests / engine debugging */
UI.__internals = { P: P, isLuaProxy: isLuaProxy, readColor: readColor, mergeInto: mergeInto, state: state, FONT_STACK: FONT_STACK };

window.DSH.UrhoxUI = UI;
})();
