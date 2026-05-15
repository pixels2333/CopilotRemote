const fs = require('fs');
const path = require('path');

const pattern = /\{\"\\":24/;
let found = [];

function scan(dir) {
  const entries = fs.readdirSync(dir);
  for (const f of entries) {
    const fp = path.join(dir, f);
    const stat = fs.statSync(fp);
    if (stat.isDirectory()) {
      if (!/^(node_modules|build|\.dart_tool|web|\.git|\.pub|\.idea|out)$/.test(f))
        scan(fp);
    } else if (/\.(ts|dart|cjs|js)$/.test(f)) {
      const c = fs.readFileSync(fp, 'utf8');
      if (pattern.test(c)) found.push(path.relative('D:\\programme\\CopilotRemote', fp));
    }
  }
}

scan('D:\\programme\\CopilotRemote\\src');
scan('D:\\programme\\CopilotRemote\\flutter_client\\lib');
scan('D:\\programme\\CopilotRemote');
if (found.length === 0) {
  console.log('RESULT: NO_DIRTY_DATA');
} else {
  console.log('RESULT: DIRTY_FILES=' + found.join(','));
}
