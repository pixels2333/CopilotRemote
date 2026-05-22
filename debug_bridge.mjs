import WebSocket from 'ws';
import CDP from 'chrome-remote-interface';

let seq = 0;

// Connect to bridge and see what's happening
const ws = new WebSocket('ws://127.0.0.1:17321/copilot-mirror/ws');

function send(type, payload = {}, requestId) {
  ws.send(JSON.stringify({
    v: 1,
    seq: ++seq,
    type,
    requestId: requestId || 'req_' + seq,
    timestamp: new Date().toISOString(),
    payload
  }));
}

ws.on('open', () => {
  console.log('=== Connected to bridge ===');
  send('client.hello', {
    clientName: 'debug_tool',
    protocolVersion: 1,
    capabilities: { acceptDelta: true, acceptThinking: true, acceptArtifacts: true }
  });
});

ws.on('message', (data) => {
  const msg = JSON.parse(data.toString());
  console.log('Bridge ->', msg.type, msg.payload ? JSON.stringify(msg.payload).slice(0, 400) : '');
  
  if (msg.type === 'server.hello' || msg.type === 'server.status') {
    const cdp = msg.payload?.cdp;
    if (cdp) {
      console.log('  CDP:', JSON.stringify(cdp));
    }
  }
  
  if (msg.type === 'session.snapshot') {
    const messages = msg.payload?.messages || [];
    const streamingMsgs = messages.filter(m => m.status === 'streaming');
    console.log(`  Messages: ${messages.length}, streaming: ${streamingMsgs.length}`);
  }
});

// Wait for hello, then check what CDP target the bridge is connected to
setTimeout(async () => {
  // Also directly check the CDP target list to see what's available
  const resp = await fetch('http://127.0.0.1:9229/json/list');
  const targets = await resp.json();
  console.log('\n=== CDP Targets on 9229 ===');
  targets.forEach((t, i) => {
    console.log(`  [${i}] type=${t.type} score=0 title="${(t.title||'').slice(0,80)}" url="${(t.url||'').slice(0,80)}"`);
  });

  // Find the workbench
  const wb = targets.find(t => t.url.includes('vscode-file'));
  if (wb) {
    console.log('\n=== Connecting to workbench to test stop button ===');
    const client = await CDP({ target: wb.webSocketDebuggerUrl });
    const { Runtime } = client;
    
    const stopScript = `
(() => {
  const sel = ['button[aria-label*="stop" i]', 'button[aria-label*="cancel" i]', 'button[title*="stop" i]', 'button[title*="cancel" i]', 'a[aria-label*="\\u53d6\\u6d88" i]', 'a[aria-label*="stop" i]', 'a[aria-label*="cancel" i]', '.chat-stop-button', '.codicon-stop', '.codicon-stop-circle'];
  for (const s of sel) {
    const els = document.querySelectorAll(s);
    for (const el of els) {
      if (el instanceof HTMLElement && el.offsetParent !== null) {
        el.click();
        return JSON.stringify({ ok: true, selector: s, tag: el.tagName, ariaLabel: el.getAttribute('aria-label')||'' });
      }
    }
  }
  return JSON.stringify({ ok: false, reason: 'stop_button_not_found' });
})();
    `.trim();
    
    const result = await Runtime.evaluate({
      expression: stopScript,
      awaitPromise: true,
      returnByValue: true
    });
    console.log('  Stop result:', result.result.value);
    
    client.close();
  }
  
  console.log('\n=== Now sending stop via bridge ===');
  send('client.command.stopGeneration', {}, 'test_stop');
}, 3000);

// Wait and disconnect
setTimeout(() => {
  console.log('\n=== Done ===');
  ws.close();
  process.exit(0);
}, 15000);

ws.on('error', (err) => {
  console.error('WebSocket error:', err.message);
});
