import fs from 'fs';

const p = 'd:/programme/CopilotRemote/flutter_client/build/web/flutter_bootstrap.js';
let c = fs.readFileSync(p, 'utf8');

// Replace all "render" (6-letter) with "render" (8-letter) using char codes
const r = String.fromCharCode(114, 101, 110, 100, 101, 114);        // "render"
const r2 = String.fromCharCode(114, 101, 110, 100, 101, 114, 101, 114); // "render"
c = c.replaceAll(r, r2);

// Now replace the builds config to add HTML render
const oldS = '{"compileTarget":"dart2js","render":"canvaskit","mainJsPath":"main.dart.js"}';
const newS = '{"compileTarget":"dart2js","render":"html","mainJsPath":"main.dart.js"},{"compileTarget":"dart2js","render":"canvaskit","mainJsPath":"main.dart.js"}';
c = c.replace(oldS.replaceAll(r, r2), newS.replaceAll(r, r2));

fs.writeFileSync(p, c);
console.log('Patched OK');
