import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';

const ROOT = 'E:/xiabandemo/OffWork-Rage/web';
const DIST = 'E:/xiabandemo/OffWork-Rage/web-dist';

// 读 manifest 拿资产清单（与 engine 同款 vm 技巧）
const sandbox = { window: {} };
vm.createContext(sandbox);
vm.runInContext(fs.readFileSync(path.join(ROOT, 'js/manifest.js'), 'utf8'), sandbox);
const assets = sandbox.window.DSH.MANIFEST.assets;

// 复制运行时文件清单
function copy(rel) {
  const src = path.join(ROOT, rel), dst = path.join(DIST, rel);
  fs.mkdirSync(path.dirname(dst), { recursive: true });
  fs.copyFileSync(src, dst);
}
fs.rmSync(DIST, { recursive: true, force: true });
fs.mkdirSync(DIST, { recursive: true });
copy('index.html');
copy('css/game.css');
copy('css/expansion.css');
copy('css/mobile-layout.css');
copy('js/mobile-display.js');
for (const f of ['manifest.js', 'ui.js', 'gfx.js', 'audio.js', 'engine.js']) copy('js/' + f);
copy('vendor/fengari-web.js');
let n = 0, bytes = 0;
for (const list of [assets.images, assets.audio, assets.fonts]) {
  for (const p of list) { copy(p); n++; bytes += fs.statSync(path.join(DIST, p)).size; }
}
function du(d) { let t = 0, c = 0; (function w(x) { for (const e of fs.readdirSync(x, { withFileTypes: true })) { const p = path.join(x, e.name); if (e.isDirectory()) w(p); else { t += fs.statSync(p).size; c++; } } })(d); return { t, c }; }
const s = du(DIST);
console.log('dist built: ' + n + ' assets (' + (bytes / 1048576).toFixed(1) + 'MB), total ' + s.c + ' files ' + (s.t / 1048576).toFixed(2) + 'MB');

// gen-manifest 已生成 30 张图（去掉了 5 张无引用 floor/partition）
// font 走 .subset.ttf 三件
