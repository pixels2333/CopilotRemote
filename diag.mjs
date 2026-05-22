import CDP from 'chrome-remote-interface';

const resp = await fetch('http://127.0.0.1:9229/json/list');
const targets = await resp.json();

// Find workbench
const wb = targets.find(t => t.url.includes('vscode-file'));
if (!wb) { console.log('NO VSCODE WORKBENCH TARGET'); process.exit(1); }
console.log('Connected to:', wb.title.slice(0,80));

const client = await CDP({ target: wb.webSocketDebuggerUrl });
const { Runtime } = client;

// 1. Test if chat-input-container exists
const prelim = await Runtime.evaluate({
  expression: `document.querySelector('.chat-input-container') ? 'YES' : 'NO'`,
  returnByValue: true
});
console.log('chat-input-container:', prelim.result.value);

// 2. Test stop button find with the ACTUAL compiled script from dist
const stopScript = `
(() => {
  const sel = ['button[aria-label*="stop" i]', 'button[aria-label*="cancel" i]', 'button[title*="stop" i]', 'button[title*="cancel" i]', 'a[aria-label*="\\u53d6\\u6d88" i]', 'a[aria-label*="stop" i]', 'a[aria-label*="cancel" i]', '.chat-stop-button', '.codicon-stop', '.codicon-stop-circle'];
  for (const s of sel) {
    const els = document.querySelectorAll(s);
    for (const el of els) {
      if (el instanceof HTMLElement && el.offsetParent !== null) {
        el.click();
        return JSON.stringify({ ok: true, selector: s });
      }
    }
  }
  return JSON.stringify({ ok: false, reason: 'stop_button_not_found' });
})();
`;

const stopResult = await Runtime.evaluate({
  expression: stopScript,
  awaitPromise: true,
  returnByValue: true
});
console.log('Stop result:', stopResult.result.value);

// 3. If it said ok, check if something happened
if (stopResult.result.value?.includes('ok')) {
  await new Promise(r => setTimeout(r, 1000));
  const check = await Runtime.evaluate({
    expression: `document.querySelector('.chat-input-container')?.classList.contains('working') ? 'still working' : 'not working anymore'`,
    returnByValue: true
  });
  console.log('After stop click:', check.result.value);
}

client.close();
