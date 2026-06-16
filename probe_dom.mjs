import CDP from 'chrome-remote-interface';

async function main() {
  const client = await CDP({ target: 'ws://127.0.0.1:9229/devtools/page/C465C706ED9B3726775E70738E8CED3D' });
  await client.Runtime.enable();
  await client.Runtime.addBinding({ name: '__copilotMirrorEmit' }).catch(() => {});

  const expr = `(() => {
    const aux = document.getElementById('workbench.parts.auxiliarybar');
    if (!aux) return 'no_aux';
    const ic = aux.querySelector('.chat-input-container');
    const working = ic instanceof HTMLElement && ic.classList.contains('working');
    const ia = ic || aux.querySelector('.interactive-session') || aux;
    const sb = ia.querySelector('button[aria-label*="stop" i], button[aria-label*="cancel" i], button[title*="stop" i], button[title*="cancel" i], .codicon-stop, .chat-stop-button');
    const anyBtns = Array.from(aux.querySelectorAll('button, a, [role="button"], .action-label'));
    const labels = anyBtns.slice(-12).map(b => ({
      aria: b.getAttribute('aria-label'),
      title: b.getAttribute('title'),
      text: (b.textContent||'').slice(0,40),
      cls: b.className.slice(0,80)
    }));
    return JSON.stringify({working, hasInputContainer: !!ic, hasStopSelector: !!sb, labels});
  })()`;

  const r = await client.Runtime.evaluate({ expression: expr, returnByValue: true, awaitPromise: true });
  console.log(r.result.value);
  await client.close();
}

main().catch(e => { console.error(e); process.exit(1); });
