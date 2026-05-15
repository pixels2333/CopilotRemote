const fs = require('fs');
const path = require('path');

const MARKER = '{"$mid":24,"mimeType":"cache_control","data":"ZXBoZW1lcmFs"}';

function cleanFile(fp) {
  let c = fs.readFileSync(fp, 'utf8');
  if (c.includes(MARKER)) {
    c = c.replace(MARKER, '');
    fs.writeFileSync(fp, c, 'utf8');
    console.log('FIXED: ' + path.basename(fp));
  }
}

// All affected files
const files = [
  'D:/programme/CopilotRemote/flutter_client/lib/providers/settings_provider.dart',
  'D:/programme/CopilotRemote/flutter_client/lib/screens/chat_screen.dart',
  'D:/programme/CopilotRemote/flutter_client/lib/widgets/connection_status_bar.dart',
  'D:/programme/CopilotRemote/flutter_client/pubspec.yaml',
  'D:/programme/CopilotRemote/src/bridge.ts',
  'D:/programme/CopilotRemote/src/wsGateway.ts',
  'D:/programme/CopilotRemote/src/main.ts',
  'D:/programme/CopilotRemote/src/domInjection.ts',
];

for (const f of files) {
  if (fs.existsSync(f)) cleanFile(f);
}
console.log('ALL DONE');
