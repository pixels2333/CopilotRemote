import CDP from 'chrome-remote-interface';

const client = await CDP({ host: 'localhost', port: 9229, target: 'ws://localhost:9229/devtools/page/312A377E48964BCE8DEB8F20A57B75F6' });
const { Runtime } = client;
await Runtime.enable();

// Execute a simplified version of the observer's extractAll to see what it returns
const r = await Runtime.evaluate({
  expression: `(() => {
    function isGenerating() {
      const container = document.querySelector('.chat-input-container.working');
      if (container) return true;
      const sel = ['button[aria-label*="stop" i]','button[aria-label*="cancel" i]','button[title*="stop" i]','button[title*="cancel" i]','a[aria-label*="\u53d6\u6d88" i]','a[aria-label*="stop" i]','a[aria-label*="cancel" i]','[role="button"][aria-label*="stop" i]','[role="button"][aria-label*="cancel" i]','.action-label[aria-label*="stop" i]','.action-label[aria-label*="cancel" i]','.chat-stop-button','.codicon-stop','.codicon-stop-circle'];
      for (const s of sel) { const el = document.querySelector(s); if (el instanceof HTMLElement && el.offsetParent !== null) return true; }
      return false;
    }
    
    // Check if observer script is installed
    const observerInstalled = !!window.__copilotMirrorInstalled;
    const generating = isGenerating();
    
    // Get a sample of last messages and their status
    const list = document.querySelector('.interactive-list .monaco-list, .chat-list-at-bottom .monaco-list, [class*="interactive-list"] .monaco-list');
    let lastMsgs = [];
    if (list) {
      const rows = Array.from(list.querySelectorAll('.monaco-list-row')).filter(r => r instanceof HTMLElement).slice(-3);
      rows.forEach((row, i) => {
        const role = (row.className||'').toLowerCase().includes('request') ? 'user' : 'assistant';
        lastMsgs.push({ role, className: row.className?.slice(0,30)||'' });
      });
    }
    
    return { observerInstalled, generating, lastMsgs, lastRowCount: list ? list.querySelectorAll('.monaco-list-row').length : 0 };
  })()`,
  returnByValue: true
});

console.log('Result:', JSON.stringify(r.result.value, null, 2));
client.close();
