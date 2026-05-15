const fs = require('fs');
const path = require('path');

function cleanFile(filePath) {
    const c = fs.readFileSync(filePath, 'utf8');
    const idx = c.indexOf('{$mid');
    if (idx >= 0) {
        const cleaned = c.substring(0, idx);
        fs.writeFileSync(filePath, cleaned);
        console.log('CLEANED: ' + path.basename(filePath));
        return true;
    }
    return false;
}

const srcDir = 'D:/programme/CopilotRemote/src';
const flutterDir = 'D:/programme/CopilotRemote/flutter_client/lib';

// Clean TS files
fs.readdirSync(srcDir).filter(f => f.endsWith('.ts')).forEach(f => {
    cleanFile(path.join(srcDir, f));
});

// Clean Dart files
function walkDir(dir) {
    fs.readdirSync(dir).forEach(f => {
        const fp = path.join(dir, f);
        if (fs.statSync(fp).isDirectory()) {
            walkDir(fp);
        } else if (f.endsWith('.dart')) {
            cleanFile(fp);
        }
    });
}
walkDir(flutterDir);

console.log('ALL DONE');
