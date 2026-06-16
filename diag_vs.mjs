import CDP from 'chrome-remote-interface';

const TARGET_ID = process.argv[2] || 'C465C706ED9B3726775E70738E8CED3D';

async function main() {
  const client = await CDP({ target: `ws://127.0.0.1:9229/devtools/page/${TARGET_ID}` });
  const { Runtime } = client;
  await Runtime.enable();

  // Evaluate generation detection and observer status
  const result = await Runtime.evaluate({
    expression: `(() => {
      const ic = document.querySelector('.chat-input-container');
      const hwc = ic instanceof HTMLElement && ic.classList.contains('working');
      const stopBtn = document.querySelector('button[aria-label*="stop" i], button[aria-label*="cancel" i], a[aria-label*="\\u53d6\\u6d88" i], .codicon-stop, .chat-stop-button');
      const rows = document.querySelectorAll('.monaco-list-row');
      const lastRow = rows.length > 0 ? rows[rows.length - 1] : null;
      const lastRole = lastRow ? ((lastRow.className||'').toLowerCase().includes('request') ? 'user' : 'assistant') : 'none';
      const installed = !!window.__copilotMirrorInstalled;
      const hasBinding = typeof window.__copilotMirrorEmit === 'function';
      return {
        installed,
        hasBinding,
        working: hwc,
        stopBtnFound: stopBtn instanceof HTMLElement,
        stopBtnAria: stopBtn?.getAttribute('aria-label') || '',
        rowCount: rows.length,
        lastRole,
        lastRowText: lastRow ? (lastRow.textContent || '').slice(0, 60) : ''
      };
    })()`,
    returnByValue: true,
    awaitPromise: true
  });

  console.log('VS Code state:', JSON.stringify(result.result.value, null, 2));

  // Test buildCurrentSnapshotScript result
  const snapshotResult = await Runtime.evaluate({
    expression: `(function(){
      const ic = document.querySelector('.chat-input-container');
      const hwc = ic instanceof HTMLElement && ic.classList.contains('working');
      const ia = ic || document.querySelector('.interactive-session') || document.body;
      const sb = ia.querySelector('button[aria-label*="stop" i], button[aria-label*="cancel" i], button[title*="stop" i], button[title*="cancel" i], a[aria-label*="\\u53d6\\u6d88" i], a[aria-label*="stop" i], a[aria-label*="cancel" i], a[title*="stop" i], a[title*="cancel" i], [role="button"][aria-label*="stop" i], [role="button"][aria-label*="cancel" i], [role="button"][title*="stop" i], [role="button"][title*="cancel" i], .action-label[aria-label*="stop" i], .action-label[aria-label*="cancel" i], .action-label[title*="stop" i], .action-label[title*="cancel" i], .monaco-button[aria-label*="stop" i], .monaco-button[aria-label*="cancel" i], .chat-stop-button, .codicon-stop, .codicon-stop-circle');
      const iw = hwc || (sb instanceof HTMLElement && sb.offsetParent !== null);
      return { hwc, stopFound: sb instanceof HTMLElement, isGenerating: iw };
    })()`,
    returnByValue: true,
    awaitPromise: true
  });

  console.log('Snapshot detection:', JSON.stringify(snapshotResult.result.value, null, 2));

  await client.close();
}

main().catch(e => { console.error(e); process.exit(1); });
