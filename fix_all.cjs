const fs = require('fs');
const path = require('path');

const regex = /\n?\{\"\$mid\":24,\"mimeType\":\"cache_control\",\"data\":\"[^\"]+\"\}\n?/g;

// Clean src/*.ts
const srcDir = 'D:/programme/CopilotRemote/src';
for (const f of fs.readdirSync(srcDir).filter(f => f.endsWith('.ts'))) {
  const fp = path.join(srcDir, f);
  const c = fs.readFileSync(fp, 'utf8').replace(regex, '\n');
  fs.writeFileSync(fp, c);
  console.log('TS:', f);
}

// Clean flutter_client/lib/**/*.dart
function walk(dir) {
  for (const f of fs.readdirSync(dir)) {
    const fp = path.join(dir, f);
    if (fs.statSync(fp).isDirectory()) {
      walk(fp);
    } else if (f.endsWith('.dart')) {
      const c = fs.readFileSync(fp, 'utf8').replace(regex, '\n');
      fs.writeFileSync(fp, c);
      console.log('DART:', path.relative(srcDir, fp));
    }
  }
}

walk('D:/programme/CopilotRemote/flutter_client/lib');

console.log('ALL CLEANED');
