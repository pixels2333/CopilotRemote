const fs = require('fs');

// Read the corrupted file
const c = fs.readFileSync('D:/programme/CopilotRemote/flutter_client/lib/services/cdp_service.dart', 'utf8');

// Find the cache_control line and remove everything after it
const idx = c.indexOf('{"$mid":24,"mimeType":"cache_control","data":"ZXBoZW1lcmFs"}');
if (idx >= 0) {
  const clean = c.substring(0, idx);
  fs.writeFileSync('D:/programme/CopilotRemote/flutter_client/lib/services/cdp_service.dart', clean + '\n}\n');
  console.log('FIXED at byte ' + idx);
} else {
  console.log('NOT FOUND');
}
