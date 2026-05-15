import fs from 'fs';

const p = 'd:/programme/CopilotRemote/flutter_client/build/web/flutter_bootstrap.js';
let c = fs.readFileSync(p, 'utf8');

const match = c.match(/_flutter\.buildConfig\s*=\s*(\{.*?\});/s);
if (!match) { console.log('ERROR: No buildConfig found'); process.exit(1); }

const config = JSON.parse(match[1]);
const origBuild = config.builds[0];

// Create HTML render build entry with CORRECT field name "render" (8 chars)
config.builds.unshift({
  [String.fromCharCode(114,101,110,100,101,114,101,114)]: 'html',
  compileTarget: origBuild.compileTarget,
  mainJsPath: origBuild.mainJsPath
});

const newConfigStr = JSON.stringify(config);
c = c.replace(match[0], '_flutter.buildConfig = ' + newConfigStr + ';');
fs.writeFileSync(p, c);

const renders = config.builds.map(b => b[String.fromCharCode(114,101,110,100,101,114,101,114)]);
console.log('Patched OK. Renders:', JSON.stringify(renders));
