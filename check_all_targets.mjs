import CDP from 'chrome-remote-interface';

// Check all targets and find which one has Copilot Chat content
const targets = await CDP.List({ host: 'localhost', port: 9229 });

for (const t of targets) {
  if (t.type !== 'page' && t.type !== 'webview') continue;
  try {
    const client = await CDP({ host: 'localhost', port: 9229, target: t.webSocketDebuggerUrl || t.id });
    const { Runtime } = client;
    await Runtime.enable();
    
    const r = await Runtime.evaluate({
      expression: `(() => {
        const hasChatList = !!document.querySelector('.interactive-list .monaco-list, .chat-list-at-bottom .monaco-list, [class*="interactive-list"] .monaco-list');
        const hasChatRows = document.querySelectorAll('.monaco-list-row').length;
        const hasWorking = !!document.querySelector('.chat-input-container.working');
        return { hasChatList, hasChatRows, hasWorking, title: document.title.slice(0,40), url: location.href.slice(0,60) };
      })()`,
      returnByValue: true
    });
    
    console.log('Target:', t.id.slice(0,20), t.type, '->', JSON.stringify(r.result.value));
    client.close();
  } catch(e) {
    console.log('Target:', t.id.slice(0,20), 'ERROR:', e.message);
  }
}
