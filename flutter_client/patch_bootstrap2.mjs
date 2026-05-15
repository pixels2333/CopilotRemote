import fs from 'fs';

const p = 'd:/programme/CopilotRemote/flutter_client/build/web/flutter_bootstrap.js';
let c = fs.readFileSync(p, 'utf8');

// Find the buildConfig assignment line
const match = c.match(/_flutter\.buildConfig\s*=\s*(\{.*?\});/s);
if (!match) {
  console.log('ERROR: Could not find buildConfig');
  process.exit(1);
}

const config = JSON.parse(match[1]);
if (config.builds && config.builds.length > 0) {
  // Add HTML render build before the first build
  config.builds.unshift({
    compileTarget: config.builds[0].compileTarget,
    render: 'html',
    mainJsPath: config.builds[0].mainJsPath
  });
}

const newConfigStr = JSON.stringify(config);
c = c.replace(match[0], `_flutter.buildConfig = ${newConfigStr};`);

fs.writeFileSync(p, c);
console.log('Patched OK. Builds:', JSON.stringify(config.builds.map(b => b.render)));
