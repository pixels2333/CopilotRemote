const fs = require('fs');
const path = require('path');

function cleanFile(filePath) {
    let c = fs.readFileSync(filePath, 'utf8');
    const regex = /\n?\{\"\$mid\":24,\"mimeType\":\"cache_control\",\"data\":\"[^\"]+\"\}\n?/g;
    const cleaned = c.replace(regex, '\n');
    if (cleaned !== c) {
        fs.writeFileSync(filePath, cleaned);
        console.log('CLEANED: ' + path.basename(filePath));
    }
}

// Source TS files
const srcDir = 'D:/programme/CopilotRemote/src';
fs.readdirSync(srcDir).filter(f => f.endsWith('.ts')).forEach(f => cleanFile(path.join(srcDir, f)));

// Flutter Dart files
const flutterDir = 'D:/programme/CopilotRemote/flutter_client/lib';
function walkDir(dir) {
    fs.readdirSync(dir).forEach(f => {
        const fp = path.join(dir, f);
        if (fs.statSync(fp).isDirectory()) walkDir(fp);
        else if (f.endsWith('.dart')) cleanFile(fp);
    });
}
walkDir(flutterDir);

console.log('ALL DONE');
